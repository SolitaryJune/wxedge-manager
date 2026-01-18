#!/bin/bash

# 网心云Docker部署脚本
# 功能：配置代理、拉取镜像、部署容器、安装测速脚本、设置定时任务

set -e  # 遇到错误立即退出

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 加载配置文件
log_info "加载配置文件..."
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
    log_info "配置文件加载成功"
else
    log_error "配置文件 config.sh 不存在！"
    exit 1
fi

# ==================== 环境检查 ====================

log_info "========== 开始环境检查 =========="

# 检查是否为root用户或有sudo权限
if [ "$EUID" -ne 0 ]; then 
    if ! sudo -n true 2>/dev/null; then
        log_error "此脚本需要root权限或sudo权限"
        exit 1
    fi
    SUDO="sudo"
else
    SUDO=""
fi

# 检查Docker是否安装
if ! command -v docker &> /dev/null; then
    log_error "Docker未安装，请先安装Docker"
    exit 1
fi
log_info "Docker已安装：$(docker --version)"

# 检查Docker服务是否运行
if ! $SUDO docker info &> /dev/null; then
    log_error "Docker服务未运行，请启动Docker服务"
    exit 1
fi
log_info "Docker服务正常运行"

# 检查wget是否安装
if ! command -v wget &> /dev/null; then
    log_error "wget未安装，请先安装wget"
    exit 1
fi

log_info "环境检查完成"

# ==================== 配置确认 ====================

log_info "========== 配置信息确认 =========="
echo ""
echo "监控路径：$MONITOR_PATH"
echo "数据目录：$WXEDGE_DATA_DIR"
echo "清理路径：$CLEAN_PATH"
echo "容器名称：$DOCKER_CONTAINER"
echo "镜像名称：$DOCKER_IMAGE"
echo "Docker代理：$DOCKER_PROXY"
echo "挂载配置：$DOCKER_VOLUME"
echo "网络模式：$DOCKER_NETWORK"
echo "重启策略：$DOCKER_RESTART"
echo "磁盘阈值：${THRESHOLD_PERCENT}%"
echo "定时任务：$CRON_SCHEDULE"
echo ""

read -p "请确认以上配置是否正确？(y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_warn "部署已取消，请修改 config.sh 后重新运行"
    exit 0
fi

# ==================== 创建必要目录 ====================

log_info "========== 创建必要目录 =========="

if [ ! -d "$WXEDGE_DATA_DIR" ]; then
    log_info "创建数据目录：$WXEDGE_DATA_DIR"
    $SUDO mkdir -p "$WXEDGE_DATA_DIR"
else
    log_info "数据目录已存在：$WXEDGE_DATA_DIR"
fi

# 创建日志目录
LOG_DIR=$(dirname "$LOG_FILE")
if [ ! -d "$LOG_DIR" ]; then
    log_info "创建日志目录：$LOG_DIR"
    $SUDO mkdir -p "$LOG_DIR"
fi

# ==================== 配置Docker代理 ====================

log_info "========== 配置Docker代理 =========="

DOCKER_DAEMON_CONFIG="/etc/docker/daemon.json"
DOCKER_PROXY_BACKUP="/etc/docker/daemon.json.backup.$(date +%Y%m%d%H%M%S)"

# 备份现有配置
if [ -f "$DOCKER_DAEMON_CONFIG" ]; then
    log_info "备份现有Docker配置到：$DOCKER_PROXY_BACKUP"
    $SUDO cp "$DOCKER_DAEMON_CONFIG" "$DOCKER_PROXY_BACKUP"
fi

# 检查现有代理配置
CURRENT_PROXY=""
if [ -f "$DOCKER_DAEMON_CONFIG" ]; then
    CURRENT_PROXY=$(grep "http-proxy" "$DOCKER_DAEMON_CONFIG" | cut -d'"' -f4 || echo "")
fi

if [ "$CURRENT_PROXY" = "$DOCKER_PROXY" ]; then
    log_info "Docker代理配置已是最新，跳过配置步骤"
else
    # 配置代理
    log_info "配置Docker代理：$DOCKER_PROXY"

    # 创建或更新daemon.json
    $SUDO bash -c "cat > $DOCKER_DAEMON_CONFIG" <<EOF
{
  "proxies": {
    "http-proxy": "$DOCKER_PROXY",
    "https-proxy": "$DOCKER_PROXY",
    "no-proxy": "localhost,127.0.0.1"
  }
}
EOF

    # 重启Docker服务
    log_info "重启Docker服务以应用代理配置..."
    $SUDO systemctl daemon-reload
    $SUDO systemctl restart docker
fi

# 等待Docker服务启动
sleep 5

if ! $SUDO docker info &> /dev/null; then
    log_error "Docker服务重启后无法正常运行，正在恢复配置..."
    if [ -f "$DOCKER_PROXY_BACKUP" ]; then
        $SUDO cp "$DOCKER_PROXY_BACKUP" "$DOCKER_DAEMON_CONFIG"
        $SUDO systemctl restart docker
    fi
    exit 1
fi

log_info "Docker代理配置成功"

# ==================== 拉取Docker镜像 ====================

log_info "========== 拉取Docker镜像 =========="

log_info "正在拉取镜像：$DOCKER_IMAGE"
log_warn "这可能需要几分钟时间，请耐心等待..."

if $SUDO docker pull "$DOCKER_IMAGE"; then
    log_info "镜像拉取成功"
else
    log_error "镜像拉取失败，请检查镜像名称和代理配置"
    exit 1
fi

