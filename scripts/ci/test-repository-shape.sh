#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for path in scripts/setup scripts/deploy scripts/provision scripts/lib .env.example; do
  if [[ -e "${repo_root}/${path}" ]]; then
    printf 'legacy repository path must stay removed: %s\n' "$path" >&2
    exit 1
  fi
done

if rg -n '^(setup-(infra|wif|vm|ar|firewall)|upload-env):' "${repo_root}/Makefile"; then
  printf '%s\n' 'legacy Make targets must stay removed' >&2
  exit 1
fi
if rg -n 'scripts/(setup|deploy|provision|lib)/' \
  "${repo_root}/Makefile" "${repo_root}/.github" "${repo_root}/scripts"; then
  printf '%s\n' 'executable code references a removed legacy script' >&2
  exit 1
fi
printf '%s\n' 'repository shape tests passed'
