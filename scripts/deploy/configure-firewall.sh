#!/bin/bash
# ==============================================================================
# 配置防火墙规则（根据端口配置动态创建）
# 注意: 此脚本应被主脚本 source，依赖库由主脚本加载
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
fi

# ------------------------------------------------------------------------------
# 获取当前 VM 的 project 和 zone（从 metadata）
# ------------------------------------------------------------------------------
get_vm_metadata() {
    # 从 GCE metadata 获取当前 VM 信息
    local metadata_url="http://metadata.google.internal/computeMetadata/v1"
    local headers="-H Metadata-Flavor:Google"
    
    if command_exists curl; then
        GCP_PROJECT=$(curl -s $headers "${metadata_url}/project/project-id" 2>/dev/null) || true
        GCP_ZONE=$(curl -s $headers "${metadata_url}/instance/zone" 2>/dev/null | awk -F/ '{print $NF}') || true
        GCP_VM_NAME=$(curl -s $headers "${metadata_url}/instance/name" 2>/dev/null) || true
    fi
    
    export GCP_PROJECT GCP_ZONE GCP_VM_NAME
}

# ------------------------------------------------------------------------------
# 检查防火墙规则是否存在
# ------------------------------------------------------------------------------
firewall_rule_exists() {
    local project="$1"
    local rule_name="$2"
    
    gcloud compute firewall-rules describe "$rule_name" --project="$project" &>/dev/null
}

# ------------------------------------------------------------------------------
# 创建或更新防火墙规则
# ------------------------------------------------------------------------------
ensure_firewall_rule() {
    local project="$1"
    local rule_name="$2"
    local protocol="$3"  # tcp 或 udp
    local port="$4"
    local description="$5"
    
    if firewall_rule_exists "$project" "$rule_name"; then
        log_substep "防火墙规则已存在: $rule_name"
        return 0
    fi
    
    log_substep "创建防火墙规则: $rule_name ($protocol:$port)"
    
    gcloud compute firewall-rules create "$rule_name" \
        --project="$project" \
        --direction=INGRESS \
        --priority=1000 \
        --network=default \
        --allow="${protocol}:${port}" \
        --source-ranges=0.0.0.0/0 \
        --description="$description"

}

# ------------------------------------------------------------------------------
# 主函数：根据端口配置创建防火墙规则
# ------------------------------------------------------------------------------
configure_firewall() {
    log_step "配置防火墙规则"
    
    # 获取 VM metadata
    get_vm_metadata
    
    if [[ -z "$GCP_PROJECT" ]]; then
        log_warn "无法获取 GCP project 信息（可能不在 GCE VM 上运行）"
        log_substep "跳过防火墙配置"
        return 0
    fi
    
    log_substep "Project: $GCP_PROJECT"
    log_substep "VM: $GCP_VM_NAME"
    
    # 检查端口变量是否已设置
    if [[ -z "$VLESS_PORT" ]] && [[ -z "$H2_PORT" ]]; then
        log_warn "端口变量未设置，请先运行 parse_config"
        return 1
    fi
    
    # 创建 VLESS 端口规则 (TCP)
    if [[ -n "$VLESS_PORT" ]] && [[ "$VLESS_PORT" != "null" ]]; then
        ensure_firewall_rule "$GCP_PROJECT" \
            "allow-vless-${VLESS_PORT}" \
            "tcp" \
            "$VLESS_PORT" \
            "Allow VLESS Reality traffic on port $VLESS_PORT"
    fi
    
    # 创建 Hysteria2 端口规则 (UDP)
    if [[ -n "$H2_PORT" ]] && [[ "$H2_PORT" != "null" ]]; then
        ensure_firewall_rule "$GCP_PROJECT" \
            "allow-hysteria2-${H2_PORT}" \
            "udp" \
            "$H2_PORT" \
            "Allow Hysteria2 traffic on port $H2_PORT"
    fi
    
    log_success "防火墙规则配置完成"
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 需要先解析配置
    if [[ -z "$VLESS_PORT" ]]; then
        echo "请先设置环境变量 VLESS_PORT 和 H2_PORT"
        echo "或者通过 deploy.sh 运行"
        exit 1
    fi
    configure_firewall
fi
