#!/usr/bin/env bash
# Pi A (lidar): prepare DDS env and run host lidar bringup stub.
# Preferred mapper: ./scripts/run_rtabmap_host.sh (after driver is publishing /scan).
# Usage:
#   ./scripts/run.sh              # host stub launch (static TF + instructions)
#   ./scripts/run.sh rtabmap      # native RTABMAP (odom from Pi B + local scan)
#   ./scripts/run.sh foxglove     # optional foxglove compose profile
#   ./scripts/run.sh build        # build optional lean foxglove image
#   ./scripts/run.sh down
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED="$(cd "${ROOT}/../../shared" && pwd)"
cd "${ROOT}"

if [[ ! -f .env ]]; then
  cp "${SHARED}/.env.example" .env
  echo "Created .env — set PI_LIDAR_IP / PI_VIO_IP / LAPTOP_IP."
fi
# shellcheck disable=SC1091
set -a; source .env; set +a

MODE="${1:-host}"

case "${MODE}" in
  host|up)
    # shellcheck disable=SC1091
    source /opt/ros/humble/setup.bash
    if command -v envsubst >/dev/null 2>&1; then
      "${SHARED}/scripts/render_cyclonedds.sh" .env /tmp/cyclonedds.xml
      export CYCLONEDDS_URI=file:///tmp/cyclonedds.xml
    fi
    export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"
    export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-42}"
    echo "Lidar Pi on domain ${ROS_DOMAIN_ID}. Publish ${LIDAR_SCAN_TOPIC:-/scan}."
    echo "Then: ./scripts/run_rtabmap_host.sh  (preferred RTABMAP host)"
    echo "Chrony: ${SHARED}/scripts/setup_chrony.sh"
    exec ros2 launch "${ROOT}/launch/lidar_bringup.launch.py"
    ;;
  rtabmap|map)
    exec "${ROOT}/scripts/run_rtabmap_host.sh"
    ;;
  build)
    if ! docker buildx inspect argos-builder >/dev/null 2>&1; then
      docker buildx create --name argos-builder --use
    else
      docker buildx use argos-builder
    fi
    ARGOS_ROOT="$(cd "${ROOT}/../.." && pwd)"
    docker buildx build --platform linux/arm64 \
      -f "${ROOT}/docker/Dockerfile" \
      -t "${IMAGE_REGISTRY:-argos}/argos-pi-lidar:${IMAGE_TAG:-latest}" \
      --load "${ARGOS_ROOT}"
    ;;
  foxglove)
    docker compose --profile foxglove up -d foxglove
    echo "Foxglove: ws://${PI_LIDAR_IP:-<PI_LIDAR_IP>}:${FOXGLOVE_PORT:-8765}"
    echo "Whitelist odom/map/scan — not raw multi-cam streams."
    ;;
  down|stop)
    docker compose --profile foxglove down || true
    ;;
  *)
    echo "Usage: $0 [host|rtabmap|build|foxglove|down]" >&2
    exit 1
    ;;
esac
