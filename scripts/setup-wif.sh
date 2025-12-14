#!/bin/bash
# ==============================================================================
# 多环境 WIF 配置脚本
# 支持 production 和 development 环境
# 
# 此脚本作为编排入口，调用各个子模块完成配置
# ==============================================================================
set -e

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载通用库（所有库都在此加载，子模块不再重复加载）
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/prompt.sh"
source "${SCRIPT_DIR}/lib/gcp.sh"

# 加载子模块
source "${SCRIPT_DIR}/setup-wif/select-environment.sh"
source "${SCRIPT_DIR}/setup-wif/select-project.sh"
source "${SCRIPT_DIR}/setup-wif/confirm-repo.sh"
source "${SCRIPT_DIR}/setup-wif/enable-apis.sh"
source "${SCRIPT_DIR}/setup-wif/setup-service-account.sh"
source "${SCRIPT_DIR}/setup-wif/setup-wif-pool.sh"
source "${SCRIPT_DIR}/setup-wif/bind-repo-to-sa.sh"
source "${SCRIPT_DIR}/setup-wif/select-or-create-vm.sh"
source "${SCRIPT_DIR}/setup-wif/ensure-oslogin.sh"
source "${SCRIPT_DIR}/setup-wif/set-github-secrets.sh"

# ==============================================================================
# 配置
# ==============================================================================
SA_NAME="github-deploy"
POOL_NAME="github-pool"
PROVIDER_NAME="github-provider"

# ==============================================================================
# 前置检查
# ==============================================================================
check_prerequisites() {
    log_step "前置检查"
    
    if ! command_exists gcloud; then
        die "gcloud CLI 未安装"
    fi
    log_success "gcloud CLI 已安装"
    
    if ! command_exists gh; then
        die "GitHub CLI (gh) 未安装"
    fi
    log_success "GitHub CLI 已安装"
    
    echo ""
}

# ==============================================================================
# 主流程
# ==============================================================================
main() {
    print_header "设置 Workload Identity Federation for GitHub Actions"
    
    # 前置检查
    check_prerequisites
    
    # Step 0: 选择环境
    select_environment
    
    # Step 1: 选择 GCP 项目
    select_gcp_project
    
    # Step 2: 确认 GitHub 仓库
    confirm_github_repo
    
    # Step 3: 启用 APIs
    enable_required_apis "$PROJECT_ID"
    
    # Step 4-5: 创建 Service Account 并授权
    setup_service_account "$PROJECT_ID"
    
    # Step 6-7: 创建 WIF Pool 和 Provider
    setup_wif_pool "$PROJECT_ID" "$REPO_OWNER"
    
    # Step 8: 绑定 GitHub 仓库到 Service Account
    bind_repo_to_sa "$PROJECT_ID" "$SA_NAME" "$POOL_ID" "$REPO"
    
    # Step 9: 选择或创建 VM
    select_or_create_vm "$PROJECT_ID" "$ENV_NAME"
    
    # Step 10: 确保 OS Login 启用
    ensure_oslogin "$PROJECT_ID" "$VM_NAME" "$VM_ZONE"
    
    # Step 11: 设置 GitHub Secrets
    set_github_secrets "$ENV_NAME" "$REPO" "$PROJECT_ID" "$PROVIDER_ID" "$SA_NAME" "$VM_NAME" "$VM_ZONE"
    
    # 打印摘要
    print_summary "$ENV_NAME" "$PROJECT_ID" "$VM_NAME" "$VM_ZONE" "$PROVIDER_ID"
}

# 运行主流程
main "$@"
