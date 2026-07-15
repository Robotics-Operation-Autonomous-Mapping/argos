# ARGOS — Pi B (cams+IMU) OpenVINS image (linux/arm64)
# Build from argos/ root (see docker-compose.yml context).
# Lean: OpenVINS + CycloneDDS + Foxglove + rosbag2. NO RTABMAP in image.
ARG BASE_IMAGE=ros:humble-ros-base
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive \
    RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
    ROS_DOMAIN_ID=42 \
    ARGOS_WS=/opt/argos_ws \
    ARGOS_BUILD_JOBS=2 \
    ARGOS_INCLUDE_RTABMAP=0

LABEL org.opencontainers.image.title="argos-pi-vio" \
      org.opencontainers.image.description="ARGOS VIO Pi: OpenVINS (no RTABMAP in image)" \
      org.opencontainers.image.source="https://github.com/argos/argos"

COPY shared/scripts/install_openvins.sh /tmp/install_openvins.sh
RUN chmod +x /tmp/install_openvins.sh \
    && /tmp/install_openvins.sh \
    && rm -f /tmp/install_openvins.sh

WORKDIR /workspace
COPY pi/vio/docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/data"]

ENTRYPOINT ["/entrypoint.sh"]
CMD ["ros2", "launch", "/workspace/launch/openvins.launch.py"]
