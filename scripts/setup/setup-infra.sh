#!/bin/bash
# ==============================================================================
# 一键基建部署脚本
# 职责: 编排 WIF → VM → AR → Firewall 全流程，确保所有基础设施使用同一项目
#
# 用法:
#   ./scripts/setup/setup-infra.sh [--non-interactive] [--skip-wif] [--skip-vm]
#                                  [--skip-ar] [--skip-firewall]
#
# 交互模式（默认）:
#   按照 select_environment + select_gcp_project + confirm_github_repo 获取上下文
#
# 非交互模式（--non-interactive 或 CI=true）:
#   通过以下环境变量传入所有参数:
#
#   必须:
#     GCP_PROJECT_ID        GCP 项目 ID
#     ENV_NAME              环境名（production / development）
#
#   WIF 必须（除非 --skip-wif）:
#     GITHUB_REPO           GitHub 仓库，格式 owner/repo
#
#   VM 参数（除非 --skip-vm，均有默认值）:
#     VM_NAME               VM 实例名称（默认: proxy-vm-{env_name}）
#     GCP_VM_ZONE           GCE 区域（默认: us-west1-b）
#     VM_MACHINE_TYPE       机器类型（默认: e2-micro）
#     VM_DISK_SIZE          磁盘大小 GB（默认: 20）
#     VM_DISK_TYPE          磁盘类型（默认: pd-standard）
#     VM_NETWORK_TIER       网络层级（默认: STANDARD）
#     VM_IS_SPOT            是否 Spot 实例（默认: false）
#
#   AR 参数（除非 --skip-ar）:
#     GCP_AR_LOCATION       AR 区域（默认: 从 GCP_VM_ZONE 推导，如 us-west1）
#     GCP_AR_REPOSITORY     AR 仓库名（默认: proxy）
#
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# --- 加载公共库 ---
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/prompt.sh"
source "${SCRIPT_DIR}/../lib/gcp.sh"
source "${SCRIPT_DIR}/../lib/github.sh"

# --- 加载上下文解析器 ---
source "${SCRIPT_DIR}/shared/resolve-context.sh"

# --- 加载功能模块层 ---
source "${SCRIPT_DIR}/modules/infra-wif.sh"
source "${SCRIPT_DIR}/modules/infra-vm.sh"
source "${SCRIPT_DIR}/modules/infra-ar.sh"
source "${SCRIPT_DIR}/modules/infra-firewall.sh"

# ==============================================================================
# 参数解析
# ==============================================================================
SKIP_WIF=false
SKIP_VM=false
SKIP_AR=false
SKIP_FIREWALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --non-interactive) export NON_INTERACTIVE=true ;;
        --skip-wif)       SKIP_WIF=true ;;
        --skip-vm)        SKIP_VM=true ;;
        --skip-ar)        SKIP_AR=true ;;
        --skip-firewall)  SKIP_FIREWALL=true ;;
        -h|--help)
            sed -n '2,40p' "${BASH_SOURCE[0]}" | grep '^#' | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            log_warn "未知参数: $1（已忽略）"
            ;;
    esac
    shift
done

# ==============================================================================
# 内部工具: 从 zone 推导 region
# ==============================================================================
_zone_to_region() {
    local zone="$1"
    echo "${zone%-*}"
}

# ==============================================================================
# 交互模式: 交互式收集 VM 参数
# ==============================================================================
_collect_vm_params_interactive() {
    local env_name="$1"
    local default_name="proxy-vm-${env_name}"

    echo ""
    log_step "VM 参数配置"

    prompt_with_default "VM 实例名称" "$default_name"
    
    VM_NAME="$INPUT_VALUE"

    echo ""
    echo "VM 预设配置:"
    echo "  1. Google Free Tier (e2-micro, us-west1-b, 30GB)"
    echo "  2. Spot 实例        (e2-micro, us-central1-a, 10GB)"
    echo "  3. 自定义配置"
    echo ""

    local preset_choice
    while true; do
        read -rp "选择预设 (1-3) [默认: 1]: " preset_choice
        preset_choice="${preset_choice:-1}"
        case "$preset_choice" in
            1)
                GCP_VM_ZONE="us-west1-b"
                VM_MACHINE_TYPE="e2-micro"
                VM_DISK_SIZE="30"
                VM_DISK_TYPE="pd-standard"
                VM_NETWORK_TIER="STANDARD"
                VM_IS_SPOT="false"
                break
                ;;
            2)
                GCP_VM_ZONE="us-central1-a"
                VM_MACHINE_TYPE="e2-micro"
                VM_DISK_SIZE="10"
                VM_DISK_TYPE="pd-standard"
                VM_NETWORK_TIER="STANDARD"
                VM_IS_SPOT="true"
                break
                ;;
            3)
                prompt_with_default "GCE 区域 (如 us-central1-a)" "us-central1-a"
                GCP_VM_ZONE="$INPUT_VALUE"
                prompt_with_default "机器类型" "e2-micro"
                VM_MACHINE_TYPE="$INPUT_VALUE"
                prompt_with_default "磁盘大小 (GB)" "20"
                VM_DISK_SIZE="$INPUT_VALUE"
                prompt_with_default "网络层级 (STANDARD/PREMIUM)" "STANDARD"
                VM_NETWORK_TIER="$INPUT_VALUE"
                VM_DISK_TYPE="pd-standard"
                VM_IS_SPOT="false"
                break
                ;;
            *) echo "无效选择，请重试。" ;;
        esac
    done
}

