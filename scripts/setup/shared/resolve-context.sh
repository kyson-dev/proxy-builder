#!/bin/bash
# ==============================================================================
# 统一上下文解析器
# 职责: 支持交互模式与非交互模式，统一设置基建所需的全局变量
# 被 setup-infra.sh 和各独立入口脚本使用
#
# 交互模式（默认）: 调用 select_environment / select_gcp_project / confirm_github_repo
# 非交互模式: 从以下环境变量读取（CI 场景，配合 --non-interactive 或 CI=true）
#
# 必须设置的环境变量（非交互模式）:
#   GCP_PROJECT_ID      GCP 项目 ID
#   ENV_NAME            环境名称（production / development）
#
# 可选环境变量（非交互模式，部分命令需要）:
#   GCP_VM_ZONE         VM 区域（如 us-west1-b），影响 AR region 的默认推导
#   GITHUB_REPO         GitHub 仓库（格式 owner/repo），upload-env 和 WIF 需要
#
# 导出的全局变量:
#   PROJECT_ID          GCP 项目 ID
#   ENV_NAME            环境名称
#   REPO                GitHub 仓库（owner/repo），若不需要则可为空
#   REPO_OWNER          GitHub 仓库拥有者
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../../lib/common.sh"
    source "${_SELF_DIR}/../../lib/prompt.sh"
    source "${_SELF_DIR}/../../lib/gcp.sh"
fi

_RESOLVE_CTX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# 内部: 非交互模式下的上下文读取
# ==============================================================================
_resolve_context_non_interactive() {
    log_substep "非交互模式: 从环境变量读取上下文"

    if [[ -z "${GCP_PROJECT_ID:-}" ]]; then
        die "非交互模式缺少必须变量: GCP_PROJECT_ID"
    fi
    if [[ -z "${ENV_NAME:-}" ]]; then
        die "非交互模式缺少必须变量: ENV_NAME (production 或 development)"
    fi

    PROJECT_ID="$GCP_PROJECT_ID"

    # GITHUB_REPO 非必须（仅在 WIF / upload-env 时需要）
    REPO="${GITHUB_REPO:-}"
    REPO_OWNER="${REPO%%/*}"

    log_success "上下文 (非交互): PROJECT_ID=$PROJECT_ID, ENV_NAME=$ENV_NAME"
    if [[ -n "$REPO" ]]; then
        log_substep "GITHUB_REPO: $REPO"
    fi

    export PROJECT_ID ENV_NAME REPO REPO_OWNER
}

# ==============================================================================
# 内部: 交互模式下的上下文读取
# ==============================================================================
_resolve_context_interactive() {
    # 加载交互式共享组件
    source "${_RESOLVE_CTX_DIR}/select-environment.sh"
    source "${_RESOLVE_CTX_DIR}/select-project.sh"

    select_environment
    select_gcp_project
}

# ==============================================================================
# 内部: 交互模式下的 GitHub 仓库确认
# ==============================================================================
_resolve_github_repo_interactive() {
    source "${_RESOLVE_CTX_DIR}/confirm-repo.sh"
    confirm_github_repo
}

# ==============================================================================
# 主函数: resolve_context
# ==============================================================================
# 参数:
#   $1  [--need-repo]  若传入此标志，则在非交互模式下强制要求 GITHUB_REPO，
#                      在交互模式下调用 confirm_github_repo
#
# 检测非交互模式的条件（任一满足即进入非交互模式）:
#   1. 脚本参数中包含 --non-interactive
#   2. 环境变量 CI=true
# ==============================================================================
resolve_context() {
    local need_repo=false

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --need-repo) need_repo=true ;;
        esac
        shift
    done

    # 判断模式
    local is_non_interactive=false
    if [[ "${CI:-}" == "true" ]] || [[ "${NON_INTERACTIVE:-}" == "true" ]]; then
        is_non_interactive=true
    fi

    if [[ "$is_non_interactive" == "true" ]]; then
        _resolve_context_non_interactive

        # 非交互模式下校验 GITHUB_REPO（若需要）
        if [[ "$need_repo" == "true" ]] && [[ -z "${REPO:-}" ]]; then
            die "非交互模式缺少必须变量: GITHUB_REPO (格式: owner/repo)"
        fi
    else
        _resolve_context_interactive

        # 交互模式下根据 need_repo 决定是否询问 GitHub 仓库
        if [[ "$need_repo" == "true" ]]; then
            _resolve_github_repo_interactive
        fi
    fi
}
