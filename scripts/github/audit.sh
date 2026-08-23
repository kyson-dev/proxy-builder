#!/usr/bin/env bash
set -euo pipefail

environment=""
while (($#)); do
  case "$1" in
    --environment) environment="${2:-}"; shift 2 ;;
    *) printf '%s\n' 'usage: audit.sh --environment <environment>' >&2; exit 2 ;;
  esac
done
case "$environment" in development|production) ;; *) exit 2 ;; esac
for command_name in gh jq; do command -v "$command_name" >/dev/null 2>&1 || exit 1; done
repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
prefix="DEV"
[[ "$environment" == "production" ]] && prefix="PROD"

repo_variable_names="$(gh variable list --repo "$repo" --json name --jq '.[].name')"
environment_variable_names="$(gh variable list --repo "$repo" --env "$environment" --json name --jq '.[].name')"
secret_names="$(gh secret list --repo "$repo" --env "$environment" --json name --jq '.[].name')"
for name in "${prefix}_GCP_WIF_PROVIDER" "${prefix}_GCP_PLAN_SERVICE_ACCOUNT"; do grep -Fxq "$name" <<<"$repo_variable_names" || { printf 'missing repository variable: %s\n' "$name" >&2; exit 1; }; done
for name in GCP_APPLY_SERVICE_ACCOUNT GCP_DEPLOY_SERVICE_ACCOUNT; do grep -Fxq "$name" <<<"$environment_variable_names" || { printf 'missing environment variable: %s\n' "$name" >&2; exit 1; }; done
for name in REALITY_PRIVATE_KEY OBFS_PASSWORD HY2_CERT_PEM HY2_KEY_PEM PROXY_USERS_JSON; do grep -Fxq "$name" <<<"$secret_names" || { printf 'missing environment secret: %s\n' "$name" >&2; exit 1; }; done

if [[ "$environment" == "production" ]]; then
  protection="$(gh api "repos/${repo}/environments/production")"
  jq -e '
    (.protection_rules | any(.type == "required_reviewers" and (.reviewers | any(.reviewer.login == "kysonzou")))) and
    (.deployment_branch_policy.protected_branches == false) and
    (.deployment_branch_policy.custom_branch_policies == true)
  ' <<<"$protection" >/dev/null || { printf '%s\n' 'production environment protection is incomplete' >&2; exit 1; }
  branch_policies="$(gh api "repos/${repo}/environments/production/deployment-branch-policies")"
  jq -e '(.total_count == 1) and (.branch_policies[0].name == "main")' <<<"$branch_policies" >/dev/null || {
    printf '%s\n' 'production deployment branch policy must allow main only' >&2
    exit 1
  }
fi
printf 'GitHub names and protection audited for %s (values were not read)\n' "$environment"
