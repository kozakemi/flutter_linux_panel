# fluuter_linux_panel

Migrating the Flutter implementation based on https://github.com/kozakemi/lvgl_t113

## Effect
![alt text](README_SOURCE/image.png)

## Compiling for Linux Desktop
``` shell
./build.sh
```

## Cross-compile arm64 with flutter-elinux
``` shell
sudo apt update
sudo apt install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
sudo dpkg --add-architecture arm64
sudo apt update
sudo apt install -y \
  libwayland-client0:arm64 libwayland-cursor0:arm64 libwayland-egl1:arm64 \
  libegl1:arm64 libxkbcommon0:arm64 libfontconfig1:arm64
chmod +x ./build_arm64_elinux.sh
./build_arm64_elinux.sh
```

Note: this script uses `flutter-elinux` for both dependency fetch and build,
so standalone `flutter` command is not required.
When host is `x86_64`, script forces `CC/CXX` to `aarch64-linux-gnu-*` and
cleans previous eLinux CMake cache before build.
After build, script auto-collects arm64 runtime dependencies into
`build/elinux/arm64/release/bundle/lib` and creates archive:
`build/elinux/arm64/release/dist/demo1-elinux-arm64-*.tar.gz`.

## Run 
### Show in weston
``` shell
./run.sh
```

## Source 

[HarmonyOS Sans](https://developer.huawei.com/consumer/cn/doc/design-guides-V1/font-0000001157868583-V1)

[icon](https://www.iconfont.cn)