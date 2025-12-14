#!/bin/bash
# ==============================================================================
# 解析 vars.json 配置文件
# 注意: 此脚本应被主脚本 source，依赖库由主脚本加载
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
fi

# ------------------------------------------------------------------------------
# 主函数
# ------------------------------------------------------------------------------
parse_config() {
    local config_file="${1:-vars.json}"
    
    log_step "解析配置文件"
    
    if [[ ! -f "$config_file" ]]; then
        die "未找到配置文件: $config_file"
    fi
    
    # 检查 jq
    if ! command_exists jq; then
        die "jq 未安装，请先运行 install-dependencies.sh"
    fi
    
    # 从 JSON 提取变量并导出
    export VLESS_PORT=$(jq -r '.ports.vless // 443' "$config_file")
    export H2_PORT=$(jq -r '.ports.hysteria2 // 443' "$config_file")
    export VLESS_USERS=$(jq -c '.vless_users' "$config_file")
    export H2_USERS=$(jq -c '.h2_users' "$config_file")
    export REALITY_PRIVATE_KEY=$(jq -r '.reality.private_key' "$config_file")
    export REALITY_PUBLIC_KEY=$(jq -r '.reality.public_key' "$config_file")
    export REALITY_SHORT_ID=$(jq -r '.reality.short_id' "$config_file")
    
    # 验证必需变量
    local missing=()
    
    [[ -z "$VLESS_USERS" ]] || [[ "$VLESS_USERS" == "null" ]] && missing+=("vless_users")
    [[ -z "$H2_USERS" ]] || [[ "$H2_USERS" == "null" ]] && missing+=("h2_users")
    [[ -z "$REALITY_PRIVATE_KEY" ]] || [[ "$REALITY_PRIVATE_KEY" == "null" ]] && missing+=("reality.private_key")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "配置文件中缺少必要的变量: ${missing[*]}"
    fi
    
    log_success "配置解析完成"
    log_substep "VLESS 端口: $VLESS_PORT"
    log_substep "Hysteria2 端口: $H2_PORT"
    log_substep "VLESS 用户数: $(echo "$VLESS_USERS" | jq 'length')"
    log_substep "H2 用户数: $(echo "$H2_USERS" | jq 'length')"
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_config "${1:-vars.json}"
    echo ""
    echo "导出的变量:"
    echo "  VLESS_PORT=$VLESS_PORT"
    echo "  H2_PORT=$H2_PORT"
    echo "  REALITY_PUBLIC_KEY=$REALITY_PUBLIC_KEY"
fi
