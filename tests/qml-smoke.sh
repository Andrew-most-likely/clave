#!/usr/bin/env bash
# Loads Clave Quickshell components offscreen and fails on QML errors (type
# errors, missing properties, bad imports), which qmllint does not catch.
#   tests/qml-smoke.sh COMPONENT [IPC_TARGET]...
#   tests/qml-smoke.sh ActivityMonitor activity forcequit
# Each IPC target gets "open" called, so the window's LazyLoader content
# loads too. Needs quickshell (qs). No windows are shown.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
comp=$1; shift
tmp=$(mktemp -d)
trap 'kill "$pid" 2>/dev/null || true; rm -rf "$tmp"' EXIT
for d in CustomTheme Clave DockApp; do ln -s "$repo/home/.config/quickshell/$d" "$tmp/$d"; done
cat > "$tmp/shell.qml" <<EOF
//@ pragma UseQApplication
import Quickshell
import "Clave"
ShellRoot {
    $comp {}
}
EOF
# Components with a PanelWindow need a Wayland compositor: SMOKE_QPA=wayland
# loads them in the running session. Without IPC targets nothing is shown,
# because every window sits in a LazyLoader.
export QT_QPA_PLATFORM="${SMOKE_QPA:-offscreen}"
qs -p "$tmp" > "$tmp/log" 2>&1 &
pid=$!
sleep 3
for t in "$@"; do qs -p "$tmp" ipc call "$t" open >/dev/null 2>&1 || echo "ipc $t open failed"; done
sleep 5
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
if ! grep -qi 'configuration loaded' "$tmp/log"; then
    cat "$tmp/log"; echo "$comp: the config did not load"; exit 1
fi
if grep -E 'ERROR|TypeError|ReferenceError|is not defined|Cannot assign|Unable to assign|failed to load' "$tmp/log"; then
    echo "QML errors in $comp"; exit 1
fi
echo "$comp loads without QML errors"
