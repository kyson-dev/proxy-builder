#!/usr/bin/env bash
set -euo pipefail

confirm=""
while (($#)); do
  case "$1" in
    --confirm) confirm="${2:-}"; shift 2 ;;
    *) printf '%s\n' 'usage: clear-legacy-production-secrets.sh --confirm <owner/repository>:production' >&2; exit 2 ;;
  esac
done

command -v gh >/dev/null 2>&1 || { printf '%s\n' 'missing command: gh' >&2; exit 1; }
repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
[[ "$confirm" == "${repo}:production" ]] || { printf '%s\n' 'production legacy secret confirmation does not match repository'; exit 2; }

for secret_name in \
  GCP_AR_LOCATION GCP_AR_REPOSITORY GCP_PROJECT_ID GCP_SERVICE_ACCOUNT GCP_VM_NAME GCP_VM_ZONE GCP_WORKLOAD_IDENTITY_PROVIDER \
  HY2_SNI REALITY_DEST REALITY_PUBLIC_KEY REALITY_SHORT_ID USERS_JSON; do
  gh secret delete "$secret_name" --repo "$repo" --env production 2>/dev/null || true
done
printf '%s\n' 'legacy production environment secrets removed; application secrets were not changed'
