#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ "$(id -u)" == "0" ]] || { printf '%s\n' 'remote deploy wrapper must run as root' >&2; exit 10; }
upload_dir="$(cd "$(dirname "$0")" && pwd -P)"

if [[ "${1:-}" == "--inspect-certificate" ]]; then
  sni="${2:-}"
  temporary="$(mktemp)"
  trap 'rm -f -- "$temporary" "$0"' EXIT
  [[ -x /opt/proxy-builder/current/bin/proxyctl && -f /opt/proxy-builder/current/cert/hysteria2.crt && -f /opt/proxy-builder/current/cert/hysteria2.key ]] || exit 0
  /opt/proxy-builder/current/bin/proxyctl inspect-certificate \
    --cert /opt/proxy-builder/current/cert/hysteria2.crt --key /opt/proxy-builder/current/cert/hysteria2.key \
    --sni "$sni" --output "$temporary" >/dev/null
  jq -r '.hy2_cert_sha256' "$temporary"
  exit 0
fi

if [[ "${1:-}" == "--rollback" ]]; then
  expected_current="${2:-}"
  trap 'rm -f -- "$0"' EXIT
  [[ -x /opt/proxy-builder/current/bin/deploy-release ]] || exit 21
  /opt/proxy-builder/current/bin/deploy-release --rollback --expected-current "$expected_current"
  exit $?
fi

release_id="${1:-}"
[[ "$release_id" =~ ^[0-9a-f]{40}-[1-9][0-9]*-[1-9][0-9]*$ ]] || { printf '%s\n' 'invalid release ID' >&2; exit 10; }
stage="/opt/proxy-builder/staging/${release_id}"
uploaded=(bundle.tar.gz reality-private-key obfs-password proxy-users.json hysteria2.crt hysteria2.key deploy-remote.sh)

cleanup() {
  rm -rf -- "$stage"
  local name
  for name in "${uploaded[@]}"; do
    rm -f -- "${upload_dir}/${name}"
  done
}
trap cleanup EXIT

install -d -m 0700 "$stage" "${stage}/bundle" "${stage}/inputs"
tar -xzf "${upload_dir}/bundle.tar.gz" -C "${stage}/bundle"
install -m 0600 "${upload_dir}/reality-private-key" "${stage}/inputs/reality-private-key"
install -m 0600 "${upload_dir}/obfs-password" "${stage}/inputs/obfs-password"
install -m 0600 "${upload_dir}/proxy-users.json" "${stage}/inputs/proxy-users.json"
if [[ -f "${upload_dir}/hysteria2.crt" || -f "${upload_dir}/hysteria2.key" ]]; then
  [[ -f "${upload_dir}/hysteria2.crt" && -f "${upload_dir}/hysteria2.key" ]] || { printf '%s\n' 'uploaded certificate pair is incomplete' >&2; exit 10; }
  install -m 0600 "${upload_dir}/hysteria2.crt" "${stage}/inputs/hysteria2.crt"
  install -m 0600 "${upload_dir}/hysteria2.key" "${stage}/inputs/hysteria2.key"
fi
"${stage}/bundle/bin/deploy-release" --bundle "${stage}/bundle" --inputs "${stage}/inputs"
