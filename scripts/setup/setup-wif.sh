#!/bin/bash
# ==============================================================================
# 多环境 GCP WIF 配置脚本（重构版）
# 支持 production 和 development 环境
#
# 此脚本作为编排入口，通过 modules/infra-wif.sh 调用底层 WIF 操作并写入本地 .env
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 加载公共库 ---
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/prompt.sh"
source "${SCRIPT_DIR}/../lib/gcp.sh"
source "${SCRIPT_DIR}/../lib/github.sh"

# --- 加载上下文解析器 + 功能模块 ---
source "${SCRIPT_DIR}/shared/resolve-context.sh"
source "${SCRIPT_DIR}/modules/infra-wif.sh"

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
    echo "   1. 运行虚拟机配置: make setup-vm"
    echo "   2. 运行仓库配置:   make setup-ar"
    echo "   3. 推送至 GitHub:  make upload-env"
    echo "   （或使用一键部署: make setup-infra）"
    echo ""
}

# ==============================================================================
# 主流程
# ==============================================================================
main() {
    print_header "设置 Workload Identity Federation for GitHub Actions"

    # 前置检查
    check_prerequisites

    # 解析上下文（选择环境 + 项目 + GitHub 仓库）
    resolve_context --need-repo

    # 调用 Layer 2 模块完成 WIF 配置
    infra::setup_wif "$PROJECT_ID" "$REPO"

    # 写入本地环境配置
    local env_file="${SCRIPT_DIR}/../../.env.${ENV_NAME}"
    echo ""
    log_step "写入 GCP WIF 凭证至本地环境配置"
    update_env_file "$env_file" "GCP_PROJECT_ID"                 "$PROJECT_ID"
    update_env_file "$env_file" "GCP_WORKLOAD_IDENTITY_PROVIDER" "$PROVIDER_ID"
    update_env_file "$env_file" "GCP_SERVICE_ACCOUNT"            "$SA_EMAIL"
    echo ""

    # 打印摘要
    print_summary "$ENV_NAME" "$PROJECT_ID" "$PROVIDER_ID" "$SA_EMAIL"
}

main "$@"
