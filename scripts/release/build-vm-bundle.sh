#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

environment=""
git_sha=""
run_id=""
run_attempt=""
created_at=""
output=""

usage() {
  printf '%s\n' 'usage: build-vm-bundle.sh --environment <environment> --git-sha <sha> --run-id <id> --run-attempt <number> --created-at <RFC3339 UTC> --output <archive>' >&2
}

while (($#)); do
  case "$1" in
    --environment) environment="${2:-}"; shift 2 ;;
    --git-sha) git_sha="${2:-}"; shift 2 ;;
    --run-id) run_id="${2:-}"; shift 2 ;;
    --run-attempt) run_attempt="${2:-}"; shift 2 ;;
    --created-at) created_at="${2:-}"; shift 2 ;;
    --output) output="${2:-}"; shift 2 ;;
    *) usage; exit 2 ;;
  esac
done

for command_name in go jq tar; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'required command is unavailable: %s\n' "$command_name" >&2
    exit 1
  }
done

case "$environment" in development|production) ;; *) usage; exit 2 ;; esac
[[ "$git_sha" =~ ^[0-9a-f]{40}$ ]] || { usage; exit 2; }
[[ "$run_id" =~ ^[1-9][0-9]*$ ]] || { usage; exit 2; }
[[ "$run_attempt" =~ ^[1-9][0-9]*$ ]] || { usage; exit 2; }
[[ "$created_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || { usage; exit 2; }
[[ -n "$output" ]] || { usage; exit 2; }

environment_file="${repo_root}/config/environments/${environment}.json"
[[ -f "$environment_file" ]] || { printf 'environment manifest not found\n' >&2; exit 1; }

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/proxy-builder-bundle.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
bundle_dir="${work_dir}/bundle"
mkdir -p "${bundle_dir}/bin"

deployment_id="${run_id}-${run_attempt}"
release_id="${git_sha}-${deployment_id}"
jq -e \
  --arg release_id "$release_id" \
  --arg environment "$environment" \
  --arg git_sha "$git_sha" \
  --arg deployment_id "$deployment_id" \
  --arg created_at "$created_at" \
  '{
    schema_version: 1,
    release_id: $release_id,
    environment: $environment,
    git_sha: $git_sha,
    deployment_id: $deployment_id,
    sing_box_image: .sing_box_image,
    reality_dest: .reality_dest,
    hy2_sni: .hy2_sni,
    created_at: $created_at
  }' "$environment_file" >"${bundle_dir}/release.json"

cp "${repo_root}/docker-compose.yml" "${bundle_dir}/docker-compose.yml"
cp "${repo_root}/config/sing-box.template.json" "${bundle_dir}/sing-box.template.json"
cp "${repo_root}/scripts/host/deploy-release.sh" "${bundle_dir}/bin/deploy-release"
chmod 0755 "${bundle_dir}/bin/deploy-release"

(
  cd "$repo_root"
  CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags='-s -w' -o "${bundle_dir}/bin/proxyctl" ./cmd/proxyctl
  go build -trimpath -o "${work_dir}/proxyctl-host" ./cmd/proxyctl
)
chmod 0755 "${bundle_dir}/bin/proxyctl"
"${work_dir}/proxyctl-host" validate-release --input "${bundle_dir}/release.json"

mkdir -p "$(dirname "$output")"
output_parent="$(cd "$(dirname "$output")" && pwd)"
output_path="${output_parent}/$(basename "$output")"
temporary_archive="${work_dir}/bundle.tar.gz"
tar -czf "$temporary_archive" -C "$bundle_dir" \
  release.json docker-compose.yml sing-box.template.json bin/proxyctl bin/deploy-release
mv -f "$temporary_archive" "$output_path"
printf 'VM release bundle created: %s\n' "$output_path"
