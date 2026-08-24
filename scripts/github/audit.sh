#!/usr/bin/env bash
set -euo pipefail

environment=""
bootstrap_output=""
while (($#)); do
  case "$1" in
    --environment) environment="${2:-}"; shift 2 ;;
    --bootstrap-output) bootstrap_output="${2:-}"; shift 2 ;;
    *) printf '%s\n' 'usage: audit.sh --environment <environment> [--bootstrap-output <tofu-output.json>]' >&2; exit 2 ;;
  esac
done
case "$environment" in development|production) ;; *) exit 2 ;; esac
for command_name in gh jq; do command -v "$command_name" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command_name" >&2; exit 1; }; done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tfvars="${repo_root}/infra/environments/${environment}.tfvars"
expected_repo="$(sed -nE 's/^github_repository[[:space:]]*=[[:space:]]*"([^"]+)"/\1/p' "$tfvars")"
expected_repo_id="$(sed -nE 's/^github_repository_id[[:space:]]*=[[:space:]]*"([^"]+)"/\1/p' "$tfvars")"
repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
actual_repo_id="$(gh api "repos/${repo}" --jq '.id')"
[[ "$repo" == "$expected_repo" && "$actual_repo_id" == "$expected_repo_id" ]] || { printf '%s\n' 'GitHub repository identity does not match environment tfvars' >&2; exit 1; }

if [[ -z "$bootstrap_output" ]]; then
  command -v tofu >/dev/null 2>&1 || { printf '%s\n' 'missing command: tofu' >&2; exit 1; }
  project_id="$(sed -nE 's/^project_id[[:space:]]*=[[:space:]]*"([^"]+)"/\1/p' "$tfvars")"
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/proxy-builder-bootstrap-audit.XXXXXX")"
  trap 'rm -rf "$work_dir"' EXIT
  bootstrap_output="${work_dir}/bootstrap.json"
  tofu -chdir="${repo_root}/infra/stacks/bootstrap" init -reconfigure -input=false \
    -backend-config="bucket=${project_id}-proxy-builder-tfstate" -backend-config="prefix=bootstrap" >/dev/null
  tofu -chdir="${repo_root}/infra/stacks/bootstrap" output -json >"$bootstrap_output"
fi
[[ -f "$bootstrap_output" ]] || { printf '%s\n' 'bootstrap output file is required' >&2; exit 2; }

provider="$(jq -er '.workload_identity_provider.value' "$bootstrap_output")"
plan_sa="$(jq -er '.plan_service_account_email.value' "$bootstrap_output")"
apply_sa="$(jq -er '.apply_service_account_email.value' "$bootstrap_output")"
deploy_sa="$(jq -er '.deploy_service_account_email.value' "$bootstrap_output")"
prefix="DEV"
[[ "$environment" == "production" ]] && prefix="PROD"

repo_variables="$(gh api "repos/${repo}/actions/variables")"
environment_variables="$(gh api "repos/${repo}/environments/${environment}/variables")"
environment_secrets="$(gh api "repos/${repo}/environments/${environment}/secrets")"
jq -e --arg prefix "${prefix}_" --arg first "${prefix}_GCP_PLAN_SERVICE_ACCOUNT" --arg second "${prefix}_GCP_WIF_PROVIDER" '
  [.variables[].name | select(startswith($prefix))] | sort == [$first, $second]
' <<<"$repo_variables" >/dev/null || { printf '%s\n' 'repository environment variable names are not exact' >&2; exit 1; }
jq -e '[.variables[].name] | sort == ["GCP_APPLY_SERVICE_ACCOUNT", "GCP_DEPLOY_SERVICE_ACCOUNT"]' \
  <<<"$environment_variables" >/dev/null || { printf '%s\n' 'GitHub environment variable names are not exact' >&2; exit 1; }
jq -e '[.secrets[].name] | sort == ["HY2_CERT_PEM", "HY2_KEY_PEM", "OBFS_PASSWORD", "PROXY_USERS_JSON", "REALITY_PRIVATE_KEY"]' \
  <<<"$environment_secrets" >/dev/null || { printf '%s\n' 'GitHub environment secret names are not exact' >&2; exit 1; }

read_variable() { jq -er --arg name "$2" '.variables[] | select(.name == $name) | .value' <<<"$1"; }
[[ "$(read_variable "$repo_variables" "${prefix}_GCP_WIF_PROVIDER")" == "$provider" ]] || { printf '%s\n' 'WIF provider variable does not match bootstrap state' >&2; exit 1; }
[[ "$(read_variable "$repo_variables" "${prefix}_GCP_PLAN_SERVICE_ACCOUNT")" == "$plan_sa" ]] || { printf '%s\n' 'plan service account variable does not match bootstrap state' >&2; exit 1; }
[[ "$(read_variable "$environment_variables" GCP_APPLY_SERVICE_ACCOUNT)" == "$apply_sa" ]] || { printf '%s\n' 'apply service account variable does not match bootstrap state' >&2; exit 1; }
[[ "$(read_variable "$environment_variables" GCP_DEPLOY_SERVICE_ACCOUNT)" == "$deploy_sa" ]] || { printf '%s\n' 'deploy service account variable does not match bootstrap state' >&2; exit 1; }

if [[ "$environment" == "production" ]]; then
  reviewer_id="$(gh api user --jq '.id')"
  protection="$(gh api "repos/${repo}/environments/production")"
  jq -e --argjson reviewer_id "$reviewer_id" '
    (.protection_rules | any(.type == "required_reviewers" and (.reviewers | any(.reviewer.id == $reviewer_id)))) and
    (.deployment_branch_policy.protected_branches == false) and
    (.deployment_branch_policy.custom_branch_policies == true)
  ' <<<"$protection" >/dev/null || { printf '%s\n' 'production environment protection is incomplete' >&2; exit 1; }
  branch_policies="$(gh api "repos/${repo}/environments/production/deployment-branch-policies")"
  jq -e '(.total_count == 1) and (.branch_policies[0].name == "main")' <<<"$branch_policies" >/dev/null || {
    printf '%s\n' 'production deployment branch policy must allow main only' >&2
    exit 1
  }
fi
printf 'GitHub names, values and protection audited for %s (secret values were not read)\n' "$environment"
