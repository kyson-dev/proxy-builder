#!/bin/bash
# ==============================================================================
# 配置 Google Cloud Ops Agent 收集 Docker 日志
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
fi

configure_ops_agent() {
    log_step "配置 Google Cloud Ops Agent"

    local agent_config_file="/etc/google-cloud-ops-agent/config.yaml"
    local config_dir="$(dirname "$agent_config_file")"

    if [[ ! -d "$config_dir" ]]; then
        log_warn "未找到 Google Cloud Ops Agent 配置目录，跳过配置"
        return 0
    fi

    # 1. 写入配置文件
    log_substep "写入日志转发规则到 ${agent_config_file}..."
    sudo tee "$agent_config_file" > /dev/null << 'EOF'
logging:
  receivers:
    docker_logs:
      type: files
      include_paths:
        - /var/lib/docker/containers/*/*.log
  processors:
    parse_docker_json:
      type: parse_json
      time_key: time
      time_format: "%Y-%m-%dT%H:%M:%S.%fZ"
  service:
    pipelines:
      default_pipeline:
        receivers: [docker_logs]
        processors: [parse_docker_json]
EOF

    # 2. 解决权限问题 (Ops Agent 默认用户 otelopscol/fluentbit 无法读取 /var/lib/docker)
    # 通过 systemd 覆盖配置，使 Ops Agent 以 root 身份运行，以确保可读性
    log_substep "配置服务运行权限 (systemd override)..."
    sudo mkdir -p /etc/systemd/system/google-cloud-ops-agent.service.d/
    sudo tee /etc/systemd/system/google-cloud-ops-agent.service.d/override.conf > /dev/null << 'EOF'
[Service]
User=root
Group=root
EOF

    # 3. 重新加载 systemd 并重启服务
    log_substep "重启 Google Cloud Ops Agent 服务..."
    sudo systemctl daemon-reload
    if sudo systemctl restart google-cloud-ops-agent; then
        log_success "Google Cloud Ops Agent 配置并重启成功"
    else
        log_error "Google Cloud Ops Agent 重启失败"
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    configure_ops_agent
fi
