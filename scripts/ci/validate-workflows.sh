#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
actionlint_bin="${ACTIONLINT_BIN:-actionlint}"
command -v "$actionlint_bin" >/dev/null 2>&1 || { printf '%s\n' 'actionlint v1.7.12 is required (or set ACTIONLINT_BIN)' >&2; exit 1; }
version="$($actionlint_bin --version | head -n1)"
[[ "$version" == *"1.7.12"* ]] || { printf 'actionlint v1.7.12 is required, got: %s\n' "$version" >&2; exit 1; }
"$actionlint_bin" -color "${repo_root}/.github/workflows/"*.yml

if rg -n 'uses: [^ ]+@(v[0-9]+|main|master)$' "${repo_root}/.github/workflows"; then
  printf '%s\n' 'all third-party actions must use full commit SHAs' >&2
  exit 1
fi
if rg -n '^permissions: write-all|^[[:space:]]+[a-z-]+: write$' "${repo_root}/.github/workflows" | rg -v 'id-token: write'; then
  printf '%s\n' 'workflow contains an unexpected write permission' >&2
  exit 1
fi
"${repo_root}/scripts/ci/test-workflow-guards.sh"

