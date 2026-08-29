#!/usr/bin/env bash

set -euo pipefail

INFRA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

infra::die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

infra::require_command() {
    command -v "$1" >/dev/null 2>&1 || infra::die "缺少命令: $1"
}

infra::require_environment() {
    local environment="${1:-}"
    case "$environment" in
        development|production) ;;
        *) infra::die "ENV 必须是 development 或 production" ;;
    esac

    local tfvars="${INFRA_ROOT}/infra/environments/${environment}.tfvars"
    [[ -f "$tfvars" ]] || infra::die "环境清单不存在: $tfvars"
    printf '%s\n' "$tfvars"
}

infra::require_stack() {
    local stack="${1:-}"
    case "$stack" in
        bootstrap|platform) ;;
        *) infra::die "STACK 必须是 bootstrap 或 platform" ;;
    esac
    [[ -d "${INFRA_ROOT}/infra/stacks/${stack}" ]] || infra::die "stack 不存在: $stack"
}

infra::read_tfvar() {
    local file="$1"
    local key="$2"
    local value
    value=$(sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"([^\"]+)\"[[:space:]]*$/\\1/p" "$file")
    [[ -n "$value" ]] || infra::die "无法从 $(basename "$file") 读取 $key"
    printf '%s\n' "$value"
}

infra::state_bucket_name() {
    local project_id="${1:-}"
    [[ -n "$project_id" ]] || infra::die "state bucket 缺少 project_id"
    printf '%s-proxy-builder-tfstate\n' "$project_id"
}

infra::tofu_bin() {
    local tofu_bin="${TOFU_BIN:-tofu}"
    command -v "$tofu_bin" >/dev/null 2>&1 || infra::die "缺少 OpenTofu；安装 1.12.6 或设置 TOFU_BIN"
    printf '%s\n' "$tofu_bin"
}

infra::require_tofu_version() {
    local tofu_bin="$1"
    local version
    version=$($tofu_bin version -json | sed -nE 's/.*"terraform_version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n 1)
    [[ "$version" == "1.12.6" ]] || infra::die "需要 OpenTofu 1.12.6，当前为 ${version:-unknown}"
}
