#!/bin/bash
# 使用标准 Flutter Linux 构建运行应用
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
  cd /home/neons/flutter_linux_panel/build/linux/arm64/release/bundle
  XDG_RUNTIME_DIR=/run/user/0 LD_LIBRARY_PATH=/home/neons/flutter_linux_panel/build/linux/arm64/release/bundle/lib ./demo1
elif [ "$ARCH" = "x86_64" ]; then
  cd /home/neons/flutter_linux_panel/build/linux/x64/release/bundle
  LD_LIBRARY_PATH=/home/neons/flutter_linux_panel/build/linux/x64/release/bundle/lib ./demo1
else
  echo "不支持的架构: $ARCH"
  exit 1
fi
