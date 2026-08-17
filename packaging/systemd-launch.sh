#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
BUNDLE_DIR="$SCRIPT_DIR/bundle"

if [ ! -x "$BUNDLE_DIR/run_in_bundle.sh" ]; then
    echo "Flutter Linux Panel bundle is incomplete: $BUNDLE_DIR" >&2
    exit 1
fi

find_wayland_socket() {
    if [ -n "${FLUTTER_PANEL_RUNTIME_DIR:-}" ]; then
        runtime_dirs=$FLUTTER_PANEL_RUNTIME_DIR
    else
        runtime_dirs='/run/user/[1-9]* /run/user/0'
    fi

    for runtime_dir in $runtime_dirs; do
        [ -d "$runtime_dir" ] || continue
        if [ -n "${FLUTTER_PANEL_WAYLAND_DISPLAY:-}" ]; then
            socket="$runtime_dir/$FLUTTER_PANEL_WAYLAND_DISPLAY"
            [ -S "$socket" ] || continue
        else
            socket=
            for candidate in "$runtime_dir"/wayland-*; do
                if [ -S "$candidate" ]; then
                    socket=$candidate
                    break
                fi
            done
            [ -n "$socket" ] || continue
        fi

        XDG_RUNTIME_DIR=$runtime_dir
        WAYLAND_DISPLAY=${socket##*/}
        export XDG_RUNTIME_DIR WAYLAND_DISPLAY
        if [ -S "$runtime_dir/bus" ]; then
            DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus"
            export DBUS_SESSION_BUS_ADDRESS
        fi
        return 0
    done
    return 1
}

until find_wayland_socket; do
    echo "Waiting for a Wayland session..." >&2
    sleep 2
done

exec "$BUNDLE_DIR/run_in_bundle.sh" "$@"
