#!/bin/bash
# ==============================================================================
# 健康检查 (S-UI 版本)
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
    
    # 验证 S-UI 是否运行
    if $docker_cmd compose ps s-ui 2>/dev/null | grep -q "Up"; then
        echo ""
        print_separator
        log_success "部署成功！"
        print_separator
        
        local server_ip
        server_ip=$(get_public_ip)
        
        echo ""
        echo "📋 S-UI 管理面板信息:"
        echo "   服务器 IP: $server_ip"
        echo "   服务器域名: $PANEL_DOMAIN"
        echo "   Web 面板: https://$PANEL_DOMAIN:2095/app/"
        echo "   订阅服务: https://$PANEL_DOMAIN:2096/sub/"
        echo ""
        echo "🔐 默认登录信息:"
        echo "   用户名: admin"
        echo "   密码: admin"
        echo ""
        echo "⚠️  安全提示: 首次登录后请立即修改默认密码！"
        echo ""
        echo "📝 查看日志: docker logs -f s-ui"
        echo ""
        echo "💡 接下来请在 Web 面板中配置 Inbound:"
        echo "   - VLESS Reality (端口 443)"
        echo "   - Hysteria2 (端口 443)"
        
        return 0
    else
        echo ""
        log_error "S-UI 启动失败"
        echo ""
        echo "请检查日志:"
        echo "   docker logs s-ui"
        echo ""
        
        # 显示最后几行日志
        log_substep "最近日志:"
        $docker_cmd logs s-ui --tail 20 2>&1 || true
        
        return 1
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    health_check "${1:-5}"
fi
