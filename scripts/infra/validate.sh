#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

tofu_bin=$(infra::tofu_bin)
infra::require_tofu_version "$tofu_bin"
infra::require_command jq
infra::require_command rg
shellcheck_bin="${SHELLCHECK_BIN:-shellcheck}"
infra::require_command "$shellcheck_bin"

"$tofu_bin" fmt -check -recursive "${INFRA_ROOT}/infra"

for stack in bootstrap platform; do
    stack_dir="${INFRA_ROOT}/infra/stacks/${stack}"
    "$tofu_bin" -chdir="$stack_dir" init -backend=false -input=false
    "$tofu_bin" -chdir="$stack_dir" validate

    for environment in development production; do
        "$tofu_bin" -chdir="$stack_dir" test \
            -var-file="../../environments/${environment}.tfvars"
    done
done

for environment in development production; do
    jq -e '
      (keys | sort) == ["hy2_sni", "reality_dest", "sing_box_image"] and
      (.reality_dest | test("^[^:]+:[0-9]+$")) and
      (.hy2_sni | length > 0) and
      (.sing_box_image | test("@sha256:[0-9a-f]{64}$"))
    ' "${INFRA_ROOT}/config/environments/${environment}.json" >/dev/null
done

if rg -ni '(private_key|password|token|certificate_pem|BEGIN [A-Z ]*PRIVATE KEY)' "${INFRA_ROOT}/infra/environments"; then
    infra::die "环境 tfvars 包含疑似秘密字段"
fi

find "${INFRA_ROOT}/scripts" -type f -name '*.sh' -exec bash -n {} +
"$shellcheck_bin" -x -P "${INFRA_ROOT}/scripts/infra" "${INFRA_ROOT}"/scripts/infra/*.sh
"${SCRIPT_DIR}/test-guards.sh"
printf '基础设施静态验证通过\n'
