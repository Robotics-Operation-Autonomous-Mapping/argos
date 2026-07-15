#!/usr/bin/env bash
# Render CycloneDDS XML for native (non-Docker) ROS on a Pi or laptop.
# Usage (from role dir with .env, or pass ENV file):
#   ./shared/scripts/render_cyclonedds.sh
#   ./shared/scripts/render_cyclonedds.sh /path/to/.env /tmp/cyclonedds.xml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE="${SHARED}/config/cyclonedds.xml.template"

ENV_FILE="${1:-.env}"
OUT="${2:-/tmp/cyclonedds.xml}"

if [[ ! -f "${TEMPLATE}" ]]; then
  echo "Missing template: ${TEMPLATE}" >&2
  exit 1
fi

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  set -a; source "${ENV_FILE}"; set +a
fi

: "${PI_LIDAR_IP:?Set PI_LIDAR_IP}"
: "${PI_VIO_IP:?Set PI_VIO_IP}"
: "${LAPTOP_IP:?Set LAPTOP_IP}"

envsubst '${PI_LIDAR_IP} ${PI_VIO_IP} ${LAPTOP_IP}' \
  < "${TEMPLATE}" \
  > "${OUT}"

export CYCLONEDDS_URI="file://${OUT}"
echo "Wrote ${OUT}"
echo "export CYCLONEDDS_URI=file://${OUT}"
echo "export RMW_IMPLEMENTATION=${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"
echo "export ROS_DOMAIN_ID=${ROS_DOMAIN_ID:-42}"
