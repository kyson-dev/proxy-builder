#!/usr/bin/env bash
set -euo pipefail
umask 077

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
legacy_users="${repo_root}/users.production.json"
legacy_environment="${repo_root}/.env.production"
config="${repo_root}/config/environments/production.json"
output_directory="${repo_root}/.secrets/production"

for command_name in go jq; do
  command -v "$command_name" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command_name" >&2; exit 1; }
done
for input in "$legacy_users" "$legacy_environment" "$config"; do
  [[ -f "$input" && ! -L "$input" ]] || { printf '%s\n' 'production import inputs must be regular files'; exit 2; }
done

sni="$(jq -er '.hy2_sni' "$config")"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/proxy-builder-production-import.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
(cd "$repo_root" && go build -trimpath -o "${work_dir}/proxyctl" ./cmd/proxyctl)
"${work_dir}/proxyctl" import-legacy-production \
  --legacy-users "$legacy_users" \
  --legacy-env "$legacy_environment" \
  --output-dir "$output_directory" \
  --sni "$sni" \
  --rename-user 'KYSON=USA'
printf '%s\n' 'production secret bundle imported; no secret was published'
