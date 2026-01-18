#!/bin/bash

# 网心云磁盘监控和清理脚本
# 功能：监控磁盘使用率，达到阈值时自动清理task目录

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载配置文件
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo "错误：配置文件 config.sh 不存在！"
    exit 1
fi

# ==================== 函数定义 ====================

# 日志函数
log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

# 错误日志函数
log_error() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [ERROR] $message" | tee -a "$LOG_FILE" >&2
}

# 路径验证函数
validate_path() {
    local path="$1"
    local path_name="$2"
    
    if [ -z "$path" ]; then
        log_error "$path_name 路径为空，脚本终止！"
        exit 1
    fi
    
    # 防止根目录被误删
    if [ "$path" = "/" ] || [ "$path" = "/root" ] || [ "$path" = "/home" ]; then
        log_error "$path_name 路径设置不安全：$path，脚本终止！"
        exit 1
    fi
    
    return 0
}

# 检查Docker容器状态
check_container_status() {
    if docker ps -q -f name="^${DOCKER_CONTAINER}$" > /dev/null 2>&1; then
        return 0  # 容器正在运行
    else
        return 1  # 容器未运行
    fi
}

# 停止Docker容器
stop_container() {
    log "正在停止容器 $DOCKER_CONTAINER（超时：${STOP_TIMEOUT}秒）..."
    
    if docker stop --time "$STOP_TIMEOUT" "$DOCKER_CONTAINER" >> "$LOG_FILE" 2>&1; then
        log "容器 $DOCKER_CONTAINER 已成功停止"
        return 0
    else
        log_error "停止容器 $DOCKER_CONTAINER 失败"
        return 1
    fi
}

# 启动Docker容器（带重试）
start_container() {
    local retry=0
    
    while [ $retry -lt $MAX_RETRY ]; do
        log "正在启动容器 $DOCKER_CONTAINER（尝试 $((retry+1))/$MAX_RETRY）..."
        
        if docker start "$DOCKER_CONTAINER" >> "$LOG_FILE" 2>&1; then
            sleep 3
            if check_container_status; then
                log "容器 $DOCKER_CONTAINER 已成功启动"
                return 0
            else
                log_error "容器启动命令执行成功，但容器未在运行状态"
            fi
        else
            log_error "启动容器 $DOCKER_CONTAINER 失败"
        fi
        
        retry=$((retry+1))
        if [ $retry -lt $MAX_RETRY ]; then
            log "等待 ${RETRY_INTERVAL} 秒后重试..."
            sleep $RETRY_INTERVAL
        fi
    done
    
    log_error "容器启动失败，已达到最大重试次数"
    return 1
}

# 清理task目录
cleanup_task_dir() {
    validate_path "$CLEAN_PATH" "清理路径"
    
    if [ ! -d "$CLEAN_PATH" ]; then
        log_error "清理目录不存在：$CLEAN_PATH"
        return 1
    fi
    
    log "正在清理目录：$CLEAN_PATH"
    
    # 获取清理前的目录大小
    local before_size=$(du -sh "$CLEAN_PATH" 2>/dev/null | awk '{print $1}')
    log "清理前目录大小：$before_size"
    
    # 执行清理
    if rm -rf "$CLEAN_PATH"/* 2>> "$LOG_FILE"; then
        local after_size=$(du -sh "$CLEAN_PATH" 2>/dev/null | awk '{print $1}')
        log "清理完成！清理后目录大小：$after_size"
        return 0
    else
        log_error "清理目录失败"
        return 1
    fi
}

# ==================== 主逻辑 ====================

log "========== 监控脚本开始执行 =========="

# 检查是否有强制执行参数
FORCE_CLEANUP=false
if [ "$1" == "force" ] || [ "$1" == "--force" ]; then
    FORCE_CLEANUP=true
    log "强制清理模式已启用"
fi

# 验证关键路径
validate_path "$MONITOR_PATH" "监控路径"
validate_path "$CLEAN_PATH" "清理路径"

# 检查监控路径是否存在
if [ ! -d "$MONITOR_PATH" ]; then
    log_error "监控路径不存在：$MONITOR_PATH"
    exit 1
fi

# 获取已用空间百分比
USED_PERCENT=$(df "$MONITOR_PATH" | awk 'NR==2 {print int($5)}')

if [ -z "$USED_PERCENT" ]; then
    log_error "无法获取磁盘使用率"
    exit 1
fi

log "监控路径 $MONITOR_PATH 已用空间：${USED_PERCENT}%（阈值：${THRESHOLD_PERCENT}%）"

# 判断是否需要清理
if [ "$FORCE_CLEANUP" = true ] || [ "$USED_PERCENT" -gt "$THRESHOLD_PERCENT" ]; then
    if [ "$FORCE_CLEANUP" = true ]; then
        log "触发原因：强制清理"
    else
        log "触发原因：已用空间 ${USED_PERCENT}% 超过阈值 ${THRESHOLD_PERCENT}%"
    fi
    
    # 检查容器状态
    if check_container_status; then
        log "容器 $DOCKER_CONTAINER 正在运行"
        
        # 停止容器
        if ! stop_container; then
            log_error "无法停止容器，清理操作中止"
            exit 1
        fi
    else
        log "容器 $DOCKER_CONTAINER 未在运行状态"
    fi
    
    # 清理文件
    if ! cleanup_task_dir; then
        log_error "清理操作失败"
        # 即使清理失败，也尝试启动容器
    fi
    
    # 启动容器
    if ! start_container; then
        log_error "容器启动失败，请手动检查！"
        exit 1
    fi
    
    # 再次检查清理后的空间
    NEW_USED_PERCENT=$(df "$MONITOR_PATH" | awk 'NR==2 {print int($5)}')
    log "清理后已用空间：${NEW_USED_PERCENT}%"
    
    # 计算释放的空间
    FREED_SPACE=$((USED_PERCENT - NEW_USED_PERCENT))
    log "释放空间：${FREED_SPACE}%"
    
else
    log "已用空间在限制范围内，无需清理"
fi

log "========== 监控脚本执行完成 =========="
