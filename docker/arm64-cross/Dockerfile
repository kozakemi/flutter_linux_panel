FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

RUN printf '%s\n' \
      'deb [arch=amd64] http://archive.ubuntu.com/ubuntu jammy main restricted universe multiverse' \
      'deb [arch=amd64] http://archive.ubuntu.com/ubuntu jammy-updates main restricted universe multiverse' \
      'deb [arch=amd64] http://security.ubuntu.com/ubuntu jammy-security main restricted universe multiverse' \
      'deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy main restricted universe multiverse' \
      'deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy-updates main restricted universe multiverse' \
      'deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy-security main restricted universe multiverse' \
      > /etc/apt/sources.list \
    && rm -f /etc/apt/sources.list.d/ubuntu.sources \
    && dpkg --add-architecture arm64 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
      bash ca-certificates cmake curl file git make ninja-build pkg-config \
      rsync tar xz-utils zip unzip \
      gcc-aarch64-linux-gnu g++-aarch64-linux-gnu binutils-aarch64-linux-gnu \
      libstdc++-11-dev-arm64-cross libc6-dev-arm64-cross \
      libwayland-dev:arm64 libegl1-mesa-dev:arm64 libxkbcommon-dev:arm64 \
      libfontconfig1-dev:arm64 libglib2.0-dev:arm64 \
      libgstreamer1.0-dev:arm64 libgstreamer-plugins-base1.0-dev:arm64 \
    && rm -rf /var/lib/apt/lists/*

ENV PATH="/opt/flutter-elinux/bin:/opt/flutter-elinux/flutter/bin:${PATH}" \
    PKG_CONFIG_LIBDIR="/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig" \
    PKG_CONFIG_PATH="" \
    PKG_CONFIG_SYSROOT_DIR="/" \
    CC="aarch64-linux-gnu-gcc" \
    CXX="aarch64-linux-gnu-g++"

WORKDIR /workspace

CMD ["bash"]
