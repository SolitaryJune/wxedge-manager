#!/bin/bash

# 网心云Docker管理工具 - 交互式配置向导
# 用于首次配置或重新配置系统参数

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.sh"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 打印标题
print_header() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
}

# 打印提示
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# 打印警告
print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# 打印错误
print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 打印问题
print_question() {
    echo -e "${BLUE}[?]${NC} $1"
}

# 读取用户输入（带默认值）
read_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    if [ -n "$default" ]; then
        read -p "$(echo -e ${BLUE}[?]${NC} $prompt ${YELLOW}[默认: $default]${NC}: )" input
        eval "$var_name=\"${input:-$default}\""
    else
        read -p "$(echo -e ${BLUE}[?]${NC} $prompt: )" input
        eval "$var_name=\"$input\""
    fi
}

# 读取Yes/No确认
read_confirm() {
    local prompt="$1"
    local default="$2"
    
    if [ "$default" = "y" ]; then
        read -p "$(echo -e ${BLUE}[?]${NC} $prompt ${YELLOW}[Y/n]${NC}: )" -n 1 -r
    else
        read -p "$(echo -e ${BLUE}[?]${NC} $prompt ${YELLOW}[y/N]${NC}: )" -n 1 -r
    fi
    echo
    
    if [ "$default" = "y" ]; then
        [[ $REPLY =~ ^[Nn]$ ]] && return 1 || return 0
    else
        [[ $REPLY =~ ^[Yy]$ ]] && return 0 || return 1
    fi
}

# 验证路径是否存在
validate_path() {
    local path="$1"
    if [ -d "$path" ]; then
        return 0
    else
        return 1
    fi
}

