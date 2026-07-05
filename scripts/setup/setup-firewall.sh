#!/bin/bash
# ==============================================================================
# 配置服务端口防火墙规则（重构版）
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# --- 加载公共库 ---
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/prompt.sh"
source "${SCRIPT_DIR}/../lib/gcp.sh"

# --- 加载系统执行层 ---
source "${SCRIPT_DIR}/modules/infra-firewall.sh"

# --- 加载辅助脚本 (解析项目 docker-compose.yml) ---
source "${SCRIPT_DIR}/firewall/parse-compose-ports.sh"

# ==============================================================================
# 主流程
# ==============================================================================
main() {
    print_header "配置服务端口防火墙规则"

    # 1. 检测非交互模式条件
    local is_non_interactive=false
    if [[ "${CI:-}" == "true" ]] || [[ "${NON_INTERACTIVE:-}" == "true" ]]; then
        is_non_interactive=true
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --non-interactive) is_non_interactive=true ;;
        esac
        shift
    done

    # 2. 确定环境
    if [[ "$is_non_interactive" == "true" ]]; then
        if [[ -z "${ENV_NAME:-}" ]]; then
            die "非交互模式错误: 必须指定环境变量 ENV_NAME (production 或 development)"
        fi
    else
        source "${SCRIPT_DIR}/shared/select-environment.sh"
        select_environment
    fi

    local env_file="${PROJECT_ROOT}/.env.${ENV_NAME}"

    # 3. Project ID 只读本地 .env 文件（只能由 setup-wif.sh 写入）
    local env_project_id=""
    if [[ -f "$env_file" ]]; then
        env_project_id=$(grep "^[[:space:]]*GCP_PROJECT_ID=" "$env_file" | cut -d'=' -f2- | xargs 2>/dev/null || echo "")
    fi
    if [[ -z "$env_project_id" ]]; then
        die "在本地环境配置 '.env.${ENV_NAME}' 中没有找到 GCP_PROJECT_ID，请先执行: make setup-wif"
    fi
    PROJECT_ID="$env_project_id"
    log_success "检测并复用项目环境: $PROJECT_ID"

    # 4. 解析 docker-compose.yml 中的端口配置
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

    if [[ "$is_non_interactive" == "false" ]]; then
        if ! confirm "是否继续?" "y"; then
            log_warn "已取消"
            exit 0
        fi
        echo ""
    fi

    # 5. 调用 Layer 2 功能模块执行防火墙规则
    infra::apply_firewall_rules "$PROJECT_ID" "${ports[@]}"
}

main "$@"
