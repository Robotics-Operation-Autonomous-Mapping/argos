#!/usr/bin/env bash
# Shared Aravis camera setup — source after blackfly_camera.conf
set -euo pipefail

blackfly_aravis_setup_network() {
  if [[ -z "${ETH:-}" ]]; then
    echo "Set ETH= in blackfly_camera.conf (ip -br link)." >&2
    return 1
  fi

  sudo ip link set "$ETH" up
  if [[ -n "${LINK_LOCAL:-}" ]]; then
    sudo ip addr add "$LINK_LOCAL" dev "$ETH" 2>/dev/null || true
  fi

  pkill -9 -f gst-launch 2>/dev/null || true
  pkill -f aravis_ros2_publisher 2>/dev/null || true
  sleep 2

  sudo sysctl -w net.core.rmem_max=26214400 >/dev/null
  sudo sysctl -w net.core.rmem_default=26214400 >/dev/null
}

blackfly_camera_ip_for() {
  local which="$1"
  case "$which" in
    cam0|0) echo "${CAM_0_IP:-192.168.1.1}" ;;
    cam1|1) echo "${CAM_1_IP:-192.168.1.3}" ;;
    *) echo "" ;;
  esac
}

blackfly_camera_check_network() {
  local cam="$1"
  local which="${2:-}"
  local expected_ip
  if [[ -n "$which" ]]; then
    expected_ip="$(blackfly_camera_ip_for "$which")"
  fi

  if ! arv-tool-0.8 2>/dev/null | grep -qF "$cam"; then
    echo "Camera not found: $cam" >&2
    echo "Check PoE, sensor network, and static IPs:" >&2
    echo "  sudo ~/used\\ for\\ ROAM/scripts/setup_blackfly_static_ips.sh" >&2
    return 1
  fi

  if [[ -n "$expected_ip" ]] && ! ping -c 1 -W 1 "$expected_ip" >/dev/null 2>&1; then
    local actual_ip
    actual_ip="$(arv-tool-0.8 2>/dev/null | grep -F "$cam" | sed -n 's/.*(\(.*\)).*/\1/p')"
    echo "WARN: $cam expected at $expected_ip but not reachable." >&2
    if [[ -n "$actual_ip" && "$actual_ip" != "$expected_ip" ]]; then
      echo "      Aravis sees it at $actual_ip (link-local after switch/reset?)." >&2
      if ping -c 1 -W 1 "$actual_ip" >/dev/null 2>&1; then
        echo "      Continuing — camera reachable at $actual_ip." >&2
        echo "      To restore static IP: sudo ~/used\\ for\\ ROAM/scripts/setup_blackfly_static_ips.sh" >&2
        return 0
      fi
      echo "      Run: sudo ~/used\\ for\\ ROAM/scripts/setup_blackfly_static_ips.sh" >&2
      echo "      White/blank preview usually means wrong subnet — fix IP first." >&2
    fi
    return 1
  fi
}

blackfly_aravis_setup_cam() {
  local cam="$1"
  local pixel_format="${2:-BayerRG8}"
  local which=""
  [[ "$cam" == "${CAM_0:-}" ]] && which=cam0
  [[ "$cam" == "${CAM_1:-}" ]] && which=cam1

  if ! blackfly_camera_check_network "$cam" "$which"; then
    return 1
  fi

  if [[ "${MINIMAL_SETUP:-0}" == "1" ]]; then
    arv-tool-0.8 -n "$cam" control UserSetSelector=Default UserSetLoad=1
    arv-tool-0.8 -n "$cam" control GevSCPSPacketSize="$PACKET_SIZE"
    arv-tool-0.8 -n "$cam" control TriggerMode=Off
    arv-tool-0.8 -n "$cam" control TestImageSelector=Off
    return 0
  fi

  arv-tool-0.8 -n "$cam" control GevSCPSPacketSize="$PACKET_SIZE"
  arv-tool-0.8 -n "$cam" control GevSCPSDoNotFragment=false
  arv-tool-0.8 -n "$cam" control PixelFormat="$pixel_format"
  arv-tool-0.8 -n "$cam" control TriggerMode=Off
  arv-tool-0.8 -n "$cam" control ExposureMode=Timed
  arv-tool-0.8 -n "$cam" control ExposureAuto=Off
  arv-tool-0.8 -n "$cam" control GainAuto=Off
  arv-tool-0.8 -n "$cam" control AcquisitionMode=Continuous

  if [[ "$pixel_format" == "Mono8" ]]; then
    arv-tool-0.8 -n "$cam" control TestImageSelector=Off
    arv-tool-0.8 -n "$cam" control "ExposureTime=${CAM_1_EXPOSURE_US:-10000}"
    arv-tool-0.8 -n "$cam" control "Gain=${CAM_1_GAIN_DB:-0}"
  else
    arv-tool-0.8 -n "$cam" control BalanceWhiteAuto=Off
    arv-tool-0.8 -n "$cam" control BalanceRatioSelector=Blue
    arv-tool-0.8 -n "$cam" control BalanceRatio="$BALANCE_BLUE"
    arv-tool-0.8 -n "$cam" control BalanceRatioSelector=Red
    arv-tool-0.8 -n "$cam" control BalanceRatio="$BALANCE_RED"
    arv-tool-0.8 -n "$cam" control Saturation="$CAM_SATURATION"
    arv-tool-0.8 -n "$cam" control ExposureAuto=Continuous
    arv-tool-0.8 -n "$cam" control GainAuto=Continuous
  fi

  if [[ "${LOW_BANDWIDTH:-0}" == "1" ]]; then
    arv-tool-0.8 -n "$cam" control Width=640
    arv-tool-0.8 -n "$cam" control Height=480
  else
    arv-tool-0.8 -n "$cam" control Width=1288
    arv-tool-0.8 -n "$cam" control Height=728
  fi
}

# Setup one camera (legacy: uses $CAM)
blackfly_aravis_setup() {
  blackfly_aravis_setup_network
  local pixel_format="${CAM_PIXEL_FORMAT:-$CAM_0_PIXEL_FORMAT}"
  if [[ "$CAM" == "$CAM_1" ]]; then
    pixel_format="${CAM_1_PIXEL_FORMAT}"
  fi
  blackfly_aravis_setup_cam "$CAM" "$pixel_format"
}

# Setup cam0 + cam1 on the sensor network
blackfly_aravis_setup_dual() {
  blackfly_aravis_setup_network
  blackfly_aravis_setup_cam "$CAM_0" "$CAM_0_PIXEL_FORMAT"
  blackfly_aravis_setup_cam "$CAM_1" "$CAM_1_PIXEL_FORMAT"
}

blackfly_gst_color_pipeline() {
  local cam="$1"
  echo "aravissrc camera-name=\"$cam\" packet-size=$GST_PACKET_SIZE auto-packet-size=false ! bayer2rgb ! videoconvert ! videobalance saturation=$GST_SATURATION hue=$GST_HUE ! autovideosink sync=false"
}

blackfly_gst_mono_pipeline() {
  local cam="$1"
  echo "aravissrc camera-name=\"$cam\" packet-size=$GST_PACKET_SIZE auto-packet-size=false ! videoconvert ! autovideosink sync=false"
}
