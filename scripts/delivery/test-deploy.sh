#!/usr/bin/env bash
# shellcheck disable=SC2016 # Single-quoted snippets are emitted into fake executables.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/proxy-builder-delivery-test.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
fake_bin="${test_root}/bin"
mkdir -p "$fake_bin"
command_log="${test_root}/commands.log"

printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
  'output=""' \
  'while (($#)); do if [[ "$1" == "-o" ]]; then output="$2"; shift 2; else shift; fi; done' \
  'cp "$FAKE_PROXYCTL" "$output"' 'chmod 0755 "$output"' >"${fake_bin}/go"

printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
  'command_name="${1:-}"' 'shift || true' \
  'if [[ "$command_name" == "inspect-environment" ]]; then' \
  '  output=""; while (($#)); do if [[ "$1" == "--output" ]]; then output="$2"; shift 2; else shift; fi; done' \
  '  printf %s '\''{"reality_public_key":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","reality_short_id":"0123456789abcdef","hy2_cert_sha256":"AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA"}'\'' >"$output"' \
  'elif [[ "$command_name" == "render-probe-config" ]]; then' \
  '  output=""; while (($#)); do if [[ "$1" == "--output" ]]; then output="$2"; shift 2; else shift; fi; done' \
  '  printf %s '\''{}'\'' >"$output"' \
  'fi' 'exit 0' >"${test_root}/proxyctl"
chmod 0755 "${test_root}/proxyctl"

printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
  'printf '\''gcloud %s\n'\'' "$*" >>"$FAKE_COMMAND_LOG"' \
  'if [[ "$1 $2 $3" == "compute ssh --tunnel-through-iap" ]]; then if [[ "$*" == *"--inspect-certificate"* ]]; then printf '\''%s'\'' "${FAKE_REMOTE_CERT:-}"; exit 0; elif [[ "$*" == *"--rollback"* ]]; then exit "${FAKE_VM_ROLLBACK_STATUS:-0}"; else exit "${FAKE_VM_STATUS:-0}"; fi; fi' \
  'if [[ "$1 $2 $3" == "secrets versions add" ]]; then printf '\''projects/p/secrets/s/versions/1\n'\''; fi' \
  'if [[ "$1 $2 $3" == "run services update-traffic" && "$*" == *"--to-revisions old-revision=100"* ]]; then exit "${FAKE_CLOUD_ROLLBACK_STATUS:-0}"; fi' \
  'if [[ "$1 $2 $3" == "run services describe" ]]; then' \
  '  case "$*" in *"--format=json"*) printf '\''%s\n'\'' '\''{"status":{"traffic":[{"percent":100,"revisionName":"old-revision"}]}}'\'' ;; *"latestCreatedRevisionName"*) printf '\''new-revision\n'\'' ;; *"status.url"*) printf '\''https://service.example\n'\'' ;; esac' \
  'fi' \
  'if [[ "$1 $2 $3" == "run revisions describe" ]]; then' \
  '  printf '\''%s\n'\'' '\''{"status":{"conditions":[{"type":"Ready","status":"True"}]}}'\''' \
  'fi' >"${fake_bin}/gcloud"

printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
  'output=""; write_out=""; args="$*"; while (($#)); do case "$1" in --output) output="$2"; shift 2 ;; --write-out) write_out="$2"; shift 2 ;; *) shift ;; esac; done' \
  'if [[ "$args" == *"https://service.example/v1/health"* ]]; then' \
  '  count="$(cat "$FAKE_HEALTH_COUNT_FILE")"; count=$((count + 1)); printf %s "$count" >"$FAKE_HEALTH_COUNT_FILE"' \
  '  if [[ "${FAKE_PUBLIC_HEALTH_FAIL:-0}" == "1" || "$count" -le "${FAKE_PUBLIC_HEALTH_FAILURES:-0}" ]]; then exit 22; fi' \
  'fi' \
  'if [[ -n "$output" ]]; then cat >/dev/null || true; printf '\''validated-response'\'' >"$output"; fi' \
  'if [[ -n "$write_out" ]]; then if [[ "${FAKE_E2E_FAIL:-0}" == "1" ]]; then printf 500; else printf 204; fi; fi' >"${fake_bin}/curl"

printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"${fake_bin}/sleep"

printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
  'printf '\''docker %s\n'\'' "$*" >>"$FAKE_COMMAND_LOG"' \
  'if [[ "${1:-}" == "run" && "$*" == *"--detach"* ]]; then printf '\''container-id\n'\''; fi' >"${fake_bin}/docker"
chmod 0755 "${fake_bin}"/*

run_deploy() {
  printf '0' >"${test_root}/health-count"
  PATH="${fake_bin}:$PATH" FAKE_PROXYCTL="${test_root}/proxyctl" FAKE_COMMAND_LOG="$command_log" FAKE_VM_STATUS="${1:-0}" FAKE_REMOTE_CERT="${2:-}" \
    FAKE_VM_ROLLBACK_STATUS="${FAKE_VM_ROLLBACK_STATUS:-0}" FAKE_CLOUD_ROLLBACK_STATUS="${FAKE_CLOUD_ROLLBACK_STATUS:-0}" \
    FAKE_PUBLIC_HEALTH_FAIL="${FAKE_PUBLIC_HEALTH_FAIL:-0}" FAKE_PUBLIC_HEALTH_FAILURES="${FAKE_PUBLIC_HEALTH_FAILURES:-0}" \
    FAKE_HEALTH_COUNT_FILE="${test_root}/health-count" FAKE_E2E_FAIL="${FAKE_E2E_FAIL:-0}" \
    ENVIRONMENT=development GIT_SHA=0123456789abcdef0123456789abcdef01234567 RUN_ID=123 RUN_ATTEMPT=1 \
    IMAGE_DIGEST=us-west1-docker.pkg.dev/project/repo/subscription@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    GCP_PROJECT_ID=project GCP_REGION=us-west1 GCP_VM_NAME=proxy-dev GCP_VM_ZONE=us-west1-b \
    SUBSCRIPTION_SERVICE_NAME=proxy-dev-subscription PROXY_IP=203.0.113.10 \
    PROXY_USERS_SECRET_ID=proxy-dev-users OBFS_PASSWORD_SECRET_ID=proxy-dev-obfs \
    REALITY_PRIVATE_KEY=REALITY_PRIVATE_CANARY_1234567890 OBFS_PASSWORD=OBFS_CANARY_12345678901234567890 \
    HY2_CERT_PEM=HY2_CERT_CANARY HY2_KEY_PEM=HY2_KEY_CANARY \
    PROXY_USERS_JSON='{"version":1,"users":[{"name":"alice","enabled":true,"vless_uuid":"00000000-0000-4000-8000-000000000001","hy2_password":"HY2_PASSWORD_CANARY_123456789","subscription_token":"SUB_TOKEN_CANARY_123456789012"}]}' \
    "$script_dir/deploy.sh"
}

set +e
run_deploy 20 >"${test_root}/rollback.log" 2>&1
status=$?
set -e
[[ "$status" == "20" ]] || { printf 'expected VM rollback status 20, got %s\n' "$status" >&2; exit 1; }
if rg -q 'secrets versions add' "$command_log"; then
  printf '%s\n' 'secret versions were created after failed VM deployment' >&2
  exit 1
fi

: >"$command_log"
run_deploy 0 >"${test_root}/success.log" 2>&1
ssh_line="$(rg -n 'gcloud compute ssh' "$command_log" | cut -d: -f1 | head -n1)"
secret_line="$(rg -n 'gcloud secrets versions add' "$command_log" | cut -d: -f1 | head -n1)"
run_line="$(rg -n 'gcloud run deploy' "$command_log" | cut -d: -f1 | head -n1)"
[[ "$ssh_line" -lt "$secret_line" && "$secret_line" -lt "$run_line" ]] || { printf '%s\n' 'deployment ordering contract failed' >&2; exit 1; }
rg -q -- '--to-revisions new-revision=100' "$command_log" || { printf '%s\n' 'healthy Cloud Run revision was not promoted by immutable revision name' >&2; exit 1; }
rg -q 'run revisions describe new-revision' "$command_log" || { printf '%s\n' 'candidate Cloud Run revision readiness was not checked directly' >&2; exit 1; }
rg 'gcloud run deploy' "$command_log" | rg -q -- '--ingress all.*--no-invoker-iam-check.*--default-url' || {
  printf '%s\n' 'Cloud Run deployment did not preserve the public entry contract' >&2
  exit 1
}
if rg -q -- '--tag|--to-tags' "$command_log"; then
  printf '%s\n' 'deployment still depends on Cloud Run traffic-tag routing' >&2
  exit 1
fi
if rg -q 'CANARY|subscription_token|REALITY_PRIVATE' "$command_log" "${test_root}/success.log" "${test_root}/rollback.log"; then
  printf '%s\n' 'secret canary leaked into arguments or logs' >&2
  exit 1
fi
if ! rg 'gcloud compute scp' "$command_log" | rg -q 'hysteria2\.crt.*hysteria2\.key'; then
  printf '%s\n' 'first deployment did not upload the certificate pair' >&2
  exit 1
fi

: >"$command_log"
FAKE_PUBLIC_HEALTH_FAILURES=2 run_deploy 0 >"${test_root}/public-health-retry.log" 2>&1
[[ "$(cat "${test_root}/health-count")" == "3" ]] || { printf '%s\n' 'public health propagation was not retried to success' >&2; exit 1; }
if rg -q -- '--to-revisions old-revision=100' "$command_log"; then
  printf '%s\n' 'transient public health propagation triggered rollback' >&2
  exit 1
fi

: >"$command_log"
matching_fingerprint='AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA'
run_deploy 0 "$matching_fingerprint" >"${test_root}/matching.log" 2>&1
if rg 'gcloud compute scp' "$command_log" | rg -q 'hysteria2\.(crt|key)'; then
  printf '%s\n' 'unchanged certificate was uploaded again' >&2
  exit 1
fi

: >"$command_log"
set +e
FAKE_E2E_FAIL=1 run_deploy 0 >"${test_root}/e2e-failure.log" 2>&1
status=$?
set -e
[[ "$status" == "20" ]] || { printf 'expected coordinated rollback status 20 after E2E failure, got %s\n' "$status" >&2; exit 1; }
rg -q -- '--rollback '\''0123456789abcdef0123456789abcdef01234567-123-1'\''' "$command_log" || { printf '%s\n' 'E2E failure did not request VM rollback' >&2; exit 1; }
e2e_cloud_rollback_line="$(rg -n -- '--to-revisions old-revision=100' "$command_log" | cut -d: -f1 | head -n1)"
e2e_vm_rollback_line="$(rg -n -- '--rollback '\''0123456789abcdef0123456789abcdef01234567-123-1'\''' "$command_log" | cut -d: -f1 | head -n1)"
[[ -n "$e2e_cloud_rollback_line" && -n "$e2e_vm_rollback_line" && "$e2e_cloud_rollback_line" -lt "$e2e_vm_rollback_line" ]] || {
  printf '%s\n' 'E2E rollback did not restore Cloud Run before VM' >&2
  exit 1
}

: >"$command_log"
set +e
FAKE_PUBLIC_HEALTH_FAIL=1 run_deploy 0 >"${test_root}/public-failure.log" 2>&1
status=$?
set -e
[[ "$status" == "20" ]] || { printf 'expected coordinated rollback status 20 after public failure, got %s\n' "$status" >&2; exit 1; }
cloud_rollback_line="$(rg -n -- '--to-revisions old-revision=100' "$command_log" | cut -d: -f1 | head -n1)"
vm_rollback_line="$(rg -n -- '--rollback '\''0123456789abcdef0123456789abcdef01234567-123-1'\''' "$command_log" | cut -d: -f1 | head -n1)"
[[ -n "$cloud_rollback_line" && -n "$vm_rollback_line" && "$cloud_rollback_line" -lt "$vm_rollback_line" ]] || { printf '%s\n' 'post-cutover rollback ordering contract failed' >&2; exit 1; }

: >"$command_log"
set +e
FAKE_PUBLIC_HEALTH_FAIL=1 FAKE_CLOUD_ROLLBACK_STATUS=1 run_deploy 0 >"${test_root}/cloud-rollback-failure.log" 2>&1
status=$?
set -e
[[ "$status" == "21" ]] || { printf 'expected intervention status 21 after Cloud Run rollback failure, got %s\n' "$status" >&2; exit 1; }
rg -q -- '--rollback '\''0123456789abcdef0123456789abcdef01234567-123-1'\''' "$command_log" || { printf '%s\n' 'VM rollback was skipped after Cloud Run rollback failure' >&2; exit 1; }
printf '%s\n' 'delivery isolation tests passed'
