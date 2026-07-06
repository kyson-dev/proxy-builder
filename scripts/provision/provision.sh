#!/bin/bash
# ==============================================================================
# 主机供给脚本（一次性系统级初始化）
#
# 执行时机：新建 VM 首次初始化，或系统环境变更后手动重新执行。
# 不在常规部署流水线中执行，只由 bootstrap-deploy.sh 在首次检测到
# 环境未就绪时调用，或由运维人员手动执行。
#
# 完成后系统状态：
#   - jq、openssl 已安装
#   - Docker 已安装，daemon 日志驱动配置为 journald
#   - BBR 已启用
#   - systemd-journald 日志容量已限制为 500M（drop-in 机制）
#   - Google Cloud Ops Agent 未启用（学习项目暂不需要云端日志/监控，
#     相关步骤已注释保留，如需启用云端日志采集，取消下方注释即可）
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载通用库
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/os.sh"
source "${SCRIPT_DIR}/../lib/docker.sh"

# 加载供给所需模块
source "${SCRIPT_DIR}/install-dependencies.sh"
source "${SCRIPT_DIR}/install-docker.sh"
source "${SCRIPT_DIR}/enable-bbr.sh"
source "${SCRIPT_DIR}/configure-journald.sh"
# source "${SCRIPT_DIR}/configure-ops-agent.sh"  # 已禁用：学习项目不需要云端日志，需要时取消注释
source "${SCRIPT_DIR}/configure-permission.sh"

# ==============================================================================
# 主流程
# ==============================================================================
main() {
    local start_time
    start_time=$(date +%s)

    print_header "主机供给（Host Provisioning）"

    # Step 1: 安装系统依赖（jq、openssl）
    check_dependencies
    echo ""

    # Step 2: 安装 Docker 并配置 daemon 日志驱动
    install_docker
    configure_docker_daemon
    echo ""

    # Step 3: 启用 BBR 拥塞控制
    enable_bbr
    echo ""

    # Step 4: 配置 systemd-journald 容量限制
    configure_journald
    echo ""

    # Step 5: 安装并配置 Google Cloud Ops Agent（已禁用，需要时取消注释）
    # configure_ops_agent
    # echo ""

    # Step 6: 初始化并授权工作目录
    configure_permission
    echo ""

    local end_time duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))

    print_separator
    log_success "主机供给完成！耗时: ${duration}s"
    log_substep "现在可以运行 scripts/deploy/deploy.sh 部署应用"
    print_separator
}

main "$@"
