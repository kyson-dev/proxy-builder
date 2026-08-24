#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

testing="${PROXY_BUILDER_TESTING:-0}"
if [[ "$testing" == "1" ]]; then
  root_dir="${PROXY_BUILDER_ROOT:?PROXY_BUILDER_ROOT is required in test mode}"
else
  root_dir="/opt/proxy-builder"
  if [[ "$(id -u)" -ne 0 ]]; then
    printf '%s\n' 'deploy-release must run as root' >&2
    exit 10
  fi
fi
[[ -d "$root_dir" ]] || { printf '%s\n' 'proxy root is not initialized' >&2; exit 10; }
root_dir="$(cd "$root_dir" && pwd -P)"

bundle_dir=""
inputs_dir=""
rollback=0
expected_current=""
while (($#)); do
  case "$1" in
    --bundle) bundle_dir="${2:-}"; shift 2 ;;
    --inputs) inputs_dir="${2:-}"; shift 2 ;;
    --rollback) rollback=1; shift ;;
    --expected-current) expected_current="${2:-}"; shift 2 ;;
    *) printf '%s\n' 'usage: deploy-release --bundle <directory> --inputs <directory> | --rollback --expected-current <release-id>' >&2; exit 10 ;;
  esac
done
if [[ "$rollback" == "1" ]]; then
  [[ -z "$bundle_dir" && -z "$inputs_dir" && "$expected_current" =~ ^[0-9a-f]{40}-[1-9][0-9]*-[1-9][0-9]*$ ]] || {
    printf '%s\n' 'rollback requires only --expected-current <release-id>' >&2
    exit 10
  }
else
  [[ -n "$bundle_dir" && -n "$inputs_dir" && -z "$expected_current" ]] || {
    printf '%s\n' 'deployment requires --bundle and --inputs' >&2
    exit 10
  }
fi

log() { printf 'proxy release: %s\n' "$1"; }
fail() { printf 'proxy release rejected at %s\n' "$1" >&2; return 1; }

metadata_url="http://metadata.google.internal/computeMetadata/v1/instance/attributes/proxy-bootstrap-sha256"
marker_file="/var/lib/proxy-builder/bootstrap.sha256"
if [[ "$testing" == "1" ]]; then
  marker_file="${root_dir}/bootstrap.sha256"
fi

release_id=""
stage_dir=""
temporary_release=""
final_release=""
old_target=""
failure_stage="preflight"

# shellcheck disable=SC2317,SC2329 # Invoked through EXIT trap; rule ID differs by ShellCheck version.
cleanup_stage() {
  if [[ -n "$stage_dir" && -d "$stage_dir" && "$stage_dir" == "${root_dir}/staging/"* ]]; then
    rm -rf -- "$stage_dir"
  fi
}
trap cleanup_stage EXIT

acquire_lock() {
  mkdir -p "${root_dir}" || { fail "lock_directory"; return 1; }
  exec 9>"${root_dir}/deploy.lock" || { fail "lock_file"; return 1; }
  flock -n 9 || fail "concurrent_deployment"
}

identify_stage_directory() {
  local bundle_real inputs_real candidate
  [[ -d "$bundle_dir" && -d "$inputs_dir" ]] || return 1
  bundle_real="$(cd "$bundle_dir" && pwd -P)" || return 1
  inputs_real="$(cd "$inputs_dir" && pwd -P)" || return 1
  candidate="$(dirname "$bundle_real")"
  [[ "$bundle_real" == "${candidate}/bundle" ]] || return 1
  [[ "$inputs_real" == "${candidate}/inputs" ]] || return 1
  [[ "$(dirname "$candidate")" == "${root_dir}/staging" ]] || return 1
  stage_dir="$candidate"
}

validate_bundle_allowlist() {
  local expected actual
  expected=$'./bin\n./bin/deploy-release\n./bin/proxyctl\n./docker-compose.yml\n./release.json\n./sing-box.template.json'
  actual="$(cd "$bundle_dir" && find . -mindepth 1 -print | LC_ALL=C sort)"
  [[ "$actual" == "$expected" ]] || { fail "bundle_allowlist"; return 1; }
  [[ -x "${bundle_dir}/bin/proxyctl" && -x "${bundle_dir}/bin/deploy-release" ]] || { fail "bundle_executable"; return 1; }
  if find "$bundle_dir" -type l -print -quit | grep -q .; then
    fail "bundle_symlink"
  fi
}

validate_private_directory() {
  local path="$1" mode owner
  [[ -d "$path" && ! -L "$path" ]] || return 1
  mode="$(stat -c '%a' "$path")"
  [[ "$mode" == "700" ]] || return 1
  if [[ "$testing" != "1" ]]; then
    owner="$(stat -c '%u' "$path")"
    [[ "$owner" == "0" ]] || return 1
  fi
}