# 验证URL格式
validate_url() {
    local url="$1"
    if [[ "$url" =~ ^https?:// ]] || [[ "$url" =~ ^socks5:// ]]; then
        return 0
    else
        return 1
    fi
}

# 开始配置
clear
print_header "网心云Docker管理工具 - 配置向导"

echo "欢迎使用配置向导！"
echo "本向导将帮助您配置所有必要的参数。"
echo "您可以按 Enter 键接受默认值（如果有）。"
echo ""

if [ -f "$CONFIG_FILE" ]; then
    print_warn "检测到已存在的配置文件：$CONFIG_FILE"
    if read_confirm "是否要重新配置？（将备份现有配置）" "n"; then
        backup_file="${CONFIG_FILE}.backup.$(date +%Y%m%d%H%M%S)"
        cp "$CONFIG_FILE" "$backup_file"
        print_info "已备份现有配置到：$backup_file"
    else
        print_info "配置向导已取消"
        exit 0
    fi
fi

echo ""

# ==================== 路径配置 ====================
print_header "1. 路径配置"

# 监控路径
while true; do
    read_input "请输入要监控的磁盘路径" "/vol2" MONITOR_PATH
    if validate_path "$MONITOR_PATH"; then
        print_info "路径验证成功：$MONITOR_PATH"
        break
    else
        print_error "路径不存在：$MONITOR_PATH"
        if read_confirm "是否继续使用此路径？（部署时会创建）" "n"; then
            break
        fi
    fi
done

# 数据目录
read_input "请输入网心云数据目录" "/vol2/1000/WXY" WXEDGE_DATA_DIR

# 清理路径
read_input "请输入需要清理的task目录" "${WXEDGE_DATA_DIR}/.onething_data/task" CLEAN_PATH

# 日志文件
read_input "请输入日志文件路径" "/var/log/wxedge-monitor.log" LOG_FILE

echo ""

# ==================== Docker配置 ====================
print_header "2. Docker配置"

# 容器名称
read_input "请输入容器名称" "wxedge" DOCKER_CONTAINER

# 镜像名称
print_info "常见的网心云镜像名称："
echo "  - onething1/wxedge:3.0.2"
echo "  - registry.hub.docker.com/onething1/wxedge:3.0.2"
read_input "请输入Docker镜像名称（包含版本号）" "onething1/wxedge:3.0.2" DOCKER_IMAGE

# 代理地址
print_info "Docker代理示例："
echo "  - http://127.0.0.1:7890"
echo "  - http://proxy.example.com:8080"
echo "  - socks5://127.0.0.1:1080"
read_input "请输入Docker代理地址" "http://127.0.0.1:7890" DOCKER_PROXY

# 容器内挂载路径
read_input "请输入容器内的挂载路径" "/storage" DOCKER_MOUNT_PATH
DOCKER_VOLUME="${WXEDGE_DATA_DIR}:${DOCKER_MOUNT_PATH}"

# 网络模式
print_info "网络模式选项："
echo "  - host: 使用主机网络（推荐，性能最好）"
echo "  - bridge: 使用桥接网络（需手动映射端口）"
if read_confirm "是否使用host网络模式？" "y"; then
    DOCKER_NETWORK="host"
    DOCKER_PORT_MAP=""
else
    DOCKER_NETWORK="bridge"
    read_input "请输入端口映射配置（格式：宿主机端口:容器端口）" "18888:18888" DOCKER_PORT_MAP
fi

# 重启策略
print_info "重启策略选项："
echo "  - always: 总是重启"
echo "  - unless-stopped: 除非手动停止，否则总是重启（推荐）"
echo "  - on-failure: 仅在失败时重启"
echo "  - no: 不自动重启"
read_input "请选择重启策略" "unless-stopped" DOCKER_RESTART

# 特权模式
if read_confirm "是否启用特权模式（privileged）？" "n"; then
    DOCKER_PRIVILEGED="true"
else
    DOCKER_PRIVILEGED="false"
fi

# 额外参数
print_info "您可以添加额外的Docker运行参数，例如："
echo "  - --memory=2g --cpus=2"
echo "  - -e ENV_VAR=value"
read_input "请输入额外的Docker参数（可留空）" "" DOCKER_EXTRA_ARGS

echo ""

# ==================== 监控配置 ====================
print_header "3. 监控配置"

# 磁盘阈值
read_input "请输入磁盘使用率阈值（百分比，1-99）" "90" THRESHOLD_PERCENT

# 容器停止超时
read_input "请输入容器停止超时时间（秒）" "30" STOP_TIMEOUT

# 最大重试次数
read_input "请输入容器启动最大重试次数" "3" MAX_RETRY

# 重试间隔
read_input "请输入重试间隔（秒）" "5" RETRY_INTERVAL

echo ""

# ==================== 测速脚本配置 ====================
print_header "4. 测速脚本配置"

print_info "测速脚本为必装项，正在配置参数..."
# 测速脚本URL
read_input "请输入测速脚本下载地址" "https://git.gushao.club/https://github.com/SolitaryJune/speed_test/raw/main/build_and_run_docker.sh" SPEED_TEST_URL

# 线程数
read_input "请输入测速线程数" "8" SPEED_TEST_THREADS

# 限速
read_input "请输入测速限速值" "10" SPEED_TEST_LIMIT

RUN_SPEED_TEST_ON_DEPLOY="true"

echo ""

# ==================== 定时任务配置 ====================
print_header "5. 定时任务配置"

print_info "定时任务使用cron格式：分 时 日 月 周"
echo "示例："
echo "  - 0 2 * * *    每天凌晨2点"
echo "  - 0 */6 * * *  每6小时"
echo "  - 0 3 * * 0    每周日凌晨3点"
read_input "请输入定时任务执行时间（cron格式）" "0 2 * * *" CRON_SCHEDULE

echo ""

# ==================== 配置确认 ====================
print_header "配置摘要"

echo "路径配置："
echo "  监控路径：$MONITOR_PATH"
echo "  数据目录：$WXEDGE_DATA_DIR"
echo "  清理路径：$CLEAN_PATH"
echo "  日志文件：$LOG_FILE"
echo ""
echo "Docker配置："
echo "  容器名称：$DOCKER_CONTAINER"
echo "  镜像名称：$DOCKER_IMAGE"
echo "  代理地址：$DOCKER_PROXY"
echo "  挂载配置：$DOCKER_VOLUME"
echo "  网络模式：$DOCKER_NETWORK"
echo "  重启策略：$DOCKER_RESTART"
echo "  特权模式：$DOCKER_PRIVILEGED"
echo "  额外参数：${DOCKER_EXTRA_ARGS:-无}"
echo ""
echo "监控配置："
echo "  磁盘阈值：${THRESHOLD_PERCENT}%"
echo "  停止超时：${STOP_TIMEOUT}秒"
echo "  最大重试：${MAX_RETRY}次"
echo "  重试间隔：${RETRY_INTERVAL}秒"
echo ""
echo "测速配置："
echo "  脚本地址：$SPEED_TEST_URL"
echo "  线程数：$SPEED_TEST_THREADS"
echo "  限速值：$SPEED_TEST_LIMIT"
echo ""
echo "定时任务："
echo "  执行时间：$CRON_SCHEDULE"
echo ""

if ! read_confirm "确认以上配置并保存？" "y"; then
    print_warn "配置已取消，未保存任何更改"
    exit 0
fi

# ==================== 保存配置 ====================
print_header "保存配置"

cat > "$CONFIG_FILE" <<EOF
#!/bin/bash
# 网心云Docker管理配置文件
# 由配置向导自动生成于 $(date '+%Y-%m-%d %H:%M:%S')

# ==================== 路径配置 ====================
# 监控的磁盘路径
MONITOR_PATH="$MONITOR_PATH"

# 网心云数据目录
WXEDGE_DATA_DIR="$WXEDGE_DATA_DIR"

# 需要清理的task目录
CLEAN_PATH="$CLEAN_PATH"

# 日志文件路径
LOG_FILE="$LOG_FILE"

# ==================== Docker配置 ====================
# 容器名称
DOCKER_CONTAINER="$DOCKER_CONTAINER"

# 镜像名称
DOCKER_IMAGE="$DOCKER_IMAGE"

# Docker代理地址
DOCKER_PROXY="$DOCKER_PROXY"

# 容器挂载配置（格式：宿主机路径:容器内路径）
DOCKER_VOLUME="$DOCKER_VOLUME"

# 网络模式（host 或 bridge）
DOCKER_NETWORK="$DOCKER_NETWORK"

# 端口映射（仅在 bridge 模式下生效）
DOCKER_PORT_MAP="$DOCKER_PORT_MAP"

# 重启策略（always, unless-stopped, on-failure, no）
DOCKER_RESTART="$DOCKER_RESTART"

# 是否需要特权模式（true/false）
DOCKER_PRIVILEGED="$DOCKER_PRIVILEGED"

# 额外的Docker运行参数
DOCKER_EXTRA_ARGS="$DOCKER_EXTRA_ARGS"

# ==================== 监控配置 ====================
# 磁盘使用率阈值（百分比，超过此值触发清理）
THRESHOLD_PERCENT=$THRESHOLD_PERCENT

# 容器停止超时时间（秒）
STOP_TIMEOUT=$STOP_TIMEOUT

# 容器启动最大重试次数
MAX_RETRY=$MAX_RETRY

# 重试间隔（秒）
RETRY_INTERVAL=$RETRY_INTERVAL

# ==================== 测速脚本配置 ====================
# 测速脚本下载地址
SPEED_TEST_URL="$SPEED_TEST_URL"

# 测速线程数
SPEED_TEST_THREADS=$SPEED_TEST_THREADS

# 测速限速
SPEED_TEST_LIMIT=$SPEED_TEST_LIMIT

# 是否在部署时运行测速脚本（true/false）
RUN_SPEED_TEST_ON_DEPLOY="$RUN_SPEED_TEST_ON_DEPLOY"

# ==================== 定时任务配置 ====================
# 监控脚本执行时间（cron格式：分 时 日 月 周）
CRON_SCHEDULE="$CRON_SCHEDULE"
EOF

chmod 644 "$CONFIG_FILE"
print_info "配置已保存到：$CONFIG_FILE"

echo ""
print_header "配置完成"

print_info "下一步操作："
echo "  1. 运行部署脚本：sudo ./deploy.sh"
echo "  2. 查看使用说明：cat README.md"
echo "  3. 重新配置：./setup.sh"
echo ""

print_info "感谢使用网心云Docker管理工具！"
