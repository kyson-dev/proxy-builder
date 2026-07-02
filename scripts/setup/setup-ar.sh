#!/bin/bash
# ==============================================================================
# 多环境 GCP Artifact Registry 配置脚本
# 支持 production 和 development 环境
# 
# 此脚本作为编排入口，调用 AR 相关子模块完成配置并写入本地 .env
# ==============================================================================
set -e

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载通用库
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/prompt.sh"
source "${SCRIPT_DIR}/../lib/gcp.sh"

# 加载子模块
source "${SCRIPT_DIR}/shared/select-environment.sh"
source "${SCRIPT_DIR}/shared/select-project.sh"
source "${SCRIPT_DIR}/ar/setup-artifact-registry.sh"

# ==============================================================================
# 前置检查
# ==============================================================================
check_prerequisites() {
    log_step "前置检查"
    
    if ! command_exists gcloud; then
        die "gcloud CLI 未安装"
    fi
    log_success "gcloud CLI 已安装"
    
    echo ""
}

# ==============================================================================
# 打印摘要
# ==============================================================================
print_summary() {
    local env_name="$1"
    local project="$2"
    local ar_location="$3"
    local ar_repo="$4"
    
    print_separator
    log_success "Artifact Registry 配置完成 - '$env_name' 环境"
    print_separator
    echo ""
    echo "配置摘要 (已写入本地 .env.${env_name}):"
    echo "  环境:     $env_name"
    echo "  项目 ID:  $project"
    echo "  AR 区域:  $ar_location"
    echo "  AR 仓库:  $ar_repo"
    echo ""
    echo "📋 下一步:"
    echo "   1. 推送至 GitHub:  ./scripts/setup/upload-env.sh"
    echo ""
}

# ==============================================================================
# 主流程
# ==============================================================================
main() {
    print_header "配置 GCP Artifact Registry Docker 仓库"
    
    # 前置检查
    check_prerequisites
    
    # Step 0: 选择环境
    select_environment
    
    # Step 1: 选择 GCP 项目
    select_gcp_project
    
    # Step 2: 尝试从本地环境文件读取已配置的 VM Zone，作为派生 Region 的依据
    local env_file="${SCRIPT_DIR}/../../.env.${ENV_NAME}"
    local zone=""
    if [[ -f "$env_file" ]]; then
        zone=$(grep "^[[:space:]]*GCP_VM_ZONE=" "$env_file" | cut -d'=' -f2- | xargs || echo "")
    fi
    
    # Step 3: 创建或选择 AR 仓库
    setup_artifact_registry "$PROJECT_ID" "$zone"
    
    # Step 4: 写入到本地环境配置
    echo ""
    log_step "写入 Artifact Registry 参数至本地环境配置"
    update_env_file "$env_file" "GCP_AR_LOCATION" "$AR_LOCATION"
    update_env_file "$env_file" "GCP_AR_REPOSITORY" "$AR_REPOSITORY"
    echo ""
    
    # 打印摘要
    print_summary "$ENV_NAME" "$PROJECT_ID" "$AR_LOCATION" "$AR_REPOSITORY"
}

# 运行主流程
main "$@"