# ==============================================================================
# 交互模式: 交互式收集 AR 参数
# ==============================================================================
_collect_ar_params_interactive() {
    local vm_zone="${1:-}"
    echo ""
    log_step "Artifact Registry 参数配置"

    local default_location="us-west1"
    if [[ -n "$vm_zone" ]]; then
        default_location=$(_zone_to_region "$vm_zone")
    fi

    prompt_with_default "AR 区域" "$default_location"
    GCP_AR_LOCATION="$INPUT_VALUE"

    prompt_with_default "AR 仓库名称" "proxy"
    GCP_AR_REPOSITORY="$INPUT_VALUE"
}

# ==============================================================================
# 打印最终摘要
# ==============================================================================
_print_summary() {
    local env_name="$1"
    local project_id="$2"
    local env_file="$3"

    print_separator
    log_success "基础设施部署完成 — '$env_name' 环境"
    print_separator
    echo ""
    echo "已写入本地配置: $(basename "$env_file")"
    echo ""

    if [[ "$SKIP_WIF" == "false" ]]; then
        echo "  GCP_PROJECT_ID:               $project_id"
        echo "  GCP_WORKLOAD_IDENTITY_PROVIDER: ${PROVIDER_ID:-（未配置）}"
        echo "  GCP_SERVICE_ACCOUNT:          ${SA_EMAIL:-（未配置）}"
    fi
    if [[ "$SKIP_VM" == "false" ]]; then
        echo "  GCP_VM_NAME:                  ${VM_NAME:-（未配置）}"
        echo "  GCP_VM_ZONE:                  ${GCP_VM_ZONE:-（未配置）}"
    fi
    if [[ "$SKIP_AR" == "false" ]]; then
        echo "  GCP_AR_LOCATION:              ${AR_LOCATION:-（未配置）}"
        echo "  GCP_AR_REPOSITORY:            ${AR_REPOSITORY:-（未配置）}"
    fi
    echo ""
    echo "📋 下一步:"
    echo "   推送配置至 GitHub Secrets: make upload-env"
    echo ""
}

