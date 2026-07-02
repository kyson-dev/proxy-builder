#!/bin/bash
# ==============================================================================
# Layer 2: WIF 功能模块
# 职责: 编排 WIF 相关子模块，完成 Workload Identity Federation 全流程
# 接口: infra::setup_wif <project_id> <github_repo> [sa_name] [pool_name] [provider_name]
# 依赖: lib/common.sh, lib/gcp.sh, wif/* 子模块
# 无交互: 不调用任何 prompt_* / read 函数
# ==============================================================================

# 防止重复加载
[[ -n "${_INFRA_WIF_LOADED:-}" ]] && return 0
_INFRA_WIF_LOADED=1

# 加载子模块（source 一次，幂等）
_INFRA_WIF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_INFRA_WIF_DIR}/../wif/enable-apis.sh"
source "${_INFRA_WIF_DIR}/../wif/setup-service-account.sh"
source "${_INFRA_WIF_DIR}/../wif/setup-wif-pool.sh"
source "${_INFRA_WIF_DIR}/../wif/bind-repo-to-sa.sh"

# ==============================================================================
# 主函数
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
    local sa_name="${3:-github-deploy}"
    local pool_name="${4:-github-pool}"
    local provider_name="${5:-github-provider}"

    # 从 repo 提取 owner
    local repo_owner="${github_repo%%/*}"

    log_step "WIF 配置: 项目=$project_id, 仓库=$github_repo"

    # Step 1: 启用必要 APIs
    SA_NAME="$sa_name"
    POOL_NAME="$pool_name"
    PROVIDER_NAME="$provider_name"
    enable_required_apis "$project_id"

    # Step 2: 创建并授权 Service Account
    setup_service_account "$project_id"

    # Step 3: 创建 WIF Pool 和 Provider
    setup_wif_pool "$project_id" "$repo_owner"

    # Step 4: 绑定 GitHub 仓库到 SA
    bind_repo_to_sa "$project_id" "$sa_name" "$POOL_ID" "$github_repo"

    # 导出结果
    export PROVIDER_ID
    export SA_EMAIL
}
