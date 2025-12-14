#!/bin/bash
# ==============================================================================
# 创建 Workload Identity Pool 和 Provider
# 注意: 此脚本应被主脚本 source，依赖库由主脚本加载
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
    source "${_SELF_DIR}/../lib/gcp.sh"
fi

# 配置
POOL_NAME="${POOL_NAME:-github-pool}"
PROVIDER_NAME="${PROVIDER_NAME:-github-provider}"
POOL_DESCRIPTION="${POOL_DESCRIPTION:-GitHub Actions Deployment}"

# ------------------------------------------------------------------------------
# 主函数
# ------------------------------------------------------------------------------
setup_wif_pool() {
    local project="${1:-$PROJECT_ID}"
    local repo_owner="${2:-$REPO_OWNER}"
    
    if [[ -z "$project" ]]; then
        die "PROJECT_ID 未设置"
    fi
    
    if [[ -z "$repo_owner" ]]; then
        die "REPO_OWNER 未设置"
    fi
    
    # Step 6: 创建 Pool
    log_step "Step 6: 创建 Workload Identity Pool ($POOL_NAME)"
    
    gcp_create_wif_pool "$POOL_NAME" "$project" "$POOL_DESCRIPTION"
    
    POOL_ID=$(gcp_get_wif_pool_id "$POOL_NAME" "$project")
    log_substep "Pool ID: $POOL_ID"
    echo ""
    
    # Step 7: 创建 Provider
    log_step "Step 7: 创建 Workload Identity Provider ($PROVIDER_NAME)"
    
    gcp_create_github_provider "$PROVIDER_NAME" "$POOL_NAME" "$project" "$repo_owner"
    
    # 等待 Provider 准备就绪
    log_substep "等待 Provider 准备就绪..."
    sleep 5
    
    # 重试获取 Provider ID
    local attempt=1
    while [[ $attempt -le 5 ]]; do
        PROVIDER_ID=$(gcloud iam workload-identity-pools providers describe "$PROVIDER_NAME" \
            --workload-identity-pool="$POOL_NAME" \
            --project "$project" \
            --location="global" \
            --format="value(name)" 2>/dev/null)
        
        if [[ -n "$PROVIDER_ID" ]]; then
            break
        fi
        
        log_substep "等待 Provider 传播 (尝试 $attempt/5)..."
        sleep 3
        ((attempt++))
    done
    
    if [[ -z "$PROVIDER_ID" ]]; then
        die "无法获取 Provider ID"
    fi
    
    log_substep "Provider ID: $PROVIDER_ID"
    log_success "WIF 配置完成"
    echo ""
    
    export POOL_NAME POOL_ID PROVIDER_NAME PROVIDER_ID
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ -z "$PROJECT_ID" ]]; then
        read -p "请输入 Project ID: " PROJECT_ID
    fi
    if [[ -z "$REPO_OWNER" ]]; then
        read -p "请输入 Repo Owner: " REPO_OWNER
    fi
    setup_wif_pool "$PROJECT_ID" "$REPO_OWNER"
    echo "POOL_ID=$POOL_ID"
    echo "PROVIDER_ID=$PROVIDER_ID"
fi
