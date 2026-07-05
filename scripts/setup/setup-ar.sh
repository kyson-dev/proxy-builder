#!/bin/bash
# ==============================================================================
# 多环境 GCP Artifact Registry 配置脚本（重构版）
# 支持 production 和 development 环境
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# --- 加载公共库 ---
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/prompt.sh"
source "${SCRIPT_DIR}/../lib/gcp.sh"

# --- 加载系统执行层 ---
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

    # 1. 检测非交互模式条件
    local is_non_interactive=false
    if [[ "${CI:-}" == "true" ]] || [[ "${NON_INTERACTIVE:-}" == "true" ]]; then
        is_non_interactive=true
    fi

    # 解析参数
    local args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --non-interactive) is_non_interactive=true ;;
            *) args+=("$1") ;;
        esac
        shift
    done

    # 2. 确定环境并加载环境上下文
    if [[ "$is_non_interactive" == "true" ]]; then
        if [[ -z "${ENV_NAME:-}" ]]; then
            die "非交互模式错误: 必须指定环境变量 ENV_NAME (production 或 development)"
        fi
    else
        # 交互模式仅选择环境，不要求选择项目
        source "${SCRIPT_DIR}/shared/select-environment.sh"
        select_environment
    fi

    local env_file="${PROJECT_ROOT}/.env.${ENV_NAME}"

    # 3. Project ID 只读本地 .env 文件 (统一读取，避免重复编码)
    local env_project_id=""
    local env_vm_zone=""
    if [[ -f "$env_file" ]]; then
        env_project_id=$(grep "^[[:space:]]*GCP_PROJECT_ID=" "$env_file" | cut -d'=' -f2- | xargs 2>/dev/null || echo "")
        env_vm_zone=$(grep "^[[:space:]]*GCP_VM_ZONE=" "$env_file" | cut -d'=' -f2- | xargs 2>/dev/null || echo "")
    fi
    if [[ -z "$env_project_id" ]]; then
        die "在本地环境配置 '.env.${ENV_NAME}' 中没有找到 GCP_PROJECT_ID，请先执行 WIF 或 VM 初始化配置！"
    fi
    PROJECT_ID="$env_project_id"
    log_success "检测并复用项目环境: $PROJECT_ID"

    # 4. 统一推导默认区域与仓库默认值 (default_location & default_repository)
    local default_location="us-west1"
    if [[ -n "$env_vm_zone" ]]; then
        default_location="${env_vm_zone%-*}"
    fi
    local default_repository="proxy-repo"

    # 5. 根据模式配置 Artifact Registry 变量
    if [[ "$is_non_interactive" == "true" ]]; then
        GCP_AR_LOCATION="${GCP_AR_LOCATION:-$default_location}"
        GCP_AR_REPOSITORY="${GCP_AR_REPOSITORY:-$default_repository}"
    else
        # 调用辅助层获取 AR 变量 (以回传值方式，不使用全局变量导出)
        source "${SCRIPT_DIR}/ar/helpers.sh"
        local selected_loc=""
        local selected_repo=""
        ar_select_or_configure_interactive "$PROJECT_ID" "$default_repository" "$default_location" "selected_loc" "selected_repo"
        
        GCP_AR_LOCATION="$selected_loc"
        GCP_AR_REPOSITORY="$selected_repo"
    fi

    # 2. 调用系统执行层执行物理创建/校验并导出标准化变量
    infra::create_ar_repo "$PROJECT_ID" "$GCP_AR_LOCATION" "$GCP_AR_REPOSITORY"

    # 3. 写入本地环境配置
    echo ""
    log_step "写入 Artifact Registry 参数至本地环境配置"
    update_env_file "$env_file" "GCP_AR_LOCATION"   "$AR_LOCATION"
    update_env_file "$env_file" "GCP_AR_REPOSITORY" "$AR_REPOSITORY"
    echo ""

    print_summary "$ENV_NAME" "$PROJECT_ID" "$AR_LOCATION" "$AR_REPOSITORY"
}

main "$@"
