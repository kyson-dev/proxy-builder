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
  'if [[ "$1" == "api" && "$*" == *"--input -"* ]]; then cat >/dev/null; exit 0; fi' \
  'if [[ "$1" == "api" && "$*" == *"repos/kyson-dev/proxy-builder/actions/variables"* && "$*" != *"--method DELETE"* ]]; then' \
  '  extra=""; [[ "${FAKE_AUDIT_EXTRA:-0}" == "1" ]] && extra='\'',{"name":"DEV_LEGACY","value":"legacy"}'\''' \
  '  printf '\''{"variables":[{"name":"DEV_GCP_WIF_PROVIDER","value":"projects/123/locations/global/workloadIdentityPools/pool/providers/provider"},{"name":"DEV_GCP_PLAN_SERVICE_ACCOUNT","value":"plan@example.iam.gserviceaccount.com"},{"name":"PROD_GCP_WIF_PROVIDER","value":"projects/123/locations/global/workloadIdentityPools/pool/providers/provider"},{"name":"PROD_GCP_PLAN_SERVICE_ACCOUNT","value":"plan@example.iam.gserviceaccount.com"}%s]}\n'\'' "$extra"; exit 0' \
  'fi' \
  'if [[ "$1" == "api" && "$*" == *"environments/development/variables"* ]]; then printf '\''{"variables":[{"name":"GCP_APPLY_SERVICE_ACCOUNT","value":"apply@example.iam.gserviceaccount.com"},{"name":"GCP_DEPLOY_SERVICE_ACCOUNT","value":"deploy@example.iam.gserviceaccount.com"}]}\n'\''; exit 0; fi' \
  'if [[ "$1" == "api" && "$*" == *"environments/development/secrets"* ]]; then printf '\''{"secrets":[{"name":"REALITY_PRIVATE_KEY"},{"name":"OBFS_PASSWORD"},{"name":"HY2_CERT_PEM"},{"name":"HY2_KEY_PEM"},{"name":"PROXY_USERS_JSON"}]}\n'\''; exit 0; fi' \
  'if [[ "$1" == "api" && "$*" == *"environments/production/variables"* ]]; then printf '\''{"variables":[{"name":"GCP_APPLY_SERVICE_ACCOUNT","value":"apply@example.iam.gserviceaccount.com"},{"name":"GCP_DEPLOY_SERVICE_ACCOUNT","value":"deploy@example.iam.gserviceaccount.com"}]}\n'\''; exit 0; fi' \
  'if [[ "$1" == "api" && "$*" == *"environments/production/secrets"* ]]; then printf '\''{"secrets":[{"name":"REALITY_PRIVATE_KEY"},{"name":"OBFS_PASSWORD"},{"name":"HY2_CERT_PEM"},{"name":"HY2_KEY_PEM"},{"name":"PROXY_USERS_JSON"}]}\n'\''; exit 0; fi' \
  'if [[ "$1" == "api" && "$*" == *"environments/production/deployment-branch-policies"* ]]; then printf '\''{"total_count":1,"branch_policies":[{"name":"main"}]}\n'\''; exit 0; fi' \
  'if [[ "$1" == "api" && "$*" == *"environments/production"* && "$*" != *"--method DELETE"* ]]; then printf '\''{"protection_rules":[{"type":"required_reviewers","reviewers":[{"reviewer":{"id":123456}}]}],"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}\n'\''; exit 0; fi' \
  'if [[ "$1" == "api" && "$2" == "user" && "$*" == *"--jq .id"* ]]; then printf '\''123456\n'\''; exit 0; fi' \
  'if [[ "$1" == "api" && "$*" == *"repos/kyson-dev/proxy-builder"* && "$*" == *"--jq .id"* ]]; then printf '\''986343343\n'\''; exit 0; fi' \
  'if [[ "$1" == "api" && "$*" == *"environments/development"* && "$*" != *"--method DELETE"* ]]; then printf '\''{}\n'\''; exit 0; fi' \
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

secret_dir="${test_root}/secret-dir"
mkdir -m 0700 "$secret_dir"
mv "$users" "${secret_dir}/users.json"
mv "$reality" "${secret_dir}/reality-private-key"
mv "$obfs" "${secret_dir}/obfs-password"
mv "$cert" "${secret_dir}/hysteria2.crt"
mv "$key" "${secret_dir}/hysteria2.key"
PATH="${fake_bin}:$PATH" FAKE_PROXYCTL="${test_root}/proxyctl" FAKE_COMMAND_LOG="$command_log" \
  "$script_dir/publish-secrets.sh" --environment development --secret-dir "$secret_dir" \
  >"${test_root}/output.log"
[[ "$(rg -c 'gh secret set' "$command_log")" == "5" ]] || { printf '%s\n' 'expected exactly five GitHub secrets' >&2; exit 1; }
if rg -q 'CANARY' "$command_log" "${test_root}/output.log"; then
  printf '%s\n' 'GitHub secret payload leaked into arguments or logs' >&2
  exit 1
fi

bootstrap_output="${test_root}/bootstrap.json"
printf '%s\n' '{"workload_identity_provider":{"value":"projects/123/locations/global/workloadIdentityPools/pool/providers/provider"},"plan_service_account_email":{"value":"plan@example.iam.gserviceaccount.com"},"apply_service_account_email":{"value":"apply@example.iam.gserviceaccount.com"},"deploy_service_account_email":{"value":"deploy@example.iam.gserviceaccount.com"}}' >"$bootstrap_output"
: >"$command_log"
PATH="${fake_bin}:$PATH" FAKE_COMMAND_LOG="$command_log" \
  "$script_dir/configure.sh" --environment development --bootstrap-output "$bootstrap_output" >"${test_root}/configure.log"
[[ "$(rg -c 'gh variable set' "$command_log")" == "4" ]] || { printf '%s\n' 'expected exactly four GitHub variables' >&2; exit 1; }
environment_line="$(rg -n 'gh api --method PUT repos/kyson-dev/proxy-builder/environments/development' "$command_log" | cut -d: -f1)"
variable_line="$(rg -n 'gh variable set' "$command_log" | cut -d: -f1 | head -n1)"
[[ -n "$environment_line" && "$environment_line" -lt "$variable_line" ]] || { printf '%s\n' 'GitHub environment was not ensured before variables' >&2; exit 1; }

: >"$command_log"
PATH="${fake_bin}:$PATH" FAKE_COMMAND_LOG="$command_log" \
  "$script_dir/audit.sh" --environment development --bootstrap-output "$bootstrap_output" >"${test_root}/audit.log"
PATH="${fake_bin}:$PATH" FAKE_COMMAND_LOG="$command_log" \
  "$script_dir/audit.sh" --environment production --bootstrap-output "$bootstrap_output" >"${test_root}/production-audit.log"
set +e
PATH="${fake_bin}:$PATH" FAKE_COMMAND_LOG="$command_log" FAKE_AUDIT_EXTRA=1 \
  "$script_dir/audit.sh" --environment development --bootstrap-output "$bootstrap_output" >/dev/null 2>&1
status=$?
set -e
[[ "$status" -ne 0 ]] || { printf '%s\n' 'strict GitHub audit accepted an unexpected DEV variable' >&2; exit 1; }

: >"$command_log"
PATH="${fake_bin}:$PATH" FAKE_COMMAND_LOG="$command_log" \
  "$script_dir/reset-environment.sh" --environment development --confirm kyson-dev/proxy-builder:development >"${test_root}/reset.log"
rg -q 'actions/variables/DEV_GCP_WIF_PROVIDER' "$command_log" || { printf '%s\n' 'reset did not delete the managed WIF variable' >&2; exit 1; }
rg -q 'actions/variables/DEV_GCP_PLAN_SERVICE_ACCOUNT' "$command_log" || { printf '%s\n' 'reset did not delete the managed plan variable' >&2; exit 1; }
rg -q -- '--method DELETE repos/kyson-dev/proxy-builder/environments/development' "$command_log" || { printf '%s\n' 'reset did not delete the development environment' >&2; exit 1; }
if rg -q 'production|PROD_' "$command_log"; then
  printf '%s\n' 'development reset touched production configuration' >&2
  exit 1
fi
set +e
PATH="${fake_bin}:$PATH" FAKE_COMMAND_LOG="$command_log" \
  "$script_dir/reset-environment.sh" --environment production --confirm kyson-dev/proxy-builder:production >/dev/null 2>&1
status=$?
set -e
[[ "$status" -ne 0 ]] || { printf '%s\n' 'reset accepted production' >&2; exit 1; }
printf '%s\n' 'GitHub tool isolation tests passed'
