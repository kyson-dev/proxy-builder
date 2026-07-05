#!/bin/bash
# ==============================================================================
# Layer 2: 环境配置上传功能模块
# 职责: 把已给定路径的配置文件/JSON 文件推送到 GitHub Environment Secrets
#       （纯基础设施交互，不知道任何"项目文件命名约定"）
# 接口:
#   infra::push_env_to_github <env_name> <env_file> <repo>
#   infra::push_json_secret_from_file <secret_name> <file_path> <env_name> <repo>
# 依赖: lib/common.sh, lib/github.sh (由调用方预先加载)
# 无交互: 不调用任何 prompt_* / read 函数; 自包含，不 source 其它 setup 子文件
#
# 注意: "users.<env>.json 还是 users.json" 这类文件发现规则属于项目约定，
#       由调用方 (setup-env.sh) 自行解析出具体文件路径后再调用本模块。
# ==============================================================================

# 防止重复加载
[[ -n "${_INFRA_ENV_LOADED:-}" ]] && return 0
_INFRA_ENV_LOADED=1

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

    log_step "正在推送配置文件: $(basename "$env_file")"

    ENV_UPLOADED_COUNT="${ENV_UPLOADED_COUNT:-0}"
    ENV_SKIPPED_COUNT="${ENV_SKIPPED_COUNT:-0}"
    ENV_FAILED_COUNT="${ENV_FAILED_COUNT:-0}"

    local local_uploaded=0
    local local_skipped=0
    local local_failed=0

    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue

        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        if [[ -z "$value" ]]; then
            log_warn "跳过空值: $key"
            ((local_skipped++))
            continue
        fi

        if github_set_secret "$key" "$value" "$env_name" "$repo"; then
            ((local_uploaded++))
        else
            ((local_failed++))
        fi
    done < "$env_file"

    ENV_UPLOADED_COUNT=$((ENV_UPLOADED_COUNT + local_uploaded))
    ENV_SKIPPED_COUNT=$((ENV_SKIPPED_COUNT + local_skipped))
    ENV_FAILED_COUNT=$((ENV_FAILED_COUNT + local_failed))
}

# ==============================================================================
# infra::push_json_secret_from_file — 将给定文件内容（可选 jq 压缩）推送为单个 Secret
# ==============================================================================
# 参数:
#   $1  secret_name   GitHub Secret 名称（必须）
#   $2  file_path     要推送的文件路径（必须）
#   $3  env_name      环境名，如 production（必须）
#   $4  repo          GitHub 仓库，格式 owner/repo（必须）
# ==============================================================================
infra::push_json_secret_from_file() {
    local secret_name="${1:?infra::push_json_secret_from_file: secret_name 不能为空}"
    local file_path="${2:?infra::push_json_secret_from_file: file_path 不能为空}"
    local env_name="${3:?infra::push_json_secret_from_file: env_name 不能为空}"
    local repo="${4:?infra::push_json_secret_from_file: repo 不能为空}"

    if [[ ! -f "$file_path" ]]; then
        die "infra::push_json_secret_from_file: 文件不存在: $file_path"
    fi

    log_step "推送文件到 GitHub Secret: $secret_name ($(basename "$file_path"))"

    ENV_UPLOADED_COUNT="${ENV_UPLOADED_COUNT:-0}"
    ENV_SKIPPED_COUNT="${ENV_SKIPPED_COUNT:-0}"
    ENV_FAILED_COUNT="${ENV_FAILED_COUNT:-0}"

    local content
    if ! command_exists jq; then
        log_warn "系统未安装 jq，将直接读取原始文本进行上传"
        content=$(cat "$file_path")
    else
        content=$(jq -c . "$file_path")
    fi

    if github_set_secret "$secret_name" "$content" "$env_name" "$repo"; then
        ENV_UPLOADED_COUNT=$((ENV_UPLOADED_COUNT + 1))
    else
        ENV_FAILED_COUNT=$((ENV_FAILED_COUNT + 1))
    fi
}
