#!/usr/bin/env bash
# Rebuilds the Hyprland plugins of the macOS look (traffic lights and genie
# minimize) for the Hyprland version installed now. Plugins only load into the
# exact Hyprland they were built against, so this runs:
#   - from the pacman hook /etc/pacman.d/hooks/macos-look-plugins.hook after
#     every Hyprland upgrade, and
#   - at login from hypr/custom.lua when a plugin failed to load (--reload).
#
# hyprbars comes from hyprwm/hyprland-plugins, at the commit that repo pins for
# this Hyprland commit in its hyprpm.toml (or the newest commit when it has no
# pin yet). hypr-minimize is our own source and just gets recompiled.
#
# Usage: rebuild-plugins.sh [--reload]   (--reload: reload Hyprland afterwards)
set -uo pipefail

look="$HOME/.local/share/macos-look"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/macos-look"
repo="$cache/hyprland-plugins"
log="$cache/rebuild-plugins.log"
mkdir -p "$cache"
exec > >(tee "$log") 2>&1

notify() {
    notify-send -a "macOS look" -i preferences-desktop-theme "$1" "$2" 2>/dev/null || true
}

hash=$(sed -n 's/^#define GIT_COMMIT_HASH *"\(.*\)"/\1/p' /usr/include/hyprland/src/version.h 2>/dev/null)
if [ -z "$hash" ]; then
    echo "Hyprland headers not found in /usr/include/hyprland"
    notify "Plugin rebuild failed" "Hyprland headers are missing."
    exit 1
fi
echo "Hyprland commit $hash"
failed=()

# --- hyprbars -------------------------------------------------------------
if [ -d "$repo/.git" ]; then
    git -C "$repo" fetch -q origin && git -C "$repo" checkout -q --detach origin/HEAD
else
    git clone -q https://github.com/hyprwm/hyprland-plugins "$repo"
fi
if [ -d "$repo/.git" ]; then
    pin=$(grep -o "\[\"$hash\", *\"[0-9a-f]*\"\]" "$repo/hyprpm.toml" | sed 's/.*, *"\([0-9a-f]*\)"\]/\1/' | head -n1)
    if [ -n "$pin" ]; then
        echo "hyprland-plugins pinned at $pin"
        git -C "$repo" checkout -q "$pin"
    else
        echo "No pin for this Hyprland yet; trying the newest hyprland-plugins"
    fi
    src="$repo/hyprbars"
    cp "$src"/*.cpp "$src"/*.hpp "$look/hyprbars/" && "$look/hyprbars/build.sh" || failed+=(hyprbars)
else
    echo "Could not get hyprland-plugins (offline?)"
    failed+=(hyprbars)
fi

# --- hypr-minimize --------------------------------------------------------
"$look/hypr-minimize/build.sh" || failed+=(hypr-minimize)

if [ ${#failed[@]} -eq 0 ]; then
    if [ "${1:-}" = "--reload" ]; then
        hyprctl reload >/dev/null
        notify "Mac plugins rebuilt" "Traffic lights and genie minimize are back."
    else
        notify "Mac plugins rebuilt" "Traffic lights and genie minimize match the new Hyprland. They load after your next login."
    fi
    exit 0
fi
notify "Plugin rebuild failed" "${failed[*]} did not build. Log: $log"
exit 1
