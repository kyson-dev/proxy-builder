#!/usr/bin/env bash
set -euo pipefail
umask 077

action="${1:-}"
environment="${ENV:-}"
user="${USER:-}"
case "$action" in add|enable|disable|rotate) ;; *) printf '%s\n' 'action must be add, enable, disable or rotate' >&2; exit 2 ;; esac
case "$environment" in development|production) ;; *) printf '%s\n' 'ENV must be development or production' >&2; exit 2 ;; esac
[[ -n "$user" ]] || { printf '%s\n' 'USER is required' >&2; exit 2; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
users="${repo_root}/.secrets/${environment}/users.json"
[[ -f "$users" ]] || { printf '%s\n' 'local users secret does not exist' >&2; exit 1; }
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/proxy-builder-user.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
(cd "$repo_root" && go build -trimpath -o "${work_dir}/proxyctl" ./cmd/proxyctl)
"${work_dir}/proxyctl" "${action}-user" --users "$users" --name "$user"
printf 'local %s completed for %s; publish and deploy explicitly\n' "$action" "$environment"
