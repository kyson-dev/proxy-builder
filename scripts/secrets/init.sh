#!/usr/bin/env bash
set -euo pipefail
umask 077

environment="${ENV:-}"
user="${USER:-}"
case "$environment" in development|production) ;; *) printf '%s\n' 'ENV must be development or production' >&2; exit 2 ;; esac
[[ -n "$user" ]] || { printf '%s\n' 'USER is required' >&2; exit 2; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
config="${repo_root}/config/environments/${environment}.json"
secret_dir="${repo_root}/.secrets/${environment}"
command -v go >/dev/null 2>&1 || { printf '%s\n' 'missing command: go' >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { printf '%s\n' 'missing command: jq' >&2; exit 1; }
sni="$(jq -er '.hy2_sni' "$config")"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/proxy-builder-init.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
(cd "$repo_root" && go build -trimpath -o "${work_dir}/proxyctl" ./cmd/proxyctl)
"${work_dir}/proxyctl" init-environment --output-dir "$secret_dir" --sni "$sni" --user "$user"
printf '%s secret bundle initialized at %s; no value was published\n' "$environment" "$secret_dir"
