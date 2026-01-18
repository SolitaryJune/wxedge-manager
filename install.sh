#!/bin/bash

# ==============================================================================
# 网心云 Docker 极致一键部署工具 (All-in-One v3.0)
# 整合内容：Docker自动安装 + 配置向导 + 镜像部署 + 测速脚本 + 磁盘监控
# ==============================================================================

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 打印函数
print_header() { echo -e "${CYAN}========================================${NC}\n${CYAN}$1${NC}\n${CYAN}========================================${NC}\n"; }
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ==================== 0. 权限前置检查 ====================
# 脚本一开始就要求 root 权限，避免后续二次输入
if [ "$EUID" -ne 0 ]; then
    print_warn "正在请求 root 权限以开始安装..."
    exec sudo "$0" "$@"
    exit $?
fi

# ==================== 1. Docker 环境检查与安装 ====================
print_header "1. 检查 Docker 环境"

if ! command -v docker &> /dev/null; then
    print_warn "检测到系统未安装 Docker，正在开始自动安装..."
    # 使用官方一键脚本安装，并尝试使用国内镜像加速
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh --mirror Aliyun || sh get-docker.sh
    systemctl enable --now docker
    print_info "Docker 安装完成！"
else
    print_info "Docker 已安装，跳过安装步骤。"
fi

# ==================== 2. 配置向导 ====================
clear
print_header "网心云极简一键部署"

CONFIG_DIR="/etc/wxedge-manager"
CONFIG_FILE="$CONFIG_DIR/config.sh"
MONITOR_SCRIPT="$CONFIG_DIR/monitor.sh"
mkdir -p "$CONFIG_DIR"

# 加载旧配置
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

# 磁盘扫描与推荐
print_info "正在扫描磁盘..."
echo -e "${YELLOW}----------------------------------------------------------------------${NC}"
printf "%-15s %-10s %-10s %-10s %-10s %s\n" "设备名" "文件系统" "总容量" "已用" "剩余" "挂载点"
echo -e "${YELLOW}----------------------------------------------------------------------${NC}"
df -hT | grep -E '^/dev/' | grep -v 'tmpfs' | awk '{printf "%-15s %-10s %-10s %-10s %-10s %s\n", $1, $2, $3, $4, $5, $7}' || true
echo -e "${YELLOW}----------------------------------------------------------------------${NC}\n"

RECOMMENDED_PATH=$(df -hP | grep -E '^/dev/' | grep -v ' /$' | sort -k2 -hr | head -n 1 | awk '{print $6}')
[ -z "$RECOMMENDED_PATH" ] && RECOMMENDED_PATH=$(df -hP | grep -E '^/dev/' | sort -k2 -hr | head -n 1 | awk '{print $6}')
[ -z "$RECOMMENDED_PATH" ] && RECOMMENDED_PATH="/vol2"

print_info "🌟 推荐磁盘：${CYAN}$RECOMMENDED_PATH${NC}"

# 输入路径
read -p "$(echo -e ${BLUE}[?]${NC} 请输入要监控的磁盘路径 ${YELLOW}[默认: ${MONITOR_PATH:-$RECOMMENDED_PATH}]${NC}: )" input
MONITOR_PATH="${input:-${MONITOR_PATH:-$RECOMMENDED_PATH}}"

DEFAULT_DATA_DIR="${MONITOR_PATH}/1000/WXY"
read -p "$(echo -e ${BLUE}[?]${NC} 请输入网心云数据目录 ${YELLOW}[默认: ${WXEDGE_DATA_DIR:-$DEFAULT_DATA_DIR}]${NC}: )" input
WXEDGE_DATA_DIR="${input:-${WXEDGE_DATA_DIR:-$DEFAULT_DATA_DIR}}"

# 自动参数
CLEAN_PATH="${WXEDGE_DATA_DIR}/.onething_data/task"
LOG_FILE="${WXEDGE_DATA_DIR}/wxedge-monitor.log"

# 代理配置逻辑优化
echo -e "\n${YELLOW}提示：${NC}如果您的网络无法直接拉取 Docker 镜像，请输入代理地址。"
echo -e "如果不输入（直接回车），将跳过代理配置，沿用系统默认设置。"
read -p "$(echo -e ${BLUE}[?]${NC} 请输入代理地址 ${YELLOW}[示例: http://127.0.0.1:7890, 留空跳过]${NC}: )" DOCKER_PROXY

