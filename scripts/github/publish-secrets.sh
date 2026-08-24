#!/usr/bin/env bash
set -euo pipefail
umask 077

environment=""
secret_dir=""
while (($#)); do
  case "$1" in
    --environment) environment="${2:-}"; shift 2 ;;
    --secret-dir) secret_dir="${2:-}"; shift 2 ;;
    *) printf '%s\n' 'usage: publish-secrets.sh --environment <environment> --secret-dir <directory>' >&2; exit 2 ;;
  esac
done
case "$environment" in development|production) ;; *) exit 2 ;; esac
[[ -d "$secret_dir" && ! -L "$secret_dir" ]] || { printf '%s\n' 'secret directory is required and must not be a symbolic link' >&2; exit 2; }
users="${secret_dir}/users.json"
reality_key="${secret_dir}/reality-private-key"
obfs="${secret_dir}/obfs-password"
cert="${secret_dir}/hysteria2.crt"
key="${secret_dir}/hysteria2.key"
for path in "$users" "$reality_key" "$obfs" "$cert" "$key"; do [[ -f "$path" ]] || { printf '%s\n' 'all five secret files are required' >&2; exit 2; }; done
command -v gh >/dev/null 2>&1 || { printf '%s\n' 'missing command: gh' >&2; exit 1; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
sni="$(jq -er '.hy2_sni' "${repo_root}/config/environments/${environment}.json")"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/proxy-builder-secrets.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
(cd "$repo_root" && go build -trimpath -o "${work_dir}/proxyctl" ./cmd/proxyctl)
"${work_dir}/proxyctl" inspect-environment --users "$users" --private-key-file "$reality_key" \
  --obfs-password-file "$obfs" --cert "$cert" --key "$key" --sni "$sni" --output "${work_dir}/public.json"
repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
expected_repo="$(sed -nE 's/^github_repository[[:space:]]*=[[:space:]]*"([^"]+)"/\1/p' "${repo_root}/infra/environments/${environment}.tfvars")"
expected_repo_id="$(sed -nE 's/^github_repository_id[[:space:]]*=[[:space:]]*"([^"]+)"/\1/p' "${repo_root}/infra/environments/${environment}.tfvars")"
actual_repo_id="$(gh api "repos/${repo}" --jq '.id')"
[[ "$repo" == "$expected_repo" && "$actual_repo_id" == "$expected_repo_id" ]] || { printf '%s\n' 'GitHub repository identity does not match environment tfvars' >&2; exit 1; }
gh secret set REALITY_PRIVATE_KEY --repo "$repo" --env "$environment" <"$reality_key"
gh secret set OBFS_PASSWORD --repo "$repo" --env "$environment" <"$obfs"
gh secret set HY2_CERT_PEM --repo "$repo" --env "$environment" <"$cert"
gh secret set HY2_KEY_PEM --repo "$repo" --env "$environment" <"$key"
gh secret set PROXY_USERS_JSON --repo "$repo" --env "$environment" <"$users"
printf 'five application secrets published for %s; no existing secret was deleted\n' "$environment"
