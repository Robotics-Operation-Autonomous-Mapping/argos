#!/bin/bash
set -euo pipefail

if [[ -f /workspace/config/cyclonedds.xml.template ]]; then
  envsubst '${PI_LIDAR_IP} ${PI_VIO_IP} ${LAPTOP_IP}' \
    < /workspace/config/cyclonedds.xml.template \
    > /tmp/cyclonedds.xml
  export CYCLONEDDS_URI="${CYCLONEDDS_URI:-file:///tmp/cyclonedds.xml}"
fi

# shellcheck disable=SC1091
source /opt/ros/humble/setup.bash
export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-42}"

exec "$@"
