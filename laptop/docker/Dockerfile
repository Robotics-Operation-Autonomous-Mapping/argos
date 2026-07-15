# ARGOS laptop — OpenVINS + RTABMAP + RViz + Foxglove + Jupyter (linux/amd64)
# Build from argos/ root (see docker-compose.yml context).
# COLMAP / CloudCompare stay host-only.
ARG BASE_IMAGE=ros:humble-desktop
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive \
    RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
    ROS_DOMAIN_ID=42 \
    ARGOS_WS=/opt/argos_ws \
    ARGOS_BUILD_JOBS=4 \
    ARGOS_INCLUDE_RTABMAP=1 \
    ARGOS_EXTRA_APT="ros-humble-rviz2"

LABEL org.opencontainers.image.title="argos-laptop" \
      org.opencontainers.image.description="ARGOS laptop: OpenVINS + RTABMAP + RViz2 + Jupyter" \
      org.opencontainers.image.source="https://github.com/argos/argos"

COPY shared/scripts/install_openvins.sh /tmp/install_openvins.sh
RUN chmod +x /tmp/install_openvins.sh \
    && /tmp/install_openvins.sh \
    && rm -f /tmp/install_openvins.sh

RUN pip3 install --no-cache-dir \
      numpy \
      pandas \
      matplotlib \
      jupyterlab

WORKDIR /workspace
COPY laptop/docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/data"]

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
