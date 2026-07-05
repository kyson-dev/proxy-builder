#!/bin/bash
# ==============================================================================
# 多环境 GCP WIF 配置脚本（重构版）
# 支持 production 和 development 环境
#
# 全局唯一允许交互式选择/写入 GCP_PROJECT_ID 的入口。
# 其它 setup-*.sh 脚本只读本地 .env.<env> 里已有的 GCP_PROJECT_ID。
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# --- 加载公共库 ---
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/prompt.sh"
source "${SCRIPT_DIR}/../lib/gcp.sh"
source "${SCRIPT_DIR}/../lib/github.sh"

# --- 加载系统执行层 ---
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

    check_prerequisites

    # 1. 检测非交互模式条件
    local is_non_interactive=false
    if [[ "${CI:-}" == "true" ]] || [[ "${NON_INTERACTIVE:-}" == "true" ]]; then
        is_non_interactive=true
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --non-interactive) is_non_interactive=true ;;
        esac
        shift
    done

    # 2. 确定环境
    if [[ "$is_non_interactive" == "true" ]]; then
        if [[ -z "${ENV_NAME:-}" ]]; then
            die "非交互模式错误: 必须指定环境变量 ENV_NAME (production 或 development)"
        fi
    else
        source "${SCRIPT_DIR}/shared/select-environment.sh"
        select_environment
    fi

    local env_file="${PROJECT_ROOT}/.env.${ENV_NAME}"

    # 3. 记录变更前的 project id，供之后判断是否需要清理旧项目资源
    local old_project_id=""
    if [[ -f "$env_file" ]]; then
        old_project_id=$(grep "^[[:space:]]*GCP_PROJECT_ID=" "$env_file" | cut -d'=' -f2- | xargs 2>/dev/null || echo "")
    fi

    # 4. 确定 PROJECT_ID 与 REPO
    if [[ "$is_non_interactive" == "true" ]]; then
        if [[ -z "${GCP_PROJECT_ID:-}" ]]; then
            die "非交互模式缺少必须变量: GCP_PROJECT_ID"
        fi
        if [[ -z "${GITHUB_REPO:-}" ]]; then
            die "非交互模式缺少必须变量: GITHUB_REPO (格式: owner/repo)"
        fi
        PROJECT_ID="$GCP_PROJECT_ID"
        REPO="$GITHUB_REPO"
        REPO_OWNER="${REPO%%/*}"
        log_success "上下文 (非交互): PROJECT_ID=$PROJECT_ID, GITHUB_REPO=$REPO"
    else
        source "${SCRIPT_DIR}/shared/select-project.sh"
        select_gcp_project

        source "${SCRIPT_DIR}/shared/confirm-repo.sh"
        confirm_github_repo
    fi

    # 5. Project 变更检测: 清除旧项目下的 VM/AR 本地配置
    if [[ -n "$old_project_id" ]] && [[ "$old_project_id" != "$PROJECT_ID" ]]; then
        log_warn "检测到 project id 变更 ($old_project_id → $PROJECT_ID)，清除旧项目下的 VM/AR 本地配置"
        remove_env_file_key "$env_file" "GCP_VM_NAME"
        remove_env_file_key "$env_file" "GCP_VM_ZONE"
        remove_env_file_key "$env_file" "GCP_AR_LOCATION"
        remove_env_file_key "$env_file" "GCP_AR_REPOSITORY"
        echo ""
    fi

    # 6. 调用 Layer 2 模块完成 WIF 配置
    infra::setup_wif "$PROJECT_ID" "$REPO"

    # 7. 写入本地环境配置
    echo ""
    log_step "写入 GCP WIF 凭证至本地环境配置"
    update_env_file "$env_file" "GCP_PROJECT_ID"                 "$PROJECT_ID"
    update_env_file "$env_file" "GCP_WORKLOAD_IDENTITY_PROVIDER" "$PROVIDER_ID"
    update_env_file "$env_file" "GCP_SERVICE_ACCOUNT"            "$SA_EMAIL"
    echo ""

    print_summary "$ENV_NAME" "$PROJECT_ID" "$PROVIDER_ID" "$SA_EMAIL"
}

main "$@"
