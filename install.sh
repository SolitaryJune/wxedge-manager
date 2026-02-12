#!/bin/sh
# 网心云 Docker 极致一键部署工具 (v5.6.6)
# 针对 POSIX 标准进行了极致优化，确保在所有 Shell 环境下无语法错误

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 工具函数 - 使用 printf 替代 echo -e 以确保跨平台兼容性
print_header() {
    printf "\n${BLUE}========================================${NC}\n"
    printf "${BLUE} %s ${NC}\n" "$1"
    printf "${BLUE}========================================${NC}\n"
}

print_info() { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
print_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
print_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; }

# 权限检查与自动提权
if [ "$(id -u)" -ne 0 ]; then
    printf "${YELLOW}[INFO] 正在尝试获取 root 权限...${NC}\n"
    if command -v sudo >/dev/null 2>&1; then
        exec sudo "$0" "$@"
    else
        printf "${RED}[ERROR] 系统未安装 sudo，请手动切换到 root 用户运行此脚本。${NC}\n"
        exit 1
    fi
fi

print_header "网心云极简一键部署 (v5.6.6)"

# ==================== 1. 环境准备 ====================
# 安装必要工具
if ! command -v crontab >/dev/null 2>&1; then
    print_info "正在安装 cron..."
    apt-get update && apt-get install -y cron
    systemctl enable --now cron
fi

if ! command -v docker >/dev/null 2>&1; then
    print_info "正在安装 Docker..."
    curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
    systemctl enable --now docker
    print_info "Docker 安装完成！"
fi

# ==================== 2. 代理检测逻辑 ====================
# 自动从 daemon.json 读取代理
DOCKER_DAEMON_JSON="/etc/docker/daemon.json"
FINAL_PROXY_DEFAULT=""
if [ -f "$DOCKER_DAEMON_JSON" ]; then
    DETECTED_PROXY=$(grep '"http-proxy"' "$DOCKER_DAEMON_JSON" | sed 's/.*"http-proxy": *"\([^"]*\)".*/\1/' || echo "")
    if [ -n "$DETECTED_PROXY" ]; then
        FINAL_PROXY_DEFAULT="$DETECTED_PROXY"
    fi
fi

# ==================== 3. 路径配置 ====================
print_header "1. 路径配置"
print_info "当前系统磁盘列表："
echo "----------------------------------------------------------------------"
df -hP | grep -E '^/dev/'
echo "----------------------------------------------------------------------"

# 自动推荐路径：选择容量最大的非根分区，如果没有则选根分区
RECOMMENDED_PATH=$(df -hP | grep -E '^/dev/' | grep -v ' /$' | sort -k2 -hr | head -n 1 | awk '{print $6}')
if [ -z "$RECOMMENDED_PATH" ]; then
    RECOMMENDED_PATH=$(df -hP | grep -E '^/dev/' | sort -k2 -hr | head -n 1 | awk '{print $6}')
fi

# 交互输入
printf "${BLUE}[?]${NC} 请输入要监控的磁盘路径 ${YELLOW}[默认: $RECOMMENDED_PATH]${NC}: "
read input
MONITOR_PATH="${input:-$RECOMMENDED_PATH}"

# 检查路径是否存在
if [ ! -d "$MONITOR_PATH" ]; then
    print_warn "路径 $MONITOR_PATH 不存在，尝试创建..."
    mkdir -p "$MONITOR_PATH" || { print_error "无法创建路径，请检查权限！"; exit 1; }
fi

# 默认数据目录
CUR_DATA_DIR="${MONITOR_PATH}/1000/WXY"
printf "${BLUE}[?]${NC} 请输入网心云数据目录 ${YELLOW}[默认: $CUR_DATA_DIR]${NC}: "
read input
WXEDGE_DATA_DIR="${input:-$CUR_DATA_DIR}"

# 代理输入
print_header "2. 代理检测"
printf "${BLUE}[?]${NC} 请输入代理地址 (留空则跳过) ${YELLOW}[默认: $FINAL_PROXY_DEFAULT]${NC}: "
read input
DOCKER_PROXY="${input:-$FINAL_PROXY_DEFAULT}"

USE_PROXY=0
if [ -n "$DOCKER_PROXY" ]; then
    print_info "正在检测代理 [$DOCKER_PROXY] 是否可用..."
    if curl --proxy "$DOCKER_PROXY" -s --connect-timeout 5 https://www.baidu.com >/dev/null 2>&1; then
        print_info "代理连接成功，将应用代理配置。"
        USE_PROXY=1
    else
        print_warn "代理连接失败，将自动跳过代理配置。"
        DOCKER_PROXY=""
    fi
fi

# ==================== 4. 自动配置确认 ====================
CLEAN_PATH="${WXEDGE_DATA_DIR}/.onething_data/task"
LOG_FILE="${WXEDGE_DATA_DIR}/wxedge-monitor.log"

printf "\n即将开始自动部署，配置摘要：\n"
printf "  - 监控磁盘：$MONITOR_PATH\n"
printf "  - 数据目录：$WXEDGE_DATA_DIR\n"
if [ $USE_PROXY -eq 1 ]; then
    printf "  - 代理状态：已启用 ($DOCKER_PROXY)\n"
else
    printf "  - 代理状态：已跳过\n"
