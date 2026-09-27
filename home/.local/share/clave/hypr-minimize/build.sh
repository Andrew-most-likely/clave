#!/bin/sh
# Rebuild after every Hyprland update: plugins must match the exact version.
set -e
cd "$(dirname "$0")"
g++ -shared -fPIC -O2 -std=c++26 main.cpp -o hypr-minimize.so \
    $(pkg-config --cflags pixman-1 libdrm hyprland libinput libudev wayland-server xkbcommon)
echo "built $(pwd)/hypr-minimize.so"
