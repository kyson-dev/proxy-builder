#!/bin/bash
# ==============================================================================
# 多环境 GCP WIF 配置脚本
# 支持 production 和 development 环境
# 
# 此脚本作为编排入口，调用 WIF 相关子模块完成配置并写入本地 .env
# ==============================================================================
set -e

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载通用库
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/prompt.sh"
source "${SCRIPT_DIR}/../lib/gcp.sh"
source "${SCRIPT_DIR}/../lib/github.sh"

# 加载子模块
source "${SCRIPT_DIR}/shared/select-environment.sh"
source "${SCRIPT_DIR}/shared/select-project.sh"
source "${SCRIPT_DIR}/shared/confirm-repo.sh"
source "${SCRIPT_DIR}/wif/enable-apis.sh"
source "${SCRIPT_DIR}/wif/setup-service-account.sh"
source "${SCRIPT_DIR}/wif/setup-wif-pool.sh"
source "${SCRIPT_DIR}/wif/bind-repo-to-sa.sh"

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
    
    github_check_cli
    log_success "GitHub CLI 已安装"
    
    echo ""
}

# ==============================================================================
# 打印摘要
# ==============================================================================
print_summary() {
    local env_name="$1"
    local project="$2"
    local provider_id="$3"
    local sa_email="$4"
    
    print_separator
    log_success "WIF 设置完成 - '$env_name' 环境"
    print_separator
    echo ""
    echo "配置摘要 (已写入本地 .env.${env_name}):"
    echo "  环境:     $env_name"
    echo "  项目 ID:  $project"
    echo "  Provider: $provider_id"
    echo "  服务账号: $sa_email"
    echo ""
    echo "📋 下一步:"
    echo "   1. 运行虚拟机配置: ./scripts/setup/setup-vm.sh"
    echo "   2. 运行仓库配置:   ./scripts/setup/setup-ar.sh"
    echo "   3. 推送至 GitHub:  ./scripts/setup/upload-env.sh"
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
    
    # Step 9: 写入到本地环境配置
    local env_file="${SCRIPT_DIR}/../../.env.${ENV_NAME}"
    local sa_email
    sa_email=$(gcp_sa_email "$SA_NAME" "$PROJECT_ID")
    
    echo ""
    log_step "写入 GCP WIF 凭证至本地环境配置"
    update_env_file "$env_file" "GCP_PROJECT_ID" "$PROJECT_ID"
    update_env_file "$env_file" "GCP_WORKLOAD_IDENTITY_PROVIDER" "$PROVIDER_ID"
    update_env_file "$env_file" "GCP_SERVICE_ACCOUNT" "$sa_email"
    echo ""
    
    # 打印摘要
    print_summary "$ENV_NAME" "$PROJECT_ID" "$PROVIDER_ID" "$sa_email"
}

# 运行主流程
main "$@"
