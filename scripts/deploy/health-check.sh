#!/bin/bash
# ==============================================================================
# 健康检查 (Sing-box 原生版本)
# 注意: 此脚本应被主脚本 source，依赖库由主脚本加载
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
    source "${_SELF_DIR}/../lib/docker.sh"
fi

# ------------------------------------------------------------------------------
# 获取服务器公网 IP
# ------------------------------------------------------------------------------
get_public_ip() {
    curl -s ifconfig.me 2>/dev/null || \
    curl -s ip.sb 2>/dev/null || \
    curl -s ipinfo.io/ip 2>/dev/null || \
    echo "<SERVER_IP>"
}

# ------------------------------------------------------------------------------
# 主函数
# ------------------------------------------------------------------------------
health_check() {
    local docker_cmd
    docker_cmd=$(get_docker_cmd)
    local wait_time="${1:-5}"
    
    if [[ -z "$docker_cmd" ]]; then
        die "无法运行 Docker"
    fi
    
    log_step "健康检查"
    
    log_substep "等待服务就绪 (${wait_time}s)..."
    sleep "$wait_time"
    
    log_substep "服务状态:"
    $docker_cmd compose ps
    
    # 验证 Sing-box 是否运行
    if $docker_cmd compose ps sing-box 2>/dev/null | grep -q "Up"; then
        echo ""
        print_separator
        log_success "部署成功！"
        print_separator
        
        local server_ip
        server_ip=$(get_public_ip)
        
        echo ""
        echo "🎉 Sing-box 核心代理已启动"
        echo "   🌍 服务器 IP: $server_ip"
        echo "   🌍 伪装域名: $REALITY_DEST"
        echo ""
        echo "✅ 支持的协议配置 (默认 443 端口多路复用):"
        echo "   - VLESS-TCP-Reality"
        echo "   - Hysteria2-UDP"
        echo ""

        # 从 users.json 读取各用户的专属订阅 URL
        local users_file="${SCRIPT_DIR}/users.json"
        if [[ -f "$users_file" ]] && command -v jq &>/dev/null; then
            echo "📱 订阅链接 (复制给对应用户):"
            local user_count
            user_count=$(jq 'length' "$users_file")
            for ((i=0; i<user_count; i++)); do
                local name
                name=$(jq -r ".[$i].name" "$users_file")
                echo "   👤 ${name}: http://${server_ip}:8080/sub?token=${name}"
            done
        else
            echo "📱 订阅服务: http://${server_ip}:8080/sub?token=<用户名>"
        fi
        echo ""
        echo "📝 查看日志以排错: docker logs -f sing-box"
        echo ""
        
        return 0
    else
        echo ""
        log_error "Sing-box 启动失败"
        echo ""
        echo "请检查日志:"
        echo "   docker logs sing-box"
        echo ""
        
        # 显示最后几行日志
        log_substep "最近日志:"
        $docker_cmd logs sing-box --tail 20 2>&1 || true
        
        return 1
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    health_check "${1:-5}"
fi
