#!/usr/bin/env bash

set -euo pipefail

# First/full build:
#   ./build_arm64_chroot.sh
#
# Subsequent incremental release build:
#   FAST_BUILD=1 ./build_arm64_chroot.sh
#
# Fast development build (skips AOT optimization):
#   FAST_BUILD=1 BUILD_MODE=debug ./build_arm64_chroot.sh
#
# Tune QEMU compiler concurrency when the host is memory constrained:
#   FAST_BUILD=1 BUILD_JOBS=2 ./build_arm64_chroot.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"

ROOTFS_IMG="${ROOTFS_IMG:-/mnt/rockdev/rootfs.img}"
CHROOT_MNT="${CHROOT_MNT:-/mnt/rockdev-rootfs}"
QEMU_STATIC="${QEMU_STATIC:-/usr/bin/qemu-aarch64-static}"
PROJECT_IN_CHROOT="${PROJECT_IN_CHROOT:-/home/kozakemi/git/flutter_linux_panel}"
WORK_CACHE_DIR="${ROOT_DIR}/.cache/chroot"
SDK_CACHE_DIR="${WORK_CACHE_DIR}/flutter-sdk"
PUB_CACHE_DIR="${WORK_CACHE_DIR}/pub-cache"
TMP_CACHE_DIR="${WORK_CACHE_DIR}/tmp"
APT_CACHE_DIR="${WORK_CACHE_DIR}/apt-cache"
APT_LISTS_DIR="${WORK_CACHE_DIR}/apt-lists"
RESOLV_CACHE="${WORK_CACHE_DIR}/resolv.conf"
FAST_BUILD="${FAST_BUILD:-0}"
BUILD_MODE="${BUILD_MODE:-release}"
BUILD_JOBS="${BUILD_JOBS:-}"
VERBOSE_BUILD="${VERBOSE_BUILD:-}"
SKIP_PUB_GET="${SKIP_PUB_GET:-auto}"

if [ "${FAST_BUILD}" = "1" ]; then
  INSTALL_DEPS="${INSTALL_DEPS:-0}"
  FREE_IMAGE_SPACE="${FREE_IMAGE_SPACE:-0}"
  VERBOSE_BUILD="${VERBOSE_BUILD:-0}"
else
  INSTALL_DEPS="${INSTALL_DEPS:-1}"
  FREE_IMAGE_SPACE="${FREE_IMAGE_SPACE:-1}"
  VERBOSE_BUILD="${VERBOSE_BUILD:-1}"
fi

if [ "${BUILD_MODE}" != "release" ] && [ "${BUILD_MODE}" != "debug" ]; then
  echo "[ERROR] BUILD_MODE must be release or debug."
  exit 1
fi

if [ -z "${BUILD_JOBS}" ]; then
  HOST_JOBS="$(nproc)"
  if [ "${HOST_JOBS}" -gt 4 ]; then
    BUILD_JOBS=4
  else
    BUILD_JOBS="${HOST_JOBS}"
  fi
fi

PUB_INPUT_HASH_FILE="${WORK_CACHE_DIR}/pub-input.sha256"
CURRENT_PUB_INPUT_HASH="$(
  {
    sha256sum "${ROOT_DIR}/pubspec.yaml"
    if [ -f "${ROOT_DIR}/pubspec.lock" ]; then
      sha256sum "${ROOT_DIR}/pubspec.lock"
    fi
  } | sha256sum | awk '{print $1}'
)"
RUN_PUB_GET=1
if [ "${SKIP_PUB_GET}" = "1" ]; then
  RUN_PUB_GET=0
elif [ "${SKIP_PUB_GET}" = "auto" ] &&
     [ -f "${PUB_INPUT_HASH_FILE}" ] &&
     [ -f "${ROOT_DIR}/.dart_tool/package_config.json" ] &&
     [ "$(cat "${PUB_INPUT_HASH_FILE}")" = "${CURRENT_PUB_INPUT_HASH}" ]; then
  RUN_PUB_GET=0
fi

BUILD_VERBOSITY_FLAG=""
if [ "${VERBOSE_BUILD}" = "1" ]; then
  BUILD_VERBOSITY_FLAG="--verbose"
fi

