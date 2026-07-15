#!/usr/bin/env bash
# Preferred native RTABMAP entrypoint — Pi A (lidar).
# Consumes OpenVINS OV_ODOM_TOPIC from Pi B over CycloneDDS + local /scan (or cloud).
# Requires: system ROS Humble + ros-humble-rtabmap-ros; lidar driver already up.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED="$(cd "${ROOT}/../../shared" && pwd)"
cd "${ROOT}"

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
# Prefer lidar fusion on this host once calibrated.
export RTABMAP_USE_LIDAR="${RTABMAP_USE_LIDAR:-true}"

mkdir -p "$(dirname "${RTABMAP_DATABASE_PATH:-$HOME/argos_data/rtabmap.db}")"

echo "Native RTABMAP on lidar Pi — odom=${OV_ODOM_TOPIC:-/ov_msckf/odomimu} (DDS) lidar=${RTABMAP_USE_LIDAR} scan=${LIDAR_SCAN_TOPIC:-/scan}"
exec ros2 launch "${ROOT}/launch/host_rtabmap.launch.py"
