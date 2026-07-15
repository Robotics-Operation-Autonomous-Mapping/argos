#!/usr/bin/env bash
# Helper: render OpenVINS YAML under /tmp/openvins from shared templates + .env
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED="$(cd "${ROOT}/../../shared" && pwd)"
cd "${ROOT}"

if [[ ! -f .env ]]; then
  cp "${SHARED}/.env.example" .env
fi
# shellcheck disable=SC1091
set -a; source .env; set +a

OUT="${1:-/tmp/openvins}"
mkdir -p "${OUT}"
cp "${SHARED}/config/openvins/estimator_config.yaml" "${OUT}/estimator_config.yaml"
envsubst '${IMU_TOPIC} ${IMU_RATE_HZ}' \
  < "${SHARED}/config/openvins/kalibr_imu_chain.yaml.template" \
  > "${OUT}/kalibr_imu_chain.yaml"
envsubst '${CAMERA_IMAGE_TOPIC} ${IMAGE_WIDTH} ${IMAGE_HEIGHT}' \
  < "${SHARED}/config/openvins/kalibr_imucam_chain.yaml.template" \
  > "${OUT}/kalibr_imucam_chain.yaml"
echo "Wrote OpenVINS configs to ${OUT}"
echo "export OV_ESTIMATOR_CONFIG=${OUT}/estimator_config.yaml"
