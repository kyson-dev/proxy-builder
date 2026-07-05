#!/bin/bash
# ==============================================================================
# 一键基建部署脚本
# 职责: 纯编排 —— 依次以子进程调用 setup-wif.sh / setup-vm.sh / setup-ar.sh /
#       setup-firewall.sh，不直接 source 任何 modules/infra-*.sh，不重复实现
#       任何交互式参数收集逻辑。
#
# 用法:
#   ./scripts/setup/setup-infra.sh [--non-interactive] [--skip-wif] [--skip-vm]
#                                  [--skip-ar] [--skip-firewall]
#
# 交互模式（默认）: 只解析一次 ENV_NAME，随后各子脚本各自完成自己的交互流程
#（PROJECT_ID 只能由 setup-wif.sh 交互式选择；VM/AR/Firewall 只读 .env 里的值）。
#
# 非交互模式（--non-interactive 或 CI=true）:
#   必须: ENV_NAME
#   WIF 必须（除非 --skip-wif）: GCP_PROJECT_ID, GITHUB_REPO
#   VM/AR 参数（除非跳过）沿用各自脚本的默认值，可通过环境变量覆盖，
#   具体见 setup-vm.sh / setup-ar.sh 的说明。
#
# Project ID 变更保护:
#   若 WIF 步骤检测到 project id 相较 .env 中原值发生变化，会自动清除旧项目下
#   的 VM/AR 本地配置（见 setup-wif.sh）。本脚本在此基础上还会强制忽略
#   --skip-vm/--skip-ar/--skip-firewall，因为这些资源必须在新项目下重新建立。
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# --- 加载公共库 ---
source "${SCRIPT_DIR}/../lib/common.sh"

# ==============================================================================
# 参数解析
# ==============================================================================
IS_NON_INTERACTIVE=false
if [[ "${CI:-}" == "true" ]] || [[ "${NON_INTERACTIVE:-}" == "true" ]]; then
    IS_NON_INTERACTIVE=true
fi

SKIP_WIF=false
SKIP_VM=false
SKIP_AR=false
SKIP_FIREWALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --non-interactive) IS_NON_INTERACTIVE=true ;;
        --skip-wif)       SKIP_WIF=true ;;
        --skip-vm)        SKIP_VM=true ;;
        --skip-ar)        SKIP_AR=true ;;
        --skip-firewall)  SKIP_FIREWALL=true ;;
        -h|--help)
            sed -n '2,25p' "${BASH_SOURCE[0]}" | grep '^#' | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            log_warn "未知参数: $1（已忽略）"
            ;;
    esac
    shift
done

# ==============================================================================
# 内部工具: 从 .env.<env> 文件读取指定 key 的值
# ==============================================================================
_read_env_value() {
    local file_path="$1"
    local key="$2"
    [[ -f "$file_path" ]] || { echo ""; return 0; }
    grep "^[[:space:]]*${key}=" "$file_path" | cut -d'=' -f2- | xargs 2>/dev/null || echo ""
}

# ==============================================================================
# 打印最终摘要（统一从 .env.<env> 回填，不依赖子进程内存中的变量）
# ==============================================================================
_print_summary() {
    local env_name="$1"
    local env_file="$2"

    print_separator
    log_success "基础设施部署完成 — '$env_name' 环境"
    print_separator
    echo ""
    echo "已写入本地配置: $(basename "$env_file")"
    echo ""

    if [[ "$SKIP_WIF" == "false" ]]; then
        echo "  GCP_PROJECT_ID:                 $(_read_env_value "$env_file" GCP_PROJECT_ID)"
        echo "  GCP_WORKLOAD_IDENTITY_PROVIDER:  $(_read_env_value "$env_file" GCP_WORKLOAD_IDENTITY_PROVIDER)"
        echo "  GCP_SERVICE_ACCOUNT:             $(_read_env_value "$env_file" GCP_SERVICE_ACCOUNT)"
    fi
    if [[ "$SKIP_VM" == "false" ]]; then
        echo "  GCP_VM_NAME:                     $(_read_env_value "$env_file" GCP_VM_NAME)"
        echo "  GCP_VM_ZONE:                     $(_read_env_value "$env_file" GCP_VM_ZONE)"
    fi
    if [[ "$SKIP_AR" == "false" ]]; then
        echo "  GCP_AR_LOCATION:                 $(_read_env_value "$env_file" GCP_AR_LOCATION)"
        echo "  GCP_AR_REPOSITORY:               $(_read_env_value "$env_file" GCP_AR_REPOSITORY)"
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

    # ---- Step 0: 解析一次 ENV_NAME，供所有子脚本复用 ----
    if [[ "$IS_NON_INTERACTIVE" == "true" ]]; then
        if [[ -z "${ENV_NAME:-}" ]]; then
            die "非交互模式错误: 必须指定环境变量 ENV_NAME (production 或 development)"
        fi
    else
        source "${SCRIPT_DIR}/shared/select-environment.sh"
        select_environment
    fi
    export ENV_NAME

    local env_file="${PROJECT_ROOT}/.env.${ENV_NAME}"
    local non_interactive_flag=()
    if [[ "$IS_NON_INTERACTIVE" == "true" ]]; then
        non_interactive_flag=(--non-interactive)
        # 同时导出环境变量，双重保证子脚本进入非交互模式
        export NON_INTERACTIVE=true
    fi

    # ---- Step 1: WIF ----
    local old_project_id=""
    if [[ "$SKIP_WIF" == "false" ]]; then
        old_project_id=$(_read_env_value "$env_file" GCP_PROJECT_ID)

        echo ""
        log_step "阶段 1/4: Workload Identity Federation"
        "${SCRIPT_DIR}/setup-wif.sh" ${non_interactive_flag[@]+"${non_interactive_flag[@]}"}

        # 若 project id 发生变化，VM/AR/Firewall 依赖的资源必须重新建立，
        # 强制忽略 --skip-* （setup-wif.sh 已经清除了 .env 里过期的 VM/AR 记录）
        local new_project_id
        new_project_id=$(_read_env_value "$env_file" GCP_PROJECT_ID)
        if [[ -n "$old_project_id" ]] && [[ -n "$new_project_id" ]] && [[ "$old_project_id" != "$new_project_id" ]]; then
            log_warn "检测到 project id 变更 ($old_project_id → $new_project_id)，强制启用 VM/AR/Firewall（忽略 --skip-*）"
            SKIP_VM=false
            SKIP_AR=false
            SKIP_FIREWALL=false
        fi
    fi

    # ---- Step 2: VM ----
    if [[ "$SKIP_VM" == "false" ]]; then
        echo ""
        log_step "阶段 2/4: 虚拟机"
        "${SCRIPT_DIR}/setup-vm.sh" ${non_interactive_flag[@]+"${non_interactive_flag[@]}"}
    fi

    # ---- Step 3: Artifact Registry ----
    if [[ "$SKIP_AR" == "false" ]]; then
        echo ""
        log_step "阶段 3/4: Artifact Registry"
        "${SCRIPT_DIR}/setup-ar.sh" ${non_interactive_flag[@]+"${non_interactive_flag[@]}"}
    fi

    # ---- Step 4: Firewall ----
    if [[ "$SKIP_FIREWALL" == "false" ]]; then
        echo ""
        log_step "阶段 4/4: 防火墙规则"
        "${SCRIPT_DIR}/setup-firewall.sh" ${non_interactive_flag[@]+"${non_interactive_flag[@]}"}
    fi

    # ---- 汇总 ----
    echo ""
    _print_summary "$ENV_NAME" "$env_file"
}

main "$@"
