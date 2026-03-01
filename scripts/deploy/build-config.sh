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
    
    # 先写入临时文件，校验通过后再原子性替换，防止校验失败时损坏正在运行的配置
    local tmp_file="${output_file}.tmp"

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
       "$template_file" > "$tmp_file"

    log_substep "校验 Sing-box 配置文件..."
    local docker_cmd
    docker_cmd=$(get_docker_cmd) || die "无法连接到 Docker，请确认 Docker 已安装并运行"
    if ! $docker_cmd run --rm \
        -v "$tmp_file":/etc/sing-box/config.json \
        -v "${SING_BOX_DATA_DIR}/cert":/etc/sing-box/cert:ro \
        ghcr.io/sagernet/sing-box:latest \
        check -c /etc/sing-box/config.json; then
        rm -f "$tmp_file"
        die "Sing-box 配置文件格式验证失败，请检查 users.json 或 .env 参数是否有误。原配置文件未被修改。"
    fi

    # 校验通过 → 原子性替换（不会中断正在运行的服务读取）
    mv "$tmp_file" "$output_file"
    log_success "配置文件生成且校验成功: $output_file"

    # 将 users.json 同步到数据目录，供订阅服务（sub）读取
    if [[ -f "$users_file" ]]; then
        # 🚨 防御性处理：如果 docker up 之前 users.json 不存在，
        # Docker volumes 会默认把它当作"目录"创建（并赋予 root 权限），导致之后 cp 报错
        if [[ -d "${SING_BOX_DATA_DIR}/users.json" ]]; then
            log_warn "检测到 users.json 是错误的目录结构，正在修复..."
            sudo rm -rf "${SING_BOX_DATA_DIR}/users.json" || rm -rf "${SING_BOX_DATA_DIR}/users.json"
        fi
        
        cp "$users_file" "${SING_BOX_DATA_DIR}/users.json"
        log_substep "users.json 已同步到: ${SING_BOX_DATA_DIR}/users.json"
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    build_config "$@"
fi