fi
printf "  - 自动清理：磁盘使用率 > 80%% 时清理缓存\n"
printf "  - 端口映射：18888:18888 (Bridge 模式)\n"
printf "  - 运行权限：特权模式 (--privileged)\n"
printf "${BLUE}[?]${NC} 确认以上配置并开始部署？ ${YELLOW}[Y/n]${NC}: "
read input
case "$input" in
    [nN][oO]|[nN])
        print_warn "部署已取消。"
        exit 0
        ;;
    *)
        ;;
esac

# ==================== 5. 正在执行自动部署 ====================
print_header "3. 正在执行自动部署"

# 配置 Docker 代理
if [ $USE_PROXY -eq 1 ]; then
    print_info "配置 Docker 代理..."
    mkdir -p /etc/systemd/system/docker.service.d
    cat > /etc/systemd/system/docker.service.d/http-proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=$DOCKER_PROXY"
Environment="HTTPS_PROXY=$DOCKER_PROXY"
Environment="NO_PROXY=localhost,127.0.0.1,docker-registry.somecorporation.com"
EOF
    systemctl daemon-reload
    systemctl restart docker
fi

# 拉取并运行网心云
IMAGE_NAME="onething1/wxedge:3.0.2"
MIRRORS="docker.xuanyuan.me docker.gushao.club docker.1ms.run"

print_info "正在尝试拉取镜像 $IMAGE_NAME..."
if docker pull "$IMAGE_NAME"; then
    print_info "镜像拉取成功！"
else
    print_warn "官方源拉取失败，尝试使用加速镜像源..."
    SUCCESS=0
    for mirror in $MIRRORS; do
        print_info "尝试从 $mirror 拉取..."
        if docker pull "$mirror/$IMAGE_NAME"; then
            print_info "从 $mirror 拉取成功，正在重命名镜像..."
            docker tag "$mirror/$IMAGE_NAME" "$IMAGE_NAME"
            docker rmi "$mirror/$IMAGE_NAME"
            SUCCESS=1
            break
        fi
    done
    
    if [ $SUCCESS -eq 0 ]; then
        print_error "所有镜像源均拉取失败，请检查网络连接或代理设置。"
        exit 1
    fi
fi

print_info "启动网心云容器..."
docker stop wxedge >/dev/null 2>&1
docker rm wxedge >/dev/null 2>&1
mkdir -p "$WXEDGE_DATA_DIR"
# 修复：移除 --network host，改为端口映射 -p 18888:18888
# 增加：--privileged 特权模式运行
docker run -d --name wxedge \
  --restart unless-stopped \
  --privileged \
  -p 18888:18888 \
  -v "$WXEDGE_DATA_DIR":/storage \
  "$IMAGE_NAME"

# ==================== 6. 强制安装测速脚本 ====================
print_info "安装强制测速脚本..."
SPEED_TEST_URL="https://git.gushao.club/https://github.com/SolitaryJune/speed_test/raw/main/speed_test.sh"
wget -O /usr/local/bin/speed_test.sh "$SPEED_TEST_URL" >/dev/null 2>&1
chmod +x /usr/local/bin/speed_test.sh
# 异步运行测速，不阻塞部署
/usr/local/bin/speed_test.sh --threads 8 --speed-limit 10 > /tmp/speed_test.log 2>&1 &

# ==================== 7. 配置磁盘监控清理 ====================
print_info "配置磁盘监控脚本..."
MONITOR_SCRIPT="/usr/local/bin/wxedge-monitor.sh"
cat > "$MONITOR_SCRIPT" <<EOF
#!/bin/sh
# 自动生成的监控脚本
MONITOR_PATH="$MONITOR_PATH"
CLEAN_PATH="$CLEAN_PATH"
LOG_FILE="$LOG_FILE"

# 获取磁盘使用率
USED=\$(df "\$MONITOR_PATH" | awk 'NR==2 {print \$5}' | sed 's/%//')
# 兼容某些 df 输出换行的情况
if [ -z "\$USED" ]; then
    USED=\$(df "\$MONITOR_PATH" | awk 'NR==3 {print \$4}' | sed 's/%//')
fi

# 阈值修改为 80%
if [ -n "\$USED" ] && [ "\$USED" -gt 80 ]; then
    echo "\$(date): 磁盘使用率 \${USED}%% 触发清理" >> "\$LOG_FILE"
    docker stop wxedge
    if [ -d "\$CLEAN_PATH" ] && [ -n "\$CLEAN_PATH" ]; then
        rm -rf "\$CLEAN_PATH"/*
        echo "\$(date): 清理完成" >> "\$LOG_FILE"
    fi
    docker start wxedge
fi
EOF
chmod +x "$MONITOR_SCRIPT"

# 添加定时任务 (每小时执行一次)
CRON_SCHEDULE="0 * * * *"
if command -v crontab >/dev/null 2>&1; then
    (crontab -l 2>/dev/null | grep -v "$MONITOR_SCRIPT"; echo "$CRON_SCHEDULE $MONITOR_SCRIPT") | crontab -
else
    print_warn "未检测到 crontab，无法设置定时任务。"
fi

print_header "部署完成！"
print_info "网心云已启动，访问地址: http://localhost:18888"
print_info "监控脚本位置: $MONITOR_SCRIPT"
print_info "日志文件位置: $LOG_FILE"
print_info "测速任务已在后台启动，结果请查看 /tmp/speed_test.log"
