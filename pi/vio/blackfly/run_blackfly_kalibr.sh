#!/usr/bin/env bash
# Run Kalibr mono intrinsics on a Blackfly rosbag.
#
# Usage:
#   ~/used\ for\ ROAM/scripts/run_blackfly_kalibr.sh
#   CALIB_ROOT=~/calib/blackfly_sub1of5 BAG_NAME=cam0_calib.bag TOPIC=/cam_0/image_raw \
#     TARGET=~/calib/checkerboard.yaml ~/used\ for\ ROAM/scripts/run_blackfly_kalibr.sh
#
# Large full-res bags OOM on ~8GB RAM (Kalibr uses cpu_count-1 workers). Use a
# lite bag: ~/calib/bag_env/bin/python ~/used\ for\ ROAM/scripts/subsample_ros1_bag.py ...
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CALIB_ROOT="${CALIB_ROOT:-}"
TARGET="${TARGET:-$HOME/calib/checkerboard.yaml}"
BAG_NAME="${BAG_NAME:-blackfly_intrinsics.bag}"
TOPIC="${TOPIC:-/cam0/image_raw}"
KALIBR_CPUS="${KALIBR_CPUS:-1}"

if [[ -z "$CALIB_ROOT" ]]; then
  CALIB_ROOT="$(ls -dt "$HOME/calib"/blackfly_* 2>/dev/null | head -1 || true)"
fi
if [[ -z "$CALIB_ROOT" || ! -f "$CALIB_ROOT/$BAG_NAME" ]]; then
  echo "Set CALIB_ROOT= to folder containing $BAG_NAME" >&2
  exit 1
fi

# Kill stray Kalibr containers from prior stuck runs.
if docker ps -q --filter ancestor=stereolabs/kalibr:kinetic 2>/dev/null | grep -q .; then
  echo "Stopping old Kalibr docker containers ..."
  docker kill $(docker ps -q --filter ancestor=stereolabs/kalibr:kinetic) >/dev/null 2>&1 || true
  sleep 2
fi

echo "Kalibr mono intrinsics"
echo "  bag:    $CALIB_ROOT/$BAG_NAME"
echo "  target: $TARGET"
echo "  cpus:   $KALIBR_CPUS (limits parallel corner extraction)"
echo ""

docker run --rm --cpus="$KALIBR_CPUS" \
  -e OMP_NUM_THREADS=1 -e OPENBLAS_NUM_THREADS=1 -e MKL_NUM_THREADS=1 \
  -v "$CALIB_ROOT:/calib" \
  -v "$TARGET:/config/target.yaml:ro" \
  stereolabs/kalibr:kinetic \
  bash -lc "$(cat <<EOF
set -e
source /opt/ros/kinetic/setup.bash
source /kalibr_workspace/devel/setup.bash
export MPLBACKEND=Agg
TARGET_PY=/kalibr_workspace/src/Kalibr/aslam_offline_calibration/kalibr/python/kalibr_common/TargetExtractor.py
# 7 parallel workers OOM on 8GB RAM with 1288x728 images — force single process.
sed -i 's/max(1,multiprocessing.cpu_count()-1)/1/' "\$TARGET_PY"
sed -i 's/if not graph.isGraphConnected():/if not graph.isGraphConnected() and len(cameraList)>1:/' \
  /kalibr_workspace/src/Kalibr/aslam_offline_calibration/kalibr/python/kalibr_calibrate_cameras
cd /calib
kalibr_calibrate_cameras \
  --bag $BAG_NAME \
  --topics $TOPIC \
  --models pinhole-radtan \
  --target /config/target.yaml \
  --mi-tol -1 \
  --dont-show-report
ls -1 /calib/camchain-* /calib/report-* /calib/results-* 2>/dev/null || true
EOF
)"

echo ""
echo "Done. Check $CALIB_ROOT for camchain-*.yaml and report-*.pdf"
