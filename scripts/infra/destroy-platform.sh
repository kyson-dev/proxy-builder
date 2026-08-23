#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

environment="${ENV:-}"
tfvars=$(infra::require_environment "$environment")
tofu_bin=$(infra::tofu_bin)
infra::require_tofu_version "$tofu_bin"

project_id=$(infra::read_tfvar "$tfvars" project_id)
confirmation="${CONFIRM_PROJECT_ID:-}"

if [[ -z "$confirmation" && -t 0 ]]; then
    printf '输入 Project ID 以确认销毁 %s platform: ' "$environment" >&2
    read -r confirmation
fi

[[ "$confirmation" == "$project_id" ]] || infra::die "确认值不匹配；未执行 destroy"

bucket="${project_id}-proxy-builder-tfstate"
stack_dir="${INFRA_ROOT}/infra/stacks/platform"

"$tofu_bin" -chdir="$stack_dir" init -reconfigure \
    -backend-config="bucket=${bucket}" \
    -backend-config="prefix=platform"
"$tofu_bin" -chdir="$stack_dir" destroy \
    -lock-timeout=5m \
    -var-file="../../environments/${environment}.tfvars"
