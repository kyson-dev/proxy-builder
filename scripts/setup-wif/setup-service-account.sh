#!/bin/bash
# ==============================================================================
# 创建和配置 Service Account
# 注意: 此脚本应被主脚本 source，依赖库由主脚本加载
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
    source "${_SELF_DIR}/../lib/gcp.sh"
fi

# 配置
SA_NAME="${SA_NAME:-github-deploy}"
SA_DESCRIPTION="${SA_DESCRIPTION:-GitHub Actions Deployment}"

# 需要的角色
SA_ROLES=(
    "roles/compute.instanceAdmin.v1"
    "roles/compute.osAdminLogin"
    "roles/iam.serviceAccountUser"
)

# ------------------------------------------------------------------------------
# 主函数
# ------------------------------------------------------------------------------
setup_service_account() {
    local project="${1:-$PROJECT_ID}"
    
    if [[ -z "$project" ]]; then
        die "PROJECT_ID 未设置"
    fi
    
    log_step "Step 4: 创建 Service Account ($SA_NAME)"
    
    # 创建 Service Account
    gcp_create_sa "$SA_NAME" "$project" "$SA_DESCRIPTION"
    
    echo ""
    log_step "Step 5: 授予权限"
    
    local sa_email
    sa_email=$(gcp_sa_email "$SA_NAME" "$project")
    
    for role in "${SA_ROLES[@]}"; do
        log_substep "授予: $role"
        gcp_grant_role "$project" "serviceAccount:$sa_email" "$role"
    done
    
    log_success "权限已授予"
    echo ""
    
    export SA_NAME SA_EMAIL="$sa_email"
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ -z "$PROJECT_ID" ]]; then
        read -p "请输入 Project ID: " PROJECT_ID
    fi
    setup_service_account "$PROJECT_ID"
    echo "SA_NAME=$SA_NAME"
    echo "SA_EMAIL=$SA_EMAIL"
fi
