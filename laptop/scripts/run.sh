#!/usr/bin/env bash
# Run ARGOS laptop compose profiles.
# Usage:
#   ./scripts/run.sh playback [BAG_PATH]
#   ./scripts/run.sh monitor
#   ./scripts/run.sh analysis
#   ./scripts/run.sh down
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if [[ ! -f .env ]]; then
  cp ../shared/.env.example .env
  echo "Created .env — set PI_LIDAR_IP / PI_VIO_IP / LAPTOP_IP."
fi

if command -v xhost >/dev/null 2>&1; then
  xhost +local:docker >/dev/null 2>&1 || true
fi

COMPOSE=(docker compose -f docker-compose.yml)
MODE="${1:-playback}"

case "${MODE}" in
  playback)
    BAG_PATH="${2:-}"
    "${COMPOSE[@]}" --profile playback up -d playback
    if [[ -n "${BAG_PATH}" ]]; then
      echo "Playing bag: ${BAG_PATH}"
      # shellcheck disable=SC1091
      set -a; source .env; set +a
      docker compose -f docker-compose.yml run --rm --no-deps \
        -e USE_SIM_TIME=true \
        playback \
        bash -lc "ros2 bag play '${BAG_PATH}' --clock"
    else
      echo "playback up (RTABMAP + RViz + Foxglove). Play a bag with --clock, e.g.:"
      echo "  $0 playback /data/bags/session_YYYYmmdd_HHMMSS"
    fi
    ;;
  monitor)
    "${COMPOSE[@]}" --profile monitor up -d monitor
    echo "RViz monitor — same ROS_DOMAIN_ID / CycloneDDS peers as both Pis."
    ;;
  analysis)
    "${COMPOSE[@]}" --profile analysis up -d analysis
    echo "Jupyter Lab: http://localhost:8888"
    "${COMPOSE[@]}" --profile analysis logs analysis 2>&1 | head -n 40 || true
    ;;
  down|stop)
    "${COMPOSE[@]}" --profile playback --profile monitor --profile analysis down
    ;;
  *)
    echo "Usage: $0 [playback [BAG]|monitor|analysis|down]" >&2
    exit 1
    ;;
esac
