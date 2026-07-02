#!/bin/bash
# ==============================================================================
# Layer 2: 环境配置上传功能模块
# 职责: 将 .env 文件和 users.json 推送到 GitHub Environment Secrets
# 接口:
#   infra::push_env_to_github <env_name> <env_file> <repo>
#   infra::push_users_to_github <env_name> <project_root> <repo>
# 依赖: lib/common.sh, lib/github.sh, env/push-env-secrets.sh, env/push-users-json.sh
# 无交互: 不调用任何 prompt_* / read 函数
# ==============================================================================

# 防止重复加载
[[ -n "${_INFRA_ENV_LOADED:-}" ]] && return 0
_INFRA_ENV_LOADED=1

# 加载子模块
_INFRA_ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_INFRA_ENV_DIR}/../env/push-env-secrets.sh"
source "${_INFRA_ENV_DIR}/../env/push-users-json.sh"

# ==============================================================================
# infra::push_env_to_github — 将 .env 文件推送到 GitHub Secrets
# ==============================================================================
# 参数:
#   $1  env_name   环境名，如 production（必须）
#   $2  env_file   .env 文件路径（必须）
#   $3  repo       GitHub 仓库，格式 owner/repo（必须）
# ==============================================================================
infra::push_env_to_github() {
    local env_name="${1:?infra::push_env_to_github: env_name 不能为空}"
    local env_file="${2:?infra::push_env_to_github: env_file 不能为空}"
    local repo="${3:?infra::push_env_to_github: repo 不能为空}"

    if [[ ! -f "$env_file" ]]; then
        die "infra::push_env_to_github: env 文件不存在: $env_file"
    fi

    log_step "推送 env 到 GitHub: 环境=$env_name, 仓库=$repo"

    # 初始化计数器（若不存在则置零）
    ENV_UPLOADED_COUNT="${ENV_UPLOADED_COUNT:-0}"
    ENV_SKIPPED_COUNT="${ENV_SKIPPED_COUNT:-0}"
    ENV_FAILED_COUNT="${ENV_FAILED_COUNT:-0}"

    push_env_secrets "$env_name" "$env_file" "$repo"
}

# ==============================================================================
# infra::push_users_to_github — 将 users JSON 推送到 GitHub Secrets
# ==============================================================================
# 参数:
#   $1  env_name      环境名，如 production（必须）
#   $2  project_root  项目根目录（必须）
#   $3  repo          GitHub 仓库，格式 owner/repo（必须）
# ==============================================================================
infra::push_users_to_github() {
    local env_name="${1:?infra::push_users_to_github: env_name 不能为空}"
    local project_root="${2:?infra::push_users_to_github: project_root 不能为空}"
    local repo="${3:?infra::push_users_to_github: repo 不能为空}"

    log_step "推送 users JSON 到 GitHub: 环境=$env_name, 仓库=$repo"

    # 初始化计数器（若不存在则置零）
    ENV_UPLOADED_COUNT="${ENV_UPLOADED_COUNT:-0}"
    ENV_SKIPPED_COUNT="${ENV_SKIPPED_COUNT:-0}"
    ENV_FAILED_COUNT="${ENV_FAILED_COUNT:-0}"

    push_users_json "$env_name" "$project_root" "$repo"
}
