#!/bin/bash
# ==============================================================================
# 绑定 GitHub 仓库到 Service Account
# 注意: 此脚本应被主脚本 source，依赖库由主脚本加载
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
    source "${_SELF_DIR}/../lib/gcp.sh"
fi

# ------------------------------------------------------------------------------
# 主函数
# ------------------------------------------------------------------------------
bind_repo_to_sa() {
    local project="${1:-$PROJECT_ID}"
    local sa_name="${2:-$SA_NAME}"
    local pool_id="${3:-$POOL_ID}"
    local repo="${4:-$REPO}"
    
    if [[ -z "$project" ]] || [[ -z "$sa_name" ]] || [[ -z "$pool_id" ]] || [[ -z "$repo" ]]; then
        die "缺少必要参数: PROJECT_ID, SA_NAME, POOL_ID, REPO"
    fi
    
    log_step "Step 8: 绑定 GitHub 仓库到 Service Account"
    
    local sa_email
    sa_email=$(gcp_sa_email "$sa_name" "$project")
    
    log_substep "SA: $sa_email"
    log_substep "Pool: $pool_id"
    log_substep "Repo: $repo"
    
    gcloud iam service-accounts add-iam-policy-binding "$sa_email" \
        --project "$project" \
        --role="roles/iam.workloadIdentityUser" \
        --member="principalSet://iam.googleapis.com/$pool_id/attribute.repository/$repo" \
        --quiet
    
    log_success "绑定完成"
    echo ""
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bind_repo_to_sa "$PROJECT_ID" "$SA_NAME" "$POOL_ID" "$REPO"
fi
