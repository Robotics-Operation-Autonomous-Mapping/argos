#!/bin/bash
# Lean OpenVINS install for ARGOS Pi VIO image / reusable by native script.
# NO RTABMAP, NO VINS-Fusion, NO Ceres-from-source (apt libceres-dev is enough).
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
NPROC="${ARGOS_BUILD_JOBS:-$(nproc)}"
INCLUDE_RTABMAP="${ARGOS_INCLUDE_RTABMAP:-0}"

echo "==> Installing ROS / system dependencies (OpenVINS)"
apt-get update
apt-get install -y --no-install-recommends \
  build-essential \
  cmake \
  git \
  wget \
  curl \
  ca-certificates \
  gettext-base \
  pkg-config \
  libeigen3-dev \
  libboost-all-dev \
  libopencv-dev \
  libceres-dev \
  libomp-dev \
  python3-pip \
  python3-colcon-common-extensions \
  ros-humble-rmw-cyclonedds-cpp \
  ros-humble-robot-state-publisher \
  ros-humble-tf2-ros \
  ros-humble-tf2-tools \
  ros-humble-cv-bridge \
  ros-humble-image-transport \
  ros-humble-image-transport-plugins \
  ros-humble-camera-info-manager \
  ros-humble-vision-opencv \
  ros-humble-rosbag2 \
  ros-humble-rosbag2-storage-mcap \
  ros-humble-foxglove-bridge \
  ros-humble-v4l2-camera \
  ros-humble-topic-tools \
  ros-humble-launch \
  ros-humble-launch-ros \
  ros-humble-nav-msgs \
  ros-humble-sensor-msgs \
  ros-humble-geometry-msgs

if [[ "${INCLUDE_RTABMAP}" == "1" ]]; then
  apt-get install -y --no-install-recommends ros-humble-rtabmap-ros
fi

# Optional extras (laptop passes ARGOS_EXTRA_APT)
if [[ -n "${ARGOS_EXTRA_APT:-}" ]]; then
  # shellcheck disable=SC2086
  apt-get install -y --no-install-recommends ${ARGOS_EXTRA_APT}
fi

rm -rf /var/lib/apt/lists/*

echo "==> Cloning OpenVINS (rpng/open_vins)"
mkdir -p /opt/argos_ws/src
cd /opt/argos_ws/src
if [[ ! -d open_vins/.git ]]; then
  git clone --depth 1 https://github.com/rpng/open_vins.git open_vins
fi

echo "==> colcon build OpenVINS into /opt/argos_ws"
# shellcheck disable=SC1091
source /opt/ros/humble/setup.bash
cd /opt/argos_ws
# Source tree is src/open_vins/{ov_core,ov_msckf,...} — colcon finds nested packages.
colcon build \
  --symlink-install \
  --cmake-args -DCMAKE_BUILD_TYPE=Release \
  --packages-up-to ov_msckf \
  --parallel-workers "${NPROC}"

if ! find /opt/argos_ws/install -type f -name 'run_subscribe_msckf' | grep -q .; then
  echo "ERROR: run_subscribe_msckf not found after colcon build" >&2
  exit 1
fi

echo "==> OpenVINS install OK"
rm -rf /opt/argos_ws/build /opt/argos_ws/log
