#!/bin/bash
# ==============================================================================
# 健康检查
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
# 从 .env 文件读取端口配置
# ------------------------------------------------------------------------------
load_ports_from_env() {
    if [[ -f .env ]]; then
        # 读取 VLESS_PORT 和 H2_PORT
        VLESS_PORT=$(grep "^VLESS_PORT=" .env 2>/dev/null | cut -d= -f2)
        H2_PORT=$(grep "^H2_PORT=" .env 2>/dev/null | cut -d= -f2)
    fi
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
        
        # 确保端口变量已加载
        load_ports_from_env
        
        echo ""
        echo "📋 代理服务信息:"
        echo "   服务器 IP: $server_ip"
        
        if [[ -n "$VLESS_PORT" ]]; then
            echo "   VLESS Reality: $server_ip:$VLESS_PORT"
        fi
        
        if [[ -n "$H2_PORT" ]]; then
            echo "   Hysteria2: $server_ip:$H2_PORT (自签名证书)"
        fi
        
        echo ""
        echo "📝 查看日志: docker logs -f sing-box"
        echo ""
        echo "⚠️  注意: Hysteria2 使用自签名证书，客户端需要设置 insecure=true"
        
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
