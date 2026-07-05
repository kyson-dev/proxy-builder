#!/bin/bash
# ==============================================================================
# Layer 2: WIF 功能模块
# 职责: 完成 Workload Identity Federation 全流程（启用 API、创建 SA、创建 Pool/Provider、绑定仓库）
# 接口: infra::setup_wif <project_id> <github_repo> [sa_name] [pool_name] [provider_name]
# 依赖: lib/common.sh, lib/gcp.sh (由调用方预先加载)
# 无交互: 不调用任何 prompt_* / read 函数; 自包含，不 source 其它 setup 子文件
# ==============================================================================

# 防止重复加载
[[ -n "${_INFRA_WIF_LOADED:-}" ]] && return 0
_INFRA_WIF_LOADED=1

# 需要启用的 APIs
_INFRA_WIF_REQUIRED_APIS=(
    "iam.googleapis.com"
    "cloudresourcemanager.googleapis.com"
    "iamcredentials.googleapis.com"
    "compute.googleapis.com"
    "artifactregistry.googleapis.com"
)

# 需要的角色
_INFRA_WIF_SA_ROLES=(
    "roles/compute.instanceAdmin.v1"
    "roles/compute.osAdminLogin"
    "roles/iam.serviceAccountUser"
    "roles/storage.admin"
    "roles/artifactregistry.writer"
)

# ------------------------------------------------------------------------------
# 内部: 启用必要的 GCP APIs
# ------------------------------------------------------------------------------
_infra_wif_enable_apis() {
    local project="$1"

    log_step "Step 3: 启用必要的 APIs"
    log_substep "启用: ${_INFRA_WIF_REQUIRED_APIS[*]}"

    gcp_enable_apis "$project" "${_INFRA_WIF_REQUIRED_APIS[@]}"

    log_success "APIs 已启用"
    echo ""
}

# ------------------------------------------------------------------------------
# 内部: 创建和配置 Service Account
# ------------------------------------------------------------------------------
_infra_wif_setup_service_account() {
    local project="$1"
    local sa_name="$2"
    local sa_description="$3"

    log_step "Step 4: 创建 Service Account ($sa_name)"

    gcp_create_sa "$sa_name" "$project" "$sa_description"

    echo ""
    log_step "Step 5: 授予权限"

    local sa_email
    sa_email=$(gcp_sa_email "$sa_name" "$project")

    for role in "${_INFRA_WIF_SA_ROLES[@]}"; do
        log_substep "授予: $role"
        gcp_grant_role "$project" "serviceAccount:$sa_email" "$role"
    done

    log_success "权限已授予"
    echo ""

    SA_EMAIL="$sa_email"
}

# ------------------------------------------------------------------------------
# 内部: 创建 Workload Identity Pool 和 Provider
# ------------------------------------------------------------------------------
_infra_wif_setup_pool() {
    local project="$1"
    local repo_owner="$2"
    local pool_name="$3"
    local provider_name="$4"
    local pool_description="$5"

    # Step 6: 创建 Pool
    log_step "Step 6: 创建 Workload Identity Pool ($pool_name)"

    gcp_create_wif_pool "$pool_name" "$project" "$pool_description"

    POOL_ID=$(gcp_get_wif_pool_id "$pool_name" "$project")
    log_substep "Pool ID: $POOL_ID"
    echo ""

    # Step 7: 创建 Provider
    log_step "Step 7: 创建 Workload Identity Provider ($provider_name)"

    gcp_create_github_provider "$provider_name" "$pool_name" "$project" "$repo_owner"

    log_substep "等待 Provider 准备就绪..."
    sleep 5

    local attempt=1
    PROVIDER_ID=""
    while [[ $attempt -le 5 ]]; do
        PROVIDER_ID=$(gcloud iam workload-identity-pools providers describe "$provider_name" \
            --workload-identity-pool="$pool_name" \
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
}

# ------------------------------------------------------------------------------
# 内部: 绑定 GitHub 仓库到 Service Account
# ------------------------------------------------------------------------------
_infra_wif_bind_repo_to_sa() {
    local project="$1"
    local sa_name="$2"
    local pool_id="$3"
    local repo="$4"

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

# ==============================================================================
# infra::setup_wif — 完成 WIF 全流程
# ==============================================================================
# 参数:
#   $1  project_id      GCP 项目 ID（必须）
#   $2  github_repo     GitHub 仓库，格式 owner/repo（必须）
#   $3  sa_name         Service Account 名称（可选，默认 github-deploy）
#   $4  pool_name       WIF Pool 名称（可选，默认 github-pool）
#   $5  provider_name   WIF Provider 名称（可选，默认 github-provider）
#
# 导出:
#   PROVIDER_ID   WIF Provider 完整资源路径
#   SA_EMAIL      Service Account 邮箱
# ==============================================================================
infra::setup_wif() {
    local project_id="${1:?infra::setup_wif: project_id 不能为空}"
    local github_repo="${2:?infra::setup_wif: github_repo 不能为空 (格式: owner/repo)}"
    local sa_name="${3:-github-deploy-sa}"
    local pool_name="${4:-github-pool}"
    local provider_name="${5:-github-provider}"

    local repo_owner="${github_repo%%/*}"

    log_step "WIF 配置: 项目=$project_id, 仓库=$github_repo"

    _infra_wif_enable_apis "$project_id"
    _infra_wif_setup_service_account "$project_id" "$sa_name" "GitHub Actions Deployment"
    _infra_wif_setup_pool "$project_id" "$repo_owner" "$pool_name" "$provider_name" "GitHub Actions Deployment"
    _infra_wif_bind_repo_to_sa "$project_id" "$sa_name" "$POOL_ID" "$github_repo"

    export PROVIDER_ID
    export SA_EMAIL
}
