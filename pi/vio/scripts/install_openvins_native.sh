#!/usr/bin/env bash
# Build OpenVINS natively on Pi B (system ROS Humble). Prefer this if you
# already run host RTABMAP and want fewer containers.
# Usage: ./scripts/install_openvins_native.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WS="${ARGOS_NATIVE_WS:-$HOME/argos_ws}"
NPROC="${ARGOS_BUILD_JOBS:-2}"

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  build-essential cmake git gettext-base \
  libeigen3-dev libboost-all-dev libopencv-dev libceres-dev libomp-dev \
  python3-colcon-common-extensions \
  ros-humble-rmw-cyclonedds-cpp \
  ros-humble-cv-bridge ros-humble-tf2-ros \
  ros-humble-foxglove-bridge \
  ros-humble-rosbag2 ros-humble-rosbag2-storage-mcap

mkdir -p "${WS}/src"
cd "${WS}/src"
if [[ ! -d open_vins/.git ]]; then
  git clone --depth 1 https://github.com/rpng/open_vins.git open_vins
fi

# shellcheck disable=SC1091
source /opt/ros/humble/setup.bash
cd "${WS}"
colcon build \
  --symlink-install \
  --cmake-args -DCMAKE_BUILD_TYPE=Release \
  --packages-up-to ov_msckf \
  --parallel-workers "${NPROC}"

if ! find "${WS}/install" -type f -name 'run_subscribe_msckf' | grep -q .; then
  echo "ERROR: run_subscribe_msckf missing after build" >&2
  exit 1
fi

echo "OpenVINS OK. Source: source ${WS}/install/setup.bash"
echo "Render DDS: ${ROOT}/../../shared/scripts/render_cyclonedds.sh"
echo "Launch example:"
echo "  ros2 run ov_msckf run_subscribe_msckf --ros-args -p config_path:=/tmp/openvins/estimator_config.yaml -p use_stereo:=false -p max_cameras:=1"
