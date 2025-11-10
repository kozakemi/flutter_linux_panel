#!/bin/bash
cd build/elinux/arm64/release/bundle
 sudo XDG_RUNTIME_DIR=/run/user/0 LD_LIBRARY_PATH=/home/neons/flutter_linux_panel/build/elinux/arm64/release/bundle/lib  ./demo1 --bundle=. --fullscreen