#!/bin/bash
set -Eeuo pipefail
umask 077

if [[ "$(id -u)" -ne 0 ]]; then
  echo "proxy bootstrap must run as root" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

readonly docker_ce_version="5:29.7.2-1~debian.12~bookworm"
readonly containerd_version="2.3.3-1~debian.12~bookworm"
readonly buildx_version="0.36.1-1~debian.12~bookworm"
readonly compose_version="5.5.0-1~debian.12~bookworm"
readonly metadata_url="http://metadata.google.internal/computeMetadata/v1/instance/attributes/proxy-bootstrap-sha256"
readonly marker_dir="/var/lib/proxy-builder"
readonly marker_file="${marker_dir}/bootstrap.sha256"
readonly proxy_root="/opt/proxy-builder"

# shellcheck source=/dev/null
source /etc/os-release
if [[ "${ID:-}" != "debian" || "${VERSION_CODENAME:-}" != "bookworm" ]]; then
  echo "proxy bootstrap requires Debian 12 bookworm" >&2
  exit 1
fi

apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates curl gnupg jq openssl iproute2 util-linux

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: bookworm
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update -qq
apt-mark unhold docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1 || true
apt-get install -y -qq --no-install-recommends \
  "docker-ce=${docker_ce_version}" \
  "docker-ce-cli=${docker_ce_version}" \
  "containerd.io=${containerd_version}" \
  "docker-buildx-plugin=${buildx_version}" \
  "docker-compose-plugin=${compose_version}"
apt-mark hold docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null

install -m 0755 -d /etc/docker
cat >/etc/docker/daemon.json <<'EOF'
{
  "log-driver": "journald",
  "live-restore": true
}
EOF
systemctl enable docker >/dev/null
systemctl restart docker

cat >/etc/sysctl.d/99-proxy-builder.conf <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
EOF
sysctl --system >/dev/null

install -m 0755 -d /etc/systemd/journald.conf.d
cat >/etc/systemd/journald.conf.d/99-proxy-builder.conf <<'EOF'
[Journal]
SystemMaxUse=500M
EOF
systemctl restart systemd-journald

install -d -o root -g root -m 0700 \
  "${proxy_root}" \
  "${proxy_root}/releases" \
  "${proxy_root}/staging" \
  "${proxy_root}/failed"

expected_sha="$(curl -fsS -H 'Metadata-Flavor: Google' "${metadata_url}")"
actual_sha="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ ! "${expected_sha}" =~ ^[0-9a-f]{64}$ || "${actual_sha}" != "${expected_sha}" ]]; then
  echo "proxy-bootstrap-sha256 metadata is missing or invalid" >&2
  exit 1
fi
install -d -o root -g root -m 0700 "${marker_dir}"
temporary_marker="$(mktemp "${marker_dir}/.bootstrap.XXXXXX")"
printf '%s\n' "${actual_sha}" >"${temporary_marker}"
chmod 0600 "${temporary_marker}"
mv -f "${temporary_marker}" "${marker_file}"

docker version --format '{{.Server.Version}}'
docker compose version --short
echo "proxy bootstrap complete: ${actual_sha}"
