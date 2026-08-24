#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

required_commands=(curl gcloud go jq tar)
for command_name in "${required_commands[@]}"; do
  command -v "$command_name" >/dev/null 2>&1 || { printf 'required command is unavailable: %s\n' "$command_name" >&2; exit 1; }
done

required_names=(ENVIRONMENT GIT_SHA RUN_ID RUN_ATTEMPT IMAGE_DIGEST GCP_PROJECT_ID GCP_REGION GCP_VM_NAME GCP_VM_ZONE SUBSCRIPTION_SERVICE_NAME PROXY_IP PROXY_USERS_SECRET_ID OBFS_PASSWORD_SECRET_ID REALITY_PRIVATE_KEY OBFS_PASSWORD HY2_CERT_PEM HY2_KEY_PEM PROXY_USERS_JSON)
for name in "${required_names[@]}"; do
  [[ -n "${!name:-}" ]] || { printf 'required environment variable is missing: %s\n' "$name" >&2; exit 1; }
done
case "$ENVIRONMENT" in development|production) ;; *) printf '%s\n' 'invalid environment' >&2; exit 2 ;; esac
[[ "$GIT_SHA" =~ ^[0-9a-f]{40}$ ]] || { printf '%s\n' 'invalid git SHA' >&2; exit 2; }
[[ "$IMAGE_DIGEST" =~ @sha256:[0-9a-f]{64}$ ]] || { printf '%s\n' 'image must be immutable by digest' >&2; exit 2; }

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/proxy-builder-delivery.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
inputs_dir="${work_dir}/inputs"
mkdir -m 0700 "$inputs_dir"
printf '%s' "$REALITY_PRIVATE_KEY" >"${inputs_dir}/reality-private-key"
printf '%s' "$OBFS_PASSWORD" >"${inputs_dir}/obfs-password"
printf '%s' "$HY2_CERT_PEM" >"${inputs_dir}/hysteria2.crt"
printf '%s' "$HY2_KEY_PEM" >"${inputs_dir}/hysteria2.key"
printf '%s' "$PROXY_USERS_JSON" >"${inputs_dir}/proxy-users.json"
chmod 0600 "${inputs_dir}"/*

hy2_sni="$(jq -er '.hy2_sni' "${repo_root}/config/environments/${ENVIRONMENT}.json")"
egress_probe_url="$(jq -er '.egress_probe_url' "${repo_root}/config/environments/${ENVIRONMENT}.json")"
sing_box_image="$(jq -er '.sing_box_image' "${repo_root}/config/environments/${ENVIRONMENT}.json")"
"${repo_root}/scripts/release/build-vm-bundle.sh" \
  --environment "$ENVIRONMENT" --git-sha "$GIT_SHA" --run-id "$RUN_ID" --run-attempt "$RUN_ATTEMPT" \
  --created-at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --output "${work_dir}/bundle.tar.gz"
(cd "$repo_root" && go build -trimpath -o "${work_dir}/proxyctl" ./cmd/proxyctl)
"${work_dir}/proxyctl" inspect-environment \
  --users "${inputs_dir}/proxy-users.json" --private-key-file "${inputs_dir}/reality-private-key" \
  --obfs-password-file "${inputs_dir}/obfs-password" --cert "${inputs_dir}/hysteria2.crt" \
  --key "${inputs_dir}/hysteria2.key" --sni "$hy2_sni" --output "${work_dir}/public.json"

release_id="${GIT_SHA}-${RUN_ID}-${RUN_ATTEMPT}"
gcloud compute scp --tunnel-through-iap --quiet --project "$GCP_PROJECT_ID" --zone "$GCP_VM_ZONE" \
  "${script_dir}/deploy-remote.sh" "${GCP_VM_NAME}:~/"
remote_cert_sha256="$(gcloud compute ssh --tunnel-through-iap --quiet --project "$GCP_PROJECT_ID" --zone "$GCP_VM_ZONE" "$GCP_VM_NAME" \
  --command "sudo bash ~/deploy-remote.sh --inspect-certificate '${hy2_sni}'" 2>/dev/null || true)"
local_cert_sha256="$(jq -er '.hy2_cert_sha256' "${work_dir}/public.json")"
scp_sources=(
  "${work_dir}/bundle.tar.gz"
  "${inputs_dir}/reality-private-key"
  "${inputs_dir}/obfs-password"
  "${inputs_dir}/proxy-users.json"
  "${script_dir}/deploy-remote.sh"
)
if [[ "$remote_cert_sha256" != "$local_cert_sha256" ]]; then
  scp_sources+=("${inputs_dir}/hysteria2.crt" "${inputs_dir}/hysteria2.key")
fi
gcloud compute scp --tunnel-through-iap --quiet --project "$GCP_PROJECT_ID" --zone "$GCP_VM_ZONE" \
  "${scp_sources[@]}" "${GCP_VM_NAME}:~/"

set +e
gcloud compute ssh --tunnel-through-iap --quiet --project "$GCP_PROJECT_ID" --zone "$GCP_VM_ZONE" "$GCP_VM_NAME" --command \
  "sudo bash ~/deploy-remote.sh '${release_id}'"
vm_status=$?
set -e
case "$vm_status" in
  0) ;;
  20) printf '%s\n' 'VM candidate failed; previous healthy release was restored' >&2; exit 20 ;;
  21) printf '%s\n' 'VM candidate and rollback failed; environment intervention is required' >&2; exit 21 ;;
  *) printf 'VM deployment failed before activation (exit %d)\n' "$vm_status" >&2; exit "$vm_status" ;;
esac

rollback_vm() {
  gcloud compute scp --tunnel-through-iap --quiet --project "$GCP_PROJECT_ID" --zone "$GCP_VM_ZONE" \
    "${script_dir}/deploy-remote.sh" "${GCP_VM_NAME}:~/" || return 21
  gcloud compute ssh --tunnel-through-iap --quiet --project "$GCP_PROJECT_ID" --zone "$GCP_VM_ZONE" "$GCP_VM_NAME" --command \
    "sudo bash ~/deploy-remote.sh --rollback '${release_id}'" || return 21
}

fetch_and_validate_subscription() {
  local service_url="$1" suffix="$2" format
  for format in base64 clash; do
    printf 'url = "%s/v1/subscription?token=%s&format=%s"\nsilent\nshow-error\nfail\n' "$service_url" "$token_encoded" "$format" | \
      curl --config - --output "${work_dir}/${format}.${suffix}.response" || return 1
    "${work_dir}/proxyctl" validate-subscription --input "${work_dir}/${format}.${suffix}.response" --format "$format" || return 1
  done
}

deploy_cloud_run() {
  local users_version obfs_version reality_public_key reality_short_id reality_dest
  local old_revision candidate_revision service_url revision_ready
  users_version="$(gcloud secrets versions add "$PROXY_USERS_SECRET_ID" --project "$GCP_PROJECT_ID" --data-file="${inputs_dir}/proxy-users.json" --format='value(name)')" || return 1
  obfs_version="$(gcloud secrets versions add "$OBFS_PASSWORD_SECRET_ID" --project "$GCP_PROJECT_ID" --data-file="${inputs_dir}/obfs-password" --format='value(name)')" || return 1
  users_version="${users_version##*/}"
  obfs_version="${obfs_version##*/}"
  reality_public_key="$(jq -er '.reality_public_key' "${work_dir}/public.json")" || return 1
  reality_short_id="$(jq -er '.reality_short_id' "${work_dir}/public.json")" || return 1
  reality_dest="$(jq -er '.reality_dest' "${repo_root}/config/environments/${ENVIRONMENT}.json")" || return 1
  old_revision="$(
    gcloud run services describe "$SUBSCRIPTION_SERVICE_NAME" --project "$GCP_PROJECT_ID" --region "$GCP_REGION" --format=json |
      jq -er '[.status.traffic[] | select(.percent == 100 and (.revisionName | length > 0)) | .revisionName][0]'
  )" || return 1
  [[ -n "$old_revision" ]] || return 1

  gcloud run deploy "$SUBSCRIPTION_SERVICE_NAME" --quiet --project "$GCP_PROJECT_ID" --region "$GCP_REGION" \
    --image "$IMAGE_DIGEST" --no-traffic \
    --set-env-vars "PROXY_IP=${PROXY_IP},REALITY_PUBLIC_KEY=${reality_public_key},REALITY_SHORT_ID=${reality_short_id},REALITY_DEST=${reality_dest},HY2_SNI=${hy2_sni},HY2_CERT_SHA256=${local_cert_sha256}" \
    --set-secrets "PROXY_USERS_JSON=${PROXY_USERS_SECRET_ID}:${users_version},OBFS_PASSWORD=${OBFS_PASSWORD_SECRET_ID}:${obfs_version}" || return 1
  candidate_revision="$(gcloud run services describe "$SUBSCRIPTION_SERVICE_NAME" --project "$GCP_PROJECT_ID" --region "$GCP_REGION" --format='value(status.latestCreatedRevisionName)')" || return 1
  [[ -n "$candidate_revision" && "$candidate_revision" != "$old_revision" ]] || return 1
  revision_ready=false
  for _ in {1..20}; do
    if gcloud run revisions describe "$candidate_revision" --project "$GCP_PROJECT_ID" --region "$GCP_REGION" --format=json |
      jq -e 'any(.status.conditions[]?; .type == "Ready" and .status == "True")' >/dev/null; then
      revision_ready=true
      break
    fi
    sleep 3
  done
  [[ "$revision_ready" == true ]] || return 1

  # From this point onward a failed command may have changed public traffic. Every
  # failure path must restore the previously serving revision before VM rollback.
  if ! gcloud run services update-traffic "$SUBSCRIPTION_SERVICE_NAME" --quiet --project "$GCP_PROJECT_ID" --region "$GCP_REGION" --to-revisions "${candidate_revision}=100"; then
    gcloud run services update-traffic "$SUBSCRIPTION_SERVICE_NAME" --quiet --project "$GCP_PROJECT_ID" --region "$GCP_REGION" --to-revisions "${old_revision}=100" || return 21
    return 1
  fi
  if ! service_url="$(gcloud run services describe "$SUBSCRIPTION_SERVICE_NAME" --project "$GCP_PROJECT_ID" --region "$GCP_REGION" --format='value(status.url)')"; then
    gcloud run services update-traffic "$SUBSCRIPTION_SERVICE_NAME" --quiet --project "$GCP_PROJECT_ID" --region "$GCP_REGION" --to-revisions "${old_revision}=100" || return 21
    return 1
  fi
  if [[ -z "$service_url" ]] || ! curl -fsS "${service_url}/healthz" >/dev/null || ! fetch_and_validate_subscription "$service_url" public; then
    gcloud run services update-traffic "$SUBSCRIPTION_SERVICE_NAME" --quiet --project "$GCP_PROJECT_ID" --region "$GCP_REGION" --to-revisions "${old_revision}=100" || return 21
    return 1
  fi
  if ! "${script_dir}/e2e-proxy.sh" --subscription "${work_dir}/base64.public.response" \
    --image "$sing_box_image" --probe-url "$egress_probe_url" --proxyctl "${work_dir}/proxyctl"; then
    gcloud run services update-traffic "$SUBSCRIPTION_SERVICE_NAME" --quiet --project "$GCP_PROJECT_ID" --region "$GCP_REGION" --to-revisions "${old_revision}=100" || return 21
    return 1
  fi
}

token="$(jq -er '.users[] | select(.enabled) | .subscription_token' "${inputs_dir}/proxy-users.json" | head -n1)"
token_encoded="$(jq -nr --arg value "$token" '$value | @uri')"
set +e
deploy_cloud_run
cloud_status=$?
set -e
if [[ "$cloud_status" -ne 0 ]]; then
  printf '%s\n' 'Cloud Run deployment or end-to-end validation failed; rolling back VM' >&2
  if rollback_vm && [[ "$cloud_status" -ne 21 ]]; then
    exit 20
  fi
  printf '%s\n' 'Cloud Run or VM rollback did not recover the environment' >&2
  exit 21
fi
printf 'deployment succeeded: %s %s\n' "$ENVIRONMENT" "$GIT_SHA"
