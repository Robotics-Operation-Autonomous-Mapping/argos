# ARGOS — Pi A (lidar) optional lean image: Foxglove + CycloneDDS helpers only.
# Build from argos/ root (see docker-compose.yml context).
ARG BASE_IMAGE=ros:humble-ros-base
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive \
    RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
    ROS_DOMAIN_ID=42

RUN apt-get update && apt-get install -y --no-install-recommends \
      gettext-base \
      ros-humble-rmw-cyclonedds-cpp \
      ros-humble-foxglove-bridge \
      ros-humble-tf2-ros \
      ros-humble-launch \
      ros-humble-launch-ros \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
COPY pi/lidar/docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