# ==============================================================================
# 主流程
# ==============================================================================
main() {
    print_header "一键基础设施部署"
    echo ""
    echo "将按顺序完成: WIF → VM → Artifact Registry → Firewall"
    echo "所有组件使用同一 GCP 项目，确保一致性。"
    if [[ "${SKIP_WIF}${SKIP_VM}${SKIP_AR}${SKIP_FIREWALL}" != "falsefalsefalsefalse" ]]; then
        local skipped=()
        [[ "$SKIP_WIF" == "true" ]] && skipped+=("WIF")
        [[ "$SKIP_VM" == "true" ]] && skipped+=("VM")
        [[ "$SKIP_AR" == "true" ]] && skipped+=("AR")
        [[ "$SKIP_FIREWALL" == "true" ]] && skipped+=("Firewall")
        log_warn "已跳过: ${skipped[*]}"
    fi
    echo ""

    # ---- Step 0: 解析上下文 ----
    local need_repo_flag=""
    [[ "$SKIP_WIF" == "false" ]] && need_repo_flag="--need-repo"
    resolve_context ${need_repo_flag}

    local env_file="${PROJECT_ROOT}/.env.${ENV_NAME}"

    # ---- Step 1: WIF ----
    if [[ "$SKIP_WIF" == "false" ]]; then
        echo ""
        log_step "阶段 1/4: Workload Identity Federation"
        infra::setup_wif "$PROJECT_ID" "$REPO"

        # 写入 .env 文件
        update_env_file "$env_file" "GCP_PROJECT_ID"                    "$PROJECT_ID"
        update_env_file "$env_file" "GCP_WORKLOAD_IDENTITY_PROVIDER"    "$PROVIDER_ID"
        update_env_file "$env_file" "GCP_SERVICE_ACCOUNT"               "$SA_EMAIL"
    fi

    # ---- Step 2: VM ----
    if [[ "$SKIP_VM" == "false" ]]; then
        echo ""
        log_step "阶段 2/4: 虚拟机"

        # 非交互模式: 从环境变量读取 VM 参数（含默认值）
        if [[ "${NON_INTERACTIVE:-}" == "true" ]] || [[ "${CI:-}" == "true" ]]; then
            VM_NAME="${VM_NAME:-proxy-vm-${ENV_NAME}}"
            GCP_VM_ZONE="${GCP_VM_ZONE:-us-west1-b}"
            VM_MACHINE_TYPE="${VM_MACHINE_TYPE:-e2-micro}"
            VM_DISK_SIZE="${VM_DISK_SIZE:-20}"
            VM_DISK_TYPE="${VM_DISK_TYPE:-pd-standard}"
            VM_NETWORK_TIER="${VM_NETWORK_TIER:-STANDARD}"
            VM_IS_SPOT="${VM_IS_SPOT:-false}"
        else
            # 交互模式: 询问 VM 参数
            _collect_vm_params_interactive "$ENV_NAME"
        fi

        infra::create_vm \
            "$PROJECT_ID" \
            "$VM_NAME" \
            "$GCP_VM_ZONE" \
            "${VM_MACHINE_TYPE:-e2-micro}" \
            "${VM_DISK_SIZE:-20}" \
            "${VM_DISK_TYPE:-pd-standard}" \
            "${VM_NETWORK_TIER:-STANDARD}" \
            "${VM_IS_SPOT:-false}"

        infra::ensure_vm_oslogin "$PROJECT_ID" "$VM_NAME" "$GCP_VM_ZONE"

        # 写入 .env 文件
        update_env_file "$env_file" "GCP_VM_NAME" "$VM_NAME"
        update_env_file "$env_file" "GCP_VM_ZONE" "$GCP_VM_ZONE"
    fi

    # ---- Step 3: Artifact Registry ----
    if [[ "$SKIP_AR" == "false" ]]; then
        echo ""
        log_step "阶段 3/4: Artifact Registry"

        # 非交互模式: 从环境变量读取 AR 参数（含默认值推导）
        if [[ "${NON_INTERACTIVE:-}" == "true" ]] || [[ "${CI:-}" == "true" ]]; then
            # 若未指定 location，从 VM zone 推导
            if [[ -z "${GCP_AR_LOCATION:-}" ]]; then
                if [[ -n "${GCP_VM_ZONE:-}" ]]; then
                    GCP_AR_LOCATION=$(_zone_to_region "$GCP_VM_ZONE")
                else
                    GCP_AR_LOCATION="us-west1"
                fi
            fi
            GCP_AR_REPOSITORY="${GCP_AR_REPOSITORY:-proxy}"
        else
            # 交互模式: 询问 AR 参数
            _collect_ar_params_interactive "${GCP_VM_ZONE:-}"
        fi

        infra::create_ar_repo "$PROJECT_ID" "$GCP_AR_LOCATION" "$GCP_AR_REPOSITORY"

        # 写入 .env 文件
        update_env_file "$env_file" "GCP_AR_LOCATION"   "$AR_LOCATION"
        update_env_file "$env_file" "GCP_AR_REPOSITORY" "$AR_REPOSITORY"
    fi

    # ---- Step 4: Firewall ----
    if [[ "$SKIP_FIREWALL" == "false" ]]; then
        echo ""
        log_step "阶段 4/4: 防火墙规则"

        local compose_file="${PROJECT_ROOT}/docker-compose.yml"
        if [[ -f "$compose_file" ]]; then
            infra::apply_firewall_from_compose "$PROJECT_ID" "$compose_file"
        else
            log_warn "docker-compose.yml 不存在，使用默认代理端口"
            infra::apply_firewall_rules "$PROJECT_ID" \
                "443/tcp" "8443/tcp" "8388/tcp" "1080/tcp"
        fi
    fi

    # ---- 汇总 ----
    _print_summary "$ENV_NAME" "$PROJECT_ID" "$env_file"
}

main "$@"
