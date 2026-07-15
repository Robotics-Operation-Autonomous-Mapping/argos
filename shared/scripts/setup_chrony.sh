#!/usr/bin/env bash
# Install/configure chrony as an NTP client for ARGOS multi-Pi sync.
# Run on Pi A, Pi B, and (if needed) the laptop — on the HOST, not in Docker.
# Usage:
#   CHRONY_NTP_SERVER=192.168.1.60 ./setup_chrony.sh
set -euo pipefail

SERVER="${CHRONY_NTP_SERVER:-}"
if [[ -z "${SERVER}" ]] && [[ -f .env ]]; then
  # shellcheck disable=SC1091
  set -a; source .env; set +a
  SERVER="${CHRONY_NTP_SERVER:-}"
fi
if [[ -z "${SERVER}" ]]; then
  echo "Set CHRONY_NTP_SERVER (NTP peer / laptop IP)." >&2
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Re-run with sudo so chrony can be installed and configured." >&2
  exec sudo CHRONY_NTP_SERVER="${SERVER}" "$0" "$@"
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends chrony

CONF=/etc/chrony/chrony.conf
if [[ -f "${CONF}" ]]; then
  cp -a "${CONF}" "${CONF}.bak.argos.$(date +%Y%m%d%H%M%S)" || true
fi

# Prefer a single LAN server; keep a public pool as fallback.
cat > /etc/chrony/conf.d/argos-ntp.conf <<EOF
# ARGOS multi-host time sync — managed by shared/scripts/setup_chrony.sh
server ${SERVER} iburst prefer
EOF

systemctl enable chrony
systemctl restart chrony

echo "chrony configured with preferred server ${SERVER}"
chronyc tracking || true
chronyc sources -v || true
