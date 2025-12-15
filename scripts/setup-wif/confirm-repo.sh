#!/bin/bash
# ==============================================================================
# 确认 GitHub 仓库
# 注意: 此脚本应被主脚本 source，依赖库由主脚本加载
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
    source "${_SELF_DIR}/../lib/prompt.sh"
fi

# ------------------------------------------------------------------------------
# 获取当前 Git 仓库信息
# ------------------------------------------------------------------------------
get_current_repo() {
    local remote_url
    remote_url=$(git config --get remote.origin.url 2>/dev/null)
    
    if [[ -z "$remote_url" ]]; then
        return 1
    fi
    
    # 处理各种 URL 格式
    # SSH: git@github.com:owner/repo.git
    # HTTPS: https://github.com/owner/repo.git
    echo "$remote_url" | sed -E 's/.*github\.com[:/]([^/]+\/[^.]+)(\.git)?$/\1/'
}

# ------------------------------------------------------------------------------
# 主函数
# ------------------------------------------------------------------------------
confirm_github_repo() {
    log_step "Step 2: 确认 GitHub 仓库"
    echo ""
    
    # 检查 gh CLI
    if ! command_exists gh; then
        die "GitHub CLI (gh) 未安装。请访问 https://cli.github.com 安装"
    fi
    
    local detected_repo
    detected_repo=$(get_current_repo)
    
    if [[ -n "$detected_repo" ]]; then
        prompt_with_default "GitHub 仓库" "$detected_repo"
        REPO="$INPUT_VALUE"
    else
        prompt_required "请输入 GitHub 仓库 (owner/repo)"
        REPO="$INPUT_VALUE"
    fi
    
    # 验证格式
    if [[ ! "$REPO" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$ ]]; then
        die "无效的仓库格式。应为: owner/repo"
    fi
    
    log_success "使用仓库: $REPO"
    echo ""
    
    # 导出仓库拥有者
    REPO_OWNER="${REPO%%/*}"
    
    export REPO REPO_OWNER
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    confirm_github_repo
    echo "REPO=$REPO"
    echo "REPO_OWNER=$REPO_OWNER"
fi