BUILD_STARTED_AT="${SECONDS}"
echo "[INFO] Build configuration:"
echo "       FAST_BUILD=${FAST_BUILD}"
echo "       BUILD_MODE=${BUILD_MODE}"
echo "       BUILD_JOBS=${BUILD_JOBS}"
echo "       RUN_PUB_GET=${RUN_PUB_GET}"
echo "       VERBOSE_BUILD=${VERBOSE_BUILD}"

# Packages required by audioplayers_elinux / video_player_elinux and build tools.
CHROOT_APT_PACKAGES=(
  pkg-config
  cmake
  ninja-build
  build-essential
  libglib2.0-dev
  libgstreamer1.0-dev
  libgstreamer-plugins-base1.0-dev
  libgstreamer-gl1.0-0
)

SUDO="${SUDO:-sudo}"

cleanup() {
  set +e
  for path in \
    "${CHROOT_MNT}/etc/resolv.conf" \
    "${CHROOT_MNT}${PROJECT_IN_CHROOT}" \
    "${CHROOT_MNT}/opt/flutter-elinux/flutter" \
    "${CHROOT_MNT}/root/.pub-cache" \
    "${CHROOT_MNT}/tmp" \
    "${CHROOT_MNT}/var/cache/apt" \
    "${CHROOT_MNT}/var/lib/apt/lists" \
    "${CHROOT_MNT}/dev/pts" \
    "${CHROOT_MNT}/dev" \
    "${CHROOT_MNT}/proc" \
    "${CHROOT_MNT}/sys"
  do
    if mountpoint -q "${path}"; then
      ${SUDO} umount -l "${path}" >/dev/null 2>&1 || true
    fi
  done

  if mountpoint -q "${CHROOT_MNT}"; then
    ${SUDO} umount -l "${CHROOT_MNT}" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "[ERROR] Missing command: ${cmd}"
    exit 1
  fi
}

require_cmd "${SUDO}"
require_cmd mount
require_cmd chroot
require_cmd rsync

if [ ! -f "${ROOTFS_IMG}" ]; then
  echo "[ERROR] rootfs image not found: ${ROOTFS_IMG}"
  echo "        Put the board rootfs image back, or set ROOTFS_IMG=/path/to/rootfs.img"
  exit 1
fi

if [ ! -x "${QEMU_STATIC}" ]; then
  echo "[ERROR] qemu static binary not found: ${QEMU_STATIC}"
  echo "        Please install: qemu-user-static qemu-user-static-binfmt"
  exit 1
fi

mkdir -p \
  "${WORK_CACHE_DIR}" \
  "${SDK_CACHE_DIR}" \
  "${PUB_CACHE_DIR}" \
  "${TMP_CACHE_DIR}" \
  "${APT_CACHE_DIR}" \
  "${APT_LISTS_DIR}"

# Host-side regular resolv.conf used for bind mount (never write into full image).
if [ -e /etc/resolv.conf ] || [ -L /etc/resolv.conf ]; then
  cp --remove-destination /etc/resolv.conf "${RESOLV_CACHE}"
else
  printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > "${RESOLV_CACHE}"
fi

echo "[INFO] Mounting rootfs image..."
${SUDO} mkdir -p "${CHROOT_MNT}"
cleanup
${SUDO} mount -o loop "${ROOTFS_IMG}" "${CHROOT_MNT}"

echo "[INFO] Preparing writable cache directories..."
if [ ! -f "${SDK_CACHE_DIR}/bin/flutter" ]; then
  echo "[INFO] Syncing flutter SDK from image to project cache..."
  ${SUDO} rsync -a "${CHROOT_MNT}/opt/flutter-elinux/flutter/" "${SDK_CACHE_DIR}/"
  ${SUDO} chown -R "$(id -u):$(id -g)" "${SDK_CACHE_DIR}"
fi

if [ "${FREE_IMAGE_SPACE}" = "1" ]; then
  echo "[INFO] Freeing duplicated data inside rootfs image..."
  # These paths are bind-mounted from project cache during build.
  if [ -d "${CHROOT_MNT}/opt/flutter-elinux/flutter" ]; then
    ${SUDO} find "${CHROOT_MNT}/opt/flutter-elinux/flutter" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  fi
  if [ -d "${CHROOT_MNT}/root/.pub-cache" ]; then
    ${SUDO} find "${CHROOT_MNT}/root/.pub-cache" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  fi
  ${SUDO} rm -rf \
    "${CHROOT_MNT}/var/cache/apt/"* \
    "${CHROOT_MNT}/var/lib/apt/lists/"* \
    "${CHROOT_MNT}/tmp/"* \
    2>/dev/null || true
  df -h "${CHROOT_MNT}" | tail -1
