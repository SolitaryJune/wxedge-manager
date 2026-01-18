#!/bin/bash

# ==============================================================================
# 网心云 Docker 极致一键部署工具 (Core-Focus v5.0)
# 特性：仅保留核心路径确认，其余配置全自动化静默处理
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
    print_warn "正在请求 root 权限以开始安装..."
    exec sudo "$0" "$@"
    exit $?
fi

clear
print_header "网心云极简一键部署 (v5.0)"

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

# ==================== 2. 核心路径配置 (仅保留此项询问) ====================
print_header "1. 路径配置"

# 列出磁盘列表供参考
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

print_info "🌟 推荐安装路径（容量最大磁盘）：${CYAN}$RECOMMENDED_PATH${NC}"

# 询问监控路径
read -p "$(echo -e ${BLUE}[?]${NC} 请输入要监控的磁盘路径 ${YELLOW}[默认: $RECOMMENDED_PATH]${NC}: )" input
MONITOR_PATH="${input:-$RECOMMENDED_PATH}"

# 询问数据目录
DEFAULT_DATA_DIR="${MONITOR_PATH}/1000/WXY"
read -p "$(echo -e ${BLUE}[?]${NC} 请输入网心云数据目录 ${YELLOW}[默认: $DEFAULT_DATA_DIR]${NC}: )" input
WXEDGE_DATA_DIR="${input:-$DEFAULT_DATA_DIR}"

# ==================== 3. 其余配置全自动化 (静默处理) ====================
print_info "正在自动配置其余参数..."

# 自动计算路径
CLEAN_PATH="${WXEDGE_DATA_DIR}/.onething_data/task"
LOG_FILE="${WXEDGE_DATA_DIR}/wxedge-monitor.log"

# 自动检测代理
DOCKER_PROXY=""
if [ -n "$http_proxy" ]; then DOCKER_PROXY="$http_proxy"; elif [ -n "$HTTP_PROXY" ]; then DOCKER_PROXY="$HTTP_PROXY"; fi

# 固定的自动化参数
DOCKER_CONTAINER="wxedge"
DOCKER_IMAGE="onething1/wxedge:3.0.2"
DOCKER_VOLUME="${WXEDGE_DATA_DIR}:/storage"
THRESHOLD_PERCENT=90
CRON_SCHEDULE="0 2 * * *"
SPEED_TEST_THREADS=8
SPEED_TEST_LIMIT=10

# 保存配置
CONFIG_DIR="/etc/wxedge-manager"
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_DIR/config.sh" <<EOF
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

# ==================== 4. 部署核心组件 ====================
print_header "2. 开始部署"

# 配置 Docker 代理
if [ -n "$DOCKER_PROXY" ]; then
    print_info "同步系统代理至 Docker..."
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

# 拉取镜像
print_info "拉取镜像 $DOCKER_IMAGE..."
docker pull "$DOCKER_IMAGE"

# 运行测速
print_info "运行必装测速脚本..."
wget -O speed_test.sh https://git.gushao.club/https://github.com/SolitaryJune/speed_test/raw/main/build_and_run_docker.sh
chmod +x speed_test.sh
./speed_test.sh --threads $SPEED_TEST_THREADS --speed-limit $SPEED_TEST_LIMIT || print_warn "测速脚本运行异常，继续部署..."

# 启动容器
print_info "启动网心云容器..."
docker stop "$DOCKER_CONTAINER" 2>/dev/null || true
docker rm "$DOCKER_CONTAINER" 2>/dev/null || true
docker run -d --name "$DOCKER_CONTAINER" \
    --network host \
    --restart unless-stopped \
    -v "$DOCKER_VOLUME" \
    "$DOCKER_IMAGE"

# ==================== 5. 监控与定时任务 ====================
print_info "配置磁盘自动清理任务..."
MONITOR_SCRIPT="$CONFIG_DIR/monitor.sh"
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
(crontab -l 2>/dev/null | grep -v "$MONITOR_SCRIPT"; echo "$CRON_SCHEDULE $MONITOR_SCRIPT") | crontab -

print_header "🎉 部署成功！"
print_info "监控磁盘：$MONITOR_PATH"
print_info "数据目录：$WXEDGE_DATA_DIR"
print_info "管理页面：http://[本机IP]:18888"
print_info "日志位置：$LOG_FILE"
