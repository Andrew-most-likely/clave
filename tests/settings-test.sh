#!/usr/bin/env bash
# Tests for System Settings that need no display:
#   - clave-idle (Lock Screen): get/set round trip, Never, the display never
#     turning off before the lock (ISSUE-7) and the repair of an old lock
#     command (ISSUE-6), on a copy of hypridle.conf
#   - every command the shipped hypridle.conf runs exists
#   - every setting the window writes is read somewhere else, and every
#     value written to hypr.lua is read by the Hyprland config
#   - every pane has rows and search keywords (ISSUE-10)
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
trap '[ -n "${KEEP:-}" ] || rm -rf "$tmp"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
ok()   { echo "ok:   $*"; }
eq()   { if [ "$1" = "$2" ]; then ok "$3"; else fail "$3: got '$1', want '$2'"; fi; }
# has FILE REGEX WHAT
has()  { if grep -qE -- "$2" "$1"; then ok "$3"; else fail "$3: /$2/ not in ${1##*/}"; fi; }

idle="$repo/home/.local/bin/clave-idle"
win="$repo/home/.config/quickshell/Clave/SettingsWindow.qml"
settings="$repo/home/.config/quickshell/Clave/ClaveSettings.qml"
export CLAVE_IDLE_CONF="$tmp/hypridle.conf" CLAVE_IDLE_NO_RESTART=1

echo "==> clave-idle"
cp "$repo/home/.config/hypr/hypridle.conf" "$CLAVE_IDLE_CONF"
eq "$("$idle" get)" "lock=600 display=660 sleep=1800" "reads the shipped timeouts"
"$idle" set 300 900 3600
eq "$("$idle" get)" "lock=300 display=900 sleep=3600" "set and get agree"
has "$CLAVE_IDLE_CONF" '^ *timeout *= *240 ' "dims one minute before the lock"
"$idle" set 600 60 0
eq "$("$idle" get)" "lock=600 display=600 sleep=0" "display raised to the lock; sleep never"
"$idle" set 0 60 0
eq "$("$idle" get)" "lock=0 display=60 sleep=0" "display alone when the lock is never"

"$idle" set 600 660 1800
"$idle" set-one lock 300
eq "$("$idle" get)" "lock=300 display=660 sleep=1800" "set-one changes one timeout only"
"$idle" set-one display 60
eq "$("$idle" get)" "lock=300 display=300 sleep=1800" "set-one keeps the display after the lock"

sed -i 's|^\( *lock_cmd *= *\).*|\1old-power -l|' "$CLAVE_IDLE_CONF"
"$idle" repair
has "$CLAVE_IDLE_CONF" '^ *lock_cmd *= *~/.local/bin/clave-power -l$' "repair puts back the lock command"
sed -i 's|^\( *lock_cmd *= *\).*|\1old-power -l|' "$CLAVE_IDLE_CONF"
"$idle" set 120 120 0
has "$CLAVE_IDLE_CONF" 'lock_cmd *= *~/.local/bin/clave-power -l' "set repairs the lock command too"
sed -i '/lock_cmd/d' "$CLAVE_IDLE_CONF"
"$idle" repair
has "$CLAVE_IDLE_CONF" 'lock_cmd *= *~/.local/bin/clave-power -l' "repair adds a missing lock command"
if command -v hypridle >/dev/null && [ -n "${WAYLAND_DISPLAY:-}" ]; then
    timeout 2 hypridle -c "$CLAVE_IDLE_CONF" > "$tmp/idle.log" 2>&1 || true
    n=$(grep -c 'Registered timeout rule' "$tmp/idle.log" || true)
    eq "$n" 4 "hypridle reads the file clave-idle wrote"
fi

echo "==> commands in hypridle.conf and hyprlock.conf"
for f in hypridle.conf hyprlock.conf; do
    sed -nE 's/^ *(lock_cmd|before_sleep_cmd|after_sleep_cmd|on-timeout|on-resume) *= *//p; s/.*cmd\[[^]]*\] *//p' \
        "$repo/home/.config/hypr/$f" | while read -r cmd _; do
        # shellcheck disable=SC2088  # the file's literal text, not a path here
        case "$cmd" in
            "~/.local/bin/"*) [ -x "$repo/home/.local/bin/${cmd#"~/.local/bin/"}" ] \
                                 || echo "$f: $cmd is not in home/.local/bin" ;;
            ""|date|loginctl|hyprctl|brightnessctl|systemctl) ;;
            *) echo "$f: $cmd is not a known command" ;;
        esac
    done
done > "$tmp/cmds"
if [ -s "$tmp/cmds" ]; then fail "$(cat "$tmp/cmds")"; else ok "every command exists"; fi

echo "==> every setting has a reader"
grep -ohE '(M|ClaveSettings)\.(get|set)\("[a-zA-Z]+", *"[a-zA-Z]+"' "$win" \
    | sed -E 's/.*\("([a-zA-Z]+)", *"([a-zA-Z]+)"/\1 \2/' | sort -u > "$tmp/keys"
while read -r group key; do
    # Readers: Quickshell parts, helper scripts, and hypr.lua through writeHypr.
    if grep -rqE "get\(\"$group\", *\"$key\"\)|\.$group\.$key\b|\.$group\b.*\b$key\b" \
            --include='*.qml' --include='*.js' --exclude=SettingsWindow.qml \
            "$repo/home/.config/quickshell" "$repo/home/.local/bin" "$repo/home/.local/share/clave" 2>/dev/null \
       || grep -rqE "\.$group\.$key\b|\"$key\"" "$repo/home/.local/bin" "$repo/home/.local/share/clave" 2>/dev/null; then
        ok "$group.$key"
    else
        fail "$group.$key is written by System Settings but nothing reads it"
    fi
done < "$tmp/keys"
sed -nE 's/^ *\+ "    ([a-z_]+) *=.*/\1/p' "$settings" | sort -u > "$tmp/hyprkeys"
while read -r k; do
    if grep -rqE "settings\.$k\b|\.$k\b" "$repo/home/.config/hypr/clave"; then ok "hypr.lua $k"
    else fail "hypr.lua $k is written but no hypr/clave/*.lua reads it"; fi
done < "$tmp/hyprkeys"
[ -s "$tmp/hyprkeys" ] || fail "found no hypr.lua keys in ClaveSettings.qml"

echo "==> every row has a name"
# A row without a label reads as part of the row above (two "Choose Picture…"
# buttons for the profile picture).
if grep -nE '"type": "(button|switch|choice|slider)", "label": ""' "$win"; then fail "rows without a label"
else ok "no unnamed rows"; fi

echo "==> search (ISSUE-10)"
grep -E '\{ "id": "[a-z]+", +"label": .*"glyph"' "$win" | sed -E 's/.*"id": "([a-z]+)".*/\1/' > "$tmp/panes"
while read -r id; do
    grep -qE "if \(id === \"$id\"\)" "$win" || fail "pane $id has no rows in paneRows()"
    grep -A1 -E "\{ \"id\": \"$id\", +\"label\"" "$win" | grep -q '"keywords"' || fail "pane $id has no search keywords"
done < "$tmp/panes"
eq "$(wc -l < "$tmp/panes")" 18 "18 panes, each with rows and keywords"

echo
if [ "$fails" -gt 0 ]; then echo "$fails FAILED"; exit 1; fi
echo "PASS"
