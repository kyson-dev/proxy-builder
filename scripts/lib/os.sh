#!/bin/bash
# ==============================================================================
# 操作系统检测和包管理库
# 依赖: common.sh (由主脚本预先加载)
# ==============================================================================

# 防止重复加载
[[ -n "${_LIB_OS_LOADED:-}" ]] && return 0
_LIB_OS_LOADED=1


# ------------------------------------------------------------------------------
# 操作系统检测
# ------------------------------------------------------------------------------

# 检测操作系统
# 设置全局变量: OS_ID, OS_VERSION, OS_CODENAME, PKG_MANAGER
detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_ID="$ID"
        OS_VERSION="${VERSION_ID:-unknown}"
        OS_CODENAME="${VERSION_CODENAME:-}"
    elif [[ -f /etc/redhat-release ]]; then
        OS_ID="rhel"
        OS_VERSION=$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+' | head -1)
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
    fi
    
    # 确定包管理器
    case "$OS_ID" in
        ubuntu|debian|raspbian)
            PKG_MANAGER="apt"
            ;;
        centos|rhel|rocky|almalinux|fedora)
            if command_exists dnf; then
                PKG_MANAGER="dnf"
            else
                PKG_MANAGER="yum"
            fi
            ;;
        alpine)
            PKG_MANAGER="apk"
            ;;
        arch|manjaro)
            PKG_MANAGER="pacman"
            ;;
        *)
            PKG_MANAGER="unknown"
            ;;
    esac
    
    export OS_ID OS_VERSION OS_CODENAME PKG_MANAGER
}

# 获取操作系统信息字符串
get_os_info() {
    detect_os
    echo "$OS_ID $OS_VERSION ($PKG_MANAGER)"
}

# ------------------------------------------------------------------------------
# 包管理函数
# ------------------------------------------------------------------------------

# 更新包列表
pkg_update() {
    detect_os
    log_substep "更新包列表..."
    
    case "$PKG_MANAGER" in
        apt)
            sudo apt-get update -qq
            ;;
        yum)
            sudo yum makecache -q
            ;;
        dnf)
            sudo dnf makecache -q
            ;;
        apk)
            sudo apk update -q
            ;;
        pacman)
            sudo pacman -Sy --noconfirm > /dev/null
            ;;
        *)
            log_warn "未知的包管理器: $PKG_MANAGER"
            return 1
            ;;
    esac
}

# 安装包
# 用法: pkg_install package1 package2 ...
pkg_install() {
    detect_os
    local packages=("$@")
    
    log_substep "安装: ${packages[*]}..."
    
    case "$PKG_MANAGER" in
        apt)
            sudo apt-get install -y -qq "${packages[@]}"
            ;;
        yum)
            sudo yum install -y -q "${packages[@]}"
            ;;
        dnf)
            sudo dnf install -y -q "${packages[@]}"
            ;;
        apk)
            sudo apk add -q "${packages[@]}"
            ;;
        pacman)
            sudo pacman -S --noconfirm --needed "${packages[@]}" > /dev/null
            ;;
        *)
            log_error "未知的包管理器: $PKG_MANAGER"
            return 1
            ;;
    esac
}

# 检查包是否已安装
pkg_installed() {
    local package="$1"
    detect_os
    
    case "$PKG_MANAGER" in
        apt)
            dpkg -l "$package" 2>/dev/null | grep -q "^ii"
            ;;
        yum|dnf)
            rpm -q "$package" &>/dev/null
            ;;
        apk)
            apk info -e "$package" &>/dev/null
            ;;
        pacman)
            pacman -Q "$package" &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# ------------------------------------------------------------------------------
# 服务管理函数
# ------------------------------------------------------------------------------

# 检查服务状态
service_is_running() {
    local service="$1"
    systemctl is-active --quiet "$service" 2>/dev/null
}

# 启动服务
service_start() {
    local service="$1"
    sudo systemctl start "$service"
}

# 停止服务
service_stop() {
    local service="$1"
    sudo systemctl stop "$service"
}

# 重启服务
service_restart() {
    local service="$1"
    sudo systemctl restart "$service"
}

# 启用服务开机自启
service_enable() {
    local service="$1"
    sudo systemctl enable "$service"
}

# 禁用服务开机自启
service_disable() {
    local service="$1"
    sudo systemctl disable "$service"
}

# ------------------------------------------------------------------------------
# 系统信息函数
# ------------------------------------------------------------------------------

# 获取内核版本
get_kernel_version() {
    uname -r
}

# 检查内核版本是否 >= 指定版本
kernel_version_ge() {
    local required="$1"
    local current
    current=$(uname -r | cut -d'-' -f1)
    
    # 比较版本
    printf '%s\n%s' "$required" "$current" | sort -V -C
}

# 获取 CPU 核心数
get_cpu_cores() {
    nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1
}

# 获取总内存 (MB)
get_total_memory_mb() {
    free -m | awk '/^Mem:/{print $2}'
}

# 获取可用内存 (MB)
get_available_memory_mb() {
    free -m | awk '/^Mem:/{print $7}'
}

# 获取磁盘可用空间 (GB)
get_disk_free_gb() {
    local path="${1:-/}"
    df -BG "$path" | awk 'NR==2 {gsub("G",""); print $4}'
}
