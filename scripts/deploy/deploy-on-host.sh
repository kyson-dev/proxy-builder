#!/bin/bash
# ==============================================================================
# VM 端部署执行脚本
#
# 职责：在目标虚拟机上完成从暂存区到生产目录的全流程部署，并在失败时执行回滚。
# 调用方：CI（deploy.yml）通过 gcloud compute ssh 远程调用此脚本。
#
# 前置条件：
#   - ~/app 已由 CI 解压就绪（包含本脚本及所有 deploy 子模块）
#   - ~/app/.env 与 ~/app/users.json 已由 CI 注入
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/paths.sh"

# ------------------------------------------------------------------------------
# 内部函数
# ------------------------------------------------------------------------------

# 停止当前运行中的服务（若存在）
_stop_current_services() {
    if [ -d "${APP_DIR}" ] && [ -f "${APP_DIR}/docker-compose.yml" ]; then
        log_step "停止当前服务..."
        cd "${APP_DIR}"
        docker compose down 2>/dev/null || true
    fi
}

# 备份当前代码目录与数据目录（作为同一版本快照）
_backup_current_version() {
    log_step "备份当前版本..."
    rm -rf "${APP_DIR}.backup"
    rm -rf "${DATA_DIR}.backup"

    [ -d "${APP_DIR}" ]  && mv "${APP_DIR}"  "${APP_DIR}.backup"
    [ -d "${DATA_DIR}" ] && cp -r "${DATA_DIR}" "${DATA_DIR}.backup" || true
}

# 检查主机环境，若不满足则执行 provision 自举
_ensure_host_provisioned() {
    log_step "诊断主机供给环境..."
    chmod +x ~/app/scripts/provision/check-host-env.sh
    if ! ~/app/scripts/provision/check-host-env.sh; then
        log_warn "主机环境不完整，开始自举 (provision.sh)..."
        chmod +x ~/app/scripts/provision/provision.sh
        sudo ~/app/scripts/provision/provision.sh
    fi
}

# 将暂存区代码迁移到生产应用目录
_migrate_to_app_dir() {
    log_step "迁移新代码到应用目录..."
    mkdir -p "${APP_DIR}"
    cp -r ~/app/. "${APP_DIR}/"
    rm -rf ~/app
}

# 执行回滚：代码目录 + 数据目录同时还原，并尝试重启旧版本服务
_rollback() {
    log_error "部署失败，开始回滚..."

    # 清除已迁移（损坏）的新版本，还原代码目录
    rm -rf "${APP_DIR}"
    if [ -d "${APP_DIR}.backup" ]; then
        mv "${APP_DIR}.backup" "${APP_DIR}"
        log_success "代码目录已回滚"
    else
        log_warn "无代码备份，跳过代码回滚"
    fi

    # 还原数据目录
    rm -rf "${DATA_DIR}" || true
    if [ -d "${DATA_DIR}.backup" ]; then
        mv "${DATA_DIR}.backup" "${DATA_DIR}"
        log_success "数据目录已回滚"
    else
        log_warn "无数据备份，跳过数据回滚"
    fi

    # 用旧代码 + 旧数据尝试重启服务
    if [ -d "${APP_DIR}" ]; then
        cd "${APP_DIR}"
        docker compose up -d 2>/dev/null || log_warn "旧版本重启失败"
        log_success "已恢复到旧版本"
    fi
}

# 清理成功部署后的备份目录
_cleanup_backup() {
    log_step "清理备份..."
    rm -rf "${APP_DIR}.backup"
    rm -rf "${DATA_DIR}.backup" || true
}

# 清理不再被任何容器引用的旧镜像（含已打 tag 的旧版本），控制磁盘占用
_prune_old_images() {
    log_step "清理无用 Docker 镜像..."
    docker image prune -af || true
}

# ------------------------------------------------------------------------------
# 主流程
# ------------------------------------------------------------------------------
main() {
    print_header "VM 端部署流程启动"

    # Step 1: 停止当前服务
    _stop_current_services

    # Step 2: 备份当前版本（代码 + 数据同一快照）
    _backup_current_version

    # Step 3: 诊断主机环境，按需执行供给自举
    _ensure_host_provisioned

    # Step 4: 迁移新代码到最终应用目录
    _migrate_to_app_dir

    # Step 5: 执行应用层部署
    log_step "执行应用层部署..."
    cd "${APP_DIR}"
    chmod +x scripts/deploy/deploy.sh

    if ./scripts/deploy/deploy.sh; then
        log_success "部署成功"
        _cleanup_backup
        _prune_old_images
    else
        _rollback
        exit 1
    fi
}

main "$@"
