#!/bin/bash

ARCH=$(uname -m)
FLUTTER_ELINUX=/opt/flutter-elinux/bin/flutter-elinux

if [ "$ARCH" = "aarch64" ]; then
    "$FLUTTER_ELINUX" build elinux --target-arch=arm64 --verbose
elif [ "$ARCH" = "x86_64" ]; then
    "$FLUTTER_ELINUX" build elinux --target-arch=x64 --verbose
else
    echo "不支持的架构: $ARCH"
    exit 1
fi
