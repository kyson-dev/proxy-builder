#!/bin/bash
# ==============================================================================
# 多环境 GCP Artifact Registry 配置脚本（重构版）
# 支持 production 和 development 环境
#
# 此脚本作为编排入口，通过 modules/infra-ar.sh 调用底层 AR 操作并写入本地 .env
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 加载公共库 ---
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/prompt.sh"
source "${SCRIPT_DIR}/../lib/gcp.sh"

# --- 加载上下文解析器 + 功能模块 ---
source "${SCRIPT_DIR}/shared/resolve-context.sh"
source "${SCRIPT_DIR}/modules/infra-ar.sh"

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
# 交互式收集 AR 参数
# 导出: GCP_AR_LOCATION, GCP_AR_REPOSITORY
# ==============================================================================
_collect_ar_params_interactive() {
    local env_name="$1"
    local env_file="${SCRIPT_DIR}/../../.env.${env_name}"

    echo ""
    log_step "Artifact Registry 参数配置"

    # 从已有 .env 文件读取 VM Zone 作为 region 推导依据
    local zone=""
    if [[ -f "$env_file" ]]; then
        zone=$(grep "^[[:space:]]*GCP_VM_ZONE=" "$env_file" | cut -d'=' -f2- | xargs 2>/dev/null || echo "")
    fi

    # 推导默认 region
    local default_location="us-west1"
    if [[ -n "$zone" ]]; then
        default_location="${zone%-*}"
    fi

    # 交互式：列出现有 AR 仓库或创建新仓库
    source "${SCRIPT_DIR}/ar/setup-artifact-registry.sh"
    setup_artifact_registry "$PROJECT_ID" "$zone"
    # setup_artifact_registry 导出 AR_LOCATION, AR_REPOSITORY
    GCP_AR_LOCATION="$AR_LOCATION"
    GCP_AR_REPOSITORY="$AR_REPOSITORY"
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
    echo "   1. 推送至 GitHub:  make upload-env"
    echo "   （或使用一键部署: make setup-infra）"
    echo ""
}

# ==============================================================================
# 主流程
# ==============================================================================
main() {
    print_header "配置 GCP Artifact Registry Docker 仓库"

    check_prerequisites

    # 解析上下文（选择环境 + 项目）
    resolve_context

    # 交互式收集 AR 参数（列出现有仓库 or 创建新仓库）
    _collect_ar_params_interactive "$ENV_NAME"

    # 写入本地环境配置
    local env_file="${SCRIPT_DIR}/../../.env.${ENV_NAME}"
    echo ""
    log_step "写入 Artifact Registry 参数至本地环境配置"
    update_env_file "$env_file" "GCP_AR_LOCATION"   "$GCP_AR_LOCATION"
    update_env_file "$env_file" "GCP_AR_REPOSITORY" "$GCP_AR_REPOSITORY"
    echo ""

    print_summary "$ENV_NAME" "$PROJECT_ID" "$GCP_AR_LOCATION" "$GCP_AR_REPOSITORY"
}

main "$@"
