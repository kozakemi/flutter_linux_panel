#!/bin/bash
./build_origin.sh

ARCH=$(uname -m)

if [ "$ARCH" = "aarch64" ]; then
    # ARM64 架构
    flutter-elinux build elinux --target-arch=arm64 --verbose
    cp -f build/linux/arm64/release/bundle/lib/libflutter_soloud_plugin.so build/elinux/arm64/release/bundle/lib/
elif [ "$ARCH" = "x86_64" ]; then
    # x64 架构
    flutter-elinux build elinux --target-arch=x64 --verbose
    cp -f build/linux/x64/release/bundle/lib/libflutter_soloud_plugin.so build/elinux/x64/release/bundle/lib/
else
    echo "不支持的架构: $ARCH"
    exit 1
fi
