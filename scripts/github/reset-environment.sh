#!/usr/bin/env bash
set -euo pipefail

environment=""
confirmation=""
while (($#)); do
  case "$1" in
    --environment) environment="${2:-}"; shift 2 ;;
    --confirm) confirmation="${2:-}"; shift 2 ;;
    *) printf '%s\n' 'usage: reset-environment.sh --environment development --confirm owner/repo:development' >&2; exit 2 ;;
  esac
done
[[ "$environment" == "development" ]] || { printf '%s\n' 'only development can be reset by this command' >&2; exit 2; }
for command_name in gh jq; do command -v "$command_name" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command_name" >&2; exit 1; }; done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tfvars="${repo_root}/infra/environments/development.tfvars"
expected_repo="$(sed -nE 's/^github_repository[[:space:]]*=[[:space:]]*"([^"]+)"/\1/p' "$tfvars")"
expected_repo_id="$(sed -nE 's/^github_repository_id[[:space:]]*=[[:space:]]*"([^"]+)"/\1/p' "$tfvars")"
repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
actual_repo_id="$(gh api "repos/${repo}" --jq '.id')"
[[ "$repo" == "$expected_repo" && "$actual_repo_id" == "$expected_repo_id" ]] || { printf '%s\n' 'GitHub repository identity does not match development tfvars' >&2; exit 1; }
[[ "$confirmation" == "${repo}:development" ]] || { printf '%s\n' 'confirmation must exactly match owner/repo:development' >&2; exit 2; }

repository_variables="$(gh api "repos/${repo}/actions/variables")"
for name in DEV_GCP_WIF_PROVIDER DEV_GCP_PLAN_SERVICE_ACCOUNT; do
  if jq -e --arg name "$name" '.variables | any(.name == $name)' <<<"$repository_variables" >/dev/null; then
    gh api --method DELETE "repos/${repo}/actions/variables/${name}" >/dev/null
  fi
done
if gh api "repos/${repo}/environments/development" >/dev/null 2>&1; then
  gh api --method DELETE "repos/${repo}/environments/development" >/dev/null
fi
printf 'GitHub development environment and managed DEV repository variables were reset for %s\n' "$repo"
