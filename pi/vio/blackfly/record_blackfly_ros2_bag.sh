#!/usr/bin/env bash
# =============================================================================
#  Record Blackfly BFLY-PGE cameras via Aravis + ROS 2 bag (mcap).
#
#  Both cameras (default):
#    ~/used\ for\ ROAM/scripts/record_blackfly_ros2_bag.sh
#
#  One camera only:
#    RECORD_CAMS=cam0 ~/used\ for\ ROAM/scripts/record_blackfly_ros2_bag.sh
#    RECORD_CAMS=cam1 ~/used\ for\ ROAM/scripts/record_blackfly_ros2_bag.sh
#
#  Aravis live preview while recording (same GStreamer pipeline, not rqt):
#    PREVIEW=1 RECORD_CAMS=cam0 ~/used\ for\ ROAM/scripts/record_blackfly_ros2_bag.sh
#
#  Stop recording with Ctrl+C.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/blackfly_camera.conf"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/blackfly_aravis_setup.sh"

RECORD_CAMS="${RECORD_CAMS:-both}"   # both | cam0 | cam1
PREVIEW="${PREVIEW:-0}"              # 1 = GStreamer autovideosink on PREVIEW_CAM
PREVIEW_CAM="${PREVIEW_CAM:-cam0}"   # cam0 | cam1 (when RECORD_CAMS=both)
BAG_DIR="${BAG_DIR:-$HOME/recordings/blackfly_$(date +%Y%m%d_%H%M%S)}"

if ! command -v ros2 >/dev/null; then
  echo "ROS 2 not found. Run: source /opt/ros/humble/setup.bash" >&2
  exit 1
fi

# ROS setup.bash references unset vars; incompatible with nounset (-u).
set +u
# shellcheck source=/dev/null
source /opt/ros/humble/setup.bash
set -u

TOPICS=()
PUB_PIDS=()

start_publisher() {
  local which="$1"
  local cam topic frame_id pixel node_name
  case "$which" in
    cam0)
      cam="$CAM_0"; topic="$CAM_0_TOPIC"; frame_id="$CAM_0_FRAME_ID"
      pixel="$CAM_0_PIXEL_FORMAT"; node_name="aravis_cam_0" ;;
    cam1)
      cam="$CAM_1"; topic="$CAM_1_TOPIC"; frame_id="$CAM_1_FRAME_ID"
      pixel="$CAM_1_PIXEL_FORMAT"; node_name="aravis_cam_1" ;;
    *)
      echo "Unknown camera: $which" >&2
      return 1
      ;;
  esac

  local sat=1.0 hue=0.0
  if [[ "$pixel" != "Mono8" ]]; then
    sat="$GST_SATURATION"
    hue="$GST_HUE"
  fi

  local preview_args=()
  if [[ "$PREVIEW" == "1" && "$which" == "$PREVIEW_CAM" ]]; then
    preview_args=(--preview)
  fi

  python3 "$SCRIPT_DIR/aravis_ros2_publisher.py" \
    --camera "$cam" \
    --packet-size "$GST_PACKET_SIZE" \
    --topic "$topic" \
    --frame-id "$frame_id" \
    --pixel-format "$pixel" \
    --node-name "$node_name" \
    --saturation "$sat" \
    --hue "$hue" \
    "${preview_args[@]}" &
  PUB_PIDS+=("$!")
  TOPICS+=("$topic")
}

cleanup() {
  local pid
  for pid in "${PUB_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  for pid in "${PUB_PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

echo "=== Blackfly Aravis -> ROS 2 bag ==="
echo "  record:  $RECORD_CAMS"
if [[ "$PREVIEW" == "1" ]]; then
  echo "  preview: $PREVIEW_CAM (Aravis/GStreamer window)"
fi
echo "  iface:   $ETH"
echo "  bag dir: $BAG_DIR"
echo "  stop:    Ctrl+C"
echo ""

case "$RECORD_CAMS" in
  both)
    blackfly_aravis_setup_dual
    start_publisher cam0
    start_publisher cam1
    ;;
  cam0|0)
    blackfly_aravis_setup_network
    blackfly_aravis_setup_cam "$CAM_0" "$CAM_0_PIXEL_FORMAT"
    start_publisher cam0
    ;;
  cam1|1)
    blackfly_aravis_setup_network
    blackfly_aravis_setup_cam "$CAM_1" "$CAM_1_PIXEL_FORMAT"
    start_publisher cam1
    ;;
  *)
    echo "RECORD_CAMS must be both, cam0, or cam1" >&2
    exit 1
    ;;
esac

echo "Waiting for publishers..."
sleep 5

for pid in "${PUB_PIDS[@]}"; do
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "A publisher failed to start. Try: $SCRIPT_DIR/launch_blackfly_preview.sh cam0" >&2
    exit 1
  fi
done

echo "Topics: ${TOPICS[*]}"
echo "Recording rosbag2 (Ctrl+C to stop)..."
ros2 bag record -o "$BAG_DIR" "${TOPICS[@]}"

echo ""
echo "Bag saved: $BAG_DIR"
ros2 bag info "$BAG_DIR" | head -30
echo ""
echo "Playback:  ros2 bag play $BAG_DIR"
echo "View bag:  ros2 run rqt_image_view rqt_image_view"
