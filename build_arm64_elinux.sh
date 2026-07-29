#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"

TARGET_ARCH="arm64"
E_LINUX_OUT_DIR="build/elinux/${TARGET_ARCH}/release/bundle"
E_LINUX_BUILD_DIR="build/elinux/${TARGET_ARCH}/release"
DIST_DIR="build/elinux/${TARGET_ARCH}/release/dist"
ARM64_SYSROOT="${ARM64_SYSROOT:-}"
SYSROOT_LIB_DIRS=()
if [ -n "${ARM64_SYSROOT}" ]; then
  SYSROOT_LIB_DIRS+=(
    "${ARM64_SYSROOT}/usr/lib/aarch64-linux-gnu"
    "${ARM64_SYSROOT}/lib/aarch64-linux-gnu"
    "${ARM64_SYSROOT}/usr/lib"
    "${ARM64_SYSROOT}/lib"
  )
fi
SYSROOT_LIB_DIRS+=(
  "/usr/lib/aarch64-linux-gnu"
  "/usr/aarch64-linux-gnu/lib"
  "/lib/aarch64-linux-gnu"
)
HOST_ARCH="$(uname -m)"

echo "[INFO] Host arch: ${HOST_ARCH}"
echo "[INFO] Target arch: ${TARGET_ARCH}"
if [ -n "${ARM64_SYSROOT}" ]; then
  echo "[INFO] ARM64_SYSROOT: ${ARM64_SYSROOT}"
fi

if ! command -v flutter-elinux >/dev/null 2>&1; then
  echo "[ERROR] flutter-elinux not found in PATH."
  echo "        Please install and configure flutter-elinux first."
  exit 1
fi

if [ "${HOST_ARCH}" = "x86_64" ]; then
  if ! command -v aarch64-linux-gnu-gcc >/dev/null 2>&1 || ! command -v aarch64-linux-gnu-g++ >/dev/null 2>&1; then
    echo "[ERROR] arm64 cross compiler not found."
    echo "        Please install: gcc-aarch64-linux-gnu g++-aarch64-linux-gnu"
    exit 1
  fi
  export CC="$(command -v aarch64-linux-gnu-gcc)"
  export CXX="$(command -v aarch64-linux-gnu-g++)"
  echo "[INFO] Using cross compiler:"
  echo "       CC=${CC}"
  echo "       CXX=${CXX}"
fi

has_arm64_lib() {
  local name="$1"
  for d in "${SYSROOT_LIB_DIRS[@]}"; do
    if [ -e "${d}/${name}" ]; then
      return 0
    fi
  done
  return 1
}

find_arm64_lib() {
  local name="$1"
  for d in "${SYSROOT_LIB_DIRS[@]}"; do
    if [ -e "${d}/${name}" ]; then
      echo "${d}/${name}"
      return 0
    fi
  done
  return 1
}

