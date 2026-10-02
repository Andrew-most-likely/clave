#!/usr/bin/env bash
# Installs v1.0.0 into a scratch home, saves display settings the old way,
# updates to this checkout and checks the v1.1.0 changes (PROJECT_PLAN.md
# APP-2, SHELL-2): the files the Clave apps replace are gone, displays.json
# has one position per screen, monitors.lua is written, and a second update
# changes nothing. Then uninstalls.
# Run as a normal user:  tests/update-test.sh [OLD_REF]
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
old_ref=${1:-v1.0.0}
tmp=$(mktemp -d "${TMPDIR:-/var/tmp}/clave-update.XXXXXX")
trap '[ -n "${KEEP:-}" ] || rm -rf "$tmp"' EXIT
home="$tmp/home" old="$tmp/old"
mkdir -p "$home" "$old"
fail() { echo "FAIL: $*" >&2; [ ! -f "$tmp/update.log" ] || tail -n 30 "$tmp/update.log" >&2; exit 1; }
run() { env -i HOME="$home" PATH="$PATH" USER="$(id -un)" TERM=dumb "$@"; }

git -C "$repo" archive "$old_ref" | tar -x -C "$old"

echo "==> install $old_ref"
run bash "$old/install.sh" --user-only --no-packages --yes >/dev/null
for f in .local/bin/clave-screenshot .config/hypr/scripts/display-mode.sh .config/rofi/clave-display.rasi \
         .config/quickshell/Clave/ForceQuit.qml; do
    [ -e "$home/$f" ] || fail "$old_ref did not install $f"
done
cfg="$home/.config/clave"
cat > "$cfg/displays.json" <<'EOF'
{
    "displays": {"Dell Inc. DELL U2720Q 7Z1QK13": {"scale": 1.5}},
    "layouts": {"BOE 0x0BCA|Dell Inc. DELL U2720Q 7Z1QK13": {"BOE 0x0BCA": [0, 200], "Dell Inc. DELL U2720Q 7Z1QK13": [1920, 0]}}
}
EOF

echo "==> update to this checkout"
run "$repo/install.sh" --update > "$tmp/update.log" 2>&1 || { cat "$tmp/update.log"; fail "update failed"; }

for f in .local/bin/clave-screenshot .config/hypr/scripts/display-mode.sh .config/rofi/clave-display.rasi \
         .config/quickshell/Clave/ForceQuit.qml; do
    [ ! -e "$home/$f" ] || fail "replaced file left behind: $f"
done
for f in .config/quickshell/Clave/ActivityMonitor.qml .config/quickshell/Clave/Screenshot.qml \
         .config/quickshell/ClaveApps/CalendarApp.qml \
         .local/bin/clave-pim .local/bin/clave-encrypt .config/gtk-4.0/clave.css \
         .local/share/applications/clave-activity-monitor.desktop; do
    [ -e "$home/$f" ] || fail "new file missing: $f"
done
grep -q "$home/.local/bin/clave-app calendar %f" "$home/.local/share/applications/clave-calendar.desktop" \
    || fail "placeholder not filled in clave-calendar.desktop"
grep -q 'clave.css' "$home/.config/gtk-4.0/gtk.css" || fail "gtk.css does not load clave.css"
[ "$(jq -r .version "$cfg/displays.json")" = 2 ] || fail "displays.json not converted"
[ "$(jq -c '.displays["Dell Inc. DELL U2720Q 7Z1QK13"].position' "$cfg/displays.json")" = '[1920,0]' ] \
    || fail "display position lost"
[ "$(jq -r '.displays["Dell Inc. DELL U2720Q 7Z1QK13"].scale' "$cfg/displays.json")" = 1.5 ] || fail "display scale lost"
grep -q 'output = "desc:Dell Inc. DELL U2720Q 7Z1QK13"' "$cfg/monitors.lua" || fail "monitors.lua not written"
grep -q 'clave/monitors.lua' "$home/.config/hypr/hyprland.lua" || fail "hyprland.lua does not load monitors.lua"
! grep -rq 'display-mode.sh\|clave-screenshot' "$home/.config/hypr" || fail "Hyprland config still calls removed scripts"

echo "==> second update changes nothing"
cp "$cfg/displays.json" "$tmp/d1"; cp "$cfg/monitors.lua" "$tmp/m1"
run "$repo/install.sh" --update > "$tmp/update.log" 2>&1 || { cat "$tmp/update.log"; fail "update failed"; }
cmp -s "$tmp/d1" "$cfg/displays.json" || fail "second update rewrote displays.json"
cmp -s "$tmp/m1" "$cfg/monitors.lua" || fail "second update rewrote monitors.lua"

echo "==> uninstall"
run "$repo/uninstall.sh" >/dev/null
[ ! -e "$home/.config/quickshell/Clave" ] || { find "$home/.config/quickshell" | head -20 >&2; fail "installed files left behind"; }

echo "PASS"
