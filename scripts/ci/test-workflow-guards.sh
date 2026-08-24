#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow_root="${repo_root}/.github/workflows"

rg -q 'head.repo.full_name == github.repository' "${workflow_root}/infra-plan.yml"
rg -q 'required repository variables are absent' "${workflow_root}/infra-plan.yml"
rg -q 'PRODUCTION_OPERATIONS_ENABLED' "${workflow_root}/infra-apply.yml" "${workflow_root}/deploy.yml" "${workflow_root}/destroy.yml"
rg -q 'confirm_project_id' "${workflow_root}/destroy.yml"
if rg -q 'upload-artifact' "${workflow_root}/deploy.yml"; then
  printf '%s\n' 'deployment workflow must not upload artifacts' >&2
  exit 1
fi
rg -q 'path: \$\{\{ runner.temp \}\}/plan.txt' "${workflow_root}/infra-plan.yml"
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

git_root="$(mktemp -d "${TMPDIR:-/tmp}/proxy-builder-production-guard.XXXXXX")"
trap 'rm -rf "$git_root"' EXIT
git -C "$git_root" init --quiet
git -C "$git_root" config user.name proxy-builder-test
git -C "$git_root" config user.email proxy-builder-test@example.invalid
git -C "$git_root" commit --quiet --allow-empty -m main
git -C "$git_root" branch -M main
main_sha="$(git -C "$git_root" rev-parse HEAD)"
git -C "$git_root" checkout --quiet --orphan feature
git -C "$git_root" commit --quiet --allow-empty -m feature
feature_sha="$(git -C "$git_root" rev-parse HEAD)"
if (
  cd "$git_root"
  GITHUB_REF=refs/heads/main PRODUCTION_OPERATIONS_ENABLED=true PROXY_BUILDER_TESTING=1 PRODUCTION_MAIN_REF=main \
    "${repo_root}/scripts/delivery/guard-operation.sh" production "$feature_sha" >/dev/null 2>&1
); then
  printf '%s\n' 'production guard accepted a SHA outside main history' >&2
  exit 1
fi
(
  cd "$git_root"
  GITHUB_REF=refs/heads/main PRODUCTION_OPERATIONS_ENABLED=true PROXY_BUILDER_TESTING=1 PRODUCTION_MAIN_REF=main \
    "${repo_root}/scripts/delivery/guard-operation.sh" production "$main_sha"
)
printf '%s\n' 'workflow guard tests passed'
