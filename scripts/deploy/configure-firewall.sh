#!/bin/bash
# ==============================================================================
# 检查防火墙规则（只检查，不创建）
# 注意: 此脚本应被主脚本 source，依赖库由主脚本加载
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
fi

# ------------------------------------------------------------------------------
# 获取当前 VM 的 project（从 metadata）
# ------------------------------------------------------------------------------
get_project_from_metadata() {
    curl -s -H "Metadata-Flavor:Google" \
        "http://metadata.google.internal/computeMetadata/v1/project/project-id" 2>/dev/null || echo ""
}

# ------------------------------------------------------------------------------
# 检查防火墙规则是否存在（带权限容错）
# 返回: 0=存在, 1=不存在, 2=无权限检查
# ------------------------------------------------------------------------------
check_firewall_rule() {
    local project="$1"
    local rule_name="$2"
    
    local result
    result=$(gcloud compute firewall-rules describe "$rule_name" --project="$project" 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        return 0  # 存在
    elif echo "$result" | grep -q "Could not fetch resource"; then
        return 2  # 无权限
    else
        return 1  # 不存在
    fi
}

# ------------------------------------------------------------------------------
# 主函数
# ------------------------------------------------------------------------------
configure_firewall() {
    log_step "检查防火墙规则"
    
    local project
    project=$(get_project_from_metadata)
    
    if [[ -z "$project" ]]; then
        log_substep "跳过（不在 GCE VM 上）"
        return 0
    fi
    
    # 检查端口变量
    if [[ -z "$VLESS_PORT" ]] && [[ -z "$H2_PORT" ]]; then
        log_substep "跳过（端口未配置）"
        return 0
    fi
    
    local has_error=0
    local no_permission=0
    
    # 检查 VLESS 端口规则 (TCP)
    if [[ -n "$VLESS_PORT" ]] && [[ "$VLESS_PORT" != "null" ]]; then
        local rule="allow-vless-${VLESS_PORT}"
        check_firewall_rule "$project" "$rule"
        case $? in
            0) log_substep "✓ $rule (tcp:$VLESS_PORT)" ;;
            1) log_substep "✗ $rule 不存在"; has_error=1 ;;
            2) no_permission=1 ;;
        esac
    fi
    
    # 检查 Hysteria2 端口规则 (UDP)
    if [[ -n "$H2_PORT" ]] && [[ "$H2_PORT" != "null" ]]; then
        local rule="allow-hysteria2-${H2_PORT}"
        check_firewall_rule "$project" "$rule"
        case $? in
            0) log_substep "✓ $rule (udp:$H2_PORT)" ;;
            1) log_substep "✗ $rule 不存在"; has_error=1 ;;
            2) no_permission=1 ;;
        esac
    fi
    
    if [[ $no_permission -eq 1 ]]; then
        log_substep "跳过（无权限检查防火墙）"
        return 0
    fi
    
    if [[ $has_error -eq 1 ]]; then
        log_warn "缺少防火墙规则，服务可能无法访问"
        echo "   💡 运行 'make setup-firewall' 创建规则"
    else
        log_success "防火墙规则检查通过"
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    configure_firewall
fi
