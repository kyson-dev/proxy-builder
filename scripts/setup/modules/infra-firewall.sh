#!/bin/bash
# ==============================================================================
# Layer 2: Firewall 功能模块
# 职责: 对给定端口/协议列表创建防火墙规则（纯基础设施交互，不解析任何项目文件）
# 接口:
#   infra::apply_firewall_rules <project_id> <port/proto>...
# 依赖: lib/common.sh, lib/gcp.sh (由调用方预先加载)
# 无交互: 不调用任何 prompt_* / read 函数; 自包含，不 source 其它 setup 子文件
#
# 注意: 从 docker-compose.yml 解析端口是"项目文件"相关的辅助逻辑，
#       由 firewall/parse-compose-ports.sh 提供，调用方 (setup-firewall.sh)
#       负责先解析出端口列表，再传给本模块的 infra::apply_firewall_rules。
# ==============================================================================

# 防止重复加载
[[ -n "${_INFRA_FIREWALL_LOADED:-}" ]] && return 0
_INFRA_FIREWALL_LOADED=1

# ------------------------------------------------------------------------------
# 内部: 创建单条防火墙规则（幂等）
# ------------------------------------------------------------------------------
_infra_firewall_create_rule() {
    local project="$1"
    local rule_name="$2"
    local protocol="$3"
    local port="$4"
    local description="$5"

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
    echo ""

    for port_proto in "${ports[@]}"; do
        local port="${port_proto%/*}"
        local protocol="${port_proto#*/}"
        local rule_name="allow-${protocol}-${port}"

        _infra_firewall_create_rule "$project_id" \
            "$rule_name" \
            "$protocol" \
            "$port" \
            "Allow proxy service traffic on port ${port}/${protocol}"
    done

    echo ""
    log_success "防火墙规则应用完成"
}
