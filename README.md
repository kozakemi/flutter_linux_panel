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

### Faster chroot incremental builds

Run the normal chroot build once to install dependencies and populate caches.
For later source-only changes use:

```shell
FAST_BUILD=1 ./build_arm64_chroot.sh
```

This preserves the image contents, skips dependency resolution when
`pubspec.yaml` and `pubspec.lock` are unchanged, disables verbose output and
limits parallel QEMU compiler processes to four. For UI development, a Debug
build avoids Release AOT optimization and is usually much faster:

```shell
FAST_BUILD=1 BUILD_MODE=debug ./build_arm64_chroot.sh
```

If QEMU processes cause memory or I/O contention, reduce concurrency:

```shell
FAST_BUILD=1 BUILD_JOBS=2 ./build_arm64_chroot.sh
```

### Native x86 Docker to ARM64 cross-compilation

The recommended build path runs the x86_64 Flutter/Dart SDK natively in an
amd64 Ubuntu container and only cross-compiles native code with
`aarch64-linux-gnu-g++`:

```shell
./build_arm64_docker.sh
```

The first run builds the Docker image and copies `/opt/flutter-elinux` into
`.docker-cache/arm64`. Later builds reuse the Docker image, Flutter SDK, pub
cache and Ninja/CMake outputs. Build modes and parallelism can be selected with:

```shell
BUILD_MODE=debug ./build_arm64_docker.sh
BUILD_MODE=release BUILD_JOBS=8 ./build_arm64_docker.sh
```

Force rebuilding the dependency image after changing the Dockerfile:

```shell
REBUILD_IMAGE=1 ./build_arm64_docker.sh
```

Release archives are written to:

```text
build/elinux/arm64/release/dist/
```

### ARM64 Debian package and systemd autostart

Build the release bundle and wrap it in an `arm64` Debian package:

```shell
./build_arm64_deb.sh
```

The package is written to `build/elinux/arm64/release/dist/`. Install it on
the board and start the service with:

```shell
sudo apt install ./flutter-linux-panel_1.0.0-1_arm64.deb
sudo systemctl start flutter-linux-panel.service
sudo systemctl status flutter-linux-panel.service
```

The package enables `flutter-linux-panel.service` for subsequent boots. The
service runs as root and waits for an available Wayland socket below
`/run/user/*`; no login user or home directory is hard-coded. Logs can be read
with:

```shell
journalctl -u flutter-linux-panel.service -f
```

On systems with multiple Wayland sessions, select one in a systemd override:

```ini
[Service]
Environment=FLUTTER_PANEL_RUNTIME_DIR=/run/user/1000
Environment=FLUTTER_PANEL_WAYLAND_DISPLAY=wayland-0
```

After creating the override with `systemctl edit flutter-linux-panel`, run
`systemctl daemon-reload` and restart the service.

If the current user cannot access `/var/run/docker.sock`, add the user to the
Docker group and log in again:

```shell
sudo usermod -aG docker "$USER"
```

## Run 
### Show in weston
``` shell
./run.sh
```

## Source 

[HarmonyOS Sans](https://developer.huawei.com/consumer/cn/doc/design-guides-V1/font-0000001157868583-V1)

[icon](https://www.iconfont.cn)
