#!/bin/bash
# ==============================================================================
# 推送配置变量到 GitHub Environment Secrets
# 编排入口，调用通用组件与子模块完成配置上传
# ==============================================================================
set -e

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 加载通用库
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/prompt.sh"
source "${SCRIPT_DIR}/../lib/github.sh"

# 加载子模块
source "${SCRIPT_DIR}/shared/select-environment.sh"
source "${SCRIPT_DIR}/shared/confirm-repo.sh"
source "${SCRIPT_DIR}/env/push-env-secrets.sh"
source "${SCRIPT_DIR}/env/push-users-json.sh"

# ------------------------------------------------------------------------------
# 主函数
# ------------------------------------------------------------------------------
main() {
    print_header "推送配置到 GitHub Secrets"
    
    # 1. 确保 GitHub CLI 已登录
    github_ensure_auth
    
    # 2. 选择目标环境
    select_environment
    
    local env_file=".env.${ENV_NAME}"
    
    # 检查配置文件是否存在
    if [[ ! -f "${PROJECT_ROOT}/$env_file" ]]; then
        log_error "配置文件 '$env_file' 不存在!"
        echo ""
        echo "请创建配置文件:"
        echo "  cp .env.example $env_file"
        echo "  nano $env_file"
        echo ""
        exit 1
    fi
    
    # 3. 确认 GitHub 仓库
    confirm_github_repo
    
    # 4. 二次确认
    if ! confirm "确认将 '$env_file' 推送到 '$ENV_NAME' 环境?" "y"; then
        log_warn "已取消"
        exit 0
    fi
    
    echo ""
    log_step "正在推送配置..."
    
    # 初始化统计变量
    ENV_UPLOADED_COUNT=0
    ENV_SKIPPED_COUNT=0
    ENV_FAILED_COUNT=0
    
    # 5. 上传环境变量
    push_env_secrets "$ENV_NAME" "${PROJECT_ROOT}/$env_file" "$REPO"
    
    # 6. 上传用户列表
    push_users_json "$ENV_NAME" "$PROJECT_ROOT" "$REPO"
    
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
    echo "📦 配置: $env_file"
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

# 运行主流程
main "$@"
