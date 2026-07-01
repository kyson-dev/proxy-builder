#!/bin/bash
# ==============================================================================
# 配置 systemd-journald 日志容量上限
#
# 使用 drop-in 机制写入 /etc/systemd/journald.conf.d/ 下的独立配置文件，
# 不修改主配置文件，避免 sed 操作带来的格式风险。
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
fi

configure_journald() {
    log_step "配置 systemd-journald"

    local dropin_dir="/etc/systemd/journald.conf.d"
    local dropin_file="${dropin_dir}/99-proxy-limit.conf"
    local expected_content="[Journal]
SystemMaxUse=500M"

    # 幂等检查：内容完全一致则跳过
    if [[ -f "$dropin_file" ]] && [[ "$(cat "$dropin_file")" == "$expected_content" ]]; then
        log_success "journald 配置已是期望状态，跳过"
        return 0
    fi

    log_substep "写入 journald drop-in 配置: $dropin_file"
    sudo mkdir -p "$dropin_dir"
    printf '%s\n' "$expected_content" | sudo tee "$dropin_file" > /dev/null

    log_substep "重启 systemd-journald 应用配置..."
    sudo systemctl restart systemd-journald
    log_success "journald 配置完成（SystemMaxUse=500M）"
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    configure_journald
fi
