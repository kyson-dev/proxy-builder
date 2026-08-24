#!/usr/bin/env bash
set -euo pipefail
umask 077

action="${1:-}"
environment="${ENV:-}"
user="${USER:-}"
protocol="${PROTOCOL:-}"
case "$action" in add|enable|disable|rotate|protocol-enable|protocol-disable) ;; *) printf '%s\n' 'action must be add, enable, disable, rotate, protocol-enable or protocol-disable' >&2; exit 2 ;; esac
case "$environment" in development|production) ;; *) printf '%s\n' 'ENV must be development or production' >&2; exit 2 ;; esac
[[ -n "$user" ]] || { printf '%s\n' 'USER is required' >&2; exit 2; }
if [[ "$action" == protocol-enable || "$action" == protocol-disable ]]; then
  [[ "$protocol" == vless || "$protocol" == hysteria2 ]] || { printf '%s\n' 'PROTOCOL must be vless or hysteria2' >&2; exit 2; }
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
users="${repo_root}/.secrets/${environment}/users.json"
[[ -f "$users" ]] || { printf '%s\n' 'local users secret does not exist' >&2; exit 1; }
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/proxy-builder-user.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
(cd "$repo_root" && go build -trimpath -o "${work_dir}/proxyctl" ./cmd/proxyctl)
command="${action}-user"
if [[ "$action" == protocol-enable ]]; then command="enable-user-protocol"; fi
if [[ "$action" == protocol-disable ]]; then command="disable-user-protocol"; fi
arguments=("$command" --users "$users" --name "$user")
if [[ -n "$protocol" ]]; then arguments+=(--protocol "$protocol"); fi
"${work_dir}/proxyctl" "${arguments[@]}"
printf 'local %s completed for %s; publish and deploy explicitly\n' "$action" "$environment"
