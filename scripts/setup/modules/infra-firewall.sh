#!/bin/bash
# ==============================================================================
# Layer 2: Firewall 功能模块
# 职责: 编排防火墙规则创建，支持直接传入端口列表或从 compose 文件解析
# 接口:
#   infra::apply_firewall_rules <project_id> <port/proto>...
#   infra::apply_firewall_from_compose <project_id> <compose_file>
# 依赖: lib/common.sh, lib/gcp.sh, firewall/parse-compose-ports.sh, firewall/apply-rules.sh
# 无交互: 不调用任何 prompt_* / read 函数
# ==============================================================================

# 防止重复加载
[[ -n "${_INFRA_FIREWALL_LOADED:-}" ]] && return 0
_INFRA_FIREWALL_LOADED=1

# 加载子模块
_INFRA_FW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_INFRA_FW_DIR}/../firewall/parse-compose-ports.sh"
source "${_INFRA_FW_DIR}/../firewall/apply-rules.sh"

# ==============================================================================
# infra::apply_firewall_rules — 对指定端口/协议列表创建防火墙规则
# ==============================================================================
# 参数:
#   $1       project_id   GCP 项目 ID（必须）
#   $2...$N  port/proto   端口协议对，如 443/tcp 8388/tcp（必须至少一个）
#
# 示例:
#   infra::apply_firewall_rules my-project 443/tcp 8443/tcp 8388/tcp 1080/tcp
# ==============================================================================
infra::apply_firewall_rules() {
    local project_id="${1:?infra::apply_firewall_rules: project_id 不能为空}"
    shift
    local ports=("$@")

    if [[ ${#ports[@]} -eq 0 ]]; then
        die "infra::apply_firewall_rules: 至少需要一个端口参数"
    fi

    log_step "防火墙规则: 项目=$project_id, 端口=[${ports[*]}]"
    apply_firewall_rules "$project_id" "${ports[@]}"
}

# ==============================================================================
# infra::apply_firewall_from_compose — 从 docker-compose.yml 解析端口并创建规则
# ==============================================================================
# 参数:
#   $1  project_id    GCP 项目 ID（必须）
#   $2  compose_file  docker-compose.yml 路径（必须）
# ==============================================================================
infra::apply_firewall_from_compose() {
    local project_id="${1:?infra::apply_firewall_from_compose: project_id 不能为空}"
    local compose_file="${2:?infra::apply_firewall_from_compose: compose_file 不能为空}"

    if [[ ! -f "$compose_file" ]]; then
        die "infra::apply_firewall_from_compose: compose 文件不存在: $compose_file"
    fi

    log_step "防火墙规则 (从 compose 解析): $compose_file"

    local ports=()
    while IFS= read -r port_proto; do
        [[ -n "$port_proto" ]] && ports+=("$port_proto")
    done < <(parse_ports_from_compose "$compose_file")

    if [[ ${#ports[@]} -eq 0 ]]; then
        die "未在 $compose_file 中找到任何端口配置"
    fi

    log_substep "解析到 ${#ports[@]} 个端口: ${ports[*]}"
    apply_firewall_rules "$project_id" "${ports[@]}"
}
