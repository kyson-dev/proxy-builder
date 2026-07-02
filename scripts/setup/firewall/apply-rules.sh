#!/bin/bash
# ==============================================================================
# 配置防火墙规则执行子模块
# ==============================================================================

# 防止重复加载
[[ -n "${_FIREWALL_APPLY_RULES_LOADED:-}" ]] && return 0
_FIREWALL_APPLY_RULES_LOADED=1

# 创建防火墙规则（底端原子操作）
create_firewall_rule() {
    local project="$1"
    local rule_name="$2"
    local protocol="$3"
    local port="$4"
    local description="$5"
    
    # 检查规则是否已存在
    if gcloud compute firewall-rules describe "$rule_name" --project="$project" &>/dev/null; then
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

# 批量应用防火墙规则
# 参数: <project_id> <ports_array_elements...>
apply_firewall_rules() {
    local project="$1"
    shift
    local ports=("$@")
    
    if [[ -z "$project" ]]; then
        die "apply_firewall_rules: 缺少项目 ID 参数"
    fi
    
    if [[ ${#ports[@]} -eq 0 ]]; then
        log_warn "未提供任何端口配置"
        return 0
    fi
    
    log_step "应用防火墙规则"
    log_substep "目标 GCP 项目: $project"
    echo ""
    
    # 创建防火墙规则
    for port_proto in "${ports[@]}"; do
        local port="${port_proto%/*}"
        local protocol="${port_proto#*/}"
        local rule_name="allow-proxy-${protocol}-${port}"
        
        create_firewall_rule "$project" \
            "$rule_name" \
            "$protocol" \
            "$port" \
            "Allow proxy service traffic on port ${port}/${protocol}"
    done
    
    echo ""
    log_success "防火墙规则应用完成"
}
