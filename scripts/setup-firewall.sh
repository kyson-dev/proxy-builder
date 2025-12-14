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
# 选择项目
# ------------------------------------------------------------------------------
select_project() {
    log_step "选择 GCP 项目"
    
    # 获取当前项目
    local current_project
    current_project=$(gcloud config get-value project 2>/dev/null || echo "")
    
    # 获取项目列表
    log_substep "获取项目列表..."
    local projects=()
    local default_index=""
    local i=1
    
    while IFS= read -r line; do
        projects+=("$line")
        if [[ "$line" == "$current_project" ]]; then
            default_index=$i
        fi
        ((i++))
    done < <(gcloud projects list --format="value(projectId)" 2>/dev/null)
    
    if [[ ${#projects[@]} -eq 0 ]]; then
        die "没有找到任何 GCP 项目"
    fi
    
    echo ""
    echo "可用项目:"
    for ((i=0; i<${#projects[@]}; i++)); do
        local marker=""
        if [[ "${projects[$i]}" == "$current_project" ]]; then
            marker=" (当前)"
        fi
        echo "  $((i+1)). ${projects[$i]}${marker}"
    done
    echo ""
    
    local selection
    while true; do
        if [[ -n "$default_index" ]]; then
            read -p "选择项目 (1-${#projects[@]}) [默认: $default_index]: " selection
            selection="${selection:-$default_index}"
        else
            read -p "选择项目 (1-${#projects[@]}): " selection
        fi
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && \
           [[ "$selection" -ge 1 ]] && \
           [[ "$selection" -le "${#projects[@]}" ]]; then
            PROJECT_ID="${projects[$((selection-1))]}"
            break
        fi
        echo "无效选择，请重试。"
    done
    
    log_success "选择的项目: $PROJECT_ID"
    echo ""
}

# ------------------------------------------------------------------------------
# 主函数
# ------------------------------------------------------------------------------
main() {
    print_header "配置服务端口防火墙规则"
    
    # 选择项目
    select_project
    
    # 询问端口配置
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
    create_firewall_rule "$PROJECT_ID" \
        "allow-vless-${vless_port}" \
        "tcp" \
        "$vless_port" \
        "Allow VLESS Reality traffic"
    
    # 创建 Hysteria2 规则 (UDP)
    create_firewall_rule "$PROJECT_ID" \
        "allow-hysteria2-${h2_port}" \
        "udp" \
        "$h2_port" \
        "Allow Hysteria2 traffic"
    
    echo ""
    log_success "防火墙规则配置完成"
}

main "$@"
