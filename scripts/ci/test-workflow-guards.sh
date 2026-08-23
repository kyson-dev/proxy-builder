#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow_root="${repo_root}/.github/workflows"

rg -q 'head.repo.full_name == github.repository' "${workflow_root}/infra-plan.yml"
rg -q 'required repository variables are absent' "${workflow_root}/infra-plan.yml"
rg -q 'PRODUCTION_OPERATIONS_ENABLED' "${workflow_root}/infra-apply.yml" "${workflow_root}/deploy.yml" "${workflow_root}/destroy.yml"
rg -q 'confirm_project_id' "${workflow_root}/destroy.yml"
if rg -q 'bootstrap' "${workflow_root}/destroy.yml"; then
  printf '%s\n' 'destroy workflow must not offer bootstrap destruction' >&2
  exit 1
fi
for workflow in infra-apply.yml deploy.yml destroy.yml; do
  rg -q 'group: proxy-builder-\$\{\{ inputs.environment \}\}' "${workflow_root}/${workflow}"
  rg -q 'cancel-in-progress: false' "${workflow_root}/${workflow}"
done

if GITHUB_REF=refs/heads/feature PRODUCTION_OPERATIONS_ENABLED=true "${repo_root}/scripts/delivery/guard-operation.sh" production >/dev/null 2>&1; then
  printf '%s\n' 'production guard accepted a non-main workflow ref' >&2
  exit 1
fi
if GITHUB_REF=refs/heads/main PRODUCTION_OPERATIONS_ENABLED=false "${repo_root}/scripts/delivery/guard-operation.sh" production >/dev/null 2>&1; then
  printf '%s\n' 'production guard accepted a disabled gate' >&2
  exit 1
fi
GITHUB_REF=refs/heads/feature "${repo_root}/scripts/delivery/guard-operation.sh" development
printf '%s\n' 'workflow guard tests passed'
