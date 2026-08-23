#!/usr/bin/env bash
set -euo pipefail
umask 077

environment=""
users=""
reality_key=""
obfs=""
cert=""
key=""
sni=""
while (($#)); do
  case "$1" in
    --environment) environment="${2:-}"; shift 2 ;;
    --users) users="${2:-}"; shift 2 ;;
    --reality-private-key) reality_key="${2:-}"; shift 2 ;;
    --obfs-password) obfs="${2:-}"; shift 2 ;;
    --cert) cert="${2:-}"; shift 2 ;;
    --key) key="${2:-}"; shift 2 ;;
    --sni) sni="${2:-}"; shift 2 ;;
    *) printf '%s\n' 'usage: publish-secrets.sh --environment <environment> --users <file> --reality-private-key <file> --obfs-password <file> --cert <file> --key <file> --sni <hostname>' >&2; exit 2 ;;
  esac
done
case "$environment" in development|production) ;; *) exit 2 ;; esac
for path in "$users" "$reality_key" "$obfs" "$cert" "$key"; do [[ -f "$path" ]] || { printf '%s\n' 'all five secret files are required' >&2; exit 2; }; done
command -v gh >/dev/null 2>&1 || { printf '%s\n' 'missing command: gh' >&2; exit 1; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/proxy-builder-secrets.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
(cd "$repo_root" && go build -trimpath -o "${work_dir}/proxyctl" ./cmd/proxyctl)
"${work_dir}/proxyctl" inspect-environment --users "$users" --private-key-file "$reality_key" \
  --obfs-password-file "$obfs" --cert "$cert" --key "$key" --sni "$sni" --output "${work_dir}/public.json"
repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
gh secret set REALITY_PRIVATE_KEY --repo "$repo" --env "$environment" <"$reality_key"
gh secret set OBFS_PASSWORD --repo "$repo" --env "$environment" <"$obfs"
gh secret set HY2_CERT_PEM --repo "$repo" --env "$environment" <"$cert"
gh secret set HY2_KEY_PEM --repo "$repo" --env "$environment" <"$key"
gh secret set PROXY_USERS_JSON --repo "$repo" --env "$environment" <"$users"
printf 'five application secrets published for %s; no existing secret was deleted\n' "$environment"
