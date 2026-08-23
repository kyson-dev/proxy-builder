#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

action="${1:-}"
environment="${ENV:-}"
stack="${STACK:-platform}"

case "$action" in
    plan|apply) ;;
    *) infra::die "用法: tofu-stack.sh plan|apply" ;;
esac

tfvars=$(infra::require_environment "$environment")
infra::require_stack "$stack"
tofu_bin=$(infra::tofu_bin)
infra::require_tofu_version "$tofu_bin"

project_id=$(infra::read_tfvar "$tfvars" project_id)
bucket="${project_id}-proxy-builder-tfstate"
stack_dir="${INFRA_ROOT}/infra/stacks/${stack}"

"$tofu_bin" -chdir="$stack_dir" init -reconfigure \
    -backend-config="bucket=${bucket}" \
    -backend-config="prefix=${stack}"

if [[ "$action" == "plan" ]]; then
    exec "$tofu_bin" -chdir="$stack_dir" plan \
        -lock-timeout=5m \
        -var-file="../../environments/${environment}.tfvars"
fi

plan_file=$(mktemp "/private/tmp/proxy-builder-${environment}-${stack}.XXXXXX")
trap 'rm -f "$plan_file"' EXIT

"$tofu_bin" -chdir="$stack_dir" plan \
    -lock-timeout=5m \
    -out="$plan_file" \
    -var-file="../../environments/${environment}.tfvars"
"$tofu_bin" -chdir="$stack_dir" apply -lock-timeout=5m "$plan_file"
