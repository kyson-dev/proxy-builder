#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/proxy-builder-bundle-test.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

expected=$'bin/deploy-release\nbin/proxyctl\ndocker-compose.yml\nrelease.json\nsing-box.template.json'
for environment in development production; do
  archive="${test_dir}/${environment}.tar.gz"
  "${script_dir}/build-vm-bundle.sh" \
    --environment "$environment" \
    --git-sha aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    --run-id 12345 \
    --run-attempt 2 \
    --created-at 2026-08-23T12:00:00Z \
    --output "$archive" >/dev/null
  actual="$(tar -tzf "$archive" | LC_ALL=C sort)"
  [[ "$actual" == "$expected" ]]
  mkdir "${test_dir}/${environment}"
  tar -xzf "$archive" -C "${test_dir}/${environment}"
  [[ "$(jq -r '.environment' "${test_dir}/${environment}/release.json")" == "$environment" ]]
  [[ "$(jq -r '.release_id' "${test_dir}/${environment}/release.json")" == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-12345-2" ]]
  if rg -ni '(REALITY_PRIVATE_KEY|OBFS_PASSWORD|PROXY_USERS_JSON|BEGIN [A-Z ]*PRIVATE KEY|subscription_token)' "${test_dir}/${environment}"; then
    printf '%s\n' 'release bundle contains secret fields or material' >&2
    exit 1
  fi
done

printf '%s\n' 'VM release bundle tests passed'
