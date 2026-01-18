#!/bin/bash

# 网心云Docker管理工具 - 极致自动化配置向导
# 仅保留核心路径和代理配置，其余全部自动处理

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

# 开始配置
clear
print_header "网心云Docker管理工具 - 极简配置向导"

if [ -f "$CONFIG_FILE" ]; then
    print_warn "检测到已存在的配置文件，将自动加载旧配置作为默认值。"
    source "$CONFIG_FILE"
    backup_file="${CONFIG_FILE}.backup.$(date +%Y%m%d%H%M%S)"
    cp "$CONFIG_FILE" "$backup_file"
fi

# ==================== 1. 路径配置 ====================
print_header "1. 路径配置"

# 列出磁盘列表
print_info "正在扫描您的系统磁盘..."
echo -e "${YELLOW}----------------------------------------------------------------------${NC}"
printf "%-15s %-10s %-10s %-10s %-10s %s\n" "设备名" "文件系统" "总容量" "已用" "剩余" "挂载点"
echo -e "${YELLOW}----------------------------------------------------------------------${NC}"
df -hT | grep -E '^/dev/' | grep -v 'tmpfs' | awk '{printf "%-15s %-10s %-10s %-10s %-10s %s\n", $1, $2, $3, $4, $5, $7}' || true
echo -e "${YELLOW}----------------------------------------------------------------------${NC}"
echo ""

# 自动寻找容量最大的挂载点作为推荐
RECOMMENDED_PATH=$(df -hP | grep -E '^/dev/' | grep -v ' /$' | sort -k2 -hr | head -n 1 | awk '{print $6}')
if [ -z "$RECOMMENDED_PATH" ]; then
    RECOMMENDED_PATH=$(df -hP | grep -E '^/dev/' | sort -k2 -hr | head -n 1 | awk '{print $6}')
fi
[ -z "$RECOMMENDED_PATH" ] && RECOMMENDED_PATH="/vol2"

print_info "💡 小贴士：网心云建议安装在剩余空间最大的磁盘上。"
print_info "🌟 系统推荐磁盘：${CYAN}$RECOMMENDED_PATH${NC}"
echo ""

# 监控路径
while true; do
    read_input "请输入要监控的磁盘路径" "${MONITOR_PATH:-$RECOMMENDED_PATH}" MONITOR_PATH
    if validate_path "$MONITOR_PATH"; then
        break
    else
        print_error "路径不存在，请重新输入。"
    fi
done

# 数据目录
DEFAULT_DATA_DIR="${MONITOR_PATH}/1000/WXY"
read_input "请输入网心云数据目录" "${WXEDGE_DATA_DIR:-$DEFAULT_DATA_DIR}" WXEDGE_DATA_DIR

# 自动计算清理路径和日志路径
CLEAN_PATH="${WXEDGE_DATA_DIR}/.onething_data/task"
LOG_FILE="${WXEDGE_DATA_DIR}/wxedge-monitor.log"

# ==================== 2. 网络与Docker配置 ====================
print_header "2. 网络与Docker配置"

# 代理地址
echo -e "由于 Docker 官方镜像站访问受限，我们需要配置代理来拉取镜像。"
read_input "请输入代理地址" "${DOCKER_PROXY:-http://127.0.0.1:7890}" DOCKER_PROXY

# 自动配置项（不再询问）
DOCKER_CONTAINER="${DOCKER_CONTAINER:-wxedge}"
DOCKER_IMAGE="onething1/wxedge:3.0.2"
DOCKER_MOUNT_PATH="/storage"
DOCKER_VOLUME="${WXEDGE_DATA_DIR}:${DOCKER_MOUNT_PATH}"
DOCKER_NETWORK="host"
DOCKER_RESTART="unless-stopped"
DOCKER_PRIVILEGED="${DOCKER_PRIVILEGED:-false}"
DOCKER_EXTRA_ARGS="${DOCKER_EXTRA_ARGS:-}"

# ==================== 3. 监控与测速自动配置 ====================
print_header "3. 自动化参数配置"

# 监控参数
THRESHOLD_PERCENT="${THRESHOLD_PERCENT:-90}"
STOP_TIMEOUT=30
MAX_RETRY=3
RETRY_INTERVAL=5

# 测速参数
SPEED_TEST_URL="https://git.gushao.club/https://github.com/SolitaryJune/speed_test/raw/main/build_and_run_docker.sh"
SPEED_TEST_THREADS=8
SPEED_TEST_LIMIT=10
RUN_SPEED_TEST_ON_DEPLOY="true"

# 定时任务
CRON_SCHEDULE="${CRON_SCHEDULE:-0 2 * * *}"

print_info "以下参数已自动配置完成："
echo -e "  - 容器名称：${CYAN}$DOCKER_CONTAINER${NC}"
echo -e "  - 镜像版本：${CYAN}$DOCKER_IMAGE${NC}"
echo -e "  - 挂载路径：${CYAN}$DOCKER_VOLUME${NC}"
echo -e "  - 磁盘阈值：${CYAN}${THRESHOLD_PERCENT}%${NC}"
echo -e "  - 测速参数：${CYAN}${SPEED_TEST_THREADS}线程 / 限速${SPEED_TEST_LIMIT}${NC}"
echo -e "  - 定时任务：${CYAN}每天凌晨 2 点${NC}"
echo ""

if ! read_confirm "确认以上配置并保存？" "y"; then
    print_warn "配置已取消。"
    exit 0
fi

# ==================== 保存配置 ====================
cat > "$CONFIG_FILE" <<EOF
#!/bin/bash
# 网心云Docker管理配置文件 - 自动生成
MONITOR_PATH="$MONITOR_PATH"
WXEDGE_DATA_DIR="$WXEDGE_DATA_DIR"
CLEAN_PATH="$CLEAN_PATH"
LOG_FILE="$LOG_FILE"
DOCKER_CONTAINER="$DOCKER_CONTAINER"
DOCKER_IMAGE="$DOCKER_IMAGE"
DOCKER_PROXY="$DOCKER_PROXY"
DOCKER_VOLUME="$DOCKER_VOLUME"
DOCKER_NETWORK="$DOCKER_NETWORK"
DOCKER_PORT_MAP=""
DOCKER_RESTART="$DOCKER_RESTART"
DOCKER_PRIVILEGED="$DOCKER_PRIVILEGED"
DOCKER_EXTRA_ARGS="$DOCKER_EXTRA_ARGS"
THRESHOLD_PERCENT=$THRESHOLD_PERCENT
STOP_TIMEOUT=$STOP_TIMEOUT
MAX_RETRY=$MAX_RETRY
RETRY_INTERVAL=$RETRY_INTERVAL
SPEED_TEST_URL="$SPEED_TEST_URL"
SPEED_TEST_THREADS=$SPEED_TEST_THREADS
SPEED_TEST_LIMIT=$SPEED_TEST_LIMIT
RUN_SPEED_TEST_ON_DEPLOY="$RUN_SPEED_TEST_ON_DEPLOY"
CRON_SCHEDULE="$CRON_SCHEDULE"
EOF

chmod 644 "$CONFIG_FILE"
print_info "配置已保存，请运行：sudo ./deploy.sh"
