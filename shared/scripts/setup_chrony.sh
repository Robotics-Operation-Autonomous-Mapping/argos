#!/usr/bin/env bash
# Install/configure chrony for ARGOS multi-host time sync so Pi A (lidar),
# Pi B (VIO), and the laptop all agree on ONE common clock — run on the HOST,
# not in Docker. See shared/docs/time_sync.md.
#
# Topology: CHRONY_NTP_SERVER is the shared time source (default = LAPTOP_IP).
#   * On the server host  -> configured as an NTP SERVER for the LAN (serves the
#     Pis even with no internet, via `local stratum`).
#   * On every other host -> configured as a CLIENT of that server.
# The role is auto-detected by comparing this host's IPs to CHRONY_NTP_SERVER,
# or forced with ROLE=server|client.
#
# Usage (from a checkout that includes shared/, or from a role dir with a .env):
#   CHRONY_NTP_SERVER=192.168.1.60 ./setup_chrony.sh          # install + configure
#   ROLE=server ./setup_chrony.sh                             # force server role
#   ./setup_chrony.sh --verify                                # just check sync (no root)
set -euo pipefail

MODE="setup"
if [[ "${1:-}" == "--verify" || "${1:-}" == "verify" ]]; then
  MODE="verify"
fi

# --- Load env (CHRONY_NTP_SERVER + peer IPs) from a nearby .env if present ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for envf in ./.env "${SCRIPT_DIR}/../.env" "${SCRIPT_DIR}/../../shared/.env" "${SCRIPT_DIR}/../.env.example"; do
  if [[ -z "${CHRONY_NTP_SERVER:-}" && -f "${envf}" ]]; then
    # shellcheck disable=SC1090
    set -a; source "${envf}"; set +a
  fi
done

SERVER="${CHRONY_NTP_SERVER:-}"

# --- Acceptable offset guidance (VIO / lidar fusion) -------------------------
# Cross-host skew you want before trusting fused lidar+VIO timestamps.
OFFSET_WARN_MS="${OFFSET_WARN_MS:-10}"   # investigate above this
OFFSET_FAIL_MS="${OFFSET_FAIL_MS:-50}"   # scan-matching / LC association degrades

verify_sync() {
  echo "==> chrony verify (offset targets: good < ${OFFSET_WARN_MS} ms, bad > ${OFFSET_FAIL_MS} ms)"
  if ! command -v chronyc >/dev/null 2>&1; then
    echo "chronyc not installed — run setup first." >&2
    return 1
  fi
  echo "--- chronyc tracking ---"
  chronyc tracking || true
  echo "--- chronyc sources -v ---"
  chronyc sources -v || true

  # Extract |Last offset| in seconds and grade it.
  local off_s off_ms
  off_s="$(chronyc tracking 2>/dev/null | awk -F':' '/Last offset/ {gsub(/[^0-9.eE+-]/,"",$2); print $2}')"
  if [[ -n "${off_s}" ]]; then
    off_ms="$(awk -v o="${off_s}" 'BEGIN{o=o<0?-o:o; printf "%.3f", o*1000.0}')"
    echo "--- measured |last offset| = ${off_ms} ms ---"
    if awk -v m="${off_ms}" -v f="${OFFSET_FAIL_MS}" 'BEGIN{exit !(m>f)}'; then
      echo "OFFSET TOO HIGH (> ${OFFSET_FAIL_MS} ms): fix sync before enabling lidar+VIO fusion." >&2
      return 2
    elif awk -v m="${off_ms}" -v w="${OFFSET_WARN_MS}" 'BEGIN{exit !(m>w)}'; then
      echo "OFFSET marginal (> ${OFFSET_WARN_MS} ms): OK for monitoring, tighten before RTABMAP_USE_LIDAR=true."
    else
      echo "OFFSET good."
    fi
  fi
  echo ""
  echo "Run this same --verify on EVERY host (Pi A, Pi B, laptop); all must track the"
  echo "same reference (${SERVER:-CHRONY_NTP_SERVER}) and settle under ${OFFSET_WARN_MS} ms."
}

if [[ "${MODE}" == "verify" ]]; then
  verify_sync
  exit $?
fi

# --- Setup requires the server IP and root -----------------------------------
if [[ -z "${SERVER}" ]]; then
  echo "Set CHRONY_NTP_SERVER (shared time source; usually LAPTOP_IP)." >&2
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Re-run with sudo so chrony can be installed and configured." >&2
  exec sudo --preserve-env=CHRONY_NTP_SERVER,ROLE,OFFSET_WARN_MS,OFFSET_FAIL_MS "$0" "$@"
fi

# --- Decide role: is THIS host the shared server? ----------------------------
ROLE="${ROLE:-}"
if [[ -z "${ROLE}" ]]; then
  if ip -o addr show 2>/dev/null | grep -qw "${SERVER}" || hostname -I 2>/dev/null | grep -qw "${SERVER}"; then
    ROLE="server"
  else
    ROLE="client"
  fi
fi

# Derive the LAN /24 from the server IP so the server can `allow` its subnet.
LAN_SUBNET="$(awk -F. '{printf "%s.%s.%s.0/24", $1,$2,$3}' <<<"${SERVER}")"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends chrony

CONF=/etc/chrony/chrony.conf
if [[ -f "${CONF}" ]]; then
  cp -a "${CONF}" "${CONF}.bak.argos.$(date +%Y%m%d%H%M%S)" || true
fi

mkdir -p /etc/chrony/conf.d
DROPIN=/etc/chrony/conf.d/argos-ntp.conf

if [[ "${ROLE}" == "server" ]]; then
  echo "==> Configuring THIS host (${SERVER}) as the ARGOS NTP SERVER for ${LAN_SUBNET}"
  cat > "${DROPIN}" <<EOF
# ARGOS shared time source — managed by shared/scripts/setup_chrony.sh
# Serve the LAN even without internet: fall back to this host's own clock.
allow ${LAN_SUBNET}
local stratum 10
# Keep any upstream pool/servers already defined in ${CONF} for real-world time.
EOF
else
  echo "==> Configuring THIS host as an ARGOS CLIENT of ${SERVER}"
  cat > "${DROPIN}" <<EOF
# ARGOS shared time source — managed by shared/scripts/setup_chrony.sh
server ${SERVER} iburst prefer minpoll 3 maxpoll 5
# Step the clock quickly on first sync so recorded bag stamps line up fast.
makestep 0.1 3
EOF
fi

systemctl enable chrony
systemctl restart chrony

echo "chrony configured (role=${ROLE}, server=${SERVER}). Waiting for first sync ..."
sleep 3
verify_sync || true

echo ""
echo "Next: run '${BASH_SOURCE[0]##*/} --verify' on ALL hosts and confirm they agree."
