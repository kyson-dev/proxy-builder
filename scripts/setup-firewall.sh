#!/bin/bash
# ==============================================================================
# 配置服务端口防火墙规则
# 独立脚本，手动运行: make setup-firewall
# 也可被其他脚本调用: setup_firewall_rules <project> [<compose_file>]
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 加载通用库
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/prompt.sh"

# ------------------------------------------------------------------------------
# 从 docker-compose.yml 解析端口配置
# 返回格式: "port/protocol" 每行一个
# ------------------------------------------------------------------------------
parse_ports_from_compose() {
    local compose_file="$1"
    
    if [[ ! -f "$compose_file" ]]; then
        die "docker-compose 文件不存在: $compose_file"
    fi
    
    # 使用 awk 解析 YAML，只提取 ports: 字段下的端口配置
    # 支持的格式:
    #   - "443:443/tcp"  -> 443/tcp
    #   - "443:443/udp"  -> 443/udp
    #   - "443:443"      -> 443/tcp (默认)
    #   - "443"          -> 443/tcp (默认)
    
    awk '
    /^[[:space:]]*ports:[[:space:]]*$/ {
        in_ports = 1
        next
    }
    
    # 如果遇到同级或更高级的字段，退出 ports 区域
    /^[[:space:]]*[a-zA-Z_]/ {
        if (in_ports && $0 !~ /^[[:space:]]*-/) {
            in_ports = 0
        }
    }
    
    # 在 ports 区域内，提取端口配置
    in_ports && /^[[:space:]]*-/ {
        line = $0
        # 移除前导空白和破折号
        sub(/^[[:space:]]*-[[:space:]]*/, "", line)
        # 移除引号
        gsub(/"/, "", line)
        
        # 提取端口和协议
        if (line ~ /^[0-9]+(:[0-9]+)?\/(tcp|udp)/) {
            # 格式: 443:443/tcp 或 443/tcp
            port = line
            sub(/:.*/, "", port)  # 移除冒号后的所有内容，保留宿主机端口
            proto = line
            sub(/.*\//, "", proto)  # 提取协议
            sub(/[[:space:]].*/, "", proto)  # 移除协议后的空白
            print port "/" proto
        } else if (line ~ /^[0-9]+(:[0-9]+)?[[:space:]]*$/) {
            # 格式: 443:443 或 443 (默认 TCP)
            port = line
            sub(/:.*/, "", port)  # 移除冒号后的所有内容
            sub(/[[:space:]].*/, "", port)  # 移除空白
            print port "/tcp"
        }
    }
    ' "$compose_file" | sort -u
}

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
# 创建防火墙规则（可被其他脚本调用）
# 参数: <project_id> [<compose_file>]
# ------------------------------------------------------------------------------
setup_firewall_rules() {
    local project="$1"
    local compose_file="${2:-${PROJECT_ROOT}/docker-compose.yml}"
    
    if [[ -z "$project" ]]; then
        die "用法: setup_firewall_rules <project_id> [<compose_file>]"
    fi
    
    log_step "配置防火墙规则"
    log_substep "项目: $project"
    log_substep "配置文件: $compose_file"
    echo ""
    
    # 解析端口配置
    log_substep "从 docker-compose.yml 解析端口配置..."
    local ports=()
    while IFS= read -r port_proto; do
        ports+=("$port_proto")
    done < <(parse_ports_from_compose "$compose_file")
    
    if [[ ${#ports[@]} -eq 0 ]]; then
        log_warn "未找到任何端口配置"
        return 0
    fi
    
    echo ""
    log_substep "检测到以下端口配置:"
    for port_proto in "${ports[@]}"; do
        echo "   - $port_proto"
    done
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
    log_success "防火墙规则配置完成"
}

# ------------------------------------------------------------------------------
# 交互式主函数
# ------------------------------------------------------------------------------
main() {
    print_header "配置服务端口防火墙规则"
    
    # 选择项目
    select_project
    
    # 默认 compose 文件路径
    local compose_file="${PROJECT_ROOT}/docker-compose.yml"
    
    # 解析端口配置
    log_step "解析 docker-compose.yml 端口配置"
    log_substep "配置文件: $compose_file"
    echo ""
    
    local ports=()
    while IFS= read -r port_proto; do
        ports+=("$port_proto")
    done < <(parse_ports_from_compose "$compose_file")
    
    if [[ ${#ports[@]} -eq 0 ]]; then
        die "未在 docker-compose.yml 中找到任何端口配置"
    fi
    
    log_success "检测到 ${#ports[@]} 个端口配置:"
    echo ""
    for port_proto in "${ports[@]}"; do
        local port="${port_proto%/*}"
        local protocol="${port_proto#*/}"
        echo "   - 端口 $port ($protocol)"
    done
    echo ""
    
    log_substep "将创建以下防火墙规则:"
    for port_proto in "${ports[@]}"; do
        local port="${port_proto%/*}"
        local protocol="${port_proto#*/}"
        echo "   - allow-proxy-${protocol}-${port} (${protocol}:${port})"
    done
    echo ""
    
    if ! confirm "是否继续?" "y"; then
        log_warn "已取消"
        exit 0
    fi
    
    echo ""
    
    # 创建规则
    for port_proto in "${ports[@]}"; do
        local port="${port_proto%/*}"
        local protocol="${port_proto#*/}"
        local rule_name="allow-proxy-${protocol}-${port}"
        
        create_firewall_rule "$PROJECT_ID" \
            "$rule_name" \
            "$protocol" \
            "$port" \
            "Allow proxy service traffic on port ${port}/${protocol}"
    done
    
    echo ""
    log_success "防火墙规则配置完成"
}

# 如果直接运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
