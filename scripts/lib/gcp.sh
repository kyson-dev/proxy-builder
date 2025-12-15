#!/bin/bash
# ==============================================================================
# GCP 相关通用函数库
# 依赖: common.sh, prompt.sh (由主脚本预先加载)
# ==============================================================================

# 防止重复加载
[[ -n "${_LIB_GCP_LOADED:-}" ]] && return 0
_LIB_GCP_LOADED=1


# ------------------------------------------------------------------------------
# gcloud 检查
# ------------------------------------------------------------------------------

# 检查 gcloud 是否已安装
require_gcloud() {
    if ! command_exists gcloud; then
        die "gcloud CLI 未安装。请访问 https://cloud.google.com/sdk/docs/install 安装"
    fi
}

# 检查是否已登录
gcloud_is_authenticated() {
    gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .
}

# 确保已登录
require_gcloud_auth() {
    require_gcloud
    if ! gcloud_is_authenticated; then
        log_warn "未登录 gcloud，请先运行: gcloud auth login"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# 项目管理
# ------------------------------------------------------------------------------

# 获取当前项目
gcp_get_current_project() {
    gcloud config get-value project 2>/dev/null
}

# 设置当前项目
gcp_set_project() {
    local project="$1"
    gcloud config set project "$project" --quiet
}

# 列出所有项目
gcp_list_projects() {
    gcloud projects list --format="value(projectId)" 2>/dev/null
}

# 检查项目是否存在且可访问
gcp_project_exists() {
    local project="$1"
    gcloud projects describe "$project" &>/dev/null
}

# 交互式选择项目
# 返回: 项目ID 通过 $GCP_PROJECT_ID
gcp_select_project() {
    local current_project
    current_project=$(gcp_get_current_project)
    
    log_substep "正在获取 GCP 项目列表..."
    local projects=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && projects+=("$line")
    done < <(gcp_list_projects)
    
    if [[ ${#projects[@]} -eq 0 ]]; then
        log_warn "未找到可用项目"
        prompt_required "请输入 GCP Project ID"
        GCP_PROJECT_ID="$INPUT_VALUE"
        return
    fi
    
    select_with_default "选择项目" "$current_project" "${projects[@]}"
    GCP_PROJECT_ID="$SELECTED_VALUE"
}

# ------------------------------------------------------------------------------
# Service Account 管理
# ------------------------------------------------------------------------------

# 检查 Service Account 是否存在
gcp_sa_exists() {
    local sa_name="$1"
    local project="$2"
    gcloud iam service-accounts describe "${sa_name}@${project}.iam.gserviceaccount.com" \
        --project "$project" &>/dev/null
}

# 创建 Service Account
gcp_create_sa() {
    local sa_name="$1"
    local project="$2"
    local display_name="${3:-$sa_name}"
    
    if gcp_sa_exists "$sa_name" "$project"; then
        log_substep "Service Account 已存在: $sa_name"
        return 0
    fi
    
    gcloud iam service-accounts create "$sa_name" \
        --display-name "$display_name" \
        --project "$project"
    
    log_success "Service Account 已创建: $sa_name"
}

# 获取 Service Account 完整邮箱
gcp_sa_email() {
    local sa_name="$1"
    local project="$2"
    echo "${sa_name}@${project}.iam.gserviceaccount.com"
}

# 授予 IAM 角色
gcp_grant_role() {
    local project="$1"
    local member="$2"
    local role="$3"
    
    gcloud projects add-iam-policy-binding "$project" \
        --member="$member" \
        --role="$role" \
        --condition=None \
        --quiet
}

# ------------------------------------------------------------------------------
# Workload Identity Federation
# ------------------------------------------------------------------------------

# 检查 WIF Pool 是否存在且处于 ACTIVE 状态
gcp_wif_pool_exists() {
    local pool_name="$1"
    local project="$2"
    local state
    state=$(gcloud iam workload-identity-pools describe "$pool_name" \
        --project "$project" \
        --location="global" \
        --format="value(state)" 2>/dev/null)
    [[ "$state" == "ACTIVE" ]]
}

# 检查 WIF Pool 是否处于软删除状态
gcp_wif_pool_deleted() {
    local pool_name="$1"
    local project="$2"
    local state
    state=$(gcloud iam workload-identity-pools describe "$pool_name" \
        --project "$project" \
        --location="global" \
        --format="value(state)" 2>/dev/null)
    [[ "$state" == "DELETED" ]]
}

# 恢复软删除的 WIF Pool
gcp_undelete_wif_pool() {
    local pool_name="$1"
    local project="$2"
    
    log_substep "恢复软删除的 Pool: $pool_name"
    gcloud iam workload-identity-pools undelete "$pool_name" \
        --project "$project" \
        --location="global" >/dev/null
    
    # 等待恢复完成
    sleep 3
    log_success "Pool 已恢复: $pool_name"
}

# 创建 WIF Pool（支持自动恢复软删除状态）
# 逻辑：1. ACTIVE → 跳过  2. DELETED → 恢复  3. 不存在 → 创建
gcp_create_wif_pool() {
    local pool_name="$1"
    local project="$2"
    local display_name="${3:-$pool_name}"
    
    # 获取当前状态
    local state
    state=$(gcloud iam workload-identity-pools describe "$pool_name" \
        --project "$project" \
        --location="global" \
        --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
    
    case "$state" in
        ACTIVE)
            log_substep "Workload Identity Pool 已存在: $pool_name"
            return 0
            ;;
        DELETED)
            log_warn "Pool 处于软删除状态，正在恢复..."
            gcp_undelete_wif_pool "$pool_name" "$project"
            return 0
            ;;
        *)
            # 不存在，创建新的
            log_substep "创建 Workload Identity Pool..."
            gcloud iam workload-identity-pools create "$pool_name" \
                --project "$project" \
                --location="global" \
                --display-name "$display_name"
            log_success "Workload Identity Pool 已创建: $pool_name"
            return 0
            ;;
    esac
}

# 获取 WIF Pool ID
gcp_get_wif_pool_id() {
    local pool_name="$1"
    local project="$2"
    gcloud iam workload-identity-pools describe "$pool_name" \
        --project "$project" \
        --location="global" \
        --format="value(name)"
}

# 检查 WIF Provider 是否存在
gcp_wif_provider_exists() {
    local provider_name="$1"
    local pool_name="$2"
    local project="$3"
    gcloud iam workload-identity-pools providers describe "$provider_name" \
        --workload-identity-pool="$pool_name" \
        --project "$project" \
        --location="global" &>/dev/null
}

# 创建 GitHub OIDC Provider
gcp_create_github_provider() {
    local provider_name="$1"
    local pool_name="$2"
    local project="$3"
    local repo_owner="$4"
    
    if gcp_wif_provider_exists "$provider_name" "$pool_name" "$project"; then
        log_substep "Workload Identity Provider 已存在: $provider_name"
        return 0
    fi
    
    gcloud iam workload-identity-pools providers create-oidc "$provider_name" \
        --workload-identity-pool="$pool_name" \
        --project "$project" \
        --location="global" \
        --issuer-uri="https://token.actions.githubusercontent.com" \
        --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
        --attribute-condition="assertion.repository_owner == '$repo_owner'"
    
    log_success "Workload Identity Provider 已创建: $provider_name"
}

# 获取 WIF Provider ID
gcp_get_wif_provider_id() {
    local provider_name="$1"
    local pool_name="$2"
    local project="$3"
    
    retry 5 3 "gcloud iam workload-identity-pools providers describe '$provider_name' \
        --workload-identity-pool='$pool_name' \
        --project '$project' \
        --location='global' \
        --format='value(name)' 2>/dev/null"
}

# ------------------------------------------------------------------------------
# VM 管理
# ------------------------------------------------------------------------------

# 列出 VM 实例
gcp_list_vms() {
    local project="$1"
    gcloud compute instances list \
        --project "$project" \
        --format="csv[no-heading](name,zone,status)"
}

# 检查 VM 是否存在
gcp_vm_exists() {
    local vm_name="$1"
    local zone="$2"
    local project="$3"
    gcloud compute instances describe "$vm_name" \
        --zone "$zone" \
        --project "$project" &>/dev/null
}

# 获取 VM 状态
gcp_get_vm_status() {
    local vm_name="$1"
    local zone="$2"
    local project="$3"
    gcloud compute instances describe "$vm_name" \
        --zone "$zone" \
        --project "$project" \
        --format="value(status)"
}

# 获取 VM 外部 IP
gcp_get_vm_external_ip() {
    local vm_name="$1"
    local zone="$2"
    local project="$3"
    gcloud compute instances describe "$vm_name" \
        --zone "$zone" \
        --project "$project" \
        --format="value(networkInterfaces[0].accessConfigs[0].natIP)"
}

# 检查 OS Login 是否启用
gcp_oslogin_enabled() {
    local vm_name="$1"
    local zone="$2"
    local project="$3"
    local status
    status=$(gcloud compute instances describe "$vm_name" \
        --zone "$zone" \
        --project "$project" \
        --format="get(metadata.items[key=enable-oslogin].value)" 2>/dev/null)
    # 处理大小写：TRUE, true, True 都算启用
    [[ "${status,,}" == "true" ]] 2>/dev/null || [[ "$status" == "TRUE" ]] || [[ "$status" == "true" ]]
}


# 启用 OS Login
gcp_enable_oslogin() {
    local vm_name="$1"
    local zone="$2"
    local project="$3"
    gcloud compute instances add-metadata "$vm_name" \
        --zone "$zone" \
        --project "$project" \
        --metadata enable-oslogin=TRUE
}

# ------------------------------------------------------------------------------
# API 管理
# ------------------------------------------------------------------------------

# 启用 API
gcp_enable_apis() {
    local project="$1"
    shift
    local apis=("$@")
    
    gcloud services enable "${apis[@]}" --project "$project"
}
