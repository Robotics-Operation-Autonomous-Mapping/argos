#!/bin/bash
# Reset sensor network to stable GigE settings for USB ethernet adapters.
# Use when SpinView is blank or ROS shows INCOMPLETE: 100.
#
# Run: sudo ros2 run spinnaker_camera_driver reset_sensor_network.sh
set -euo pipefail

IFACE="${1:-enx00e04cf5fd7c}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0 [interface]" >&2
  exit 1
fi

echo "Resetting GigE interface ${IFACE} to standard (MTU 1500) settings..."

# Socket buffers (safe on all setups)
sysctl -w net.core.rmem_max=33554432 >/dev/null
sysctl -w net.core.rmem_default=33554432 >/dev/null
sysctl -w net.core.netdev_max_backlog=30000 >/dev/null

# Large RX ring helps GigE Vision bursts
if ethtool -g "${IFACE}" >/dev/null 2>&1; then
  max_rx=$(ethtool -g "${IFACE}" 2>/dev/null | awk '/Pre-set maximums/ {getline; print $2}')
  if [[ -n "${max_rx}" && "${max_rx}" != "n/a" ]]; then
    ethtool -G "${IFACE}" rx "${max_rx}" || true
    echo "RX ring: ${max_rx}"
  fi
fi

# Do NOT use jumbo MTU on USB-GigE adapters — gev_nettweak sets 9216 and often breaks streaming
ip link set "${IFACE}" mtu 1500
echo "MTU: 1500"

echo ""
echo "Next steps (no sudo):"
echo "  1. Close SpinView completely"
echo "  2. nmcli connection up 'sensor network'"
echo "  3. Test ONE camera at a time on the sensor port"
echo "  4. Open SpinView, pick your camera, set GevSCPS Packet Size = 1500"
echo "  5. Start acquisition and adjust exposure if the image is dark"