collect_runtime_deps() {
  local bundle_dir="$1"
  local bin_path
  local lib_dir="${bundle_dir}/lib"
  local tmp_queue
  local tmp_seen
  local needed
  local resolved
  local item

  if ! command -v aarch64-linux-gnu-readelf >/dev/null 2>&1; then
    echo "[WARN] aarch64-linux-gnu-readelf not found, skip dependency collection."
    return 0
  fi

  mkdir -p "${lib_dir}"
  tmp_queue="$(mktemp)"
  tmp_seen="$(mktemp)"
  trap 'rm -f "${tmp_queue}" "${tmp_seen}"' RETURN

  # Queue app binary and current bundled .so files.
  for bin_path in "${bundle_dir}"/*; do
    if [ -f "${bin_path}" ] && [ -x "${bin_path}" ]; then
      echo "${bin_path}" >> "${tmp_queue}"
    fi
  done
  for bin_path in "${lib_dir}"/*.so*; do
    if [ -f "${bin_path}" ]; then
      echo "${bin_path}" >> "${tmp_queue}"
    fi
  done

  while IFS= read -r item; do
    [ -z "${item}" ] && continue
    if grep -F -x -q "${item}" "${tmp_seen}" 2>/dev/null; then
      continue
    fi
    echo "${item}" >> "${tmp_seen}"

    needed="$(aarch64-linux-gnu-readelf -d "${item}" 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p')"
    if [ -z "${needed}" ]; then
      continue
    fi
    while IFS= read -r dep; do
      [ -z "${dep}" ] && continue
      if [ -e "${lib_dir}/${dep}" ]; then
        continue
      fi
      resolved="$(find_arm64_lib "${dep}" || true)"
      if [ -z "${resolved}" ]; then
        echo "[WARN] Missing runtime dependency in sysroot: ${dep}"
        continue
      fi
      cp -L -f "${resolved}" "${lib_dir}/${dep}"
      echo "[INFO] Added runtime dependency: ${dep}"
      echo "${lib_dir}/${dep}" >> "${tmp_queue}"
    done <<< "${needed}"
  done < "${tmp_queue}"
}

MISSING_ARM64_LIBS=()
for lib in \
  libwayland-client.so.0 \
  libwayland-cursor.so.0 \
  libwayland-egl.so.1 \
  libEGL.so.1 \
  libxkbcommon.so.0 \
  libfontconfig.so.1
do
  if ! has_arm64_lib "${lib}"; then
    MISSING_ARM64_LIBS+=("${lib}")
  fi
done

if [ "${#MISSING_ARM64_LIBS[@]}" -gt 0 ]; then
  echo "[ERROR] Missing required arm64 runtime libraries:"
  for lib in "${MISSING_ARM64_LIBS[@]}"; do
    echo "        - ${lib}"
  done
  echo "        Install with:"
  echo "        sudo dpkg --add-architecture arm64"
  echo "        sudo apt update"
  echo "        sudo apt install -y \\"
  echo "          libwayland-client0:arm64 libwayland-cursor0:arm64 libwayland-egl1:arm64 \\"
  echo "          libegl1:arm64 libxkbcommon0:arm64 libfontconfig1:arm64"
  exit 1
fi

echo "[INFO] Running flutter-elinux pub get ..."
flutter-elinux pub get

if [ -d "${E_LINUX_BUILD_DIR}" ]; then
  echo "[INFO] Cleaning old CMake cache: ${E_LINUX_BUILD_DIR}"
  rm -rf "${E_LINUX_BUILD_DIR}"
fi

echo "[INFO] Building eLinux arm64 bundle ..."
flutter-elinux build elinux --target-arch="${TARGET_ARCH}" --release --verbose

echo "[INFO] Collecting runtime dependencies ..."
collect_runtime_deps "${E_LINUX_OUT_DIR}"

# Create a self-contained run script inside the bundle.
RUN_SCRIPT="${E_LINUX_OUT_DIR}/run_in_bundle.sh"
cat > "${RUN_SCRIPT}" <<'EOF'
#!/usr/bin/env sh
set -eu
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
cd "$DIR"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/0}"
export LD_LIBRARY_PATH="$DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

if [ ! -f "$DIR/lib/libflutter_engine.so" ]; then
  echo "[ERROR] $DIR/lib/libflutter_engine.so not found."
  echo "         Current directory: $DIR"
  ls -l "$DIR/lib" || true
  exit 1
fi

exec ./demo1 --bundle=. --fullscreen "$@"
EOF
chmod +x "${RUN_SCRIPT}"

mkdir -p "${DIST_DIR}"
ARCHIVE_NAME="demo1-elinux-${TARGET_ARCH}-$(date +%Y%m%d-%H%M%S).tar.gz"
ARCHIVE_PATH="${DIST_DIR}/${ARCHIVE_NAME}"
tar -czf "${ARCHIVE_PATH}" -C "$(dirname "${E_LINUX_OUT_DIR}")" "$(basename "${E_LINUX_OUT_DIR}")"
echo "[INFO] Created archive: ${ARCHIVE_PATH}"

echo "[OK] Build finished: ${E_LINUX_OUT_DIR}"
