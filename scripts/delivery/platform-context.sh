#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
# shellcheck source=../infra/common.sh
source "${repo_root}/scripts/infra/common.sh"

environment="${ENV:-}"
output_file="${GITHUB_OUTPUT:-}"
[[ -n "$output_file" ]] || infra::die "GITHUB_OUTPUT is required"
tfvars="$(infra::require_environment "$environment")"
tofu_bin="$(infra::tofu_bin)"
infra::require_tofu_version "$tofu_bin"
project_id="$(infra::read_tfvar "$tfvars" project_id)"
region="$(infra::read_tfvar "$tfvars" region)"
state_bucket="$(infra::state_bucket_name "$project_id")"
stack_dir="${repo_root}/infra/stacks/platform"

"$tofu_bin" -chdir="$stack_dir" init -reconfigure -input=false \
  -backend-config="bucket=${state_bucket}" \
  -backend-config="prefix=platform" >/dev/null
outputs="$($tofu_bin -chdir="$stack_dir" output -json)"

for name in proxy_ip_address proxy_vm_name proxy_vm_zone artifact_repository_url subscription_service_name subscription_service_url proxy_users_secret_id obfs_password_secret_id subscription_request_log_exclusion_name; do
  jq -e --arg name "$name" '.[$name].value | strings | length > 0' <<<"$outputs" >/dev/null || infra::die "platform output is missing: $name"
done

{
  printf 'project_id=%s\n' "$project_id"
  printf 'region=%s\n' "$region"
  for name in proxy_ip_address proxy_vm_name proxy_vm_zone artifact_repository_url subscription_service_name subscription_service_url proxy_users_secret_id obfs_password_secret_id subscription_request_log_exclusion_name; do
    printf '%s=%s\n' "$name" "$(jq -r --arg name "$name" '.[$name].value' <<<"$outputs")"
  done
} >>"$output_file"
