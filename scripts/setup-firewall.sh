#!/bin/bash
# ==============================================================================
# 配置服务端口防火墙规则
# 独立脚本，手动运行: make setup-firewall
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载通用库
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/prompt.sh"

# ------------------------------------------------------------------------------
# 创建防火墙规则
# ------------------------------------------------------------------------------
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

# ------------------------------------------------------------------------------
# 主函数
# ------------------------------------------------------------------------------
main() {
    print_header "配置服务端口防火墙规则"
    
    # 获取当前项目
    local project
    project=$(gcloud config get-value project 2>/dev/null)
    
    if [[ -z "$project" ]]; then
        prompt_required "请输入 GCP 项目 ID"
        project="$INPUT_VALUE"
    else
        log_substep "当前项目: $project"
        if ! confirm "使用此项目?" "y"; then
            prompt_required "请输入 GCP 项目 ID"
            project="$INPUT_VALUE"
        fi
    fi
    
    echo ""
    echo "请输入服务端口配置:"
    echo ""
    
    prompt_with_default "VLESS Reality 端口 (TCP)" "443"
    local vless_port="$INPUT_VALUE"
    
    prompt_with_default "Hysteria2 端口 (UDP)" "443"
    local h2_port="$INPUT_VALUE"
    
    echo ""
    log_substep "将创建以下防火墙规则:"
    echo "   - allow-vless-${vless_port} (tcp:${vless_port})"
    echo "   - allow-hysteria2-${h2_port} (udp:${h2_port})"
    echo ""
    
    if ! confirm "是否继续?" "y"; then
        log_warn "已取消"
        exit 0
    fi
    
    echo ""
    
    # 创建 VLESS 规则 (TCP)
    create_firewall_rule "$project" \
        "allow-vless-${vless_port}" \
        "tcp" \
        "$vless_port" \
        "Allow VLESS Reality traffic"
    
    # 创建 Hysteria2 规则 (UDP)
    create_firewall_rule "$project" \
        "allow-hysteria2-${h2_port}" \
        "udp" \
        "$h2_port" \
        "Allow Hysteria2 traffic"
    
    echo ""
    log_success "防火墙规则配置完成"
}

main "$@"
