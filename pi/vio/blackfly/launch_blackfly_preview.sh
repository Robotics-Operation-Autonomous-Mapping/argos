#!/usr/bin/env bash
# =============================================================================
#  Blackfly live preview (Aravis)
#
#    ~/used\ for\ ROAM/scripts/launch_blackfly_preview.sh cam0
#    ~/used\ for\ ROAM/scripts/launch_blackfly_preview.sh cam1
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/blackfly_camera.conf"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/blackfly_aravis_setup.sh"

WHICH="${1:-cam0}"
case "$WHICH" in
  cam0|0) CAM="$CAM_0"; PIXEL="$CAM_0_PIXEL_FORMAT" ;;
  cam1|1) CAM="$CAM_1"; PIXEL="$CAM_1_PIXEL_FORMAT" ;;
  *)
    echo "Usage: $0 [cam0|cam1]" >&2
    exit 1
    ;;
esac

echo "Blackfly preview (Aravis) — $WHICH"
echo "  camera:  $CAM"
echo "  format:  $PIXEL"
echo "  iface:   $ETH"

blackfly_aravis_setup_network
blackfly_aravis_setup_cam "$CAM" "$PIXEL"

if [[ "$PIXEL" == "Mono8" ]]; then
  GST_EXPOSURE_ARGS=()
  if [[ "${MINIMAL_SETUP:-0}" != "1" ]]; then
    GST_EXPOSURE_ARGS=(exposure="${CAM_1_EXPOSURE_US:-10000}" exposure-auto=off gain="${CAM_1_GAIN_DB:-0}" gain-auto=off)
  fi
  exec gst-launch-1.0 aravissrc camera-name="$CAM" packet-size="$GST_PACKET_SIZE" \
    auto-packet-size=false packet-resend=true \
    "${GST_EXPOSURE_ARGS[@]}" \
    ! video/x-raw,format=GRAY8 ! videoconvert ! autovideosink sync=false
fi

exec gst-launch-1.0 aravissrc camera-name="$CAM" packet-size="$GST_PACKET_SIZE" \
  auto-packet-size=false packet-resend=true \
  ! bayer2rgb ! videoconvert \
  ! videobalance saturation="$GST_SATURATION" hue="$GST_HUE" \
  ! autovideosink sync=false
