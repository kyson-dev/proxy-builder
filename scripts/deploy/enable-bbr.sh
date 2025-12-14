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
# 主函数
# ------------------------------------------------------------------------------
enable_bbr() {
    log_step "检查 BBR 拥塞控制"
    
    # 检查当前拥塞控制算法
    local current_cc
    current_cc=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
    
    if [[ "$current_cc" == "bbr" ]]; then
        log_success "BBR 已启用"
        return 0
    fi
    
    log_substep "当前拥塞控制: $current_cc"
    log_substep "正在启用 BBR..."
    
    # 检查内核是否支持 BBR (Linux 4.9+)
    if ! grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        # 尝试加载 BBR 模块
        sudo modprobe tcp_bbr 2>/dev/null || true
    fi
    
    # 再次检查是否可用
    if ! grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        log_warn "内核不支持 BBR (需要 Linux 4.9+)"
        log_substep "当前内核: $(uname -r)"
        return 0
    fi
    
    # 配置 sysctl 参数
    sudo tee /etc/sysctl.d/99-bbr.conf > /dev/null << 'EOF'
# BBR congestion control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 优化网络性能
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 3
EOF
    
    # 应用配置
    sudo sysctl -p /etc/sysctl.d/99-bbr.conf > /dev/null 2>&1 || \
        sudo sysctl --system > /dev/null 2>&1
    
    # 验证
    local new_cc
    new_cc=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
    
    if [[ "$new_cc" == "bbr" ]]; then
        log_success "BBR 启用成功"
    else
        log_warn "BBR 启用失败，使用默认拥塞控制: $new_cc"
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    enable_bbr
fi
