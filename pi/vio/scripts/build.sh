#!/usr/bin/env bash
# Build lean OpenVINS image for Pi B (VIO) — no RTABMAP in the image.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

REGISTRY="${IMAGE_REGISTRY:-argos}"
TAG="${IMAGE_TAG:-latest}"
PLATFORM="${ARGOS_PI_PLATFORM:-linux/arm64}"

if [[ ! -f .env ]]; then
  echo "Note: copying shared/.env.example → .env (edit peer IPs before run)."
  cp ../../shared/.env.example .env
fi

if ! docker buildx inspect argos-builder >/dev/null 2>&1; then
  docker buildx create --name argos-builder --use
else
  docker buildx use argos-builder
fi

ARGOS_ROOT="$(cd "${ROOT}/../.." && pwd)"
echo "Building ${REGISTRY}/argos-pi-vio:${TAG} for ${PLATFORM} ..."
docker buildx build \
  --platform "${PLATFORM}" \
  -f "${ROOT}/docker/Dockerfile" \
  -t "${REGISTRY}/argos-pi-vio:${TAG}" \
  --load \
  "${ARGOS_ROOT}"

echo "Done: ${REGISTRY}/argos-pi-vio:${TAG}"
