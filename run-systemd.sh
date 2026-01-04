#!/bin/bash
# 专用于 systemd 服务的启动脚本（不需要 sudo）

ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
  cd /home/neons/flutter_linux_panel/build/elinux/arm64/release/bundle
  XDG_RUNTIME_DIR=/run/user/0 LD_LIBRARY_PATH=/home/neons/flutter_linux_panel/build/elinux/arm64/release/bundle/lib ./demo1 --bundle=. --fullscreen
elif [ "$ARCH" = "x86_64" ]; then
  cd /home/neons/flutter_linux_panel/build/elinux/x64/release/bundle
  LD_LIBRARY_PATH=/home/neons/flutter_linux_panel/build/elinux/x64/release/bundle/lib ./demo1 --bundle=. --fullscreen
else
  echo "不支持的架构: $ARCH"
  exit 1
fi
