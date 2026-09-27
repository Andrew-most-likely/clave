#!/usr/bin/env bash
# Installs into a scratch home that looks like an ML4W setup, checks the
# result, uninstalls and checks that the earlier setup is back.
# Run as a normal user:  tests/install-test.sh
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
home=$(mktemp -d "${TMPDIR:-/var/tmp}/amh-test.XXXXXX")
trap 'rm -rf "$home"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# An "ML4W" home: config directories linked into ~/.mydotfiles.
ml4w="$home/.mydotfiles/cfg"
mkdir -p "$home/.config" "$ml4w/hypr" "$ml4w/rofi"
echo 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 2 })' > "$ml4w/hypr/monitors.lua"
echo 'old' > "$ml4w/hypr/hyprland.lua"
echo 'old' > "$ml4w/rofi/config.rasi"
ln -s "$ml4w/hypr" "$home/.config/hypr"
ln -s "$ml4w/rofi" "$home/.config/rofi"

run() { env -i HOME="$home" PATH="$PATH" USER="$(id -un)" TERM=dumb "$@"; }

echo "==> install"
run "$repo/install.sh" --user-only --no-packages --yes

state="$home/.local/state/macos-look"
for f in .config/hypr/hyprland.lua .config/hypr/macos/binds.lua .config/hypr/custom.lua \
         .config/quickshell/shell.qml .local/bin/macos-wallpaper .local/share/applications/launchpad.desktop; do
    [ -f "$home/$f" ] || fail "missing ~/$f"
done
[ -L "$home/.config/hypr.bak-$(date +%F)" ] || fail "old hypr link was not moved aside"
grep -q 'scale = 2' "$home/.config/hypr/monitors.lua" || fail "monitors.lua was not carried over"
[ -d "$home/.config/rofi" ] && [ ! -L "$home/.config/rofi" ] || fail "rofi link was not turned into a directory"
[ "$(cat "$ml4w/rofi/config.rasi")" = old ] || fail "installer wrote into the linked ML4W tree"
! grep -rl '__HOME__\|__REPO__\|__GITHUB_REPO__' "$home/.config" "$home/.local" 2>/dev/null | grep -v '\.bak-' \
    || fail "placeholders left unfilled"
[ -s "$state/installed-files" ] || fail "no install record"

if command -v Hyprland >/dev/null; then
    echo "==> Hyprland --verify-config"
    out=$(XDG_RUNTIME_DIR="$home" HOME="$home" Hyprland --verify-config -c "$home/.config/hypr/hyprland.lua" 2>&1 || true)
    echo "$out" | tail -n 5
    echo "$out" | grep -q 'config ok' || fail "installed Hyprland config has errors"
fi

echo "==> second install keeps user files"
echo '-- mine' >> "$home/.config/hypr/custom.lua"
run "$repo/install.sh" --update
grep -q -- '-- mine' "$home/.config/hypr/custom.lua" || fail "custom.lua was replaced"

echo "==> uninstall"
run "$repo/uninstall.sh"
[ "$(readlink "$home/.config/hypr")" = "$ml4w/hypr" ] || fail "hypr link not restored"
[ "$(readlink "$home/.config/rofi")" = "$ml4w/rofi" ] || fail "rofi link not restored"
[ ! -e "$home/.local/bin/macos-wallpaper" ] || fail "installed file left behind"

echo "PASS"
