#!/usr/bin/env bash

set -euo pipefail

cd /workspace

BUILD_MODE="${BUILD_MODE:-release}"
BUILD_JOBS="${BUILD_JOBS:-4}"
SKIP_PUB_GET="${SKIP_PUB_GET:-auto}"
PUB_HASH_FILE="/cache/pub-input.sha256"

if [ "${BUILD_MODE}" != "release" ] && [ "${BUILD_MODE}" != "debug" ]; then
  echo "[ERROR] BUILD_MODE must be release or debug."
  exit 1
fi

export PUB_CACHE="${PUB_CACHE:-/cache/pub-cache}"
export CMAKE_BUILD_PARALLEL_LEVEL="${BUILD_JOBS}"
export NINJAFLAGS="-j${BUILD_JOBS}"
export PKG_CONFIG_LIBDIR="/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig"
export PKG_CONFIG_PATH=""
export PKG_CONFIG_SYSROOT_DIR="/"
export CC="aarch64-linux-gnu-gcc"
export CXX="aarch64-linux-gnu-g++"

CURRENT_HASH="$(
  {
    sha256sum pubspec.yaml
    if [ -f pubspec.lock ]; then sha256sum pubspec.lock; fi
  } | sha256sum | awk '{print $1}'
)"

RUN_PUB_GET=1
if [ "${SKIP_PUB_GET}" = "1" ]; then
  RUN_PUB_GET=0
elif [ "${SKIP_PUB_GET}" = "auto" ] &&
     [ -f "${PUB_HASH_FILE}" ] &&
     [ -f .dart_tool/package_config.json ] &&
     [ "$(cat "${PUB_HASH_FILE}")" = "${CURRENT_HASH}" ] &&
     grep -q 'file:///cache/pub-cache/' .dart_tool/package_config.json; then
  RUN_PUB_GET=0
fi

echo "[INFO] Native amd64 Flutter + ARM64 cross compiler"
echo "       BUILD_MODE=${BUILD_MODE}"
echo "       BUILD_JOBS=${BUILD_JOBS}"
echo "       RUN_PUB_GET=${RUN_PUB_GET}"

echo "[INFO] Verifying ARM64 pkg-config dependencies..."
for module in glib-2.0 gstreamer-1.0 gstreamer-gl-1.0 wayland-client; do
  version="$(pkg-config --modversion "${module}")"
  echo "       ${module}: ${version}"
done

if [ "${RUN_PUB_GET}" = "1" ]; then
  flutter-elinux pub get
else
  echo "[INFO] pubspec inputs unchanged; skipping pub get."
fi

STARTED_AT="${SECONDS}"
flutter-elinux build elinux \
  --target-arch=arm64 \
  --target-compiler-triple=aarch64-linux-gnu \
  --system-include-directories="/usr/aarch64-linux-gnu/include;/usr/include/aarch64-linux-gnu;/usr/include" \
  --"${BUILD_MODE}" \
  --no-pub

printf '%s\n' "${CURRENT_HASH}" > "${PUB_HASH_FILE}"

OUTPUT_DIR="build/elinux/arm64/${BUILD_MODE}/bundle"
if [ ! -d "${OUTPUT_DIR}" ]; then
  echo "[ERROR] Expected bundle was not generated: ${OUTPUT_DIR}"
  exit 1
fi

cat > "${OUTPUT_DIR}/run_in_bundle.sh" <<'EOF'
#!/bin/sh
set -eu

BUNDLE_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)

export LD_LIBRARY_PATH="$BUNDLE_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    for socket in "$XDG_RUNTIME_DIR"/wayland-*; do
        if [ -S "$socket" ]; then
            WAYLAND_DISPLAY=${socket##*/}
            export WAYLAND_DISPLAY
            break
        fi
    done
fi

exec "$BUNDLE_DIR/demo1" --bundle="$BUNDLE_DIR" "$@" --fullscreen
EOF
chmod +x "${OUTPUT_DIR}/run_in_bundle.sh"

DIST_DIR="build/elinux/arm64/${BUILD_MODE}/dist"
mkdir -p "${DIST_DIR}"
ARCHIVE="${DIST_DIR}/demo1-elinux-arm64-${BUILD_MODE}-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -czf "${ARCHIVE}" -C "$(dirname "${OUTPUT_DIR}")" "$(basename "${OUTPUT_DIR}")"

echo "[INFO] Build time: $((SECONDS - STARTED_AT)) seconds"
echo "[OK] Bundle: ${OUTPUT_DIR}"
echo "[OK] Archive: ${ARCHIVE}"
file "${OUTPUT_DIR}/demo1"
