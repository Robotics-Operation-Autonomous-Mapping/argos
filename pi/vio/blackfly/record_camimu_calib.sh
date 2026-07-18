#!/usr/bin/env bash
# =============================================================================
#  Record the cam–IMU calibration bag (Blackfly + ICM-20948) OR a long static
#  Allan-variance bag (IMU only) on Pi B — into an mcap/ros2 bag.
#
#  Bring the sensors up FIRST (both must already be publishing):
#    ros2 launch ./blackfly_vio.launch.py serial:="Point Grey Research-Blackfly ..."
#    ros2 run ros2_icm20948 icm20948_node --ros-args -p raw_only:=true -p pub_rate_hz:=200
#  (IMU free-runs at its native ~320 Hz — pub_rate_hz does NOT cap /imu/data_raw;
#   see ../README.md "IMU rate: run at native ~320 Hz and keep it consistent".)
#
#  Usage (from pi/vio/blackfly/):
#    ./record_camimu_calib.sh                 # cam+IMU calib bag (excite all 6 DoF)
#    DURATION_SEC=120 ./record_camimu_calib.sh
#    ./record_camimu_calib.sh --allan         # long STATIC IMU-only Allan bag
#    ALLAN_HOURS=3 ./record_camimu_calib.sh --allan
#
#  A preflight VERIFY clause confirms BOTH topics are live at a nonzero rate
#  (expect ~10 Hz cam, ~320 Hz IMU) and ABORTS if either is missing/silent.
# =============================================================================
set -euo pipefail

MODE="camimu"
if [[ "${1:-}" == "--allan" || "${1:-}" == "allan" ]]; then
  MODE="allan"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"          # pi/vio (holds the role .env)
SHARED="$(cd "${SCRIPT_DIR}/../../../shared" && pwd)"

# --- Env: topics + output (parameterized, same names as the rest of ARGOS) ---
if [[ -f "${VIO_DIR}/.env" ]]; then
  ENVF="${VIO_DIR}/.env"
else
  ENVF="${SHARED}/.env.example"
  echo "No pi/vio/.env — falling back to ${ENVF}. Copy it to pi/vio/.env to customize."
fi
# shellcheck disable=SC1090
set -a; source "${ENVF}"; set +a

# shellcheck disable=SC1091
source /opt/ros/humble/setup.bash

if command -v envsubst >/dev/null 2>&1 && [[ -x "${SHARED}/scripts/render_cyclonedds.sh" ]]; then
  "${SHARED}/scripts/render_cyclonedds.sh" "${ENVF}" /tmp/cyclonedds.xml || true
  [[ -f /tmp/cyclonedds.xml ]] && export CYCLONEDDS_URI=file:///tmp/cyclonedds.xml
fi
export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-42}"

IMAGE_TOPIC="${CAMERA_IMAGE_TOPIC:-${BLACKFLY_IMAGE_TOPIC:-/blackfly/image_raw}}"
INFO_TOPIC="${CAMERA_INFO_TOPIC:-${BLACKFLY_INFO_TOPIC:-/blackfly/camera_info}}"
IMU_T="${IMU_TOPIC:-/imu/data_raw}"

BAG_OUTPUT_DIR="${BAG_OUTPUT_DIR:-$HOME/argos_data/bags}"
BAG_STORAGE_ID="${BAG_STORAGE_ID:-mcap}"

# Expected rates (Hz) — used for reporting + a nonzero preflight gate.
CAM_EXPECT_HZ="${CAM_EXPECT_HZ:-10}"
IMU_EXPECT_HZ="${IMU_EXPECT_HZ:-${IMU_RATE_HZ:-320}}"

# =============================================================================
#  Preflight VERIFY — both topics must be LIVE at a nonzero rate, else ABORT.
# =============================================================================
# Measure a topic's publish rate with a hard timeout. Prints the numeric Hz
# (empty if the topic is absent/silent).
measure_hz() {
  local topic="$1" window="${2:-30}" secs="${3:-10}"
  timeout "${secs}" ros2 topic hz "${topic}" --window "${window}" 2>/dev/null \
    | grep -m1 'average rate' | awk '{print $3}'
}

nonzero() { awk -v v="${1:-0}" 'BEGIN{exit !(v+0 > 0)}'; }

