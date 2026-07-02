#!/bin/bash
# ==============================================================================
# 创建 Artifact Registry Docker 仓库
# 注意: 此脚本应被主脚本 source，依赖库由主脚本加载
# ==============================================================================

# 如果直接运行，加载依赖
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_SELF_DIR}/../lib/common.sh"
    source "${_SELF_DIR}/../lib/gcp.sh"
fi

# ------------------------------------------------------------------------------
# 从 zone 派生 region（去掉最后一段，如 us-west1-b → us-west1）
# ------------------------------------------------------------------------------
_ar_zone_to_region() {
    local zone="$1"
    echo "${zone%-*}"
}

# ------------------------------------------------------------------------------
# 检查 AR 仓库是否存在
# ------------------------------------------------------------------------------
_ar_repo_exists() {
    local project="$1"
    local location="$2"
    local repo="$3"
    gcloud artifacts repositories describe "$repo" \
        --project="$project" \
        --location="$location" &>/dev/null
}

# ------------------------------------------------------------------------------
# 创建 AR Docker 仓库（幂等）
# ------------------------------------------------------------------------------
setup_artifact_registry() {
    local project="${1:-$PROJECT_ID}"
    local zone="${2:-$VM_ZONE}"
    local repo="${AR_REPOSITORY:-proxy}"

    if [[ -z "$project" ]]; then
        die "PROJECT_ID 未设置"
    fi
    if [[ -z "$zone" ]]; then
        die "VM_ZONE 未设置，无法派生 AR region"
    fi

    local location
    location=$(_ar_zone_to_region "$zone")

    log_step "设置 Artifact Registry"
    log_substep "仓库: ${location}-docker.pkg.dev/${project}/${repo}"

    if _ar_repo_exists "$project" "$location" "$repo"; then
        log_success "Artifact Registry 仓库已存在，跳过创建"
    else
        log_substep "创建 Docker 仓库: $repo (位置: $location)..."
        gcloud artifacts repositories create "$repo" \
            --project="$project" \
            --repository-format=docker \
            --location="$location" \
            --description="Proxy sub service image" \
            --quiet
        log_success "Artifact Registry 仓库已创建: $repo"
    fi

    # 导出供后续步骤使用
    export AR_LOCATION="$location"
    export AR_REPOSITORY="$repo"
    export AR_HOST="${location}-docker.pkg.dev"
    export AR_IMAGE="${AR_HOST}/${project}/${repo}/sub"
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ -z "$PROJECT_ID" ]]; then
        read -p "请输入 Project ID: " PROJECT_ID
    fi
    if [[ -z "$VM_ZONE" ]]; then
        read -p "请输入 VM Zone (如 us-west1-b): " VM_ZONE
    fi
    setup_artifact_registry "$PROJECT_ID" "$VM_ZONE"
    echo "AR_LOCATION=$AR_LOCATION"
    echo "AR_REPOSITORY=$AR_REPOSITORY"
    echo "AR_IMAGE=$AR_IMAGE"
fi
