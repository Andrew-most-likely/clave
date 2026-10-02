#!/usr/bin/env bash
# Loads Clave Quickshell components offscreen and fails on QML errors (type
# errors, missing properties, bad imports), which qmllint does not catch.
#   tests/qml-smoke.sh COMPONENT [IPC_TARGET]...
#   tests/qml-smoke.sh ActivityMonitor activity forcequit
# Each IPC target gets "open" called, so the window's LazyLoader content
# loads too. Needs quickshell (qs). No windows are shown.
#   tests/qml-smoke.sh --file clave-calendar.qml
# --file runs one of the app entry files in home/.config/quickshell with a
# scratch HOME, so the app's files land in a temp folder.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
pid=
trap 'kill "$pid" 2>/dev/null || true; rm -rf "$tmp"' EXIT
if [ "$1" = --file ]; then
    comp=$2; shift 2
    target="$repo/home/.config/quickshell/$comp"
    mkdir -p "$tmp/home/.local"
    ln -s "$repo/home/.local/bin" "$tmp/home/.local/bin"
    export HOME="$tmp/home" XDG_DATA_HOME="$tmp/home/.local/share" XDG_CONFIG_HOME="$tmp/home/.config"
    # SMOKE_PREPATH: put first on PATH (a venv with the Python libraries).
    # SMOKE_SEED: a script run first with the scratch HOME (sample data).
    [ -z "${SMOKE_PREPATH:-}" ] || export PATH="$SMOKE_PREPATH:$PATH"
    [ -z "${SMOKE_SEED:-}" ] || sh "$SMOKE_SEED"
else
    comp=$1; shift
    for d in CustomTheme Clave DockApp; do ln -s "$repo/home/.config/quickshell/$d" "$tmp/$d"; done
    cat > "$tmp/shell.qml" <<EOF
//@ pragma UseQApplication
import Quickshell
import "Clave"
ShellRoot {
    $comp {}
}
EOF
    target="$tmp"
fi
# Components with a PanelWindow need a Wayland compositor: SMOKE_QPA=wayland
# loads them in the running session. Without IPC targets nothing is shown,
# because every window sits in a LazyLoader.
export QT_QPA_PLATFORM="${SMOKE_QPA:-offscreen}"
qs -p "$target" > "$tmp/log" 2>&1 &
pid=$!
sleep 3
for t in "$@"; do qs -p "$target" ipc call "$t" open >/dev/null 2>&1 || echo "ipc $t open failed"; done
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
