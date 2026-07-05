#!/bin/bash
# ==============================================================================
# 虚拟机端主机环境诊断与校验脚本
#
# 职责：
#   通过调用各供给子模块的内置 is_*_ready 函数，一键健康诊断主机环境。
#   完全消除检测逻辑在多处的重复编写与硬编码。
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/paths.sh"

# 导入所有自举配置脚本以使用其内部封装的 is_*_ready 检测逻辑
source "${SCRIPT_DIR}/install-dependencies.sh"
source "${SCRIPT_DIR}/install-docker.sh"
source "${SCRIPT_DIR}/enable-bbr.sh"
source "${SCRIPT_DIR}/configure-journald.sh"
# source "${SCRIPT_DIR}/configure-ops-agent.sh"  # 已禁用：学习项目不需要云端日志，需要时取消注释
source "${SCRIPT_DIR}/configure-permission.sh"

log_step "启动主机部署环境健康诊断"
echo "--------------------------------------------------"

env_ok=true

# 1. 检查核心系统工具 (jq, openssl)
if is_dependencies_ready; then
    log_success "系统工具: jq 与 openssl 已就绪"
else
    log_error "系统工具: 缺失必要依赖工具 jq 或 openssl"
    env_ok=false
fi

# 2. 检查 BBR 拥塞控制
if is_bbr_ready; then
    log_success "系统内核: BBR 拥塞控制协议已启用"
else
    log_warn "系统内核: 未检测到 BBR 拥塞控制（或尚未启用）"
    env_ok=false
fi

# 3. 检查 journald 日志限制
if is_journald_ready; then
    log_success "系统日志: journald 容量限制配置已写入并符合预期"
else
    log_warn "系统日志: 缺失 journald 容量限制配置"
    env_ok=false
fi

# 4. 检查 Google Cloud Ops Agent（已禁用：学习项目不需要云端日志，需要时取消下方注释）
# if is_ops_agent_ready; then
#     log_success "系统监控: Google Cloud Ops Agent 已启动且日志/指标流水线就绪"
# else
#     log_warn "系统监控: Ops Agent 尚未安装、未运行或配置有偏差"
#     env_ok=false
# fi

# 5. 检查 Docker 引擎与容器运行环境
if is_docker_ready; then
    log_success "容器引擎: Docker 与 Docker Compose 已就绪并处于活跃运行状态"
else
    log_error "容器引擎: Docker 或 Docker Compose 未就绪或配置有偏差"
    env_ok=false
fi

# 6. 检查工作区目录所有权与权限是否就绪 (Owner, Group & SGID Check)
if is_permission_ready; then
    log_success "工作空间: $PROXY_ROOT 的所有权与权限锁配置已就绪"
else
    log_warn "工作空间: 目标根路径 $PROXY_ROOT 属性尚未就绪或未创建"
    env_ok=false
fi

echo "--------------------------------------------------"
if [[ "$env_ok" == "true" ]]; then
    log_success "诊断结论：主机供给状态完全就绪，无需运行主机自举。"
    exit 0
else
    log_warn "诊断结论：主机环境不完整或配置偏差，需要提权运行一次主机自举 (provision.sh)。"
    exit 1
fi
