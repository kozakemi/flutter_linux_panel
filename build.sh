#!/bin/bash
./build_origin.sh
flutter-elinux build elinux --target-arch=arm64 --verbose
cp -f build/linux/arm64/release/bundle/lib/libflutter_soloud_plugin.so build/elinux/arm64/release/bundle/lib/