validate_inputs_allowlist() {
  local expected actual
  expected=$'obfs-password\nproxy-users.json\nreality-private-key'
  if [[ -e "${inputs_dir}/hysteria2.crt" || -e "${inputs_dir}/hysteria2.key" ]]; then
    expected=$'hysteria2.crt\nhysteria2.key\nobfs-password\nproxy-users.json\nreality-private-key'
  fi
  actual="$(cd "$inputs_dir" && find . -mindepth 1 -maxdepth 1 -print | sed 's|^\./||' | LC_ALL=C sort)"
  [[ "$actual" == "$expected" ]] || { fail "inputs_allowlist"; return 1; }
}

validate_secret_file() {
  local path="$1"
  [[ -f "$path" && ! -L "$path" ]] || return 1
  local mode owner
  mode="$(stat -c '%a' "$path")"
  [[ "$mode" == "600" ]] || return 1
  if [[ "$testing" != "1" ]]; then
    owner="$(stat -c '%u' "$path")"
    [[ "$owner" == "0" ]] || return 1
  fi
}

host_bootstrap_ready() {
  local expected actual
  if [[ "$testing" == "1" ]]; then
    expected="${PROXY_BOOTSTRAP_EXPECTED_SHA:?PROXY_BOOTSTRAP_EXPECTED_SHA is required in test mode}"
  else
    expected="$(curl -fsS -H 'Metadata-Flavor: Google' "$metadata_url")" || return 1
  fi
  [[ "$expected" =~ ^[0-9a-f]{64}$ && -f "$marker_file" ]] || return 1
  actual="$(tr -d '\r\n' <"$marker_file")"
  [[ "$actual" == "$expected" ]]
}

preflight() {
  command -v docker >/dev/null 2>&1 || { fail "docker_missing"; return 1; }
  command -v jq >/dev/null 2>&1 || { fail "jq_missing"; return 1; }
  command -v flock >/dev/null 2>&1 || { fail "flock_missing"; return 1; }
  command -v ss >/dev/null 2>&1 || { fail "ss_missing"; return 1; }
  host_bootstrap_ready || { fail "host_bootstrap_outdated"; return 1; }
  [[ -d "$bundle_dir" && -d "$inputs_dir" ]] || { fail "staging_missing"; return 1; }
  validate_bundle_allowlist || return 1
  "${bundle_dir}/bin/proxyctl" validate-release --input "${bundle_dir}/release.json" || { fail "release_manifest"; return 1; }

  release_id="$(jq -er '.release_id' "${bundle_dir}/release.json")" || { fail "release_manifest"; return 1; }
  [[ "$stage_dir" == "${root_dir}/staging/${release_id}" ]] || { fail "staging_path"; return 1; }
  validate_private_directory "$stage_dir" || { fail "staging_directory_permissions"; return 1; }
  validate_private_directory "$inputs_dir" || { fail "inputs_directory_permissions"; return 1; }
  validate_inputs_allowlist || return 1
  final_release="${root_dir}/releases/${release_id}"
  temporary_release="${stage_dir}/release"
  [[ ! -e "$final_release" ]] || { fail "release_exists"; return 1; }

  for name in reality-private-key obfs-password proxy-users.json; do
    validate_secret_file "${inputs_dir}/${name}" || { fail "secret_file_permissions"; return 1; }
  done
  local cert_exists=0 key_exists=0
  [[ -e "${inputs_dir}/hysteria2.crt" ]] && cert_exists=1
  [[ -e "${inputs_dir}/hysteria2.key" ]] && key_exists=1
  [[ "$cert_exists" == "$key_exists" ]] || { fail "certificate_pair_incomplete"; return 1; }
  if [[ "$cert_exists" == "1" ]]; then
    validate_secret_file "${inputs_dir}/hysteria2.crt" || { fail "secret_file_permissions"; return 1; }
    validate_secret_file "${inputs_dir}/hysteria2.key" || { fail "secret_file_permissions"; return 1; }
  elif [[ ! -f "${root_dir}/current/cert/hysteria2.crt" || ! -f "${root_dir}/current/cert/hysteria2.key" ]]; then
    fail "certificate_required"; return 1
  fi
}

