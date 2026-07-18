#!/bin/bash
# One-time GigE tuning for sensor network (Blackfly on enx00e04cf5fd7c).
# Run with: sudo ./setup_gige_sensor_network.sh
set -euo pipefail

IFACE="${1:-enx00e04cf5fd7c}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0 [interface]" >&2
  exit 1
fi

if ! ip link show "${IFACE}" >/dev/null 2>&1; then
  echo "Interface ${IFACE} not found" >&2
  exit 1
fi

echo "Tuning GigE interface: ${IFACE}"

# Socket buffers + RX ring only. Do not run gev_nettweak — it forces MTU 9216, which
# often breaks USB-GigE adapters and causes blank SpinView / INCOMPLETE frames.
sysctl -w net.core.rmem_max=33554432 >/dev/null
sysctl -w net.core.rmem_default=33554432 >/dev/null
sysctl -w net.core.netdev_max_backlog=30000 >/dev/null

# Increase NIC RX ring (default 100 is too small for GigE Vision bursts)
if ethtool -g "${IFACE}" >/dev/null 2>&1; then
  max_rx=$(ethtool -g "${IFACE}" 2>/dev/null | awk '/Pre-set maximums/ {getline; print $2}')
  if [[ -n "${max_rx}" && "${max_rx}" != "n/a" ]]; then
    ethtool -G "${IFACE}" rx "${max_rx}" || true
    echo "RX ring set to ${max_rx}"
  fi
fi

# Standard MTU is most reliable on USB-GigE adapters
ip link set "${IFACE}" mtu 1500

# Persist NM profile to match (run as normal user after this script)
echo ""
echo "Done. Recommended follow-up (no sudo):"
echo "  nmcli connection modify 'sensor network' 802-3-ethernet.mtu 1500"
echo "  nmcli connection modify 'sensor network' ipv4.addresses 192.168.1.2/24"
echo "  nmcli connection up 'sensor network'"
echo ""
echo "In SpinView set Transport Layer Control -> GevSCPS Packet Size = 1500"
echo "Close SpinView, then launch:"
echo "  ros2 launch spinnaker_camera_driver blackfly_pge_09s2c_launch.py"
