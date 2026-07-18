#!/bin/bash
# GigE diagnostic for BFLY-PGE cameras on sensor network.
set -u

IFACE="${1:-enx00e04cf5fd7c}"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
bad() { echo -e "${RED}[FAIL]${NC} $*"; }

echo "=== GigE sensor network diagnostic ==="
echo ""

if ip link show "${IFACE}" >/dev/null 2>&1; then
  mtu=$(ip link show "${IFACE}" | awk '/mtu/ {print $5}')
  ipaddr=$(ip -br addr show "${IFACE}" | awk '{print $3}')
  ok "Interface ${IFACE}: IP ${ipaddr:-none}, MTU ${mtu}"
  speed=$(ethtool "${IFACE}" 2>/dev/null | awk '/Speed:/ {print $2}')
  driver=$(ethtool -i "${IFACE}" 2>/dev/null | awk '/driver:/ {print $2}')
  echo "     Driver: ${driver:-unknown}, Link: ${speed:-unknown}"
  if [[ "${driver}" == "cdc_ncm" || "${driver}" == "cdc_ether" ]]; then
    bad "Wrong USB ethernet driver (${driver}). GigE Vision needs r8152."
    echo "     Fix: install Realtek udev rules, replug adapter."
  elif [[ "${driver}" == "r8152" ]]; then
    warn "USB Realtek r8152 adapter — works for ping but often drops GigE Vision frames."
    echo "     If streaming fails, use a PCIe Intel GigE NIC or industrial PoE switch."
  fi
  rx=$(ethtool -g "${IFACE}" 2>/dev/null | awk '/Current hardware settings/ {getline; print $2}')
  if [[ -n "${rx}" && "${rx}" -lt 512 ]]; then
    bad "RX ring too small (${rx}). Run: sudo ros2 run spinnaker_camera_driver reset_sensor_network.sh"
  else
    ok "RX ring: ${rx:-unknown}"
  fi
else
  bad "Interface ${IFACE} not found. Is sensor network cable plugged in?"
fi

echo ""
if pgrep -f SpinView_QT >/dev/null; then
  warn "SpinView is running — close it before running Spinnaker test examples."
else
  ok "SpinView not running"
fi

echo ""
echo "=== Cameras ==="
ENUM_OUT=$(printf '\n' | timeout 20 /opt/spinnaker/bin/Enumeration 2>&1 || true)
count=$(echo "${ENUM_OUT}" | grep -m1 '^Number of cameras detected:' | awk '{print $NF}')
if [[ "${count:-0}" == "0" ]]; then
  bad "No cameras detected."
  echo "     Check PoE power, ethernet cable, and that sensor network is active."
else
  ok "Cameras detected: ${count}"
  echo "${ENUM_OUT}" | grep -E '^\tDevice [0-9]+ ' | sed 's/^\t/  /'
fi

echo ""
if [[ "${count:-0}" != "0" ]] && ! pgrep -f SpinView_QT >/dev/null; then
  echo "=== Stream test (10 frames) ==="
  ACQ_OUT=$(printf '\n' | timeout 20 /opt/spinnaker/bin/Acquisition 2>&1 || true)
  inc=$(echo "${ACQ_OUT}" | grep -ci "incomplete" || true)
  if [[ "${inc}" -gt 5 ]]; then
    bad "Spinnaker Acquisition: ${inc} incomplete frames — packets are being lost."
    echo ""
    echo "  Try in SpinView (after closing/reopening):"
    echo "    1. Transport Layer -> GevSCPS Packet Size = 1500"
    echo "    2. Device Control -> Device Link Throughput Limit = 50000000 (50 Mbps)"
    echo "    3. Acquisition -> Exposure Auto = Continuous"
    echo "    4. Click Start Acquisition (green play)"
    echo "    5. Point camera at a bright scene; remove lens cap"
  elif [[ "${inc}" -gt 0 ]]; then
    warn "Some incomplete frames (${inc}) — reduce throughput or fix adapter."
  else
    ok "Acquisition test passed with no incomplete frame errors."
  fi
fi

echo ""
echo "=== Your other FLIR cameras vs these ==="
echo "  cam0/cam1 setup = Blackfly S over USB3 (direct) — easy, no IP tuning."
echo "  BFLY-PGE        = legacy GigE over Ethernet — needs stable NIC + PoE + tuning."
echo ""
echo "=== If SpinView window is open but black ==="
echo "  - Click Start Acquisition (not just select the camera in the list)"
echo "  - Check frame counter is increasing (bottom status bar)"
echo "  - Increase exposure or enable Exposure Auto"
echo "  - Save settings after fixing: User Set 0"
