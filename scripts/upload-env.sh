#!/bin/bash
# ==============================================================================
# 推送配置变量到 GitHub Environment Secrets
# 参考之前的 push-config.sh 实现
# ==============================================================================

set -e

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 加载依赖库
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/prompt.sh"

# ------------------------------------------------------------------------------
# 主函数
# ------------------------------------------------------------------------------
push_config() {
    print_header "推送配置到 GitHub Secrets"
    
    # 检查 gh CLI
    if ! command_exists gh; then
        die "GitHub CLI (gh) 未安装。请先安装: brew install gh"
    fi
    
    # 检查是否已登录
    if ! gh auth status &>/dev/null; then
        log_warn "未登录 GitHub CLI"
        echo ""
        echo "请先登录:"
        echo "  gh auth login"
        echo ""
        exit 1
    fi
    
    # 根据当前 git 分支推荐默认环境
    local current_branch=""
    local default_env=""
    local default_index=2 # 默认 development
    
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    
    case "$current_branch" in
        main|master) 
            default_env="production" 
            default_index=1
            ;;
        dev|development) 
            default_env="development"
            default_index=2
            ;;
        *) 
            default_env="development"
            default_index=2
            ;;
    esac
    
    if [[ -n "$current_branch" ]]; then
        log_substep "检测到分支: $current_branch → 推荐环境: $default_env"
    fi
    
    echo ""
    echo "请选择目标环境:"
    echo "  1. production  (.env.production)"
    echo "  2. development (.env.development)"
    echo "  0. 退出"
    echo ""
    
    local selection
    local env_name=""
    local env_file=""
    
    while true; do
        read -p "选择 (0-2) [默认: $default_index]: " selection
        selection="${selection:-$default_index}"
        
        case "$selection" in
            0) log_warn "已退出"; exit 0 ;;
            1) 
                env_name="production"
                env_file=".env.production"
                break 
                ;;
            2) 
                env_name="development"
                env_file=".env.development"
                break 
                ;;
            *) echo "无效选择，请重试。" ;;
        esac
    done
    
    echo ""
    log_substep "目标环境: $env_name"
    log_substep "配置文件: $env_file"
    echo ""
    
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
    
    # 二次确认
    if ! confirm "确认将 '$env_file' 推送到 '$env_name' 环境?" "y"; then
        log_warn "已取消"
        exit 0
    fi
    
    echo ""
    log_step "正在推送配置..."
    
    # 读取 .env 文件并逐个上传
    local uploaded_count=0
    local skipped_count=0
    local failed_count=0
    
    # 使用不同的方法读取文件，处理没有换行符的情况
    while IFS='=' read -r key value || [ -n "$key" ]; do
        # 跳过空行和注释
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        
        # 去除前后空格
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        
        # 跳过空值
        if [ -z "$value" ]; then
            log_warn "跳过空值: $key"
            ((skipped_count++))
            continue
        fi
        
        # 上传到 GitHub Secrets
        if gh secret set "$key" \
            --env "$env_name" \
            --body "$value" 2>/dev/null; then
            echo "   ✓ $key"
            ((uploaded_count++))
        else
            log_error "上传失败: $key"
            ((failed_count++))
        fi
    done < "${PROJECT_ROOT}/$env_file"
    
    # NEW: 推送结构化的用户列表文件
    local users_file="users.json"
    if [[ -f "${PROJECT_ROOT}/$users_file" ]]; then
        echo ""
        log_step "发现 ${users_file}，正在推送到 GitHub Secrets..."
        # 使用 jq 压缩所有的空白符和换行
        if ! command_exists jq; then
             log_warn "未找到 jq 工具，将尝试直接上传"
             users_json_content=$(cat "${PROJECT_ROOT}/$users_file")
        else
             users_json_content=$(jq -c . "${PROJECT_ROOT}/$users_file")
        fi
        
        if gh secret set "USERS_JSON" \
            --env "$env_name" \
            --body "$users_json_content" 2>/dev/null; then
            echo "   ✓ USERS_JSON"
            ((uploaded_count++))
        else
            log_error "上传失败: USERS_JSON"
            ((failed_count++))
        fi
    else
        echo ""
        log_substep "未发现 ${users_file}，跳过用户列表上传"
    fi
    
    echo ""
    print_separator
    
    if [ $failed_count -eq 0 ]; then
        log_success "✅ 配置推送完成!"
    else
        log_warn "⚠️  配置推送完成（有失败项）"
    fi
    
    print_separator
    echo ""
    echo "📊 统计:"
    echo "   成功: $uploaded_count"
    echo "   跳过: $skipped_count"
    echo "   失败: $failed_count"
    echo ""
    echo "📋 环境: $env_name"
    echo "📦 配置: $env_file"
    echo ""
    
    if [ $failed_count -gt 0 ]; then
        echo "⚠️  可能原因:"
        echo "   1. GitHub 环境 '$env_name' 不存在"
        echo "   2. 没有权限访问该仓库"
        echo "   3. gh 登录失效"
        echo ""
        echo "解决方法:"
        echo "   - 确保已创建环境: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/settings/environments"
        echo "   - 重新登录: gh auth login"
        echo ""
    else
        echo "🎉 下一步:"
        echo "   推送代码触发部署:"
        if [ "$env_name" == "production" ]; then
            echo "     git push origin main"
        else
            echo "     git push origin dev"
        fi
        echo ""
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    push_config
fi
