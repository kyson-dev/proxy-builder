#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/proxy-builder-host-test.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

root_dir="${test_dir}/root"
fake_bin="${test_dir}/bin"
mkdir -p "$fake_bin" "${root_dir}/releases" "${root_dir}/secrets" "${root_dir}/staging" "${root_dir}/failed"
chmod 0700 "$root_dir" "${root_dir}/releases" "${root_dir}/secrets" "${root_dir}/staging" "${root_dir}/failed"

cat >"${fake_bin}/flock" <<'EOF'
#!/usr/bin/env bash
[[ ! -f "${PROXY_BUILDER_ROOT}/lock-busy" ]]
EOF
cat >"${fake_bin}/ss" <<'EOF'
#!/usr/bin/env bash
[[ -f "${PROXY_BUILDER_ROOT}/mock-running" ]] && printf 'LISTEN 0 4096 *:443 *:*\n'
EOF
cat >"${fake_bin}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  pull|run) exit 0 ;;
  inspect)
    [[ -f "${PROXY_BUILDER_ROOT}/mock-running" ]] && printf 'true\n' || printf 'false\n'
    ;;
  compose)
    for argument in "$@"; do
      if [[ "$argument" == "up" ]]; then
        if [[ -f "${PROXY_BUILDER_ROOT}/fail-next-up" ]]; then
          rm -f "${PROXY_BUILDER_ROOT}/fail-next-up"
          exit 1
        fi
        touch "${PROXY_BUILDER_ROOT}/mock-running"
        exit 0
      fi
      if [[ "$argument" == "down" ]]; then
        rm -f "${PROXY_BUILDER_ROOT}/mock-running"
        exit 0
      fi
    done
    ;;
esac
exit 0
EOF
cat >"${fake_bin}/stat" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-c" && "${2:-}" == "%a" ]]; then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    /usr/bin/stat -f '%Lp' "$3"
  else
    /usr/bin/stat -c '%a' "$3"
  fi
else
  /usr/bin/stat "$@"
fi
EOF
cat >"${fake_bin}/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
root_real="$(cd "${PROXY_BUILDER_ROOT}" && pwd -P)"
if [[ "${1:-}" == *'/secrets-candidate' && "${2:-}" == "${root_real}/secrets" && -f "${root_real}/fail-certificate-commit" ]]; then
  rm -f "${PROXY_BUILDER_ROOT}/fail-certificate-commit"
  exit 1
fi
if [[ "${1:-}" == "-Tf" ]]; then
  /bin/mv -f "$2" "$3"
else
  /bin/mv "$@"
