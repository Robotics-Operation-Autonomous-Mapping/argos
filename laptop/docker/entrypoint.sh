#!/bin/bash
set -euo pipefail

if [[ -f /workspace/config/cyclonedds.xml.template ]]; then
  envsubst '${PI_LIDAR_IP} ${PI_VIO_IP} ${LAPTOP_IP}' \
    < /workspace/config/cyclonedds.xml.template \
    > /tmp/cyclonedds.xml
  export CYCLONEDDS_URI="${CYCLONEDDS_URI:-file:///tmp/cyclonedds.xml}"
fi

OV_OUT_DIR="$(dirname "${OV_ESTIMATOR_CONFIG:-/tmp/openvins/estimator_config.yaml}")"
mkdir -p "${OV_OUT_DIR}"

OV_ESTIMATOR_TEMPLATE="${OV_ESTIMATOR_TEMPLATE:-/workspace/config/openvins/estimator_config.yaml}"
OV_IMU_CONFIG_TEMPLATE="${OV_IMU_CONFIG_TEMPLATE:-/workspace/config/openvins/kalibr_imu_chain.yaml.template}"
OV_CAM_CONFIG_TEMPLATE="${OV_CAM_CONFIG_TEMPLATE:-/workspace/config/openvins/kalibr_imucam_chain.yaml.template}"

if [[ -f "${OV_ESTIMATOR_TEMPLATE}" ]]; then
  cp "${OV_ESTIMATOR_TEMPLATE}" "${OV_OUT_DIR}/estimator_config.yaml"
  export OV_ESTIMATOR_CONFIG="${OV_OUT_DIR}/estimator_config.yaml"
fi
if [[ -f "${OV_IMU_CONFIG_TEMPLATE}" ]]; then
  envsubst '${IMU_TOPIC} ${IMU_RATE_HZ}' \
    < "${OV_IMU_CONFIG_TEMPLATE}" \
    > "${OV_OUT_DIR}/kalibr_imu_chain.yaml"
fi
if [[ -f "${OV_CAM_CONFIG_TEMPLATE}" ]]; then
  envsubst '${CAMERA_IMAGE_TOPIC} ${IMAGE_WIDTH} ${IMAGE_HEIGHT}' \
    < "${OV_CAM_CONFIG_TEMPLATE}" \
    > "${OV_OUT_DIR}/kalibr_imucam_chain.yaml"
fi

# shellcheck disable=SC1091
source /opt/ros/humble/setup.bash
if [[ -f /opt/argos_ws/install/setup.bash ]]; then
  # shellcheck disable=SC1091
  source /opt/argos_ws/install/setup.bash
else
  echo "ERROR: /opt/argos_ws/install/setup.bash missing — OpenVINS was not built into this image." >&2
  exit 1
fi

export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-42}"

exec "$@"
