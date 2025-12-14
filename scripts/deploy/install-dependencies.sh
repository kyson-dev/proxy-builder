#!/bin/bash
# ==============================================================================
# 安装必要依赖 (OpenSSL, jq 等)
# 注意: 此脚本应被主脚本 source，依赖库由主脚本加载
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
    source "${_SELF_DIR}/../lib/os.sh"
fi

# ------------------------------------------------------------------------------
# 安装 OpenSSL
# ------------------------------------------------------------------------------
install_openssl() {
    log_substep "安装 OpenSSL..."
    
    detect_os
    
    case $OS_ID in
        ubuntu|debian)
            sudo apt-get update -qq
            sudo apt-get install -y -qq openssl
            ;;
        centos|rhel|fedora|rocky|almalinux)
            sudo yum install -y -q openssl || sudo dnf install -y -q openssl
            ;;
        alpine)
            sudo apk add openssl
            ;;
        *)
            die "无法自动安装 openssl，请手动安装"
            ;;
    esac
    
    log_success "OpenSSL 安装完成"
}

# ------------------------------------------------------------------------------
# 安装 jq
# ------------------------------------------------------------------------------
install_jq() {
    log_substep "安装 jq..."
    
    detect_os
    
    case $OS_ID in
        ubuntu|debian)
            sudo apt-get update -qq
            sudo apt-get install -y -qq jq
            ;;
        centos|rhel|fedora|rocky|almalinux)
            sudo yum install -y -q jq || sudo dnf install -y -q jq
            ;;
        alpine)
            sudo apk add jq
            ;;
        *)
            die "无法自动安装 jq，请手动安装"
            ;;
    esac
    
    log_success "jq 安装完成"
}

# ------------------------------------------------------------------------------
# 检查并安装依赖
# ------------------------------------------------------------------------------
check_dependencies() {
    log_step "检查必要依赖"
    
    # 检查 OpenSSL
    if ! command_exists openssl; then
        log_warn "OpenSSL 未安装"
        install_openssl
    else
        log_success "OpenSSL 已安装"
    fi
    
    # 检查 jq
    if ! command_exists jq; then
        log_warn "jq 未安装"
        install_jq
    else
        log_success "jq 已安装"
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_dependencies
fi
