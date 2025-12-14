#!/bin/bash
# ==============================================================================
# 通用库函数 - 颜色、日志、错误处理
# ==============================================================================

# 防止重复加载
[[ -n "${_LIB_COMMON_LOADED:-}" ]] && return 0
_LIB_COMMON_LOADED=1

# ------------------------------------------------------------------------------
# 颜色定义
# ------------------------------------------------------------------------------
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    NC=''
fi

# ------------------------------------------------------------------------------
# 日志函数
# ------------------------------------------------------------------------------
log_info() {
    echo -e "${BLUE}ℹ️ ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✅${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}⚠️ ${NC} $*"
}

log_error() {
    echo -e "${RED}❌${NC} $*" >&2
}

log_step() {
    echo -e "${CYAN}📋${NC} ${BOLD}$*${NC}"
}

log_substep() {
    echo -e "   $*"
}

# 打印分隔线
print_separator() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# 打印标题
print_header() {
    echo ""
    echo -e "🚀 ${BOLD}$*${NC}"
    print_separator
    echo ""
}

# ------------------------------------------------------------------------------
# 错误处理
# ------------------------------------------------------------------------------
die() {
    log_error "$@"
    exit 1
}

# 设置错误处理陷阱
setup_error_trap() {
    trap 'die "脚本在第 $LINENO 行执行失败"' ERR
}

# ------------------------------------------------------------------------------
# 工具函数
# ------------------------------------------------------------------------------

# 检查命令是否存在
command_exists() {
    command -v "$1" &> /dev/null
}

# 检查是否以 root 运行
is_root() {
    [[ $EUID -eq 0 ]]
}

# 需要 root 权限
require_root() {
    if ! is_root; then
        die "此脚本需要 root 权限运行"
    fi
}

# 获取脚本所在目录
get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    while [[ -h "$source" ]]; do
        local dir="$(cd -P "$(dirname "$source")" && pwd)"
        source="$(readlink "$source")"
        [[ "$source" != /* ]] && source="$dir/$source"
    done
    cd -P "$(dirname "$source")" && pwd
}

# 确保目录存在
ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || die "无法创建目录: $dir"
    fi
}

# 备份文件
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup"
        log_substep "已备份: $backup"
    fi
}

# 重试执行命令
retry() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    local cmd="$*"
    
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if eval "$cmd"; then
            return 0
        fi
        log_warn "尝试 $attempt/$max_attempts 失败，${delay}秒后重试..."
        sleep "$delay"
        ((attempt++))
    done
    
    return 1
}

# 等待条件满足
wait_for() {
    local max_wait="$1"
    local interval="$2"
    local condition="$3"
    local message="${4:-等待条件满足...}"
    
    local elapsed=0
    while [[ $elapsed -lt $max_wait ]]; do
        if eval "$condition"; then
            return 0
        fi
        echo -ne "\r   $message (${elapsed}s/${max_wait}s)"
        sleep "$interval"
        ((elapsed += interval))
    done
    echo ""
    return 1
}