prepare_release() {
  failure_stage="prepare"
  mkdir -p "$temporary_release" "${temporary_release}/bin" || { fail "release_directory"; return 1; }
  chmod 0700 "$temporary_release" "${temporary_release}/bin" || { fail "release_permissions"; return 1; }
  cp "${bundle_dir}/release.json" "${temporary_release}/release.json" || { fail "release_manifest_copy"; return 1; }
  cp "${bundle_dir}/docker-compose.yml" "${temporary_release}/docker-compose.yml" || { fail "compose_copy"; return 1; }
  cp "${bundle_dir}/bin/deploy-release" "${temporary_release}/bin/deploy-release" || { fail "release_tool_copy"; return 1; }
  cp "${bundle_dir}/bin/proxyctl" "${temporary_release}/bin/proxyctl" || { fail "release_tool_copy"; return 1; }
  chmod 0600 "${temporary_release}/release.json" "${temporary_release}/docker-compose.yml" || { fail "release_file_permissions"; return 1; }
  chmod 0755 "${temporary_release}/bin/deploy-release" "${temporary_release}/bin/proxyctl" || { fail "release_tool_permissions"; return 1; }

  local sni cert_dir image
  sni="$(jq -er '.hy2_sni' "${bundle_dir}/release.json")" || { fail "release_manifest"; return 1; }
  cert_dir="${temporary_release}/cert"
  mkdir -p "$cert_dir" || { fail "certificate_directory"; return 1; }
  chmod 0700 "$cert_dir" || { fail "certificate_directory_permissions"; return 1; }
  if [[ -f "${inputs_dir}/hysteria2.crt" ]]; then
    cp "${inputs_dir}/hysteria2.crt" "${cert_dir}/hysteria2.crt" || { fail "certificate_copy"; return 1; }
    cp "${inputs_dir}/hysteria2.key" "${cert_dir}/hysteria2.key" || { fail "certificate_key_copy"; return 1; }
  else
    cp "${root_dir}/current/cert/hysteria2.crt" "${cert_dir}/hysteria2.crt" || { fail "certificate_copy"; return 1; }
    cp "${root_dir}/current/cert/hysteria2.key" "${cert_dir}/hysteria2.key" || { fail "certificate_key_copy"; return 1; }
  fi
  chmod 0600 "${cert_dir}/hysteria2.crt" "${cert_dir}/hysteria2.key" || { fail "certificate_permissions"; return 1; }
  "${bundle_dir}/bin/proxyctl" inspect-certificate \
    --cert "${cert_dir}/hysteria2.crt" --key "${cert_dir}/hysteria2.key" \
    --sni "$sni" --output "${stage_dir}/certificate.json" || { fail "certificate_validation"; return 1; }
  "${bundle_dir}/bin/proxyctl" render-sing-box \
    --template "${bundle_dir}/sing-box.template.json" \
    --users "${inputs_dir}/proxy-users.json" \
    --private-key-file "${inputs_dir}/reality-private-key" \
    --obfs-password-file "${inputs_dir}/obfs-password" \
    --release "${bundle_dir}/release.json" \
    --output "${temporary_release}/config.json" || { fail "config_render"; return 1; }
  chmod 0600 "${temporary_release}/config.json"

  image="$(jq -er '.sing_box_image' "${bundle_dir}/release.json")" || { fail "release_manifest"; return 1; }
  docker pull "$image" >/dev/null || { fail "image_pull"; return 1; }
  docker run --rm \
    -v "${temporary_release}/config.json:/etc/sing-box/config.json:ro" \
    -v "${cert_dir}:/etc/sing-box/cert:ro" \
    "$image" check -c /etc/sing-box/config.json >/dev/null 2>&1 || { fail "sing_box_check"; return 1; }
}

atomic_link() {
  local target="$1" name="$2" temporary
  temporary="${root_dir}/.${name}.${release_id}"
  rm -f -- "$temporary" || return 1
  ln -s "$target" "$temporary" || return 1
  mv -Tf "$temporary" "${root_dir}/${name}"
}

compose_up() {
  local release_path="$1" image
  image="$(jq -er '.sing_box_image' "${release_path}/release.json")" || return 1
  PROXY_ROOT="$root_dir" SING_BOX_IMAGE="$image" \
    docker compose --project-name proxy-builder --file "${release_path}/docker-compose.yml" \
    up -d --remove-orphans --force-recreate >/dev/null 2>&1
}

