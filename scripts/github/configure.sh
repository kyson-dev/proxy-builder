#!/usr/bin/env bash
set -euo pipefail

environment=""
bootstrap_output=""
enable_production=0
while (($#)); do
  case "$1" in
    --environment) environment="${2:-}"; shift 2 ;;
    --bootstrap-output) bootstrap_output="${2:-}"; shift 2 ;;
    --enable-production) enable_production=1; shift ;;
    *) printf '%s\n' 'usage: configure.sh --environment <environment> [--bootstrap-output <tofu-output.json>] [--enable-production]' >&2; exit 2 ;;
  esac
done
case "$environment" in development|production) ;; *) exit 2 ;; esac
for command_name in gh jq; do command -v "$command_name" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command_name" >&2; exit 1; }; done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ -z "$bootstrap_output" ]]; then
  command -v tofu >/dev/null 2>&1 || { printf '%s\n' 'missing command: tofu' >&2; exit 1; }
  tfvars="${repo_root}/infra/environments/${environment}.tfvars"
  project_id="$(sed -nE 's/^project_id[[:space:]]*=[[:space:]]*"([^"]+)"/\1/p' "$tfvars")"
  [[ -n "$project_id" ]] || { printf '%s\n' 'project_id is missing from environment tfvars' >&2; exit 1; }
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/proxy-builder-bootstrap-output.XXXXXX")"
  trap 'rm -rf "$work_dir"' EXIT
  bootstrap_output="${work_dir}/bootstrap.json"
  tofu -chdir="${repo_root}/infra/stacks/bootstrap" init -reconfigure -input=false \
    -backend-config="bucket=${project_id}-proxy-builder-tfstate" -backend-config="prefix=bootstrap" >/dev/null
  tofu -chdir="${repo_root}/infra/stacks/bootstrap" output -json >"$bootstrap_output"
fi
[[ -f "$bootstrap_output" ]] || { printf '%s\n' 'bootstrap output file is required' >&2; exit 2; }

repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
expected_repo="$(sed -nE 's/^github_repository[[:space:]]*=[[:space:]]*"([^"]+)"/\1/p' "${repo_root}/infra/environments/${environment}.tfvars")"
expected_repo_id="$(sed -nE 's/^github_repository_id[[:space:]]*=[[:space:]]*"([^"]+)"/\1/p' "${repo_root}/infra/environments/${environment}.tfvars")"
actual_repo_id="$(gh api "repos/${repo}" --jq '.id')"
[[ "$repo" == "$expected_repo" && "$actual_repo_id" == "$expected_repo_id" ]] || { printf '%s\n' 'GitHub repository identity does not match environment tfvars' >&2; exit 1; }
provider="$(jq -er '.workload_identity_provider.value' "$bootstrap_output")"
plan_sa="$(jq -er '.plan_service_account_email.value' "$bootstrap_output")"
apply_sa="$(jq -er '.apply_service_account_email.value' "$bootstrap_output")"
deploy_sa="$(jq -er '.deploy_service_account_email.value' "$bootstrap_output")"
prefix="DEV"
[[ "$environment" == "production" ]] && prefix="PROD"

printf '%s' '{}' | gh api --method PUT "repos/${repo}/environments/${environment}" --input - >/dev/null
gh variable set "${prefix}_GCP_WIF_PROVIDER" --repo "$repo" --body "$provider"
gh variable set "${prefix}_GCP_PLAN_SERVICE_ACCOUNT" --repo "$repo" --body "$plan_sa"
gh variable set GCP_APPLY_SERVICE_ACCOUNT --repo "$repo" --env "$environment" --body "$apply_sa"
gh variable set GCP_DEPLOY_SERVICE_ACCOUNT --repo "$repo" --env "$environment" --body "$deploy_sa"

if [[ "$environment" == "production" ]]; then
  reviewer_id="$(gh api user --jq '.id')"
  jq -n --argjson reviewer_id "$reviewer_id" '{
    wait_timer: 0,
    prevent_self_review: false,
    reviewers: [{type: "User", id: $reviewer_id}],
    deployment_branch_policy: {protected_branches: false, custom_branch_policies: true}
  }' | gh api --method PUT "repos/${repo}/environments/production" --input - >/dev/null
  policies="$(gh api "repos/${repo}/environments/production/deployment-branch-policies")"
  main_exists=0
  while IFS=$'\t' read -r policy_id policy_name; do
    [[ -n "$policy_id" ]] || continue
    if [[ "$policy_name" == "main" ]]; then
      main_exists=1
    else
      gh api --method DELETE "repos/${repo}/environments/production/deployment-branch-policies/${policy_id}" >/dev/null
    fi
  done < <(jq -r '.branch_policies[] | [.id, .name] | @tsv' <<<"$policies")
  if [[ "$main_exists" == "0" ]]; then
    printf '%s' '{"name":"main","type":"branch"}' | gh api --method POST \
      "repos/${repo}/environments/production/deployment-branch-policies" --input - >/dev/null
  fi
  if [[ "$enable_production" == "1" ]]; then
    "$(dirname "$0")/audit.sh" --environment production
    gh variable set PRODUCTION_OPERATIONS_ENABLED --repo "$repo" --body true
  fi
fi
printf 'GitHub configuration updated for %s\n' "$environment"
