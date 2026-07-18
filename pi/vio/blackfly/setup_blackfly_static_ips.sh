#!/usr/bin/env bash
# One-time: assign static GigE IPs to both Blackfly cameras on sensor network.
#
#   sudo ~/used\ for\ ROAM/scripts/setup_blackfly_static_ips.sh
#
# After a PoE switch reset cameras fall back to 169.254.x. This script:
#   1) brings up host 192.168.1.2 + temporary link-local for discovery
#   2) GigEConfig -a  (AutoForceIP onto the host subnet)
#   3) GigEConfig -s  (write persistent IP / mask / gateway)
#
# Host: 192.168.1.2  |  cam_0: 192.168.1.1  |  cam_1: 192.168.1.3
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/blackfly_camera.conf"

GIGE_CONFIG="${GIGE_CONFIG:-/opt/spinnaker/bin/GigEConfig}"
MASK="255.255.255.0"
GATEWAY="${HOST_IP:-192.168.1.2}"
SERIAL_0="13125051"
SERIAL_1="13294999"
LLA_HOST="169.254.0.10/16"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

if [[ ! -x "$GIGE_CONFIG" ]]; then
  echo "GigEConfig not found at $GIGE_CONFIG (install Spinnaker SDK)" >&2
  exit 1
fi

echo "=== Blackfly static IP setup (GigEConfig) ==="
echo "  host:  ${HOST_IP:-192.168.1.2} on ${ETH}"
echo "  cam_0: ${CAM_0_IP:-192.168.1.1}  (serial $SERIAL_0)"
echo "  cam_1: ${CAM_1_IP:-192.168.1.3}  (serial $SERIAL_1)"
echo ""

ip link set "$ETH" up
nmcli connection up "sensor network" 2>/dev/null || true
# Link-local lets GigEConfig / GVCP reach cameras at 169.254.x after switch reset.
ip addr add "$LLA_HOST" dev "$ETH" 2>/dev/null || true
sleep 3

echo "Cameras before config:"
"$GIGE_CONFIG" 2>&1 | grep -E "DeviceSerial|GevDeviceIP|GevPersistent" || true
echo ""

echo "Step 1: AutoForceIP (move cameras from 169.254.x onto ${HOST_IP:-192.168.1.2}/24) ..."
# USB-GigE adapters expose duplicate GEV interfaces; -a may abort on the 2nd pass
# after succeeding on the first. Treat that as non-fatal.
if ! "$GIGE_CONFIG" -a; then
  echo "WARN: GigEConfig -a exited with an error (duplicate interface is common on USB NICs)." >&2
  echo "      Continuing if any camera was forced onto ${HOST_IP%.*}.x ..." >&2
fi
sleep 5

camera_serial_visible() {
  "$GIGE_CONFIG" 2>&1 | grep -q "DeviceSerialNumber : $1"
}

set_persistent_ip() {
  local serial="$1"
  local ip="$2"
  local label="$3"
  if ! camera_serial_visible "$serial"; then
    echo "Step 2: skip $label (serial $serial not connected)"
    return 0
  fi
  echo "Step 2: persistent $label -> $ip (gateway $GATEWAY) ..."
  if ! "$GIGE_CONFIG" -s "$serial" -i "$ip" -n "$MASK" -g "$GATEWAY"; then
    echo "WARN: persistent IP failed for $label (serial $serial)" >&2
    return 0
  fi
}

set_persistent_ip "$SERIAL_0" "${CAM_0_IP:-192.168.1.1}" "cam_0"
set_persistent_ip "$SERIAL_1" "${CAM_1_IP:-192.168.1.3}" "cam_1"

echo ""
echo "Waiting for cameras on ${HOST_IP%.*}.x ..."
ip addr del "$LLA_HOST" dev "$ETH" 2>/dev/null || true
sleep 3

ok=0
for ip in "${CAM_0_IP:-192.168.1.1}" "${CAM_1_IP:-192.168.1.3}"; do
  if ping -c 2 -W 2 "$ip" >/dev/null 2>&1; then
    echo "[OK] ping $ip"
    ok=$((ok + 1))
  else
    echo "[SKIP] no ping on $ip (camera may be unplugged)" >&2
  fi
done

echo ""
echo "Cameras after config:"
"$GIGE_CONFIG" 2>&1 | grep -E "DeviceSerial|GevDeviceIP|GevPersistent" || true
echo ""
echo "arv-tool-0.8:"
arv-tool-0.8 2>/dev/null | grep -F "Blackfly" || true

if [[ "$ok" -ge 1 ]]; then
  echo ""
  echo "Ready (cam1 only is fine):"
  echo "  ~/used\\ for\\ ROAM/scripts/launch_blackfly_preview.sh cam1"
  echo "  PREVIEW=1 RECORD_CAMS=cam1 ~/used\\ for\\ ROAM/scripts/record_blackfly_ros2_bag.sh"
fi
