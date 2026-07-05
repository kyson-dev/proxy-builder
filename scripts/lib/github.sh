#!/bin/bash
# ==============================================================================
# GitHub CLI 公共交互与操作接口
# ==============================================================================

# 防止重复加载
[[ -n "${_LIB_GITHUB_LOADED:-}" ]] && return 0
_LIB_GITHUB_LOADED=1

# 检查 gh CLI 是否安装
github_check_cli() {
    if ! command_exists gh; then
        die "GitHub CLI (gh) 未安装。请先安装: brew install gh"
    fi
}

# 确保 gh CLI 登录
github_ensure_auth() {
    github_check_cli
    if ! gh auth status &>/dev/null; then
        log_warn "未登录 GitHub CLI"
        echo ""
        echo "请先登录:"
        echo "  gh auth login"
        echo ""
        exit 1
    fi
}

# 设置 GitHub 环境变量 Secret
github_set_secret() {
    local key="$1"
    local value="$2"
    local env_name="$3"
    local repo="$4"

    if [[ -z "$key" || -z "$env_name" ]]; then
        die "github_set_secret 用法: github_set_secret <key> <value> <env_name> [<repo>]"
    fi

    local extra_args=()
    if [[ -n "$repo" ]]; then
        extra_args+=(--repo "$repo")
    fi

    # 设置 secret
    if gh secret set "$key" \
        --env "$env_name" \
        --body "$value" \
        "${extra_args[@]}" &>/dev/null; then
        echo "   ✓ $key"
        return 0
    else
        log_error "上传失败: $key"
        return 1
    fi
}
