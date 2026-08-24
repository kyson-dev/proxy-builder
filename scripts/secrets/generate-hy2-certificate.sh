#!/usr/bin/env bash
set -euo pipefail
umask 077

sni=""
cert=""
key=""
days="3650"
while (($#)); do
  case "$1" in
    --sni) sni="${2:-}"; shift 2 ;;
    --cert) cert="${2:-}"; shift 2 ;;
    --key) key="${2:-}"; shift 2 ;;
    --days) days="${2:-}"; shift 2 ;;
    *) printf '%s\n' 'usage: generate-hy2-certificate.sh --sni <hostname> --cert <path> --key <path> [--days <days>]' >&2; exit 2 ;;
  esac
done
[[ -n "$sni" && -n "$cert" && -n "$key" && "$days" =~ ^[1-9][0-9]*$ ]] || exit 2
[[ ! -e "$cert" && ! -e "$key" ]] || { printf '%s\n' 'refusing to overwrite an existing certificate or key' >&2; exit 1; }
mkdir -p "$(dirname "$cert")" "$(dirname "$key")"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -sha256 -days "$days" \
  -subj "/CN=${sni}" -addext "subjectAltName=DNS:${sni}" -keyout "$key" -out "$cert"
chmod 0600 "$cert" "$key"
printf 'HY2 certificate created for %s\n' "$sni"
