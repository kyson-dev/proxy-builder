#!/bin/bash
# ==============================================================================
# 生成自签名证书
# 注意: 此脚本应被主脚本 source，依赖库由主脚本加载
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
fi

# 默认配置
DEFAULT_CERT_DIR="./sing-box/certs"
DEFAULT_CN="bing.com"
DEFAULT_DAYS="3650"  # 10 年

# ------------------------------------------------------------------------------
# 生成 RSA 自签名证书
# ------------------------------------------------------------------------------
generate_rsa_cert() {
    local cert_dir="$1"
    local cn="$2"
    local days="$3"
    
    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout "${cert_dir}/key.pem" \
        -out "${cert_dir}/cert.pem" \
        -subj "/CN=${cn}" \
        -days "$days" >/dev/null 2>&1
}

# ------------------------------------------------------------------------------
# 生成 EC 自签名证书 (备用)
# ------------------------------------------------------------------------------
generate_ec_cert() {
    local cert_dir="$1"
    local cn="$2"
    local days="$3"
    
    openssl ecparam -name prime256v1 -genkey -noout -out "${cert_dir}/key.pem" 2>/dev/null && \
    openssl req -new -x509 -key "${cert_dir}/key.pem" \
        -out "${cert_dir}/cert.pem" \
        -subj "/CN=${cn}" \
        -days "$days" >/dev/null 2>&1
}

# ------------------------------------------------------------------------------
# 检查证书有效性
# ------------------------------------------------------------------------------
check_cert_validity() {
    local cert_file="$1"
    local days_valid="${2:-1}"  # 默认检查是否在 1 天内过期
    
    if [[ ! -f "$cert_file" ]]; then
        return 1
    fi
    
    openssl x509 -in "$cert_file" -noout -checkend $((days_valid * 86400)) >/dev/null 2>&1
}

# ------------------------------------------------------------------------------
# 获取证书信息
# ------------------------------------------------------------------------------
get_cert_info() {
    local cert_file="$1"
    
    if [[ ! -f "$cert_file" ]]; then
        echo "证书不存在"
        return 1
    fi
    
    local cn expire_date
    cn=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed -n 's/.*CN=\([^,]*\).*/\1/p')
    expire_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
    
    echo "CN=$cn"
    echo "EXPIRE=$expire_date"
}

# ------------------------------------------------------------------------------
# 主函数
# ------------------------------------------------------------------------------
generate_certs() {
    local cert_dir="${1:-$DEFAULT_CERT_DIR}"
    local cn="${2:-$DEFAULT_CN}"
    local days="${3:-$DEFAULT_DAYS}"
    
    log_step "检查自签名证书"
    
    # 确保目录存在
    mkdir -p "$cert_dir"
    
    local need_generate=false
    local cert_file="${cert_dir}/cert.pem"
    local key_file="${cert_dir}/key.pem"
    
    # 检查证书文件
    if [[ ! -f "$cert_file" ]] || [[ ! -f "$key_file" ]]; then
        log_substep "证书文件不存在"
        need_generate=true
    elif ! check_cert_validity "$cert_file" 1; then
        log_substep "证书已过期或无效"
        need_generate=true
    else
        log_success "证书已存在且有效"
        
        # 显示证书信息
        local cert_cn cert_expire
        cert_cn=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed -n 's/.*CN=\([^,]*\).*/\1/p')
        cert_expire=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
        
        log_substep "CN: $cert_cn"
        log_substep "过期时间: $cert_expire"
        return 0
    fi
    
    if [[ "$need_generate" == true ]]; then
        log_substep "生成新的自签名证书..."
        
        # 尝试 RSA 方式
        if generate_rsa_cert "$cert_dir" "$cn" "$days"; then
            log_success "自签名证书生成成功 (RSA)"
        else
            log_warn "RSA 证书生成失败，尝试 EC 密钥..."
            
            if generate_ec_cert "$cert_dir" "$cn" "$days"; then
                log_success "自签名证书生成成功 (EC)"
            else
                die "证书生成失败，请检查 openssl 安装"
            fi
        fi
        
        log_substep "CN: $cn"
        log_substep "有效期: $days 天"
        
        # 设置正确的权限
        chmod 644 "$cert_file"
        chmod 600 "$key_file"
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    generate_certs "${1:-$DEFAULT_CERT_DIR}" "${2:-$DEFAULT_CN}" "${3:-$DEFAULT_DAYS}"
fi