fi

echo "[INFO] Preparing chroot mounts..."
${SUDO} mkdir -p \
  "${CHROOT_MNT}/dev" \
  "${CHROOT_MNT}/proc" \
  "${CHROOT_MNT}/sys" \
  "${CHROOT_MNT}/tmp" \
  "${CHROOT_MNT}/var/cache/apt" \
  "${CHROOT_MNT}/var/lib/apt/lists" \
  "${CHROOT_MNT}/root/.pub-cache" \
  "${CHROOT_MNT}/opt/flutter-elinux/flutter" \
  "${CHROOT_MNT}${PROJECT_IN_CHROOT}"

# resolv.conf may be a dangling symlink; replace with a regular file mount point.
${SUDO} rm -f "${CHROOT_MNT}/etc/resolv.conf"
${SUDO} touch "${CHROOT_MNT}/etc/resolv.conf"

${SUDO} mount --bind /dev "${CHROOT_MNT}/dev"
${SUDO} mkdir -p "${CHROOT_MNT}/dev/pts"
${SUDO} mount --bind /dev/pts "${CHROOT_MNT}/dev/pts" || true
${SUDO} mount --bind /proc "${CHROOT_MNT}/proc"
${SUDO} mount --bind /sys "${CHROOT_MNT}/sys"
${SUDO} mount --bind "${ROOT_DIR}" "${CHROOT_MNT}${PROJECT_IN_CHROOT}"
# apt-key needs a real writable /tmp; use tmpfs instead of image or host bind.
${SUDO} mount -t tmpfs -o mode=1777,size=512m tmpfs "${CHROOT_MNT}/tmp"
${SUDO} mount --bind "${PUB_CACHE_DIR}" "${CHROOT_MNT}/root/.pub-cache"
${SUDO} mount --bind "${SDK_CACHE_DIR}" "${CHROOT_MNT}/opt/flutter-elinux/flutter"
${SUDO} mount --bind "${APT_CACHE_DIR}" "${CHROOT_MNT}/var/cache/apt"
${SUDO} mount --bind "${APT_LISTS_DIR}" "${CHROOT_MNT}/var/lib/apt/lists"
${SUDO} mount --bind "${RESOLV_CACHE}" "${CHROOT_MNT}/etc/resolv.conf"

if [ ! -x "${CHROOT_MNT}/usr/bin/qemu-aarch64-static" ]; then
  ${SUDO} cp "${QEMU_STATIC}" "${CHROOT_MNT}/usr/bin/qemu-aarch64-static"
fi

PKG_LIST="${CHROOT_APT_PACKAGES[*]}"

