#!/usr/bin/env bash
# Display mode menu (Super+P), like Win+P on Windows.
#
#   display-mode.sh              show the menu
#   display-mode.sh <mode>       apply a mode: extend | duplicate | external | laptop
#   display-mode.sh --hotplug    run by Hyprland when a screen is plugged in or out
#                                or the lid is opened or closed
#
# The chosen mode is saved and re-applied when a screen is plugged in, except
# "second screen only": a new screen never turns the laptop screen off.
# Unplugging the last second screen always turns the laptop screen back on.
# While the lid is closed with a second screen connected, the laptop screen is
# off (what the laptop itself does on lid close is System Settings > Battery).
# Position, orientation, resolution and scale of each screen come from
# System Settings > Displays (macos-displays spec), when set there.

# The built-in panel: eDP, LVDS or DSI. Empty on desktops.
LAPTOP=$(hyprctl monitors all -j | jq -r '[.[].name | select(test("^(eDP|LVDS|DSI)-"))][0] // empty')
STATE="${XDG_CACHE_HOME:-$HOME/.cache}/display-mode"
THEME="$HOME/.config/rofi/macos-display.rasi"
CONFIRM_SECONDS=15

monitors()  { hyprctl monitors all -j; }
lid_closed() { grep -qs closed /proc/acpi/button/lid/*/state; }
externals() { monitors | jq -r --arg l "$LAPTOP" '.[] | select(.name != $l) | .name'; }
# Hyprland merges monitor rules, so every rule spells out disabled and mirror.
monitor()   { hyprctl eval "hl.monitor({ $1 })" >/dev/null; }

# jq helper: the scale a second screen should use, from its widest mode.
# 1x for 1080p and below, 1.25x for 1440p, 2x for 4K.
JQ_SCALE='def want_scale: ([.availableModes[]? | split("x")[0] | tonumber] | max // 0) as $w
    | if $w >= 3840 then 2 elif $w >= 2560 then 1.25 else 1 end;'

ext_scale() {
    monitors | jq -r --arg n "$1" "$JQ_SCALE"' .[] | select(.name == $n) | want_scale'
}

current_mode() {
    monitors | jq -r --arg l "$LAPTOP" '
        (map(select(.name == $l))[0]) as $lap
        | map(select(.name != $l)) as $ext
        | if ($ext | length) == 0 then "laptop"
          elif $lap.disabled then "external"
          elif ($ext | all(.disabled)) then "laptop"
          elif ($ext | any(.mirrorOf != "none")) then "duplicate"
          else "extend" end'
}

# True when every active second screen uses the scale ext_scale would pick.
scales_ok() {
    monitors | jq -e --arg l "$LAPTOP" "$JQ_SCALE"'
        all(.[] | select(.name != $l and (.disabled | not) and .mirrorOf == "none");
            .scale == want_scale)' >/dev/null
}

# Saved settings for a screen shown on its own in mode $MODE.
spec() { "$HOME/.local/bin/macos-displays" spec "$1" "${MODE:-extend}"; }

laptop_on() {
    monitor "output = \"$LAPTOP\", $(spec "$LAPTOP"), disabled = false, mirror = \"\""
}

external_on() {  # name [mirror source]
    # A screen that stops mirroring stays invisible to the bars and awww until
    # it is turned off and on again.
    if [ -z "$2" ] && [ "$(monitors | jq -r --arg n "$1" '.[] | select(.name == $n) | .mirrorOf')" != none ]; then
        monitor "output = \"$1\", disabled = true"
        sleep 1
    fi
    if [ -n "$2" ]; then
        monitor "output = \"$1\", mode = \"preferred\", position = \"auto-right\", scale = $(ext_scale "$1"), disabled = false, mirror = \"$2\""
    else
        monitor "output = \"$1\", $(spec "$1"), disabled = false, mirror = \"\""
    fi
}

# awww paints new screens black. Give every visible screen that shows a plain
# color the same image as a screen that has one.
fix_wallpaper() {
    local q img out
    q=$(awww query 2>/dev/null) || return
    img=$(sed -n 's/.*currently displaying: image: //p' <<<"$q" | head -n1)
    [ -n "$img" ] || return
    while read -r out; do
        [ -n "$out" ] && awww img -o "$out" "$img"
    done < <(sed -n 's/^: \([^:]*\): .*currently displaying: color:.*/\1/p' <<<"$q")
}

