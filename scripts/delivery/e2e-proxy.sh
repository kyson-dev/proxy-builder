#!/usr/bin/env bash
set -euo pipefail
umask 077

subscription=""
image=""
probe_url=""
proxyctl=""
protocol=""
while (($#)); do
  case "$1" in
    --subscription) subscription="${2:-}"; shift 2 ;;
    --image) image="${2:-}"; shift 2 ;;
    --probe-url) probe_url="${2:-}"; shift 2 ;;
    --proxyctl) proxyctl="${2:-}"; shift 2 ;;
    --protocol) protocol="${2:-}"; shift 2 ;;
    *) printf '%s\n' 'usage: e2e-proxy.sh --subscription <file> --protocol vless|hysteria2 --image <digest> --probe-url <https-url> --proxyctl <binary>' >&2; exit 2 ;;
  esac
done
[[ -f "$subscription" && -x "$proxyctl" ]] || { printf '%s\n' 'subscription and proxyctl are required' >&2; exit 2; }
[[ "$protocol" == vless || "$protocol" == hysteria2 ]] || { printf '%s\n' 'protocol must be vless or hysteria2' >&2; exit 2; }
[[ "$image" =~ @sha256:[0-9a-f]{64}$ ]] || { printf '%s\n' 'probe image must use a sha256 digest' >&2; exit 2; }
[[ "$probe_url" =~ ^https://[^?#]+$ ]] || { printf '%s\n' 'probe URL must be HTTPS without query or fragment' >&2; exit 2; }
for command_name in curl docker; do command -v "$command_name" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command_name" >&2; exit 1; }; done

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/proxy-builder-e2e.XXXXXX")"
containers=()
cleanup() {
  local container
  for container in "${containers[@]}"; do docker rm -f "$container" >/dev/null 2>&1 || true; done
  rm -rf "$work_dir"
}
trap cleanup EXIT

port=18080
[[ "$protocol" == hysteria2 ]] && port=18081
config="${work_dir}/${protocol}.json"
container="proxy-builder-probe-${protocol}-${RANDOM}-${RANDOM}"
"$proxyctl" render-probe-config --input "$subscription" --protocol "$protocol" --listen-port "$port" --output "$config"
docker run --rm -v "${config}:/etc/sing-box/config.json:ro" "$image" check -c /etc/sing-box/config.json >/dev/null 2>&1
docker run --detach --name "$container" --network host -v "${config}:/etc/sing-box/config.json:ro" "$image" run -c /etc/sing-box/config.json >/dev/null
containers+=("$container")
status=""
for _ in {1..20}; do
  status="$(curl --silent --show-error --max-time 10 --proxy "socks5h://127.0.0.1:${port}" --output /dev/null --write-out '%{http_code}' "$probe_url" 2>/dev/null || true)"
  [[ "$status" == "204" ]] && break
  sleep 1
done
[[ "$status" == "204" ]] || { printf '%s proxy egress probe failed\n' "$protocol" >&2; exit 1; }
docker rm -f "$container" >/dev/null
containers=()
printf '%s egress probe passed\n' "$protocol"
