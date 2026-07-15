#!/usr/bin/env bash
# Alternative native RTABMAP on Pi B (VIO).
# Preferred mapper is Pi A: ../lidar/scripts/run_rtabmap_host.sh
# Use this when RTABMAP is already set up on the VIO Pi (pulls /scan over DDS).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED="$(cd "${ROOT}/../../shared" && pwd)"
cd "${ROOT}"

echo "NOTE: Preferred RTABMAP host is Pi A — pi/lidar/scripts/run_rtabmap_host.sh" >&2

if [[ ! -f .env ]]; then
  cp "${SHARED}/.env.example" .env
fi
# shellcheck disable=SC1091
set -a; source .env; set +a

# shellcheck disable=SC1091
source /opt/ros/humble/setup.bash

if command -v envsubst >/dev/null 2>&1; then
  "${SHARED}/scripts/render_cyclonedds.sh" .env /tmp/cyclonedds.xml
  export CYCLONEDDS_URI=file:///tmp/cyclonedds.xml
fi

export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-42}"
export ARGOS_SHARED="${SHARED}"
export RTABMAP_CONFIG="${SHARED}/config/rtabmap.yaml"
export USE_SIM_TIME="${USE_SIM_TIME:-false}"

mkdir -p "$(dirname "${RTABMAP_DATABASE_PATH:-$HOME/argos_data/rtabmap.db}")"

echo "Native RTABMAP on VIO Pi (alt) — odom=${OV_ODOM_TOPIC:-/ov_msckf/odomimu} lidar=${RTABMAP_USE_LIDAR:-false}"
exec ros2 launch "${ROOT}/launch/host_rtabmap.launch.py"
