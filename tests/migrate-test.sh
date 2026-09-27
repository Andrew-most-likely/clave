#!/usr/bin/env bash
# Installs the last release under the old names into a scratch home, changes
# some settings, updates to this checkout and checks that the install moved to
# the Clave names with the settings kept (PROJECT_PLAN.md BR-9). Then
# uninstalls and checks that nothing is left.
# Run as a normal user:  tests/migrate-test.sh [OLD_REF]
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
old_ref=${1:-fbdf4dd}
tmp=$(mktemp -d "${TMPDIR:-/var/tmp}/clave-migrate.XXXXXX")
trap '[ -n "${KEEP:-}" ] || rm -rf "$tmp"' EXIT
home="$tmp/home" old="$tmp/old"
mkdir -p "$home" "$old"
fail() { echo "FAIL: $*" >&2; exit 1; }
run() { env -i HOME="$home" PATH="$PATH" USER="$(id -un)" TERM=dumb "$@"; }

git -C "$repo" archive "$old_ref" | tar -x -C "$old"
old_name=$(grep -o 'state}/[a-z-]*' "$old/lib/common.sh" | cut -d/ -f2)

echo "==> install $old_ref"
run bash "$old/install.sh" --user-only --no-packages --yes >/dev/null
cfg="$home/.config/$old_name"
[ -f "$cfg/settings.json" ] || fail "old install has no settings.json"
jq '.search_old = 1 | .display.nightShiftTemp = 3800 | .hotCorners.topLeft = "launchpad"
    | .spotlight = {"web": true}' "$cfg/settings.json" > "$tmp/s" && mv "$tmp/s" "$cfg/settings.json"
printf '{\n    "apps": {\n        "pinned": ["firefox", "launchpad"]\n    }\n}\n' > "$cfg/dock.json"
echo 'hl.layer_rule({ match = { namespace = "macos-genie" }, no_anim = true }) -- macos-spotlight' \
    >> "$home/.config/hypr/custom.lua"

echo "==> update to this checkout"
run "$repo/install.sh" --user-only --no-packages --yes >/dev/null

new="$home/.config/clave"
[ ! -e "$cfg" ] || fail "old config directory still there"
[ ! -e "$home/.local/state/$old_name" ] || fail "old state directory still there"
[ ! -e "$home/.local/share/$old_name" ] || fail "old data directory still there"
[ "$(jq -r .display.nightLightTemp "$new/settings.json")" = 3800 ] || fail "night light temperature lost"
[ "$(jq -r .hotCorners.topLeft "$new/settings.json")" = apps ] || fail "hot corner not renamed"
[ "$(jq -r .search.web "$new/settings.json")" = true ] || fail "search settings lost"
[ "$(jq -r .search_old "$new/settings.json")" = 1 ] || fail "unknown settings dropped"
[ "$(jq -c .apps.pinned "$new/dock.json")" = '["firefox","clave-apps"]' ] || fail "Dock pins not renamed"
grep -q 'namespace = "clave-genie".*clave-search' "$home/.config/hypr/custom.lua" || fail "custom.lua not updated"
[ -f "$home/.local/state/clave/backups/.config/hypr/custom.lua.pre-clave" ] || fail "no copy of the old custom.lua"
[ -f "$home/.config/hypr/clave/binds.lua" ] || fail "new Hyprland config missing"
[ ! -e "$home/.config/hypr/macos" ] || fail "old Hyprland config left behind"
[ ! -e "$home/.config/hypr.bak-$(date +%F)" ] || fail "old install was moved aside instead of updated"
! find "$home" -iname '*macos*' -not -name '*.pre-clave' | grep . || fail "files with old names left behind"
while IFS= read -r f; do [ -e "$f" ] || fail "install record lists missing $f"; done \
    < "$home/.local/state/clave/installed-files"

echo "==> second update changes nothing"
cp "$new/settings.json" "$tmp/before"
out=$(run "$repo/install.sh" --update)
! grep -qE '^  updated|Moving' <<< "$out" || fail "second update migrated again"
cmp -s "$tmp/before" "$new/settings.json" || fail "second update rewrote settings.json"

echo "==> uninstall"
run "$repo/uninstall.sh" >/dev/null
[ ! -e "$home/.config/quickshell/Clave" ] || fail "installed files left behind"

echo "PASS"