# 验证镜像
if $SUDO docker images | grep -q "$(echo $DOCKER_IMAGE | cut -d: -f1)"; then
    log_info "镜像验证成功"
else
    log_error "镜像验证失败"
    exit 1
fi

# ==================== 部署Docker容器 ====================

log_info "========== 部署Docker容器 =========="

# 检查容器是否已存在
if $SUDO docker ps -a | grep -q "$DOCKER_CONTAINER"; then
    log_warn "容器 $DOCKER_CONTAINER 已存在"
    read -p "是否删除现有容器并重新创建？(y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "停止并删除现有容器..."
        $SUDO docker stop "$DOCKER_CONTAINER" 2>/dev/null || true
        $SUDO docker rm "$DOCKER_CONTAINER" 2>/dev/null || true
    else
        log_warn "保留现有容器，跳过容器创建"
        SKIP_CONTAINER_CREATE=true
    fi
fi

if [ "$SKIP_CONTAINER_CREATE" != true ]; then
    log_info "创建并启动容器：$DOCKER_CONTAINER"
    
    # 构建docker run命令
    DOCKER_CMD="$SUDO docker run -d \
        --name $DOCKER_CONTAINER \
        --restart $DOCKER_RESTART \
        --network $DOCKER_NETWORK"
    
    # 添加端口映射（如果不是host模式）
    if [ "$DOCKER_NETWORK" != "host" ] && [ -n "$DOCKER_PORT_MAP" ]; then
        DOCKER_CMD="$DOCKER_CMD -p $DOCKER_PORT_MAP"
    fi
    
    # 添加挂载
    if [ -n "$DOCKER_VOLUME" ]; then
        DOCKER_CMD="$DOCKER_CMD -v $DOCKER_VOLUME"
    fi
    
    # 添加特权模式
    if [ "$DOCKER_PRIVILEGED" = "true" ]; then
        DOCKER_CMD="$DOCKER_CMD --privileged"
    fi
    
    # 添加额外参数
    if [ -n "$DOCKER_EXTRA_ARGS" ]; then
        DOCKER_CMD="$DOCKER_CMD $DOCKER_EXTRA_ARGS"
    fi
    
    # 添加镜像名称
    DOCKER_CMD="$DOCKER_CMD $DOCKER_IMAGE"
    
    # 执行命令
    log_info "执行命令：$DOCKER_CMD"
    if eval "$DOCKER_CMD"; then
        log_info "容器创建成功"
        sleep 3
        
        # 检查容器状态
        if $SUDO docker ps | grep -q "$DOCKER_CONTAINER"; then
            log_info "容器运行正常"
        else
            log_error "容器未在运行状态，请检查日志"
            $SUDO docker logs "$DOCKER_CONTAINER"
            exit 1
        fi
    else
        log_error "容器创建失败"
        exit 1
    fi
fi

# ==================== 部署测速脚本 ====================

log_info "========== 部署测速脚本 =========="

SPEED_TEST_SCRIPT="$SCRIPT_DIR/build_and_run_docker.sh"

log_info "下载测速脚本..."
if wget -O "$SPEED_TEST_SCRIPT" "$SPEED_TEST_URL" 2>&1 | grep -q "saved"; then
    log_info "测速脚本下载成功"
    chmod +x "$SPEED_TEST_SCRIPT"
    
    log_info "运行测速脚本（线程：$SPEED_TEST_THREADS，限速：$SPEED_TEST_LIMIT）..."
    if "$SPEED_TEST_SCRIPT" --threads "$SPEED_TEST_THREADS" --speed-limit "$SPEED_TEST_LIMIT"; then
        log_info "测速脚本执行成功"
    else
        log_error "测速脚本执行失败！"
        exit 1
    fi
else
    log_error "测速脚本下载失败！"
    exit 1
fi

# ==================== 设置定时任务 ====================

log_info "========== 设置定时任务 =========="

MONITOR_SCRIPT="$SCRIPT_DIR/monitor.sh"
chmod +x "$MONITOR_SCRIPT"

# 幂等性添加定时任务：先删除旧任务，再添加新任务
CRON_ENTRY="$CRON_SCHEDULE $MONITOR_SCRIPT >> $LOG_FILE 2>&1"

log_info "更新定时任务配置..."
# 提取不包含该脚本的所有现有任务，然后追加新任务
($SUDO crontab -l 2>/dev/null | grep -v "$MONITOR_SCRIPT" || true; echo "$CRON_ENTRY") | $SUDO crontab -
log_info "定时任务已更新：$CRON_SCHEDULE"

# 显示当前的crontab
log_info "当前定时任务列表："
$SUDO crontab -l | grep "$MONITOR_SCRIPT" || log_warn "未找到相关定时任务"

# ==================== 部署完成 ====================

log_info "========== 部署完成 =========="
echo ""
log_info "部署摘要："
echo "  ✓ Docker代理已配置"
echo "  ✓ 网心云镜像已拉取"
echo "  ✓ 容器已创建并运行"
echo "  ✓ 测速脚本已部署"
echo "  ✓ 定时任务已设置"
echo ""
log_info "常用命令："
echo "  查看容器状态：  $SUDO docker ps -a | grep $DOCKER_CONTAINER"
echo "  查看容器日志：  $SUDO docker logs -f $DOCKER_CONTAINER"
echo "  手动执行监控：  $MONITOR_SCRIPT"
echo "  强制清理：      $MONITOR_SCRIPT force"
echo "  查看监控日志：  tail -f $LOG_FILE"
echo ""
log_info "部署脚本执行完毕！"