apply() {
    local e
    MODE=$1
    # A mirrored screen shows a second, stuck cursor when the hardware cursor
    # is on. Draw the cursor in software while duplicating (1), auto otherwise (2).
    hyprctl eval "hl.config({ cursor = { no_hardware_cursors = $([ "$1" = duplicate ] && echo 1 || echo 2) } })" >/dev/null
    case "$1" in
        extend)
            laptop_on
            for e in $(externals); do external_on "$e"; done ;;
        duplicate)
            laptop_on
            for e in $(externals); do external_on "$e" "$LAPTOP"; done ;;
        external)
            # Turn the second screens on before the laptop screen goes off.
            for e in $(externals); do external_on "$e"; done
            monitor "output = \"$LAPTOP\", disabled = true" ;;
        laptop)
            laptop_on
            for e in $(externals); do monitor "output = \"$e\", disabled = true"; done ;;
        *)
            echo "unknown mode: $1" >&2; return 1 ;;
    esac
    sleep 0.5
    fix_wallpaper
}

# Apply a mode the user picked. The laptop screen going dark is the one change
# that can leave nothing visible (a TV on the wrong input, a bad cable), so
# "second screen only" asks for confirmation and reverts on its own.
choose() {
    local prev choice
    prev=$(current_mode)
    [ "$prev" = external ] && prev=extend
    echo "$1" > "$STATE"
    ( flock 9; apply "$1" ) 9>"$STATE.lock" || return

    [ "$1" = external ] || return 0
    sleep 1
    choice=$(printf 'Keep\nRevert\n' | timeout "$CONFIRM_SECONDS" \
        rofi -dmenu -i -no-custom -theme "$THEME" \
             -mesg "Keep this display setting? Reverting in ${CONFIRM_SECONDS}s")
    if [ "$choice" != Keep ]; then
        echo "$prev" > "$STATE"
        ( flock 9; apply "$prev" ) 9>"$STATE.lock"
    fi
}

hotplug() {
    sleep 1   # let Hyprland finish adding or removing the screen
    exec 9>"$STATE.lock"
    flock 9
    if [ -z "$(externals)" ]; then
        # No second screen left: never leave the laptop screen off.
        [ "$(monitors | jq -r --arg l "$LAPTOP" '.[] | select(.name == $l) | .disabled')" = true ] && laptop_on
        return
    fi
    local want cur
    want=$(cat "$STATE" 2>/dev/null || echo extend)
    cur=$(current_mode)
    if [ "$want" = external ] && [ "$cur" != external ]; then
        want=extend
    fi
    lid_closed && want=external
    if [ "$cur" != "$want" ] || { [ ! -s "$HOME/.config/macos-look/displays.json" ] && ! scales_ok; }; then
        apply "$want"
    else
        fix_wallpaper
    fi
}

menu() {
    if [ -z "$(externals)" ]; then
        notify-send -a "Displays" "No second screen connected"
        return
    fi
    local modes=(laptop duplicate extend external)
    local labels=("Laptop screen only" "Duplicate" "Extend" "Second screen only")
    local cur i active=0 choice
    cur=$(current_mode)
    for i in "${!modes[@]}"; do
        [ "${modes[$i]}" = "$cur" ] && active=$i
    done
    choice=$(printf '%s\n' "${labels[@]}" | rofi -dmenu -i -no-custom -format i \
        -theme "$THEME" -mesg "Display" -a "$active" -selected-row "$active") || return
    [ -n "$choice" ] && choose "${modes[$choice]}"
}

# Desktops have no built-in panel: the modes are about the laptop screen, so
# only keep every screen's wallpaper right.
if [ -z "$LAPTOP" ]; then
    case "$1" in
        --hotplug) sleep 1; fix_wallpaper ;;
        *) notify-send -a "Displays" "Arrange screens in System Settings > Displays" ;;
    esac
    exit 0
fi

case "$1" in
    "")                                  pkill -x rofi || menu ;;
    --hotplug)                           hotplug ;;
    extend|duplicate|external|laptop)    choose "$1" ;;
    *) echo "usage: ${0##*/} [extend|duplicate|external|laptop|--hotplug]" >&2; exit 1 ;;
esac
