#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"

DOCKER="${DOCKER:-docker}"
IMAGE_NAME="${IMAGE_NAME:-flutter-linux-panel-arm64-cross:jammy}"
SDK_SOURCE="${SDK_SOURCE:-/opt/flutter-elinux}"
CACHE_ROOT="${CACHE_ROOT:-${ROOT_DIR}/.docker-cache/arm64}"
SDK_CACHE="${CACHE_ROOT}/flutter-elinux"
PUB_CACHE="${CACHE_ROOT}/pub-cache"
HOME_CACHE="${CACHE_ROOT}/home"
BUILD_MODE="${BUILD_MODE:-release}"
BUILD_JOBS="${BUILD_JOBS:-4}"
SKIP_PUB_GET="${SKIP_PUB_GET:-auto}"
REBUILD_IMAGE="${REBUILD_IMAGE:-0}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[ERROR] Missing command: $1"
    exit 1
  fi
}

require_cmd "${DOCKER}"
require_cmd rsync

if [ ! -x "${SDK_SOURCE}/bin/flutter-elinux" ]; then
  echo "[ERROR] flutter-elinux SDK not found: ${SDK_SOURCE}"
  echo "        Set SDK_SOURCE=/path/to/flutter-elinux"
  exit 1
fi

mkdir -p "${CACHE_ROOT}" "${PUB_CACHE}" "${HOME_CACHE}"

if [ ! -x "${SDK_CACHE}/bin/flutter-elinux" ]; then
  echo "[INFO] Copying x86_64 flutter-elinux SDK into persistent cache..."
  mkdir -p "${SDK_CACHE}"
  rsync -a --delete "${SDK_SOURCE}/" "${SDK_CACHE}/"
fi

if [ "${REBUILD_IMAGE}" = "1" ] ||
   ! "${DOCKER}" image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
  echo "[INFO] Building Docker cross-compilation image..."
  "${DOCKER}" build \
    --platform linux/amd64 \
    -t "${IMAGE_NAME}" \
    -f docker/arm64-cross/Dockerfile \
    docker/arm64-cross
fi

echo "[INFO] Normalizing ownership of generated Flutter directories..."
"${DOCKER}" run --rm \
  --platform linux/amd64 \
  -e TARGET_UID="$(id -u)" \
  -e TARGET_GID="$(id -g)" \
  -v "${ROOT_DIR}:/workspace" \
  "${IMAGE_NAME}" \
  bash -lc '
    shopt -s nullglob
    paths=(
      /workspace/.dart_tool
      /workspace/build
      /workspace/.flutter-plugins
      /workspace/.flutter-plugins-dependencies
      /workspace/*/flutter/ephemeral
    )
    for path in "${paths[@]}"; do
      if [ -e "$path" ] || [ -L "$path" ]; then
        chown -R "${TARGET_UID}:${TARGET_GID}" "$path"
      fi
    done
  '

echo "[INFO] Starting native x86_64 -> ARM64 cross build..."
"${DOCKER}" run --rm \
  --platform linux/amd64 \
  --user "$(id -u):$(id -g)" \
  -e HOME=/cache/home \
  -e PUB_CACHE=/cache/pub-cache \
  -e BUILD_MODE="${BUILD_MODE}" \
  -e BUILD_JOBS="${BUILD_JOBS}" \
  -e SKIP_PUB_GET="${SKIP_PUB_GET}" \
  -v "${ROOT_DIR}:/workspace" \
  -v "${SDK_CACHE}:/opt/flutter-elinux" \
  -v "${CACHE_ROOT}:/cache" \
  -w /workspace \
  "${IMAGE_NAME}" \
  bash docker/arm64-cross/build-in-container.sh
