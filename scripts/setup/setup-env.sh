#!/bin/bash
# ==============================================================================
# 推送配置变量到 GitHub Environment Secrets（重构版，原 upload-env.sh）
# 此脚本作为编排入口，通过 modules/infra-env.sh 调用底层上传操作
# 不涉及 GCP_PROJECT_ID（推送 secret 不需要）
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# --- 加载公共库 ---
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/prompt.sh"
source "${SCRIPT_DIR}/../lib/github.sh"

# --- 加载系统执行层 ---
source "${SCRIPT_DIR}/modules/infra-env.sh"

# ==============================================================================
# 主流程
# ==============================================================================
main() {
    print_header "推送配置到 GitHub Secrets"

    # 1. 确保 GitHub CLI 已登录
    github_ensure_auth

    # 2. 检测非交互模式条件
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

    # 3. 确定环境
    if [[ "$is_non_interactive" == "true" ]]; then
        if [[ -z "${ENV_NAME:-}" ]]; then
            die "非交互模式错误: 必须指定环境变量 ENV_NAME (production 或 development)"
        fi
    else
        source "${SCRIPT_DIR}/shared/select-environment.sh"
        select_environment
    fi

    # 4. 确定 GitHub 仓库
    if [[ "$is_non_interactive" == "true" ]]; then
        if [[ -z "${GITHUB_REPO:-}" ]]; then
            die "非交互模式缺少必须变量: GITHUB_REPO (格式: owner/repo)"
        fi
        REPO="$GITHUB_REPO"
        REPO_OWNER="${REPO%%/*}"
    else
        source "${SCRIPT_DIR}/shared/confirm-repo.sh"
        confirm_github_repo
    fi

    local env_file="${PROJECT_ROOT}/.env.${ENV_NAME}"

    # 检查配置文件是否存在
    if [[ ! -f "$env_file" ]]; then
        log_error "配置文件 '.env.${ENV_NAME}' 不存在!"
        echo ""
        echo "请创建配置文件:"
        echo "  cp .env.example .env.${ENV_NAME}"
        echo "  nano .env.${ENV_NAME}"
        echo ""
        exit 1
    fi

    # 5. 二次确认（非交互模式下跳过）
    if [[ "$is_non_interactive" == "false" ]]; then
        if ! confirm "确认将 '.env.${ENV_NAME}' 推送到 '$ENV_NAME' 环境?" "y"; then
            log_warn "已取消"
            exit 0
        fi
    fi

    echo ""
    log_step "正在推送配置..."

    ENV_UPLOADED_COUNT=0
    ENV_SKIPPED_COUNT=0
    ENV_FAILED_COUNT=0

    # 6. 推送环境变量
    infra::push_env_to_github "$ENV_NAME" "$env_file" "$REPO"

    # 7. 发现并推送用户列表文件（users.<env>.json 优先，否则 fallback users.json）
    local users_file="${PROJECT_ROOT}/users.${ENV_NAME}.json"
    if [[ ! -f "$users_file" ]]; then
        users_file="${PROJECT_ROOT}/users.json"
    fi

    if [[ -f "$users_file" ]]; then
        log_step "发现用户列表文件: $(basename "$users_file")，准备推送到 GitHub Secrets"
        infra::push_json_secret_from_file "USERS_JSON" "$users_file" "$ENV_NAME" "$REPO"
    else
        log_substep "未检测到 users.${ENV_NAME}.json 或 users.json，跳过用户配置上传"
    fi

    echo ""
    print_separator

    if [[ $ENV_FAILED_COUNT -eq 0 ]]; then
        log_success "配置推送完成!"
    else
        log_warn "配置推送完成（有失败项）"
    fi

    print_separator
    echo ""
    echo "📊 统计:"
    echo "   成功: $ENV_UPLOADED_COUNT"
    echo "   跳过: $ENV_SKIPPED_COUNT"
    echo "   失败: $ENV_FAILED_COUNT"
    echo ""
    echo "📋 环境: $ENV_NAME"
    echo "📦 配置: .env.${ENV_NAME}"
    echo ""

    if [[ $ENV_FAILED_COUNT -gt 0 ]]; then
        echo "⚠️  可能原因:"
        echo "   1. GitHub 环境 '$ENV_NAME' 不存在"
        echo "   2. 没有权限访问该仓库"
        echo "   3. gh 登录失效"
        echo ""
        echo "解决方法:"
        echo "   - 确保已创建环境: https://github.com/${REPO}/settings/environments"
        echo "   - 重新登录: gh auth login"
        echo ""
    else
        echo "🎉 下一步:"
        echo "   推送代码触发部署:"
        if [[ "$ENV_NAME" == "production" ]]; then
            echo "     git push origin main"
        else
            echo "     git push origin dev"
        fi
        echo ""
    fi
}

main "$@"
