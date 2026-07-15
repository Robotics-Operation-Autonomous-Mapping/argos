#!/usr/bin/env bash
# Run Pi B OpenVINS compose (preferred RTABMAP is on Pi A / lidar).
# Usage:
#   ./scripts/run.sh              # openvins + foxglove
#   ./scripts/run.sh recording    # + general session rosbag
#   ./scripts/run.sh colmap       # + Vivotek COLMAP rosbag
#   ./scripts/run.sh down | logs
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if [[ ! -f .env ]]; then
  cp ../../shared/.env.example .env
  echo "Created .env — set PI_LIDAR_IP / PI_VIO_IP / LAPTOP_IP."
fi

COMPOSE=(docker compose -f docker-compose.yml)
MODE="${1:-openvins}"

case "${MODE}" in
  openvins|slam|up)
    "${COMPOSE[@]}" up -d openvins
    # shellcheck disable=SC1091
    set -a; source .env; set +a
    echo "OpenVINS up on VIO Pi. Foxglove: ws://${PI_VIO_IP:-<PI_VIO_IP>}:${FOXGLOVE_PORT:-8765}"
    echo "Preferred RTABMAP: ../lidar/scripts/run_rtabmap_host.sh (Pi A)"
    echo "COLMAP bags: ./scripts/record_colmap.sh  (or: $0 colmap)"
    ;;
  recording|record)
    "${COMPOSE[@]}" --profile recording up -d
    echo "OpenVINS + recorder up. Bags in volume argos-vio-data → /data/bags"
    ;;
  colmap)
    "${COMPOSE[@]}" --profile colmap up -d
    echo "OpenVINS + COLMAP recorder up (Vivotek + tf/odom). Prefer ./scripts/record_colmap.sh for throttling."
    ;;
  down|stop)
    "${COMPOSE[@]}" --profile recording --profile colmap down
    ;;
  logs)
    "${COMPOSE[@]}" logs -f openvins
    ;;
  *)
    echo "Usage: $0 [openvins|recording|colmap|down|logs]" >&2
    exit 1
    ;;
esac
