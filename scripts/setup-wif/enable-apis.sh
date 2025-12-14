#!/bin/bash
# ==============================================================================
# 启用必要的 GCP APIs
# 注意: 此脚本应被主脚本 source，依赖库由主脚本加载
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
    source "${_SELF_DIR}/../lib/gcp.sh"
fi

# 需要启用的 APIs
REQUIRED_APIS=(
    "iam.googleapis.com"
    "cloudresourcemanager.googleapis.com"
    "iamcredentials.googleapis.com"
    "compute.googleapis.com"
)

# ------------------------------------------------------------------------------
# 主函数
# ------------------------------------------------------------------------------
enable_required_apis() {
    local project="${1:-$PROJECT_ID}"
    
    if [[ -z "$project" ]]; then
        die "PROJECT_ID 未设置"
    fi
    
    log_step "Step 3: 启用必要的 APIs"
    log_substep "启用: ${REQUIRED_APIS[*]}"
    
    gcp_enable_apis "$project" "${REQUIRED_APIS[@]}"
    
    log_success "APIs 已启用"
    echo ""
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ -z "$PROJECT_ID" ]]; then
        read -p "请输入 Project ID: " PROJECT_ID
    fi
    enable_required_apis "$PROJECT_ID"
fi
