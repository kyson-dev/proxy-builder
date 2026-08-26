#!/usr/bin/env bash
set -euo pipefail
umask 077

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
# shellcheck source=../infra/common.sh
source "${repo_root}/scripts/infra/common.sh"

environment="${ENV:-}"
user_name="${USER:-}"
format="${FORMAT:-base64}"
tfvars="$(infra::require_environment "$environment")"
[[ -n "$user_name" ]] || infra::die "USER 不能为空"
case "$format" in base64|clash) ;; *) infra::die "FORMAT 必须是 base64 或 clash" ;; esac

secrets_root="${PROXY_BUILDER_SECRETS_ROOT:-${repo_root}/.secrets}"
users_path="${secrets_root}/${environment}/users.json"
[[ -f "$users_path" && ! -L "$users_path" ]] || infra::die "本地 users.json 不存在或不安全；先运行 make secrets-init"
match_count="$(jq -er --arg name "$user_name" '[.users[] | select(.name == $name and .enabled == true)] | length' "$users_path")"
[[ "$match_count" == "1" ]] || infra::die "用户不存在、未启用或数据不唯一: $user_name"
token="$(jq -er --arg name "$user_name" '.users[] | select(.name == $name and .enabled == true) | .subscription_token' "$users_path")"
token_encoded="$(jq -nr --arg value "$token" '$value | @uri')"

tofu_bin="$(infra::tofu_bin)"
infra::require_tofu_version "$tofu_bin"
project_id="$(infra::read_tfvar "$tfvars" project_id)"
bucket="$(infra::state_bucket_name "$project_id")"
stack_dir="${repo_root}/infra/stacks/platform"
"$tofu_bin" -chdir="$stack_dir" init -reconfigure -input=false \
  -backend-config="bucket=${bucket}" -backend-config="prefix=platform" >/dev/null
service_url="$("$tofu_bin" -chdir="$stack_dir" output -raw subscription_service_url)"
[[ "$service_url" =~ ^https://[^/?#]+$ ]] || infra::die "platform state 中没有有效的 subscription service URL"

printf '%s/v1/subscription?token=%s&format=%s\n' "$service_url" "$token_encoded" "$format"
