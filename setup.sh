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

# 开始配置
clear
print_header "网心云Docker管理工具 - 配置向导"

echo "欢迎使用配置向导！"
echo "本向导将帮助您配置所有必要的参数。"
echo "您可以按 Enter 键接受默认值（如果有）。"
echo ""

if [ -f "$CONFIG_FILE" ]; then
    print_warn "检测到已存在的配置文件：$CONFIG_FILE"
    if read_confirm "是否加载现有配置作为默认值？" "y"; then
        source "$CONFIG_FILE"
        print_info "已加载现有配置"
    fi
    backup_file="${CONFIG_FILE}.backup.$(date +%Y%m%d%H%M%S)"
    cp "$CONFIG_FILE" "$backup_file"
    print_info "已备份当前配置到：$backup_file"
fi

echo ""

# ==================== 路径配置 ====================
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
# 排除根目录，优先寻找挂载在 /vol 或 /mnt 等位置的大容量磁盘
RECOMMENDED_PATH=$(df -hP | grep -E '^/dev/' | grep -v ' /$' | sort -k2 -hr | head -n 1 | awk '{print $6}')
# 如果没找到非根目录的大盘，再考虑根目录
if [ -z "$RECOMMENDED_PATH" ]; then
    RECOMMENDED_PATH=$(df -hP | grep -E '^/dev/' | sort -k2 -hr | head -n 1 | awk '{print $6}')
fi
# 兜底方案
if [ -z "$RECOMMENDED_PATH" ]; then
    RECOMMENDED_PATH="/vol2"
fi

print_info "💡 小贴士：网心云建议安装在剩余空间最大的机械硬盘（HDD）上。"
print_info "🌟 系统为您自动选中的最佳磁盘是：${CYAN}$RECOMMENDED_PATH${NC}"
echo ""

# 监控路径
while true; do
    echo -e "${BLUE}[步骤 1/2]${NC} 请确认要监控的磁盘挂载点。"
    echo -e "（脚本会监控这个盘的剩余空间，快满时自动清理缓存）"
    # 强制使用检测到的最大磁盘作为默认值，除非用户之前已经配置过其他路径
    CURRENT_DEFAULT="${MONITOR_PATH:-$RECOMMENDED_PATH}"
    read_input "请输入磁盘路径" "$CURRENT_DEFAULT" MONITOR_PATH
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
echo -e "\n${BLUE}[步骤 2/2]${NC} 请确认网心云的数据存储目录。"
echo -e "（这是网心云存放缓存文件的地方，建议保持默认）"
if [ -z "$WXEDGE_DATA_DIR" ] || [[ "$WXEDGE_DATA_DIR" != "$MONITOR_PATH"* ]]; then
    DEFAULT_DATA_DIR="${MONITOR_PATH}/1000/WXY"
else
    DEFAULT_DATA_DIR="$WXEDGE_DATA_DIR"
fi
read_input "请输入数据目录" "$DEFAULT_DATA_DIR" WXEDGE_DATA_DIR

# 自动计算清理路径和日志路径（不再询问用户）
CLEAN_PATH="${WXEDGE_DATA_DIR}/.onething_data/task"
LOG_FILE="${WXEDGE_DATA_DIR}/wxedge-monitor.log"

print_info "路径自动关联完成："
echo -e "  - 自动清理路径：${CYAN}$CLEAN_PATH${NC}"
echo -e "  - 自动日志路径：${CYAN}$LOG_FILE${NC}"

echo ""

# ==================== Docker配置 ====================
print_header "2. Docker配置"

# 容器名称
read_input "请输入容器名称" "${DOCKER_CONTAINER:-wxedge}" DOCKER_CONTAINER

# 镜像名称
print_info "镜像版本已锁定为：onething1/wxedge:3.0.2"
DOCKER_IMAGE="onething1/wxedge:3.0.2"

# 代理地址
echo -e "\n${BLUE}[网络设置]${NC} 由于 Docker 官方镜像站访问受限，我们需要配置代理来拉取镜像。"
echo -e "（如果您有自己的代理服务器，请在下方输入；如果没有，请保持默认或咨询管理员）"
read_input "请输入代理地址" "${DOCKER_PROXY:-http://127.0.0.1:7890}" DOCKER_PROXY

# 容器内挂载路径（强制锁定为 /storage，不再询问用户）
DOCKER_MOUNT_PATH="/storage"
DOCKER_VOLUME="${WXEDGE_DATA_DIR}:${DOCKER_MOUNT_PATH}"
print_info "容器内挂载路径已锁定为：${CYAN}$DOCKER_MOUNT_PATH${NC}"

# 网络模式
print_info "网络模式：默认使用 host 模式（推荐，性能最好）"
DOCKER_NETWORK="host"
DOCKER_PORT_MAP=""

# 重启策略
print_info "重启策略选项："
echo "  - always: 总是重启"
echo "  - unless-stopped: 除非手动停止，否则总是重启（推荐）"
echo "  - on-failure: 仅在失败时重启"
echo "  - no: 不自动重启"
read_input "请选择重启策略" "${DOCKER_RESTART:-unless-stopped}" DOCKER_RESTART

# 特权模式
if [ "$DOCKER_PRIVILEGED" = "true" ]; then
    DEFAULT_PRIV="y"
else
    DEFAULT_PRIV="n"
fi
if read_confirm "是否启用特权模式（privileged）？" "$DEFAULT_PRIV"; then
    DOCKER_PRIVILEGED="true"
else
    DOCKER_PRIVILEGED="false"
fi

# 额外参数
read_input "请输入额外的Docker参数（可留空）" "${DOCKER_EXTRA_ARGS:-}" DOCKER_EXTRA_ARGS

echo ""

# ==================== 监控配置 ====================
print_header "3. 监控配置"

# 磁盘阈值
read_input "请输入磁盘使用率阈值（百分比，1-99）" "${THRESHOLD_PERCENT:-90}" THRESHOLD_PERCENT

# 容器停止超时
read_input "请输入容器停止超时时间（秒）" "${STOP_TIMEOUT:-30}" STOP_TIMEOUT

# 最大重试次数
read_input "请输入容器启动最大重试次数" "${MAX_RETRY:-3}" MAX_RETRY

# 重试间隔
read_input "请输入重试间隔（秒）" "${RETRY_INTERVAL:-5}" RETRY_INTERVAL

echo ""

# ==================== 测速脚本配置 ====================
print_header "4. 测速脚本配置"

print_info "测速脚本为必装项，正在配置参数..."
# 测速脚本URL（自动设置，不再询问用户）
SPEED_TEST_URL="https://git.gushao.club/https://github.com/SolitaryJune/speed_test/raw/main/build_and_run_docker.sh"
print_info "测速脚本地址已自动设置为：${CYAN}$SPEED_TEST_URL${NC}"

# 线程数
read_input "请输入测速线程数" "${SPEED_TEST_THREADS:-8}" SPEED_TEST_THREADS

# 限速
read_input "请输入测速限速值" "${SPEED_TEST_LIMIT:-10}" SPEED_TEST_LIMIT

RUN_SPEED_TEST_ON_DEPLOY="true"

echo ""

# ==================== 定时任务配置 ====================
print_header "5. 定时任务配置"

print_info "定时任务使用cron格式：分 时 日 月 周"
echo "示例："
echo "  - 0 2 * * *    每天凌晨2点"
echo "  - 0 */6 * * *  每6小时"
read_input "请输入定时任务执行时间（cron格式）" "${CRON_SCHEDULE:-0 2 * * *}" CRON_SCHEDULE

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