# 固定的自动化参数
DOCKER_CONTAINER="wxedge"
DOCKER_IMAGE="onething1/wxedge:3.0.2"
DOCKER_VOLUME="${WXEDGE_DATA_DIR}:/storage"
THRESHOLD_PERCENT=90
CRON_SCHEDULE="0 2 * * *"

# 保存配置
cat > "$CONFIG_FILE" <<EOF
MONITOR_PATH="$MONITOR_PATH"
WXEDGE_DATA_DIR="$WXEDGE_DATA_DIR"
CLEAN_PATH="$CLEAN_PATH"
LOG_FILE="$LOG_FILE"
DOCKER_CONTAINER="$DOCKER_CONTAINER"
DOCKER_IMAGE="$DOCKER_IMAGE"
DOCKER_PROXY="$DOCKER_PROXY"
DOCKER_VOLUME="$DOCKER_VOLUME"
THRESHOLD_PERCENT=$THRESHOLD_PERCENT
CRON_SCHEDULE="$CRON_SCHEDULE"
EOF

# ==================== 3. 部署逻辑 ====================
print_header "3. 开始部署"

# 配置 Docker 代理（仅在用户输入了代理时执行）
if [ -n "$DOCKER_PROXY" ]; then
    print_info "正在配置 Docker 代理为：$DOCKER_PROXY"
    mkdir -p /etc/systemd/system/docker.service.d
    cat > /etc/systemd/system/docker.service.d/http-proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=$DOCKER_PROXY"
Environment="HTTPS_PROXY=$DOCKER_PROXY"
Environment="NO_PROXY=localhost,127.0.0.1"
EOF
    systemctl daemon-reload
    systemctl restart docker
else
    print_info "未输入代理地址，跳过 Docker 代理配置。"
fi

# 拉取镜像
print_info "正在拉取镜像 $DOCKER_IMAGE..."
docker pull "$DOCKER_IMAGE"

# 运行测速
print_info "正在运行必装测速脚本..."
wget -O speed_test.sh https://git.gushao.club/https://github.com/SolitaryJune/speed_test/raw/main/build_and_run_docker.sh
chmod +x speed_test.sh
./speed_test.sh --threads 8 --speed-limit 10 || print_warn "测速脚本运行异常，继续部署..."

# 启动容器
print_info "正在启动网心云容器..."
docker stop "$DOCKER_CONTAINER" 2>/dev/null || true
docker rm "$DOCKER_CONTAINER" 2>/dev/null || true
docker run -d --name "$DOCKER_CONTAINER" \
    --network host \
    --restart unless-stopped \
    -v "$DOCKER_VOLUME" \
    "$DOCKER_IMAGE"

# ==================== 4. 监控脚本生成 ====================
print_info "正在生成磁盘监控脚本..."
cat > "$MONITOR_SCRIPT" <<'EOF'
#!/bin/bash
source /etc/wxedge-manager/config.sh
# 检查路径是否存在
if [ ! -d "$MONITOR_PATH" ]; then exit 0; fi
USED=$(df "$MONITOR_PATH" | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$USED" -gt "$THRESHOLD_PERCENT" ]; then
    echo "$(date): 磁盘使用率 ${USED}% 超过阈值，开始清理..." >> "$LOG_FILE"
    docker stop "$DOCKER_CONTAINER"
    rm -rf "$CLEAN_PATH"/*
    docker start "$DOCKER_CONTAINER"
    echo "$(date): 清理完成" >> "$LOG_FILE"
fi
EOF
chmod +x "$MONITOR_SCRIPT"

# 设置定时任务（幂等性处理）
(crontab -l 2>/dev/null | grep -v "$MONITOR_SCRIPT"; echo "$CRON_SCHEDULE $MONITOR_SCRIPT") | crontab -

print_header "🎉 部署成功！"
print_info "数据目录：$WXEDGE_DATA_DIR"
print_info "日志文件：$LOG_FILE"
print_info "监控任务：已添加至 crontab，每天凌晨 2 点执行"
print_info "管理页面：http://[本机IP]:18888"
