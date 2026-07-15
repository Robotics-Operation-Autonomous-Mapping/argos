#!/usr/bin/env bash
# COLMAP recording profile — Pi B (VIO).
# Bags both Vivotek image streams (+ info), /tf, OpenVINS odom for later alignment.
# Optionally throttles to COLMAP_IMAGE_RATE_HZ when topic_tools throttle is available.
#
# Usage (from pi/vio/, OpenVINS / camera drivers already up):
#   ./scripts/record_colmap.sh
#   COLMAP_INCLUDE_BLACKFLY=true ./scripts/record_colmap.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED="$(cd "${ROOT}/../../shared" && pwd)"
cd "${ROOT}"

if [[ ! -f .env ]]; then
  cp "${SHARED}/.env.example" .env
  echo "Created .env — set VIVOTEK_* topics and peer IPs."
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

BAG_OUTPUT_DIR="${BAG_OUTPUT_DIR:-$HOME/argos_data/bags}"
BAG_STORAGE_ID="${BAG_STORAGE_ID:-mcap}"
RATE_HZ="${COLMAP_IMAGE_RATE_HZ:-2}"
LEFT="${VIVOTEK_LEFT_TOPIC:-/vivotek/left/image_raw}"
RIGHT="${VIVOTEK_RIGHT_TOPIC:-/vivotek/right/image_raw}"
LEFT_INFO="${VIVOTEK_LEFT_INFO_TOPIC:-/vivotek/left/camera_info}"
RIGHT_INFO="${VIVOTEK_RIGHT_INFO_TOPIC:-/vivotek/right/camera_info}"
ODOM="${OV_ODOM_TOPIC:-/ov_msckf/odomimu}"
INCLUDE_BF="${COLMAP_INCLUDE_BLACKFLY:-false}"

mkdir -p "${BAG_OUTPUT_DIR}"
OUT="${BAG_OUTPUT_DIR}/colmap_$(date +%Y%m%d_%H%M%S)"

THROTTLE_PIDS=()
cleanup() {
  for pid in "${THROTTLE_PIDS[@]:-}"; do
    kill "${pid}" 2>/dev/null || true
  done
}
trap cleanup EXIT

# Topics actually recorded (may be throttled republish names).
REC_LEFT="${LEFT}"
REC_RIGHT="${RIGHT}"

maybe_throttle() {
  local in_topic="$1"
  local out_topic="$2"
  if ! ros2 pkg prefix topic_tools >/dev/null 2>&1; then
    return 1
  fi
  # Humble: throttle messages <intopic> <msgs_per_sec> [<outtopic>]
  ros2 run topic_tools throttle messages "${in_topic}" "${RATE_HZ}" "${out_topic}" &
  THROTTLE_PIDS+=("$!")
  sleep 0.5
  return 0
}

if maybe_throttle "${LEFT}" "${LEFT}/colmap_throttle"; then
  REC_LEFT="${LEFT}/colmap_throttle"
  echo "Throttling ${LEFT} → ${REC_LEFT} @ ${RATE_HZ} Hz"
else
  echo "topic_tools throttle not found — recording ${LEFT} at full rate (subsample offline)."
fi
if maybe_throttle "${RIGHT}" "${RIGHT}/colmap_throttle"; then
  REC_RIGHT="${RIGHT}/colmap_throttle"
  echo "Throttling ${RIGHT} → ${REC_RIGHT} @ ${RATE_HZ} Hz"
else
  echo "topic_tools throttle not found — recording ${RIGHT} at full rate (subsample offline)."
fi

TOPICS=(
  "${REC_LEFT}"
  "${REC_RIGHT}"
  "${LEFT_INFO}"
  "${RIGHT_INFO}"
  "${ODOM}"
  /tf
  /tf_static
)

if [[ "${INCLUDE_BF}" =~ ^(1|true|yes)$ ]]; then
  TOPICS+=(
    "${CAMERA_IMAGE_TOPIC:-${BLACKFLY_IMAGE_TOPIC:-/blackfly/image_raw}}"
    "${CAMERA_INFO_TOPIC:-${BLACKFLY_INFO_TOPIC:-/blackfly/camera_info}}"
  )
fi

echo "COLMAP bag → ${OUT} (storage=${BAG_STORAGE_ID})"
echo "Topics: ${TOPICS[*]}"
exec ros2 bag record -o "${OUT}" --storage "${BAG_STORAGE_ID}" "${TOPICS[@]}"
