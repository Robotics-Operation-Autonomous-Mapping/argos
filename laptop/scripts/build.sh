#!/usr/bin/env bash
# Build ARGOS laptop image (linux/amd64) with buildx.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARGOS_ROOT="$(cd "${ROOT}/.." && pwd)"
cd "${ROOT}"

REGISTRY="${IMAGE_REGISTRY:-argos}"
TAG="${IMAGE_TAG:-latest}"
PLATFORM="${ARGOS_LAPTOP_PLATFORM:-linux/amd64}"

if [[ ! -f .env ]]; then
  echo "Note: copying shared/.env.example → .env"
  cp ../shared/.env.example .env
fi

if ! docker buildx inspect argos-builder >/dev/null 2>&1; then
  docker buildx create --name argos-builder --use
else
  docker buildx use argos-builder
fi

echo "Building ${REGISTRY}/argos-laptop:${TAG} for ${PLATFORM} ..."
docker buildx build \
  --platform "${PLATFORM}" \
  -f "${ROOT}/docker/Dockerfile" \
  -t "${REGISTRY}/argos-laptop:${TAG}" \
  --load \
  "${ARGOS_ROOT}"

echo "Done: ${REGISTRY}/argos-laptop:${TAG}"
