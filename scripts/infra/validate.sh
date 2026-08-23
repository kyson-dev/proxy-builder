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

if find "${INFRA_ROOT}/infra/modules" -name '.terraform.lock.hcl' -print -quit | grep -q .; then
    infra::die "provider lock file 只能由 stack 拥有，不能写入 module"
fi

for stack in bootstrap platform; do
    stack_dir="${INFRA_ROOT}/infra/stacks/${stack}"
    "$tofu_bin" -chdir="$stack_dir" init -backend=false -input=false
    "$tofu_bin" -chdir="$stack_dir" validate

    for environment in development production; do
        "$tofu_bin" -chdir="$stack_dir" test \
            -var-file="../../environments/${environment}.tfvars"
    done
done

module_test_root=$(mktemp -d "${TMPDIR:-/tmp}/proxy-builder-tofu-modules.XXXXXX")
trap 'rm -rf "$module_test_root"' EXIT
for module_name in proxy_vm subscription_service; do
    module_dir="${module_test_root}/${module_name}"
    cp -R "${INFRA_ROOT}/infra/modules/${module_name}" "$module_dir"
    cp "${INFRA_ROOT}/infra/stacks/platform/.terraform.lock.hcl" "${module_dir}/.terraform.lock.hcl"
    "$tofu_bin" -chdir="$module_dir" init -backend=false -input=false
    "$tofu_bin" -chdir="$module_dir" validate
    "$tofu_bin" -chdir="$module_dir" test
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

if rg -ni '(REALITY_PRIVATE_KEY|OBFS_PASSWORD|PROXY_USERS_JSON|BEGIN [A-Z ]*PRIVATE KEY)' \
    "${INFRA_ROOT}/infra/modules/proxy_vm/files/startup.sh"; then
    infra::die "VM startup metadata 包含应用秘密名称或内容"
fi

find "${INFRA_ROOT}/scripts" -type f -name '*.sh' -exec bash -n {} +
"$shellcheck_bin" -x -P "${INFRA_ROOT}/scripts/infra" \
    "${INFRA_ROOT}"/scripts/infra/*.sh \
    "${INFRA_ROOT}"/scripts/host/*.sh \
    "${INFRA_ROOT}"/scripts/release/*.sh \
    "${INFRA_ROOT}/scripts/validate.sh" \
    "${INFRA_ROOT}/infra/modules/proxy_vm/files/startup.sh"
"${SCRIPT_DIR}/test-guards.sh"
printf '基础设施静态验证通过\n'
