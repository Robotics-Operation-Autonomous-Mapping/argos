#!/usr/bin/env bash
# =============================================================================
#  Record Blackfly checkerboard images for Kalibr intrinsics calibration.
#
#  Usage:
#    ~/summer_research/scripts/record_blackfly_calib.sh
#    PACK_ONLY=1 CALIB_ROOT=~/calib/blackfly_20250617 ~/summer_research/scripts/record_blackfly_calib.sh
#
#  Output layout (Kalibr bagcreater format):
#    $CALIB_ROOT/cam0/<timestamp_ns>.jpg
#    $CALIB_ROOT/blackfly_intrinsics.bag   (after packing)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/blackfly_camera.conf"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/blackfly_aravis_setup.sh"

CALIB_ROOT="${CALIB_ROOT:-$HOME/calib/blackfly_$(date +%Y%m%d_%H%M%S)}"
FPS="${FPS:-5}"                    # target save rate (~30 fps cam / FRAME_KEEP_EVERY)
FRAME_KEEP_EVERY="${FRAME_KEEP_EVERY:-6}"  # keep every 6th frame ≈ 5 Hz at 30 fps
DURATION_SEC="${DURATION_SEC:-150}"  # 2.5 min default; aim 50+ board poses
PACK_ONLY="${PACK_ONLY:-0}"        # 1 = skip capture, only build .bag

# =============================================================================
#  Helpers
# =============================================================================

setup_camera() {
  blackfly_aravis_setup
}

rename_frames_for_kalibr() {
  local tmp_dir="$1"
  local cam_dir="$2"
  mkdir -p "$cam_dir"
  local t0
  t0=$(date +%s%N)
  local i=0
  local kept=0
  local f
  # At ~30 fps camera, keep every Nth frame to approximate target FPS
  local step="${FRAME_KEEP_EVERY:-6}"
  shopt -s nullglob
  for f in "$tmp_dir"/frame_*.jpg; do
    if (( i % step != 0 )); then
      rm -f "$f"
      i=$((i + 1))
      continue
    fi
    local ts=$((t0 + kept * 1000000000 / FPS))
    mv "$f" "$cam_dir/${ts}.jpg"
    kept=$((kept + 1))
    i=$((i + 1))
  done
  shopt -u nullglob
}

pack_rosbag() {
  local root="$1"
  local bag="$root/blackfly_intrinsics.bag"
  local n
  n=$(find "$root/cam0" -name '*.jpg' 2>/dev/null | wc -l)
  if [[ "$n" -lt 20 ]]; then
    echo "Only $n images in $root/cam0 — aim for 50+ with checkerboard visible." >&2
    exit 1
  fi

  echo "Packing $n images -> $bag"
  docker run --rm --entrypoint bash \
    -v "$root:/data" \
    stereolabs/kalibr:kinetic \
    -lc 'source /opt/ros/kinetic/setup.bash && source /kalibr_workspace/devel/setup.bash && \
      kalibr_bagcreater --folder /data --output-bag /data/blackfly_intrinsics.bag'

  docker run --rm --entrypoint bash \
    -v "$root:/data" \
    stereolabs/kalibr:kinetic \
    -lc 'source /opt/ros/kinetic/setup.bash && rosbag info /data/blackfly_intrinsics.bag | head -20'

  echo ""
  echo "Rosbag ready: $bag"
  echo "Topic: /cam0/image_raw"
  echo ""
  echo "Run Kalibr:"
  echo "  docker run --rm -it \\"
  echo "    -v $root:/calib \\"
  echo "    -v $HOME/summer_research/config/kalibr:/config:ro \\"
  echo "    stereolabs/kalibr:kinetic \\"
  echo "    bash -lc 'source /opt/ros/kinetic/setup.bash && source /kalibr_workspace/devel/setup.bash && cd /calib && kalibr_calibrate_cameras --bag blackfly_intrinsics.bag --topics /cam0/image_raw --models pinhole-radtan --target /config/checkerboard.yaml'"
}

record_frames() {
  local root="$1"
  local tmp="$root/_capture_tmp"
  local cam="$root/cam0"
  mkdir -p "$tmp" "$cam"

  echo "Recording to $root"
  echo "  Live preview window opens — check focus before moving the board"
  echo "  Move the checkerboard SLOWLY for ${DURATION_SEC}s"
  echo "  Cover center, corners, edges, near/far, and tilt (~30-45 deg)"
  echo "  Press Ctrl+C early if you have enough poses (50+ frames with board visible)"
  echo ""

  local gst_rc=0
  timeout "$DURATION_SEC" gst-launch-1.0 -e \
    aravissrc camera-name="$CAM" packet-size="$GST_PACKET_SIZE" auto-packet-size=false \
    ! bayer2rgb ! videoconvert \
    ! videobalance saturation="$GST_SATURATION" hue="$GST_HUE" \
    ! tee name=rec allow-not-linked=false \
    rec. ! queue max-size-buffers=120 leaky=downstream \
         ! videoconvert ! video/x-raw,format=I420 \
         ! jpegenc quality=95 \
         ! multifilesink location="$tmp/frame_%06d.jpg" \
    rec. ! queue max-size-buffers=2 leaky=downstream \
         ! autovideosink sync=false || gst_rc=$?

  if [[ "$gst_rc" -ne 0 && "$gst_rc" -ne 124 ]]; then
    echo "GStreamer exited with error code $gst_rc" >&2
  fi

  rename_frames_for_kalibr "$tmp" "$cam"
  rmdir "$tmp" 2>/dev/null || true

  local n tmp_n
  tmp_n=$(find "$tmp" -name 'frame_*.jpg' 2>/dev/null | wc -l)
  n=$(find "$cam" -name '*.jpg' | wc -l)
  echo "Captured $n frames in $cam (from $tmp_n raw frames, keep-every=${FRAME_KEEP_EVERY:-6})"
}

# =============================================================================
#  Main
# =============================================================================

if [[ "$PACK_ONLY" == "1" ]]; then
  pack_rosbag "$CALIB_ROOT"
  exit 0
fi

setup_camera
record_frames "$CALIB_ROOT"
pack_rosbag "$CALIB_ROOT"
