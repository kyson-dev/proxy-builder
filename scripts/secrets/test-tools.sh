#!/usr/bin/env bash
# shellcheck disable=SC2016 # Single-quoted snippets are emitted into a fake executable.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/proxy-builder-secret-tools.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
fake_tofu="${test_root}/tofu"
secrets_root="${test_root}/secrets"
mkdir -p "$secrets_root/development"
printf '%s\n' '{"version":1,"users":[{"name":"alice","enabled":true,"vless_uuid":"00000000-0000-4000-8000-000000000001","hy2_password":"hy2-password-123456789012","subscription_token":"token with spaces 123456789012"}]}' >"$secrets_root/development/users.json"
chmod 0600 "$secrets_root/development/users.json"

printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
  'if [[ "${1:-}" == "version" ]]; then printf '\''{"terraform_version":"1.12.6"}\n'\''; exit 0; fi' \
  'if [[ "$*" == *" output -raw subscription_service_url"* ]]; then printf '\''https://subscription.example'\''; fi' >"$fake_tofu"
chmod 0755 "$fake_tofu"

url="$(ENV=development USER=alice FORMAT=clash TOFU_BIN="$fake_tofu" PROXY_BUILDER_SECRETS_ROOT="$secrets_root" "$repo_root/scripts/secrets/subscription-url.sh")"
[[ "$url" == 'https://subscription.example/v1/subscription?token=token%20with%20spaces%20123456789012&format=clash' ]] || { printf 'unexpected subscription URL: %s\n' "$url" >&2; exit 1; }
set +e
ENV=development USER=missing TOFU_BIN="$fake_tofu" PROXY_BUILDER_SECRETS_ROOT="$secrets_root" "$repo_root/scripts/secrets/subscription-url.sh" >/dev/null 2>&1
status=$?
set -e
[[ "$status" -ne 0 ]] || { printf '%s\n' 'missing user unexpectedly produced a URL' >&2; exit 1; }
set +e
ENV=development USER=alice FORMAT=singbox TOFU_BIN="$fake_tofu" PROXY_BUILDER_SECRETS_ROOT="$secrets_root" "$repo_root/scripts/secrets/subscription-url.sh" >/dev/null 2>&1
status=$?
set -e
[[ "$status" -ne 0 ]] || { printf '%s\n' 'unsupported sing-box format unexpectedly produced a URL' >&2; exit 1; }
printf '%s\n' 'local secret tool tests passed'
