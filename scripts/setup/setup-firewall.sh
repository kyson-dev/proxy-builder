#!/bin/bash
# ==============================================================================
# 配置服务端口防火墙规则
# 编排入口，调用子模块完成配置
# ==============================================================================
set -e

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 加载通用库
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/prompt.sh"

# 加载子模块
source "${SCRIPT_DIR}/shared/select-project.sh"
source "${SCRIPT_DIR}/firewall/parse-compose-ports.sh"
source "${SCRIPT_DIR}/firewall/apply-rules.sh"

# ------------------------------------------------------------------------------
# 主函数
# ------------------------------------------------------------------------------
main() {
    print_header "配置服务端口防火墙规则"
    
    # 1. 选择 GCP 项目
    select_gcp_project
    
    # 2. 默认 compose 文件路径
    local compose_file="${PROJECT_ROOT}/docker-compose.yml"
    
    # 3. 解析端口配置
    log_step "解析 docker-compose.yml 端口配置"
    log_substep "配置文件: $compose_file"
    echo ""
    
    local ports=()
    while IFS= read -r port_proto; do
        [[ -n "$port_proto" ]] && ports+=("$port_proto")
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
        echo "   - allow-${protocol}-${port} (${protocol}:${port})"
    done
    echo ""
    
    if ! confirm "是否继续?" "y"; then
        log_warn "已取消"
        exit 0
    fi
    
    echo ""
    
    # 4. 执行防火墙规则应用
    apply_firewall_rules "$PROJECT_ID" "${ports[@]}"
}

# 运行主流程
main "$@"