preflight_verify() {
  local need_cam="$1"
  echo "==> Preflight VERIFY (topics must be live before recording)"
  echo "    image:      ${IMAGE_TOPIC}   (expect ~${CAM_EXPECT_HZ} Hz)"
  echo "    camera_info:${INFO_TOPIC}"
  echo "    imu:        ${IMU_T}   (expect ~${IMU_EXPECT_HZ} Hz)"
  echo ""

  local topics
  topics="$(ros2 topic list 2>/dev/null || true)"

  # IMU is required in every mode.
  if ! grep -qx "${IMU_T}" <<<"${topics}"; then
    echo "ABORT: IMU topic ${IMU_T} is not in 'ros2 topic list'." >&2
    echo "       Start the driver: ros2 run ros2_icm20948 icm20948_node --ros-args -p raw_only:=true -p pub_rate_hz:=200" >&2
    exit 1
  fi
  local imu_hz
  imu_hz="$(measure_hz "${IMU_T}" 50 10)"
  if ! nonzero "${imu_hz}"; then
    echo "ABORT: ${IMU_T} is listed but SILENT (no messages in 10 s)." >&2
    exit 1
  fi
  printf '    measured IMU rate: %.1f Hz\n' "${imu_hz}"

  local cam_hz=""
  if [[ "${need_cam}" == "1" ]]; then
    if ! grep -qx "${IMAGE_TOPIC}" <<<"${topics}"; then
      echo "ABORT: image topic ${IMAGE_TOPIC} is not in 'ros2 topic list'." >&2
      echo "       Launch the Blackfly: ros2 launch ./blackfly_vio.launch.py serial:=\"...\"" >&2
      exit 1
    fi
    cam_hz="$(measure_hz "${IMAGE_TOPIC}" 20 12)"
    if ! nonzero "${cam_hz}"; then
      echo "ABORT: ${IMAGE_TOPIC} is listed but SILENT (no frames in 12 s)." >&2
      exit 1
    fi
    printf '    measured cam rate: %.1f Hz\n' "${cam_hz}"
    if ! grep -qx "${INFO_TOPIC}" <<<"${topics}"; then
      echo "WARNING: ${INFO_TOPIC} not published — recording without camera_info." >&2
    fi
  fi

  echo "==> VERIFY OK — both required topics are live."
  echo ""
}

# =============================================================================
#  Record
# =============================================================================
mkdir -p "${BAG_OUTPUT_DIR}"

if [[ "${MODE}" == "allan" ]]; then
  preflight_verify 0

  ALLAN_HOURS="${ALLAN_HOURS:-3}"
  OUT="${BAG_OUTPUT_DIR}/imu_allan_$(date +%Y%m%d_%H%M%S)"
  echo "==> Allan/static IMU recording (IMU ONLY): ${IMU_T}"
  echo "    Keep the rig PERFECTLY STILL on a solid surface for >= ${ALLAN_HOURS} h."
  echo "    Bag → ${OUT} (storage=${BAG_STORAGE_ID})"
  echo "    Stop with Ctrl+C when done, then compute noise/bias:"
  echo "      python3 ${SHARED}/scripts/imu_allan_variance.py ${OUT} --topic ${IMU_T} \\"
  echo "          --out ${SHARED}/calib/<name>-imu.yaml"
  echo ""
  if [[ -n "${DURATION_SEC:-}" ]]; then
    echo "    (DURATION_SEC=${DURATION_SEC}: auto-stop; otherwise Ctrl+C)"
    exec timeout "${DURATION_SEC}" ros2 bag record -o "${OUT}" --storage "${BAG_STORAGE_ID}" "${IMU_T}"
  else
    exec ros2 bag record -o "${OUT}" --storage "${BAG_STORAGE_ID}" "${IMU_T}"
  fi
fi

# --- cam + IMU calibration bag ------------------------------------------------
preflight_verify 1

OUT="${BAG_OUTPUT_DIR}/camimu_calib_$(date +%Y%m%d_%H%M%S)"

TOPICS=("${IMAGE_TOPIC}" "${INFO_TOPIC}" "${IMU_T}")
# Include /tf + /tf_static only if actually present.
LIST="$(ros2 topic list 2>/dev/null || true)"
grep -qx "/tf" <<<"${LIST}" && TOPICS+=(/tf)
grep -qx "/tf_static" <<<"${LIST}" && TOPICS+=(/tf_static)

echo "==> cam–IMU calibration recording"
echo "    Excite ALL 6 DoF in front of the April/checkerboard target (smooth, no blur):"
echo "    roll/pitch/yaw + up-down/left-right/fwd-back; keep the target fully in view."
echo "    Bag → ${OUT} (storage=${BAG_STORAGE_ID})"
echo "    Topics: ${TOPICS[*]}"
if [[ -n "${DURATION_SEC:-}" ]]; then
  echo "    Auto-stop after ${DURATION_SEC}s."
  echo ""
  exec timeout "${DURATION_SEC}" ros2 bag record -o "${OUT}" --storage "${BAG_STORAGE_ID}" "${TOPICS[@]}"
else
  echo "    Stop with Ctrl+C when you have ~60-90 s of good excitation."
  echo ""
  exec ros2 bag record -o "${OUT}" --storage "${BAG_STORAGE_ID}" "${TOPICS[@]}"
fi
