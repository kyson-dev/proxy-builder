#!/bin/bash
# ==============================================================================
# Layer 2: Artifact Registry 功能模块
# 职责: 创建或复用 AR Docker 仓库（幂等），无交互
# 接口: infra::create_ar_repo <project_id> <location> <repo_name>
# 依赖: lib/common.sh, lib/gcp.sh
# 无交互: 不调用任何 prompt_* / read 函数
# ==============================================================================

# 防止重复加载
[[ -n "${_INFRA_AR_LOADED:-}" ]] && return 0
_INFRA_AR_LOADED=1

# ==============================================================================
# infra::create_ar_repo — 创建（幂等）AR Docker 仓库
# ==============================================================================
# 参数:
#   $1  project_id   GCP 项目 ID（必须）
#   $2  location     AR 区域，如 us-west1（必须）
#   $3  repo_name    仓库名称（必须）
#
# 导出:
#   AR_LOCATION     AR 区域
#   AR_REPOSITORY   AR 仓库名称
#   AR_HOST         AR 镜像仓库主机，如 us-west1-docker.pkg.dev
#   AR_IMAGE        完整镜像前缀，如 us-west1-docker.pkg.dev/proj/repo/subscription
# ==============================================================================
infra::create_ar_repo() {
    local project_id="${1:?infra::create_ar_repo: project_id 不能为空}"
    local location="${2:?infra::create_ar_repo: location 不能为空}"
    local repo_name="${3:?infra::create_ar_repo: repo_name 不能为空}"

    log_step "Artifact Registry: $repo_name (区域: $location)"

    # 检查仓库是否已存在
    if gcloud artifacts repositories describe "$repo_name" \
        --project="$project_id" \
        --location="$location" &>/dev/null; then
        log_substep "AR 仓库已存在: $repo_name，跳过创建"
    else
        log_substep "创建 AR Docker 仓库: $repo_name..."
        gcloud artifacts repositories create "$repo_name" \
            --project="$project_id" \
            --repository-format=docker \
            --location="$location" \
            --description="Proxy subscription service image" \
            --quiet
        log_success "AR 仓库已创建: $repo_name"
    fi

    # 导出结果
    export AR_LOCATION="$location"
    export AR_REPOSITORY="$repo_name"
    export AR_HOST="${location}-docker.pkg.dev"
    export AR_IMAGE="${AR_HOST}/${project_id}/${repo_name}/subscription"

    echo ""
}