healthy() {
  local _
  for _ in {1..30}; do
    if [[ "$(docker inspect --format '{{.State.Running}}' proxy-builder-sing-box 2>/dev/null || true)" == "true" ]] &&
      [[ -n "$(ss -ltnH 'sport = :443' 2>/dev/null)" ]] &&
      [[ -n "$(ss -lunH 'sport = :443' 2>/dev/null)" ]]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

activate_release() {
  failure_stage="activate"
  if [[ -L "${root_dir}/current" ]]; then
    old_target="$(readlink "${root_dir}/current")" || { fail "current_readlink"; return 1; }
    [[ -d "${root_dir}/${old_target}" ]] || { fail "current_target_missing"; return 1; }
  elif [[ -e "${root_dir}/current" ]]; then
    fail "current_not_symlink"; return 1
  fi

  mv "$temporary_release" "$final_release" || { fail "release_commit"; return 1; }
  atomic_link "releases/${release_id}" current || { fail "current_switch"; return 1; }
  compose_up "$final_release" || return 1
  healthy
}

restore_previous() {
  failure_stage="rollback"
  if [[ -n "$old_target" ]]; then
    atomic_link "$old_target" current || return 1
    compose_up "${root_dir}/${old_target}" || return 1
    healthy
  else
    rm -f -- "${root_dir}/current" || return 1
    local image
    image="$(jq -er '.sing_box_image' "${final_release}/release.json")" || return 1
    PROXY_ROOT="$root_dir" SING_BOX_IMAGE="$image" \
      docker compose --project-name proxy-builder --file "${final_release}/docker-compose.yml" down >/dev/null 2>&1 || true
    return 1
  fi
}

rollback_committed_release() {
  local current_target previous_target candidate_dir failed_dir
  acquire_lock || return 10
  [[ -L "${root_dir}/current" && -L "${root_dir}/previous" ]] || { fail "rollback_release_missing"; return 21; }
  current_target="$(readlink "${root_dir}/current")" || return 21
  previous_target="$(readlink "${root_dir}/previous")" || return 21
  [[ "$current_target" == "releases/${expected_current}" ]] || { fail "rollback_current_mismatch"; return 10; }
  [[ "$previous_target" == releases/* && -d "${root_dir}/${previous_target}" ]] || { fail "rollback_previous_missing"; return 21; }
  [[ -f "${root_dir}/${previous_target}/release.json" && -f "${root_dir}/${previous_target}/cert/hysteria2.crt" && -f "${root_dir}/${previous_target}/cert/hysteria2.key" ]] || { fail "rollback_previous_incomplete"; return 21; }
  candidate_dir="${root_dir}/${current_target}"
  atomic_link "$previous_target" current || return 21
  if ! compose_up "${root_dir}/${previous_target}" || ! healthy; then
    atomic_link "$current_target" current || true
    compose_up "$candidate_dir" || true
    return 21
  fi
  failed_dir="${root_dir}/failed/${expected_current}"
  find "${root_dir}/failed" -mindepth 1 -maxdepth 1 -type d -exec rm -rf -- {} +
  mkdir -p "$failed_dir"
  chmod 0700 "$failed_dir"
  cp "${candidate_dir}/release.json" "${failed_dir}/release.json"
  jq -n --arg failed_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" '{stage:"post_activation",code:20,failed_at:$failed_at}' >"${failed_dir}/failure.json"
  chmod 0600 "${failed_dir}/release.json" "${failed_dir}/failure.json"
  rm -f -- "${root_dir}/previous"
  rm -rf -- "$candidate_dir"
  log "committed release ${expected_current} rolled back"
  return 0
}

record_failure() {
  local code="$1" failed_dir="${root_dir}/failed/${release_id}"
  find "${root_dir}/failed" -mindepth 1 -maxdepth 1 -type d -exec rm -rf -- {} +
  mkdir -p "$failed_dir"
  chmod 0700 "$failed_dir"
  cp "${bundle_dir}/release.json" "${failed_dir}/release.json"
  jq -n --arg stage "$failure_stage" --argjson code "$code" \
    --arg failed_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    '{stage: $stage, code: $code, failed_at: $failed_at}' >"${failed_dir}/failure.json"
  chmod 0600 "${failed_dir}/release.json" "${failed_dir}/failure.json"
  rm -rf -- "$final_release"
}

cleanup_releases() {
  local current_id previous_id=""
  current_id="${release_id}"
  if [[ -n "$old_target" ]]; then
    previous_id="${old_target#releases/}"
    atomic_link "$old_target" previous
  else
    rm -f -- "${root_dir}/previous"
  fi
  local directory name
  for directory in "${root_dir}/releases"/*; do
    [[ -d "$directory" ]] || continue
    name="$(basename "$directory")"
    if [[ "$name" != "$current_id" && "$name" != "$previous_id" ]]; then
      rm -rf -- "$directory"
    fi
  done
  find "${root_dir}/failed" -mindepth 1 -maxdepth 1 -type d -exec rm -rf -- {} +
}

main() {
  acquire_lock || exit 10
  identify_stage_directory || true
  if ! preflight; then
    exit 10
  fi
  if ! prepare_release; then
    record_failure 10
    exit 10
  fi
  if activate_release; then
    cleanup_releases
    log "release ${release_id} is healthy"
    exit 0
  fi
  if restore_previous; then
    record_failure 20
    log "activation failed; previous release is healthy"
    exit 20
  fi
  record_failure 21
  log "activation and rollback both failed"
  exit 21
}

if [[ "$rollback" == "1" ]]; then
  set +e
  rollback_committed_release
  rollback_status=$?
  set -e
  exit "$rollback_status"
fi
main
