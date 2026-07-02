#!/bin/bash
# ==============================================================================
# 配置服务端口防火墙规则（重构版）
# 此脚本作为编排入口，通过 modules/infra-firewall.sh 调用底层防火墙操作
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# --- 加载公共库 ---
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/prompt.sh"

# --- 加载上下文解析器 + 功能模块 ---
source "${SCRIPT_DIR}/shared/resolve-context.sh"
source "${SCRIPT_DIR}/modules/infra-firewall.sh"

# ==============================================================================
# 主流程
# ==============================================================================
main() {
    print_header "配置服务端口防火墙规则"

    # 仅需选择项目，无需选择环境（防火墙规则与环境无关）
    # 通过 resolve_context 会调用 select_environment + select_gcp_project
    # 对于 setup-firewall 而言只需 PROJECT_ID，ENV_NAME 不使用
    resolve_context

    # 解析 docker-compose.yml 中的端口配置
    local compose_file="${PROJECT_ROOT}/docker-compose.yml"

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

    # 调用 Layer 2 功能模块执行防火墙规则
    infra::apply_firewall_rules "$PROJECT_ID" "${ports[@]}"
}

main "$@"
