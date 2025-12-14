#!/bin/bash
# ==============================================================================
# 设置 GitHub Environment Secrets
# ==============================================================================

# 加载依赖库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/prompt.sh"
source "${SCRIPT_DIR}/../lib/gcp.sh"

# ------------------------------------------------------------------------------
# 主函数
# ------------------------------------------------------------------------------
set_github_secrets() {
    local env_name="${1:-$ENV_NAME}"
    local repo="${2:-$REPO}"
    local project="${3:-$PROJECT_ID}"
    local provider_id="${4:-$PROVIDER_ID}"
    local sa_name="${5:-$SA_NAME}"
    local vm_name="${6:-$VM_NAME}"
    local vm_zone="${7:-$VM_ZONE}"
    
    # 验证必要参数
    local missing_params=()
    [[ -z "$env_name" ]] && missing_params+=("ENV_NAME")
    [[ -z "$repo" ]] && missing_params+=("REPO")
    [[ -z "$project" ]] && missing_params+=("PROJECT_ID")
    [[ -z "$provider_id" ]] && missing_params+=("PROVIDER_ID")
    [[ -z "$sa_name" ]] && missing_params+=("SA_NAME")
    [[ -z "$vm_name" ]] && missing_params+=("VM_NAME")
    [[ -z "$vm_zone" ]] && missing_params+=("VM_ZONE")
    
    if [[ ${#missing_params[@]} -gt 0 ]]; then
        die "缺少必要参数: ${missing_params[*]}"
    fi
    
    log_step "Step 11: 设置 GitHub Secrets ('$env_name' 环境)"
    echo ""
    
    # 检查 gh CLI
    if ! command_exists gh; then
        die "GitHub CLI (gh) 未安装"
    fi
    
    # 提示用户创建 environment
    echo "📝 请确保已在 GitHub 中创建 '$env_name' 环境:"
    echo "   Settings → Environments → New environment → '$env_name'"
    echo ""
    echo "   如果还没创建，请访问: https://github.com/$repo/settings/environments"
    echo ""
    
    # 默认为 y，直接回车即可继续
    if ! confirm "是否已创建 '$env_name' 环境?" "y"; then
        echo ""
        log_warn "请先创建环境后再继续"
        echo ""
        echo "创建步骤:"
        echo "   1. 访问: https://github.com/$repo/settings/environments"
        echo "   2. 点击 'New environment'"
        echo "   3. 命名为: $env_name"
        echo "   4. 保存后重新运行此脚本"
        echo ""
        exit 1
    fi
    
    echo ""
    log_substep "正在设置 secrets..."
    
    local sa_email
    sa_email=$(gcp_sa_email "$sa_name" "$project")
    
    # 设置各个 secret
    local secrets=(
        "GCP_PROJECT_ID:$project"
        "GCP_WORKLOAD_IDENTITY_PROVIDER:$provider_id"
        "GCP_SERVICE_ACCOUNT:$sa_email"
        "GCP_VM_NAME:$vm_name"
        "GCP_VM_ZONE:$vm_zone"
    )
    
    for secret in "${secrets[@]}"; do
        local name="${secret%%:*}"
        local value="${secret#*:}"
        
        gh secret set "$name" \
            --env "$env_name" \
            --body "$value" \
            --repo "$repo"
        
        echo "   ✓ $name"
    done
    
    log_success "GitHub Secrets 设置完成"
    echo ""
}

# 打印配置摘要
print_summary() {
    local env_name="${1:-$ENV_NAME}"
    local project="${2:-$PROJECT_ID}"
    local vm_name="${3:-$VM_NAME}"
    local vm_zone="${4:-$VM_ZONE}"
    local provider_id="${5:-$PROVIDER_ID}"
    
    print_separator
    log_success "WIF 设置完成 - '$env_name' 环境"
    print_separator
    echo ""
    echo "配置摘要:"
    echo "  环境:     $env_name"
    echo "  项目 ID:  $project"
    echo "  VM 名称:  $vm_name"
    echo "  VM 区域:  $vm_zone"
    echo "  Provider: $provider_id"
    echo ""
    echo "📋 后续步骤:"
    echo "   1. 创建环境配置文件: .env.$env_name"
    echo "   2. 推送环境变量: make push-env ENV=$env_name"
    
    if [[ "$env_name" == "production" ]]; then
        echo "   3. 推送到 main 分支部署: git push origin main"
    else
        echo "   3. 推送到 dev 分支部署: git push origin dev"
    fi
    echo ""
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set_github_secrets
    print_summary
fi
