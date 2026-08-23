#!/usr/bin/env bash
# shellcheck disable=SC2016 # Single-quoted snippets are emitted into fake executables.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/proxy-builder-github-test.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
fake_bin="${test_root}/bin"
mkdir -p "$fake_bin"
command_log="${test_root}/commands.log"

printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
  'output=""; while (($#)); do if [[ "$1" == "-o" ]]; then output="$2"; shift 2; else shift; fi; done' \
  'cp "$FAKE_PROXYCTL" "$output"; chmod 0755 "$output"' >"${fake_bin}/go"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
  'output=""; while (($#)); do if [[ "$1" == "--output" ]]; then output="$2"; shift 2; else shift; fi; done' \
  'printf '\''{"reality_public_key":"public","reality_short_id":"0123456789abcdef","hy2_cert_sha256":"fingerprint"}'\'' >"$output"' >"${test_root}/proxyctl"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
  'printf '\''gh %s\n'\'' "$*" >>"$FAKE_COMMAND_LOG"' \
  'if [[ "$1 $2" == "repo view" ]]; then printf '\''kyson-dev/proxy-builder\n'\''; exit 0; fi' \
  'if [[ "$1 $2" == "secret set" ]]; then cat >/dev/null; exit 0; fi' >"${fake_bin}/gh"
chmod 0755 "${fake_bin}"/* "${test_root}/proxyctl"

users="${test_root}/users-secret"
reality="${test_root}/reality-secret"
obfs="${test_root}/obfs-secret"
cert="${test_root}/cert-secret"
key="${test_root}/key-secret"
printf '%s' 'USERS_CANARY_123456' >"$users"
printf '%s' 'REALITY_CANARY_123456' >"$reality"
printf '%s' 'OBFS_CANARY_123456' >"$obfs"
printf '%s' 'CERT_CANARY_123456' >"$cert"
printf '%s' 'KEY_CANARY_123456' >"$key"

PATH="${fake_bin}:$PATH" FAKE_PROXYCTL="${test_root}/proxyctl" FAKE_COMMAND_LOG="$command_log" \
  "$script_dir/publish-secrets.sh" --environment development --users "$users" \
  --reality-private-key "$reality" --obfs-password "$obfs" --cert "$cert" --key "$key" --sni www.example.com \
  >"${test_root}/output.log"
[[ "$(rg -c 'gh secret set' "$command_log")" == "5" ]] || { printf '%s\n' 'expected exactly five GitHub secrets' >&2; exit 1; }
if rg -q 'CANARY' "$command_log" "${test_root}/output.log"; then
  printf '%s\n' 'GitHub secret payload leaked into arguments or logs' >&2
  exit 1
fi
printf '%s\n' 'GitHub tool isolation tests passed'
