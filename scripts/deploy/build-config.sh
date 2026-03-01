#!/bin/bash
# ==============================================================================
# 构建 Sing-box 最终配置
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
fi

build_config() {
    log_step "构建 Sing-box 配置文件"
    
    local template_file="${SCRIPT_DIR}/sing-box/config.template.json"
    local output_file="${SING_BOX_DATA_DIR}/config.json"
    local users_file="${SCRIPT_DIR}/users.json"
    
    if [[ ! -f "$template_file" ]]; then
        die "找不到配置文件模板: $template_file"
    fi
    
    # 拆分 REALITY_DEST
    local dest_name="${REALITY_DEST%:*}"
    local dest_port="${REALITY_DEST##*:}"
    if [[ "$dest_name" == "$dest_port" ]]; then
        dest_port="443"
    fi
    
    # 构建用户数组
    local vless_users="[]"
    local hy2_users="[]"
    
    if [[ -f "$users_file" ]]; then
         # VLESS 绑定 vision 流量控制以支持 XTLS-Reality
         vless_users=$(jq -c '[.[] | {name: (.name), uuid: (.vless_uuid), flow: "xtls-rprx-vision"}] | map(select(.uuid != null))' "$users_file")
         hy2_users=$(jq -c '[.[] | {name: (.name), password: (.hy2_password)}] | map(select(.password != null))' "$users_file")
    else
         log_warn "未找到 users.json，将创建空用户"
    fi
    
    # 使用 jq 替换配置
    jq --argjson vless "$vless_users" \
       --argjson hy2 "$hy2_users" \
       --arg dest_name "$dest_name" \
       --argjson dest_port "$dest_port" \
       --arg private_key "$REALITY_PRIVATE_KEY" \
       --arg short_id "$REALITY_SHORT_ID" \
       '(.inbounds[] | select(.type=="vless")).users = $vless |
        (.inbounds[] | select(.type=="vless")).tls.server_name = $dest_name |
        (.inbounds[] | select(.type=="vless")).tls.reality.handshake.server = $dest_name |
        (.inbounds[] | select(.type=="vless")).tls.reality.handshake.server_port = $dest_port |
        (.inbounds[] | select(.type=="vless")).tls.reality.private_key = $private_key |
        (.inbounds[] | select(.type=="vless")).tls.reality.short_id = ($short_id | split(",")) |
        (.inbounds[] | select(.type=="hysteria2")).users = $hy2' \
       "$template_file" > "$output_file"
       
    log_substep "校验 Sing-box 配置文件..."
    if ! docker run --rm -v "$output_file":/etc/sing-box/config.json ghcr.io/sagernet/sing-box:latest check -c /etc/sing-box/config.json; then
        die "Sing-box 配置文件格式验证失败，请检查用户的 users.json 或 底层参数变量是否有误。"
    fi
       
    log_success "配置文件生成且校验成功: $output_file"
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    build_config "$@"
fi
