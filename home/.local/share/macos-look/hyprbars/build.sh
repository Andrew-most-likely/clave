#!/bin/sh
# hyprbars from hyprwm/hyprland-plugins, commit 7644cecd (pinned for Hyprland
# 0.56.2). Rebuild after every Hyprland update: plugins must match the exact
# version. For a new Hyprland, copy the sources from the commit hyprpm.toml in
# that repo pins for it.
set -e
cd "$(dirname "$0")"
g++ -shared -fPIC -O2 -std=c++2b -Wno-c++11-narrowing --no-gnu-unique \
    main.cpp barDeco.cpp BarPassElement.cpp -o hyprbars.so \
    $(pkg-config --cflags pixman-1 libdrm hyprland libinput libudev wayland-server xkbcommon)
echo "built $(pwd)/hyprbars.so"
