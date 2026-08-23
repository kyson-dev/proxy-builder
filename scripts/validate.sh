#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
cache_root="${PROXY_BUILDER_CACHE_ROOT:-${TMPDIR:-/tmp}/proxy-builder-validation-cache}"
mkdir -p "${cache_root}/gopath" "${cache_root}/gocache" "${cache_root}/bin" "${cache_root}/tofu-plugin-cache"
export GOPATH="${cache_root}/gopath"
export GOMODCACHE="${GOPATH}/pkg/mod"
export GOCACHE="${cache_root}/gocache"
export TF_PLUGIN_CACHE_DIR="${cache_root}/tofu-plugin-cache"

for command_name in docker go jq rg; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'required command is unavailable: %s\n' "$command_name" >&2
    exit 1
  }
done

unformatted="$(gofmt -l "${repo_root}/cmd" "${repo_root}/internal")"
if [[ -n "$unformatted" ]]; then
  printf 'Go files require gofmt:\n%s\n' "$unformatted" >&2
  exit 1
fi

(
  cd "$repo_root"
  go vet ./...
  go test -race ./...
  CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags='-s -w' -o "${cache_root}/bin/subscription" ./cmd/subscription
)

"${repo_root}/scripts/release/test-build-vm-bundle.sh"
"${repo_root}/scripts/host/test-deploy-release.sh"
"${repo_root}/scripts/delivery/test-deploy.sh"
"${repo_root}/scripts/github/test-tools.sh"

sing_box_image="$(jq -er '.sing_box_image' "${repo_root}/config/environments/development.json")"
PROXY_ROOT="${cache_root}/compose-root" SING_BOX_IMAGE="$sing_box_image" \
  docker compose -f "${repo_root}/docker-compose.yml" config --quiet

"${repo_root}/scripts/infra/validate.sh"
"${repo_root}/scripts/ci/validate-workflows.sh"
printf '%s\n' 'repository validation passed'
