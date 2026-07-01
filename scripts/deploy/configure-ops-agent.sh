#!/bin/bash
# ==============================================================================
# 安装并配置 Google Cloud Ops Agent
#
# 职责：
#   1. 安装 Ops Agent（幂等，已运行则跳过）
#   2. 写入日志采集配置（systemd_journal receiver）+ 主机监控（hostmetrics）
#      幂等检查使用文件内容哈希对比，而非 grep 关键词匹配
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
fi

# ------------------------------------------------------------------------------
# 安装 Ops Agent
# ------------------------------------------------------------------------------
install_ops_agent() {
    log_substep "下载并安装 Google Cloud Ops Agent..."
    if curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh; then
        sudo bash add-google-cloud-ops-agent-repo.sh --also-install
        rm -f add-google-cloud-ops-agent-repo.sh
        log_success "Google Cloud Ops Agent 安装成功"
    else
        die "下载 Ops Agent 安装脚本失败"
    fi
}

# ------------------------------------------------------------------------------
# 配置 Ops Agent
# ------------------------------------------------------------------------------
configure_ops_agent() {
    log_step "配置 Google Cloud Ops Agent"

    # 1. 安装（幂等：已运行则跳过）
    if systemctl is-active --quiet google-cloud-ops-agent; then
        log_success "Ops Agent 已运行，跳过安装"
    else
        log_substep "Ops Agent 未安装或未启动"
        install_ops_agent
    fi

    # 2. 写入配置
    local agent_config_file="/etc/google-cloud-ops-agent/config.yaml"
    if [[ ! -f "$agent_config_file" ]]; then
        die "Ops Agent 配置文件不存在: $agent_config_file（安装是否成功？）"
    fi

    # 期望的完整配置内容
    local expected_config
    expected_config=$(cat <<'EOF'
logging:
  receivers:
    systemd_journal:
      type: systemd_journald
  service:
    pipelines:
      default_pipeline:
        receivers: [systemd_journal]
metrics:
  receivers:
    hostmetrics:
      type: hostmetrics
  service:
    pipelines:
      default_pipeline:
        receivers: [hostmetrics]
EOF
)

    # 幂等检查：用内容哈希对比，而非关键词 grep
    local expected_hash current_hash
    expected_hash=$(printf '%s\n' "$expected_config" | sha256sum | cut -d' ' -f1)
    current_hash=$(sha256sum "$agent_config_file" 2>/dev/null | cut -d' ' -f1)

    if [[ "$expected_hash" == "$current_hash" ]]; then
        log_success "Ops Agent 配置已是期望状态，跳过"
        return 0
    fi

    log_substep "备份当前配置文件..."
    sudo cp "$agent_config_file" "${agent_config_file}.$(date +%Y%m%d%H%M%S).bak"

    log_substep "写入新配置..."
    printf '%s\n' "$expected_config" | sudo tee "$agent_config_file" > /dev/null

    # 验证写入后内容哈希一致
    local written_hash
    written_hash=$(sha256sum "$agent_config_file" | cut -d' ' -f1)
    if [[ "$written_hash" != "$expected_hash" ]]; then
        die "Ops Agent 配置写入后内容与期望不一致，请检查磁盘状态"
    fi

    log_substep "重启 Google Cloud Ops Agent..."
    if sudo systemctl restart google-cloud-ops-agent; then
        log_success "Ops Agent 配置并重启成功"
    else
        die "Ops Agent 重启失败，请检查配置文件"
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    configure_ops_agent
fi
