#!/usr/bin/env bash
# Restore a Blackfly to factory UserSet + minimal GigE streaming settings.
#
#   ~/used\ for\ ROAM/scripts/restore_blackfly_cam.sh cam1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/blackfly_camera.conf"

WHICH="${1:-cam1}"
case "$WHICH" in
  cam0|0) CAM="$CAM_0"; PIXEL="$CAM_0_PIXEL_FORMAT" ;;
  cam1|1) CAM="$CAM_1"; PIXEL="$CAM_1_PIXEL_FORMAT" ;;
  *) echo "Usage: $0 [cam0|cam1]" >&2; exit 1 ;;
esac

echo "=== Restore $WHICH ($CAM) ==="
pkill -9 -f gst-launch 2>/dev/null || true
pkill -f aravis_ros2_publisher 2>/dev/null || true
sleep 2

if ! arv-tool-0.8 2>/dev/null | grep -qF "$CAM"; then
  echo "Camera not visible. Check cable/IP first." >&2
  exit 1
fi

echo "Loading factory UserSet (Default) ..."
arv-tool-0.8 -n "$CAM" control UserSetSelector=Default UserSetLoad=1
arv-tool-0.8 -n "$CAM" control TriggerMode=Off
arv-tool-0.8 -n "$CAM" control TestImageSelector=Off
arv-tool-0.8 -n "$CAM" control GevSCPSPacketSize="${PACKET_SIZE:-1440}"
arv-tool-0.8 -n "$CAM" control GevSCPSDoNotFragment=false
arv-tool-0.8 -n "$CAM" control PixelFormat="$PIXEL"
arv-tool-0.8 -n "$CAM" control ExposureMode=Timed
arv-tool-0.8 -n "$CAM" control ExposureAuto=Continuous
arv-tool-0.8 -n "$CAM" control GainAuto=Continuous

echo ""
echo "Current settings:"
arv-tool-0.8 -n "$CAM" values 2>&1 | grep -iE "PixelFormat|ExposureMode|ExposureAuto|ExposureTime|TestImage|GevSCPSPacketSize|Width|Height" || true
echo ""
echo "Done. Try:"
echo "  MINIMAL_SETUP=1 ~/used\\ for\\ ROAM/scripts/launch_blackfly_preview.sh $WHICH"
echo "  ~/used\\ for\\ ROAM/scripts/diagnose_blackfly_cam.sh $WHICH"
