#!/bin/bash

# ==============================================================================
# 网心云 Docker 极致一键部署工具 (v5.4.0)
# 特性：优先读取 daemon.json，代理自动检测与回退，配置自动读取，一键到底
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
print_header() { echo -e "\n${CYAN}========================================${NC}\n${CYAN}$1${NC}\n${CYAN}========================================${NC}\n"; }
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ==================== 0. 权限前置检查 ====================
if [ "$EUID" -ne 0 ]; then
    print_warn "正在请求 root 权限以开始安装..."
    exec sudo "$0" "$@"
    exit $?
fi

clear
print_header "网心云极简一键部署 (v5.4.0)"

# ==================== 1. 配置读取逻辑 ====================
CONFIG_DIR="/etc/wxedge-manager"
CONFIG_FILE="$CONFIG_DIR/config.sh"
mkdir -p "$CONFIG_DIR"

# 默认参数
DOCKER_CONTAINER="wxedge"
DOCKER_IMAGE="onething1/wxedge:3.0.2"
THRESHOLD_PERCENT=90
CRON_SCHEDULE="0 2 * * *"
DOCKER_DAEMON_JSON="/etc/docker/daemon.json"

# 1.1 尝试从 daemon.json 读取代理
DETECTED_PROXY=""
if [ -f "$DOCKER_DAEMON_JSON" ]; then
    # 尝试提取 proxies 字段中的 http-proxy (需要 jq，如果没有则用 grep 简单提取)
    if command -v jq &> /dev/null; then
        DETECTED_PROXY=$(jq -r '.proxies."http-proxy" // empty' "$DOCKER_DAEMON_JSON")
    else
        DETECTED_PROXY=$(grep -oP '"http-proxy":\s*"\K[^"]+' "$DOCKER_DAEMON_JSON" || true)
    fi
fi

# 1.2 读取本地已保存配置
if [ -f "$CONFIG_FILE" ]; then
    print_info "检测到本地配置，正在加载..."
    source "$CONFIG_FILE"
fi

# 1.3 确定代理默认值：优先已保存配置 > daemon.json > 留空
FINAL_PROXY_DEFAULT="${DOCKER_PROXY:-$DETECTED_PROXY}"

# ==================== 2. Docker 环境检查与安装 ====================
print_info "正在检查 Docker 环境..."
if ! command -v docker &> /dev/null; then
    print_warn "未检测到 Docker，正在自动安装..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh --mirror Aliyun || sh get-docker.sh || { print_error "Docker 安装失败，请检查网络。"; exit 1; }
    systemctl enable --now docker
    print_info "Docker 安装完成！"
else
    print_info "Docker 已就绪。"
fi

# ==================== 3. 核心路径配置 ====================
print_header "1. 路径配置"

# 列出磁盘列表
print_info "当前系统磁盘列表："
echo -e "${YELLOW}----------------------------------------------------------------------${NC}"
printf "%-15s %-10s %-10s %-10s %-10s %s\n" "设备名" "文件系统" "总容量" "已用" "剩余" "挂载点"
echo -e "${YELLOW}----------------------------------------------------------------------${NC}"
df -hT | grep -E '^/dev/' | grep -v 'tmpfs' | awk '{printf "%-15s %-10s %-10s %-10s %-10s %s\n", $1, $2, $3, $4, $5, $7}' || true
echo -e "${YELLOW}----------------------------------------------------------------------${NC}\n"

# 自动寻找容量最大的挂载点作为推荐
RECOMMENDED_PATH=$(df -hP | grep -E '^/dev/' | grep -v ' /$' | sort -k2 -hr | head -n 1 | awk '{print $6}')
if [ -z "$RECOMMENDED_PATH" ]; then
    RECOMMENDED_PATH=$(df -hP | grep -E '^/dev/' | sort -k2 -hr | head -n 1 | awk '{print $6}')
fi
[ -z "$RECOMMENDED_PATH" ] && RECOMMENDED_PATH="/vol2"

# 优先使用已保存的路径
CUR_MONITOR_PATH="${MONITOR_PATH:-$RECOMMENDED_PATH}"
while true; do
    read -p "$(echo -e ${BLUE}[?]${NC} 请输入要监控的磁盘路径 ${YELLOW}[默认: $CUR_MONITOR_PATH]${NC}: )" input
    MONITOR_PATH="${input:-$CUR_MONITOR_PATH}"
    if [ -d "$MONITOR_PATH" ]; then break; else print_error "路径 [$MONITOR_PATH] 不存在，请重新输入！"; fi
done

# 优先使用已保存的数据目录
CUR_DATA_DIR="${WXEDGE_DATA_DIR:-${MONITOR_PATH}/1000/WXY}"
read -p "$(echo -e ${BLUE}[?]${NC} 请输入网心云数据目录 ${YELLOW}[默认: $CUR_DATA_DIR]${NC}: )" input
WXEDGE_DATA_DIR="${input:-$CUR_DATA_DIR}"

# ==================== 4. 代理检测逻辑 ====================
print_header "2. 代理检测"

read -p "$(echo -e ${BLUE}[?]${NC} 请输入代理地址 (留空则跳过) ${YELLOW}[默认: $FINAL_PROXY_DEFAULT]${NC}: )" input
DOCKER_PROXY="${input:-$FINAL_PROXY_DEFAULT}"

USE_PROXY=false
if [ -z "$DOCKER_PROXY" ]; then
    print_info "未设置代理，将直接使用本地网络。"
