#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"

PACKAGE_NAME="${PACKAGE_NAME:-flutter-linux-panel}"
PACKAGE_VERSION="${PACKAGE_VERSION:-$(sed -n "s/^version: *\([^+]*\).*/\1/p" pubspec.yaml)}"
PACKAGE_REVISION="${PACKAGE_REVISION:-1}"
PACKAGE_ARCH="arm64"
BUILD_MODE="${BUILD_MODE:-release}"
DOCKER="${DOCKER:-docker}"
IMAGE_NAME="${IMAGE_NAME:-flutter-linux-panel-arm64-cross:jammy}"
BUNDLE_DIR="${ROOT_DIR}/build/elinux/arm64/${BUILD_MODE}/bundle"
PACKAGE_ROOT="${ROOT_DIR}/build/debian/${PACKAGE_NAME}_${PACKAGE_VERSION}-${PACKAGE_REVISION}_${PACKAGE_ARCH}"
DIST_DIR="${ROOT_DIR}/build/elinux/arm64/${BUILD_MODE}/dist"
DEB_NAME="${PACKAGE_NAME}_${PACKAGE_VERSION}-${PACKAGE_REVISION}_${PACKAGE_ARCH}.deb"

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  BUILD_MODE="${BUILD_MODE}" "${ROOT_DIR}/build_arm64_docker.sh"
fi

if [ ! -x "${BUNDLE_DIR}/demo1" ]; then
  echo "[ERROR] ARM64 bundle not found: ${BUNDLE_DIR}" >&2
  exit 1
fi

rm -rf "${PACKAGE_ROOT}"
mkdir -p \
  "${PACKAGE_ROOT}/DEBIAN" \
  "${PACKAGE_ROOT}/usr/bin" \
  "${PACKAGE_ROOT}/usr/lib/flutter-linux-panel" \
  "${PACKAGE_ROOT}/lib/systemd/system" \
  "${DIST_DIR}"

cp -a "${BUNDLE_DIR}" "${PACKAGE_ROOT}/usr/lib/flutter-linux-panel/bundle"
install -m 0755 packaging/systemd-launch.sh \
  "${PACKAGE_ROOT}/usr/lib/flutter-linux-panel/systemd-launch"
install -m 0755 packaging/launcher.sh \
  "${PACKAGE_ROOT}/usr/bin/flutter-linux-panel"
install -m 0644 packaging/flutter-linux-panel.service \
  "${PACKAGE_ROOT}/lib/systemd/system/flutter-linux-panel.service"

cat > "${PACKAGE_ROOT}/DEBIAN/control" <<EOF
Package: ${PACKAGE_NAME}
Version: ${PACKAGE_VERSION}-${PACKAGE_REVISION}
Section: misc
Priority: optional
Architecture: ${PACKAGE_ARCH}
Maintainer: kozakemi
Depends: libc6, libstdc++6, libglib2.0-0, libwayland-client0, libegl1, libgles2, libgstreamer1.0-0, libgstreamer-plugins-base1.0-0, libasound2, libdbus-1-3
Recommends: bluez, iproute2, iw
Description: Flutter touch panel for ARM64 Wayland devices
 Material-themed touch panel with launchpad, media, networking and remote
 control features. Includes a root systemd service for appliance deployments.
EOF

cat > "${PACKAGE_ROOT}/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
    systemctl enable flutter-linux-panel.service >/dev/null 2>&1 || true
fi
EOF

cat > "${PACKAGE_ROOT}/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e

if [ "$1" = remove ] && command -v systemctl >/dev/null 2>&1; then
    systemctl stop flutter-linux-panel.service >/dev/null 2>&1 || true
    systemctl disable flutter-linux-panel.service >/dev/null 2>&1 || true
fi
EOF

cat > "${PACKAGE_ROOT}/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
fi
EOF

chmod 0755 \
  "${PACKAGE_ROOT}/DEBIAN/postinst" \
  "${PACKAGE_ROOT}/DEBIAN/prerm" \
  "${PACKAGE_ROOT}/DEBIAN/postrm"

"${DOCKER}" run --rm \
  --platform linux/amd64 \
  -v "${ROOT_DIR}:/workspace" \
  -w /workspace \
  "${IMAGE_NAME}" \
  dpkg-deb --root-owner-group --build \
    "/workspace/${PACKAGE_ROOT#${ROOT_DIR}/}" \
    "/workspace/${DIST_DIR#${ROOT_DIR}/}/${DEB_NAME}"

echo "[OK] Debian package: ${DIST_DIR}/${DEB_NAME}"
echo "[INFO] Install: sudo apt install ./${DEB_NAME}"
echo "[INFO] Start now: sudo systemctl start flutter-linux-panel.service"
