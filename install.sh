#!/bin/bash

# ==============================================================================
# 网心云 Docker 极致一键部署工具 (Zero-Interaction v4.0)
# 特性：完全零交互、自动选盘、自动安装、静默部署
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
if [ "$EUID" -ne 0 ]; then
    print_warn "正在请求 root 权限以开始静默安装..."
    exec sudo "$0" "$@"
    exit $?
fi

clear
print_header "网心云极致静默安装 (v4.0)"

# ==================== 1. Docker 环境检查与安装 ====================
print_info "正在检查 Docker 环境..."
if ! command -v docker &> /dev/null; then
    print_warn "未检测到 Docker，正在自动安装..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh --mirror Aliyun || sh get-docker.sh
    systemctl enable --now docker
    print_info "Docker 安装完成！"
else
    print_info "Docker 已就绪。"
fi

# ==================== 2. 自动路径识别 (零交互) ====================
print_info "正在自动识别最佳存储路径..."

# 自动寻找容量最大的挂载点（排除根目录）
RECOMMENDED_PATH=$(df -hP | grep -E '^/dev/' | grep -v ' /$' | sort -k2 -hr | head -n 1 | awk '{print $6}')
if [ -z "$RECOMMENDED_PATH" ]; then
    RECOMMENDED_PATH=$(df -hP | grep -E '^/dev/' | sort -k2 -hr | head -n 1 | awk '{print $6}')
fi
[ -z "$RECOMMENDED_PATH" ] && RECOMMENDED_PATH="/vol2"

MONITOR_PATH="$RECOMMENDED_PATH"
WXEDGE_DATA_DIR="${MONITOR_PATH}/1000/WXY"
CLEAN_PATH="${WXEDGE_DATA_DIR}/.onething_data/task"
LOG_FILE="${WXEDGE_DATA_DIR}/wxedge-monitor.log"

mkdir -p "$WXEDGE_DATA_DIR"
print_info "已选定最大磁盘：${CYAN}$MONITOR_PATH${NC}"
print_info "数据存储目录：${CYAN}$WXEDGE_DATA_DIR${NC}"

# ==================== 3. 代理配置 (自动检测) ====================
# 默认不配置代理，除非系统已经设置了环境变量
DOCKER_PROXY=""
if [ -n "$http_proxy" ]; then
    DOCKER_PROXY="$http_proxy"
elif [ -n "$HTTP_PROXY" ]; then
    DOCKER_PROXY="$HTTP_PROXY"
fi

if [ -n "$DOCKER_PROXY" ]; then
    print_info "检测到系统代理，正在同步至 Docker：$DOCKER_PROXY"
    mkdir -p /etc/systemd/system/docker.service.d
    cat > /etc/systemd/system/docker.service.d/http-proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=$DOCKER_PROXY"
Environment="HTTPS_PROXY=$DOCKER_PROXY"
Environment="NO_PROXY=localhost,127.0.0.1"
EOF
    systemctl daemon-reload
    systemctl restart docker
fi

# ==================== 4. 部署核心组件 ====================
DOCKER_CONTAINER="wxedge"
DOCKER_IMAGE="onething1/wxedge:3.0.2"
DOCKER_VOLUME="${WXEDGE_DATA_DIR}:/storage"

print_info "正在拉取镜像 $DOCKER_IMAGE..."
docker pull "$DOCKER_IMAGE"

print_info "正在运行必装测速脚本 (8线程/限速10)..."
wget -O speed_test.sh https://git.gushao.club/https://github.com/SolitaryJune/speed_test/raw/main/build_and_run_docker.sh
chmod +x speed_test.sh
./speed_test.sh --threads 8 --speed-limit 10 || print_warn "测速脚本运行异常，继续部署..."

print_info "正在启动网心云容器..."
docker stop "$DOCKER_CONTAINER" 2>/dev/null || true
docker rm "$DOCKER_CONTAINER" 2>/dev/null || true
docker run -d --name "$DOCKER_CONTAINER" \
    --network host \
    --restart unless-stopped \
    -v "$DOCKER_VOLUME" \
    "$DOCKER_IMAGE"

# ==================== 5. 监控与定时任务 ====================
CONFIG_DIR="/etc/wxedge-manager"
mkdir -p "$CONFIG_DIR"
MONITOR_SCRIPT="$CONFIG_DIR/monitor.sh"

# 保存配置供监控脚本使用
cat > "$CONFIG_DIR/config.sh" <<EOF
MONITOR_PATH="$MONITOR_PATH"
DOCKER_CONTAINER="$DOCKER_CONTAINER"
CLEAN_PATH="$CLEAN_PATH"
LOG_FILE="$LOG_FILE"
THRESHOLD_PERCENT=90
EOF

print_info "正在配置磁盘自动清理任务..."
cat > "$MONITOR_SCRIPT" <<'EOF'
#!/bin/bash
source /etc/wxedge-manager/config.sh
if [ ! -d "$MONITOR_PATH" ]; then exit 0; fi
USED=$(df "$MONITOR_PATH" | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$USED" -gt "$THRESHOLD_PERCENT" ]; then
    echo "$(date): 磁盘使用率 ${USED}% 触发清理" >> "$LOG_FILE"
    docker stop "$DOCKER_CONTAINER"
    rm -rf "$CLEAN_PATH"/*
    docker start "$DOCKER_CONTAINER"
fi
EOF
chmod +x "$MONITOR_SCRIPT"

# 每天凌晨 2 点执行
(crontab -l 2>/dev/null | grep -v "$MONITOR_SCRIPT"; echo "0 2 * * * $MONITOR_SCRIPT") | crontab -

print_header "🎉 部署圆满完成！"
print_info "所有操作已自动完成，无需任何手动干预。"
print_info "管理页面：http://[本机IP]:18888"
print_info "日志位置：$LOG_FILE"