echo "[INFO] Starting chroot build..."
if ${SUDO} chroot "${CHROOT_MNT}" /usr/bin/qemu-aarch64-static /bin/bash -lc "
  set -euo pipefail
  export PATH=/opt/flutter-elinux/bin:/opt/flutter-elinux/flutter/bin:\$PATH
  export TMPDIR=/tmp
  export PUB_CACHE=/root/.pub-cache
  export DEBIAN_FRONTEND=noninteractive
  export CMAKE_BUILD_PARALLEL_LEVEL='${BUILD_JOBS}'
  export NINJAFLAGS='-j${BUILD_JOBS}'

  apply_known_source_patches() {
    local elinux_cmake='${PROJECT_IN_CHROOT}/elinux/CMakeLists.txt'
    local wrapper_header='${PROJECT_IN_CHROOT}/elinux/flutter/ephemeral/cpp_client_wrapper/include/flutter/event_stream_handler_functions.h'
    local video_player_src=''

    echo '[INFO] Applying compiler compatibility fixes...'

    if [ -f \"\$elinux_cmake\" ]; then
      if ! grep -q 'Wno-error=pessimizing-move' \"\$elinux_cmake\"; then
        sed -i '/target_compile_options(\${TARGET} PRIVATE -Wall -Werror)/a\  target_compile_options(\${TARGET} PRIVATE -Wno-error=pessimizing-move -Wno-error=unused-result)' \"\$elinux_cmake\"
        echo '[INFO] Patched eLinux CMake warning policy.'
      fi
    else
      echo '[WARN] eLinux CMakeLists.txt not found; skipping warning policy patch.'
    fi

    if [ -f \"\$wrapper_header\" ]; then
      if grep -q 'return std::move(error);' \"\$wrapper_header\"; then
        sed -i 's/return std::move(error);/return error;/g' \"\$wrapper_header\"
        echo '[INFO] Patched Flutter wrapper pessimizing-move warning.'
      fi
    else
      echo '[WARN] Flutter wrapper header not found; skipping wrapper patch.'
    fi

    video_player_src=\$(find /root/.pub-cache -path '*/packages/video_player/elinux/video_player_elinux_plugin.cc' -print -quit 2>/dev/null || true)
    if [ -n \"\$video_player_src\" ] && [ -f \"\$video_player_src\" ]; then
      if grep -q 'readlink("/proc/self/exe", buf, sizeof(buf) - 1);' \"\$video_player_src\"; then
        sed -i 's#  readlink("/proc/self/exe", buf, sizeof(buf) - 1);#  const ssize_t len = readlink("/proc/self/exe", buf, sizeof(buf) - 1); if (len >= 0) { buf[len] = 0; }#' \"\$video_player_src\"
        echo '[INFO] Patched video_player_elinux readlink warning.'
      fi
    else
      echo '[WARN] video_player_elinux source not found; skipping plugin patch.'
    fi
  }

  if [ '${INSTALL_DEPS}' = '1' ]; then
    if ! command -v apt-get >/dev/null 2>&1; then
      echo '[ERROR] apt-get not found in rootfs; cannot auto-install build deps.'
      exit 1
    fi

    NEED_INSTALL=0
    for mod in glib-2.0 gstreamer-1.0 gstreamer-gl-1.0; do
      if ! pkg-config --exists \"\$mod\" 2>/dev/null; then
        echo \"[INFO] Missing pkg-config module: \$mod\"
        NEED_INSTALL=1
      fi
    done

    if [ \"\$NEED_INSTALL\" = '1' ]; then
      echo '[INFO] Installing missing chroot build dependencies...'
      echo \"[INFO] Packages: ${PKG_LIST}\"
      # Ensure apt/apt-key can write temp files under qemu-user.
      chmod 1777 /tmp
      export TMPDIR=/tmp
      apt-get update || {
        echo '[ERROR] apt-get update failed'
        exit 1
      }
      apt-get install -y --no-install-recommends ${PKG_LIST} || {
        echo '[ERROR] apt-get install failed'
        exit 1
      }
    else
      echo '[INFO] Required pkg-config modules already present.'
    fi

    pkg-config --exists glib-2.0
    pkg-config --exists gstreamer-1.0
    pkg-config --exists gstreamer-gl-1.0
    echo \"[INFO] glib: \$(pkg-config --modversion glib-2.0)\"
    echo \"[INFO] gstreamer: \$(pkg-config --modversion gstreamer-1.0)\"
    echo \"[INFO] gstreamer-gl: \$(pkg-config --modversion gstreamer-gl-1.0)\"
  fi

  cd '${PROJECT_IN_CHROOT}'
  if [ '${FAST_BUILD}' != '1' ]; then
    flutter-elinux --version
  fi
  if [ '${RUN_PUB_GET}' = '1' ]; then
    echo '[INFO] Resolving Flutter packages...'
    flutter-elinux pub get
  else
    echo '[INFO] pubspec inputs unchanged; skipping pub get.'
  fi
  apply_known_source_patches
  echo '[INFO] Building with ${BUILD_JOBS} parallel job(s)...'
  flutter-elinux build elinux \
    --target-arch=arm64 \
    --${BUILD_MODE} \
    --no-pub \
    ${BUILD_VERBOSITY_FLAG}
"; then
  printf '%s\n' "${CURRENT_PUB_INPUT_HASH}" > "${PUB_INPUT_HASH_FILE}"
  echo "[INFO] Total build time: $((SECONDS - BUILD_STARTED_AT)) seconds"
  echo "[OK] Chroot build finished."
else
  echo "[ERROR] Chroot build failed."
  exit 1
fi
