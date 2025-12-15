#!/bin/bash
# ==============================================================================
# 启用 BBR 拥塞控制算法
# 注意: 此脚本应被主脚本 source，依赖库由主脚本加载
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
fi

# ------------------------------------------------------------------------------
# 辅助函数：读取 sysctl 值
# ------------------------------------------------------------------------------
get_sysctl() {
    sudo sysctl -n "$1" 2>/dev/null || sysctl -n "$1" 2>/dev/null || echo ""
}

# ------------------------------------------------------------------------------
# 主函数
# ------------------------------------------------------------------------------
enable_bbr() {
    log_step "检查 BBR 拥塞控制"
    
    local current_cc
    current_cc=$(get_sysctl net.ipv4.tcp_congestion_control)
    
    if [[ "$current_cc" == "bbr" ]]; then
        log_success "BBR 已启用"
        return 0
    fi
    
    log_substep "当前: ${current_cc:-unknown}，正在启用 BBR..."
    
    # 加载 BBR 模块（如果需要）
    sudo modprobe tcp_bbr 2>/dev/null || true
    
    # 检查内核是否支持 BBR
    if ! grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        log_warn "内核不支持 BBR (需要 Linux 4.9+)"
        return 0
    fi
    
    # 设置 BBR
    sudo sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1 || true
    sudo sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1 || true
    
    # 持久化配置
    sudo tee /etc/sysctl.d/99-bbr.conf >/dev/null 2>&1 << 'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
EOF
    
    # 验证
    if [[ "$(get_sysctl net.ipv4.tcp_congestion_control)" == "bbr" ]]; then
        log_success "BBR 启用成功"
    else
        log_warn "BBR 启用失败，不影响服务运行"
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    enable_bbr
fi
