#!/usr/bin/env bash
# Rebuilds the Hyprland plugins of Clave (traffic lights and genie
# minimize) for the Hyprland version installed now. Plugins only load into the
# exact Hyprland they were built against, so this runs:
#   - from the pacman hook /etc/pacman.d/hooks/clave-plugins.hook after
#     every Hyprland upgrade, and
#   - at login from hypr/clave/plugins.lua when a plugin failed to load; with
#     --ask it first shows a notification and only builds when you click it.
#
# hyprbars comes from hyprwm/hyprland-plugins, at the commit that repo pins for
# this Hyprland commit in its hyprpm.toml. Without a pin nothing is built unless
# you pass --allow-unpinned (then the newest commit is used). hypr-minimize is
# our own source and just gets recompiled.
#
# Usage: rebuild-plugins.sh [--ask] [--reload] [--allow-unpinned]
set -uo pipefail

ask=0 reload=0 unpinned=0
for a in "$@"; do
    case "$a" in
        --ask) ask=1 ;;
        --reload) reload=1 ;;
        --allow-unpinned) unpinned=1 ;;
    esac
done

if [ "$ask" -eq 1 ]; then
    action=$(notify-send -a "Clave" -i preferences-desktop-theme -A rebuild="Rebuild" \
        "Clave plugins need a rebuild" \
        "Traffic lights and genie minimize do not match this Hyprland. Rebuild downloads hyprland-plugins from GitHub." \
        2>/dev/null || true)
    [ "$action" = rebuild ] || exit 0
fi

look="$HOME/.local/share/clave"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/clave"
repo="$cache/hyprland-plugins"
log="$cache/rebuild-plugins.log"
mkdir -p "$cache"
exec > >(tee "$log") 2>&1

notify() {
    notify-send -a "Clave" -i preferences-desktop-theme "$1" "$2" 2>/dev/null || true
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
    elif [ "$unpinned" -eq 1 ]; then
        echo "No pin for this Hyprland yet; using the newest hyprland-plugins (--allow-unpinned)"
    else
        echo "No pin for this Hyprland yet; hyprbars not built. Retry later, or run with --allow-unpinned."
        pin=none
    fi
    src="$repo/hyprbars"
    if [ "${pin:-}" = none ]; then
        failed+=(hyprbars)
    else
        cp "$src"/*.cpp "$src"/*.hpp "$look/hyprbars/" || failed+=(hyprbars)
        # The ×, − and + on the buttons: upstream draws them at 62% of the
        # button size, about a third of the dot. 90% makes them about half the
        # dot, like the GTK traffic lights (clave.css). Only this number changes.
        sed -i 's/button\.size \* 0\.62 \* scale/button.size * 0.9 * scale/' "$look/hyprbars/barDeco.cpp"
        grep -q 'button.size \* 0.9 \* scale' "$look/hyprbars/barDeco.cpp" \
            || echo "hyprbars: the symbol size line changed upstream; symbols keep the upstream size"
        [[ " ${failed[*]} " == *" hyprbars "* ]] || "$look/hyprbars/build.sh" || failed+=(hyprbars)
    fi
else
    echo "Could not get hyprland-plugins (offline?)"
    failed+=(hyprbars)
fi

# --- hypr-minimize --------------------------------------------------------
"$look/hypr-minimize/build.sh" || failed+=(hypr-minimize)

if [ ${#failed[@]} -eq 0 ]; then
    # The Hyprland commit the plugins match, for clave-doctor.
    echo "$hash" > "$look/plugins-hyprland"
    if [ "$reload" -eq 1 ]; then
        hyprctl reload >/dev/null
        notify "Clave plugins rebuilt" "Traffic lights and genie minimize are back."
    else
        notify "Clave plugins rebuilt" "Traffic lights and genie minimize match the new Hyprland. They load after your next login."
    fi
    exit 0
fi
notify "Plugin rebuild failed" "${failed[*]} did not build. Log: $log"
exit 1