else
    print_info "正在检测代理 [$DOCKER_PROXY] 是否可用..."
    # 尝试通过代理访问 Docker Hub 或 Google
    if curl --proxy "$DOCKER_PROXY" -s --connect-timeout 5 https://registry-1.docker.io > /dev/null || \
       curl --proxy "$DOCKER_PROXY" -s --connect-timeout 5 https://www.google.com > /dev/null; then
        print_info "代理连接成功，将应用代理配置。"
        USE_PROXY=true
    else
        print_warn "代理连接失败 (Connection Refused)，将自动跳过代理配置。"
        DOCKER_PROXY=""
    fi
fi

# ==================== 5. 自动配置确认 ====================
CLEAN_PATH="${WXEDGE_DATA_DIR}/.onething_data/task"
LOG_FILE="${WXEDGE_DATA_DIR}/wxedge-monitor.log"
DOCKER_VOLUME="${WXEDGE_DATA_DIR}:/storage"

echo -e "\n${CYAN}即将开始自动部署，配置摘要：${NC}"
echo -e "  - 监控磁盘：$MONITOR_PATH"
echo -e "  - 数据目录：$WXEDGE_DATA_DIR"
echo -e "  - 代理状态：$( [ "$USE_PROXY" = true ] && echo "已启用 ($DOCKER_PROXY)" || echo "已跳过" )"
echo -e "  - 自动清理：磁盘使用率 > 90% 时清理缓存"

read -p "$(echo -e ${BLUE}[?]${NC} 确认以上配置并开始部署？ ${YELLOW}[Y/n]${NC}: )" confirm
if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
    print_warn "部署已取消。"
    exit 0
fi

# ==================== 6. 自动部署流程 ====================
print_header "3. 正在执行自动部署"

# 保存配置
cat > "$CONFIG_FILE" <<EOF
MONITOR_PATH="$MONITOR_PATH"
WXEDGE_DATA_DIR="$WXEDGE_DATA_DIR"
CLEAN_PATH="$CLEAN_PATH"
LOG_FILE="$LOG_FILE"
DOCKER_CONTAINER="$DOCKER_CONTAINER"
DOCKER_IMAGE="$DOCKER_IMAGE"
DOCKER_VOLUME="$DOCKER_VOLUME"
THRESHOLD_PERCENT=$THRESHOLD_PERCENT
CRON_SCHEDULE="$CRON_SCHEDULE"
DOCKER_PROXY="$DOCKER_PROXY"
EOF

# 应用 Docker 代理 (使用 systemd 方式，这是最通用的)
if [ "$USE_PROXY" = true ]; then
    print_info "配置 Docker 代理..."
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
    print_info "清理旧的 Docker 代理配置..."
    rm -f /etc/systemd/system/docker.service.d/http-proxy.conf
    systemctl daemon-reload
    systemctl restart docker
fi

# 拉取镜像
print_info "拉取镜像 $DOCKER_IMAGE..."
docker pull "$DOCKER_IMAGE" || { print_warn "镜像拉取失败，尝试直接拉取..."; docker pull "$DOCKER_IMAGE"; }

# 运行测速
print_info "运行必装测速脚本..."
wget -q -O speed_test.sh https://git.gushao.club/https://github.com/SolitaryJune/speed_test/raw/main/build_and_run_docker.sh || true
if [ -f speed_test.sh ]; then
    chmod +x speed_test.sh
    ./speed_test.sh --threads 8 --speed-limit 10 || print_warn "测速脚本运行异常，继续部署..."
fi

# 启动容器
print_info "启动网心云容器..."
mkdir -p "$WXEDGE_DATA_DIR"
docker stop "$DOCKER_CONTAINER" 2>/dev/null || true
docker rm "$DOCKER_CONTAINER" 2>/dev/null || true
docker run -d --name "$DOCKER_CONTAINER" \
    --network host \
    --restart unless-stopped \
    -v "$DOCKER_VOLUME" \
    "$DOCKER_IMAGE"

# 配置监控脚本
print_info "配置磁盘自动清理任务..."
MONITOR_SCRIPT="$CONFIG_DIR/monitor.sh"
cat > "$MONITOR_SCRIPT" <<'EOF'
#!/bin/bash
source /etc/wxedge-manager/config.sh
if [ ! -d "$MONITOR_PATH" ]; then exit 0; fi
USED=$(df "$MONITOR_PATH" | awk 'NR==2 {print $5}' | sed 's/%//')
if [[ ! "$USED" =~ ^[0-9]+$ ]]; then USED=$(df "$MONITOR_PATH" | awk 'NR==3 {print $4}' | sed 's/%//'); fi
if [ "$USED" -gt "$THRESHOLD_PERCENT" ]; then
    echo "$(date): 磁盘使用率 ${USED}% 触发清理" >> "$LOG_FILE"
    docker stop "$DOCKER_CONTAINER"
    [ -n "$CLEAN_PATH" ] && [ -d "$CLEAN_PATH" ] && rm -rf "$CLEAN_PATH"/*
    docker start "$DOCKER_CONTAINER"
fi
EOF
chmod +x "$MONITOR_SCRIPT"

# 设置定时任务
(crontab -l 2>/dev/null | grep -v "$MONITOR_SCRIPT"; echo "$CRON_SCHEDULE $MONITOR_SCRIPT") | crontab -

print_header "🎉 部署圆满成功！"
print_info "管理页面：http://[本机IP]:18888"
print_info "日志位置：$LOG_FILE"
