#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

invalid_env_log=$(mktemp "${TMPDIR:-/tmp}/proxy-builder-invalid-env.XXXXXX")
destroy_guard_log=$(mktemp "${TMPDIR:-/tmp}/proxy-builder-destroy-guard.XXXXXX")
trap 'rm -f "$invalid_env_log" "$destroy_guard_log"' EXIT

if ENV=invalid "${SCRIPT_DIR}/bootstrap-state.sh" >"$invalid_env_log" 2>&1; then
    infra::die "bootstrap-state.sh 接受了无效环境"
fi
rg -q 'ENV 必须是 development 或 production' "$invalid_env_log" || infra::die "无效环境错误不明确"

if ENV=development CONFIRM_PROJECT_ID=wrong "${SCRIPT_DIR}/destroy-platform.sh" >"$destroy_guard_log" 2>&1; then
    infra::die "destroy-platform.sh 接受了错误 Project ID"
fi
rg -q '确认值不匹配' "$destroy_guard_log" || infra::die "destroy 拒绝原因不明确"

rg -q -- '-auto-approve' "${SCRIPT_DIR}/destroy-platform.sh" || infra::die "GitHub destroy 必须显式非交互批准"
rg -q -- '-input=false' "${SCRIPT_DIR}/destroy-platform.sh" || infra::die "GitHub destroy 不得等待交互输入"

subscription_module="${INFRA_ROOT}/infra/modules/subscription_service/main.tf"
rg -q '^[[:space:]]+client,$' "$subscription_module" || infra::die "platform 必须忽略 Cloud Run deploy client 元数据"
rg -q '^[[:space:]]+client_version,$' "$subscription_module" || infra::die "platform 必须忽略 Cloud Run deploy client version 元数据"

development_file=$(infra::require_environment development)
production_file=$(infra::require_environment production)
development_project=$(infra::read_tfvar "$development_file" project_id)
production_project=$(infra::read_tfvar "$production_file" project_id)
[[ "$development_project" != "$production_project" ]] || infra::die "两个环境不能共用 GCP Project"
[[ "$development_project" == "kyson-proxy-dev" ]] || infra::die "development 必须使用 kyson-proxy-dev Project"
[[ "$(infra::read_tfvar "$development_file" resource_prefix)" == "proxy" ]] || infra::die "development 必须使用 proxy 完整资源名前缀"
[[ "$(infra::read_tfvar "$production_file" resource_prefix)" == "proxy" ]] || infra::die "production 必须使用 proxy 完整资源名前缀"

if rg -q 'environment_short' "${INFRA_ROOT}/infra/modules"; then
    infra::die "资源模块不得从 environment 自动追加资源名后缀"
fi

printf '基础设施保护条件测试通过\n'