fi
EOF
chmod 0755 "${fake_bin}"/*

bootstrap_sha="$(printf 'host-bootstrap-v1' | shasum -a 256 | awk '{print $1}')"
printf '%s\n' "$bootstrap_sha" >"${root_dir}/bootstrap.sha256"
chmod 0600 "${root_dir}/bootstrap.sha256"

host_proxyctl="${test_dir}/proxyctl"
(
  cd "$repo_root"
  go build -trimpath -o "$host_proxyctl" ./cmd/proxyctl
)

make_stage() {
  local git_sha="$1" run_id="$2" run_attempt="$3" cert_suffix="$4"
  local release_id="${git_sha}-${run_id}-${run_attempt}"
  local stage="${root_dir}/staging/${release_id}"
  mkdir -p "${stage}/bundle/bin" "${stage}/inputs"
  chmod 0700 "$stage" "${stage}/inputs"
  jq -n \
    --arg release_id "$release_id" --arg git_sha "$git_sha" \
    --arg deployment_id "${run_id}-${run_attempt}" \
    --arg image "ghcr.io/sagernet/sing-box@sha256:$(printf 'b%.0s' {1..64})" \
    '{schema_version:1,release_id:$release_id,environment:"development",git_sha:$git_sha,deployment_id:$deployment_id,sing_box_image:$image,reality_dest:"www.example.com:443",hy2_sni:"www.bing.com",created_at:"2026-08-23T12:00:00Z"}' \
    >"${stage}/bundle/release.json"
  cp "${repo_root}/docker-compose.yml" "${stage}/bundle/docker-compose.yml"
  cp "${repo_root}/config/sing-box.template.json" "${stage}/bundle/sing-box.template.json"
  cp "$host_proxyctl" "${stage}/bundle/bin/proxyctl"
  cp "${repo_root}/scripts/host/deploy-release.sh" "${stage}/bundle/bin/deploy-release"
  chmod 0755 "${stage}/bundle/bin/proxyctl" "${stage}/bundle/bin/deploy-release"

  printf '%s\n' 'dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo' >"${stage}/inputs/reality-private-key"
  printf '%s\n' 'obfs-password-canary-12345678' >"${stage}/inputs/obfs-password"
  printf '%s\n' '{"version":1,"users":[{"name":"alice","enabled":true,"vless_uuid":"00000000-0000-4000-8000-000000000001","hy2_password":"hy2-password-canary-123456789","subscription_token":"subscription-token-canary-123456"}]}' >"${stage}/inputs/proxy-users.json"
  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "${stage}/inputs/hysteria2.key" -out "${stage}/inputs/hysteria2.crt" \
    -subj "/CN=ignored-${cert_suffix}" -addext 'subjectAltName=DNS:www.bing.com' -days 30 >/dev/null 2>&1
  chmod 0600 "${stage}/inputs"/*
  printf '%s\n' "$stage"
}

run_deploy() {
  local stage="$1" expected_sha="$2"
  PROXY_BUILDER_TESTING=1 PROXY_BUILDER_ROOT="$root_dir" PROXY_BOOTSTRAP_EXPECTED_SHA="$expected_sha" \
    PATH="${fake_bin}:${PATH}" \
    "${stage}/bundle/bin/deploy-release" --bundle "${stage}/bundle" --inputs "${stage}/inputs"
}

first_sha="$(printf 'a%.0s' {1..40})"
first_stage="$(make_stage "$first_sha" 100 1 first)"
run_deploy "$first_stage" "$bootstrap_sha"
first_target="$(readlink "${root_dir}/current")"
[[ "$first_target" == "releases/${first_sha}-100-1" ]]
[[ ! -d "$first_stage" ]]
first_cert_hash="$(shasum -a 256 "${root_dir}/secrets/hysteria2.crt" | awk '{print $1}')"

concurrent_sha="$(printf 'b%.0s' {1..40})"
concurrent_stage="$(make_stage "$concurrent_sha" 104 1 concurrent)"
touch "${root_dir}/lock-busy"
set +e
run_deploy "$concurrent_stage" "$bootstrap_sha" >/dev/null 2>&1
concurrent_status=$?
set -e
rm -f "${root_dir}/lock-busy"
[[ "$concurrent_status" -eq 10 ]]
[[ "$(readlink "${root_dir}/current")" == "$first_target" ]]
rm -rf -- "$concurrent_stage"

outdated_sha="$(printf 'c%.0s' {1..40})"
outdated_stage="$(make_stage "$outdated_sha" 101 1 outdated)"
set +e
run_deploy "$outdated_stage" "$(printf 'f%.0s' {1..64})" >/dev/null 2>&1
outdated_status=$?
set -e
[[ "$outdated_status" -eq 10 ]]
[[ "$(readlink "${root_dir}/current")" == "$first_target" ]]
[[ ! -d "$outdated_stage" ]]

second_sha="$(printf 'd%.0s' {1..40})"
second_stage="$(make_stage "$second_sha" 102 1 rotated)"
touch "${root_dir}/fail-next-up"
set +e
run_deploy "$second_stage" "$bootstrap_sha" >/dev/null 2>&1
rollback_status=$?
set -e
[[ "$rollback_status" -eq 20 ]]
[[ "$(readlink "${root_dir}/current")" == "$first_target" ]]
[[ "$(shasum -a 256 "${root_dir}/secrets/hysteria2.crt" | awk '{print $1}')" == "$first_cert_hash" ]]
[[ ! -d "$second_stage" ]]
[[ -f "${root_dir}/failed/${second_sha}-102-1/failure.json" ]]
if rg -n 'canary|PRIVATE KEY|subscription-token|hy2-password|obfs-password' "${root_dir}/failed"; then
  printf '%s\n' 'failed diagnostics contain secret material' >&2
  exit 1
fi

third_sha="$(printf 'e%.0s' {1..40})"
third_stage="$(make_stage "$third_sha" 103 1 commit-failure)"
touch "${root_dir}/fail-certificate-commit"
set +e
run_deploy "$third_stage" "$bootstrap_sha" >/dev/null 2>&1
commit_status=$?
set -e
[[ "$commit_status" -eq 20 ]]
[[ "$(readlink "${root_dir}/current")" == "$first_target" ]]
[[ "$(shasum -a 256 "${root_dir}/secrets/hysteria2.crt" | awk '{print $1}')" == "$first_cert_hash" ]]
[[ ! -d "$third_stage" ]]

rg -q 'flock -n' "${repo_root}/scripts/host/deploy-release.sh"
printf '%s\n' 'VM release guard and rollback tests passed'
