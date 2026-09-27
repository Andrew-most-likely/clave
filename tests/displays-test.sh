#!/usr/bin/env bash
# Tests for clave-displays (SHELL-2) with a fake hyprctl: the migration of an
# old displays.json, the desc: rules in monitors.lua, "use" (extend, mirror,
# off), mirroring from Control Center and the lid. With Hyprland installed,
# the generated rules also pass `Hyprland --verify-config`.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
trap '[ -n "${KEEP:-}" ] || rm -rf "$tmp"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
ok()   { echo "ok:   $*"; }
has()  { if grep -qE -- "$2" "$1" 2>/dev/null; then ok "$3"; else fail "$3: /$2/ not in $1"; sed 's/^/      /' "$1"; fi; }
hasnt() { if grep -qE -- "$2" "$1" 2>/dev/null; then fail "$3: /$2/ in $1"; else ok "$3"; fi; }

export XDG_CONFIG_HOME="$tmp/config"
mkdir -p "$XDG_CONFIG_HOME/clave" "$tmp/bin"
# Fake hyprctl: prints $tmp/monitors.json, logs every eval.
cat > "$tmp/bin/hyprctl" <<EOF
#!/bin/sh
case "\$1" in
    monitors) cat "$tmp/monitors.json" ;;
    eval) printf '%s\n' "\$2" >> "$tmp/evals" ;;
esac
EOF
chmod +x "$tmp/bin/hyprctl"
export PATH="$tmp/bin:$PATH"
cat > "$tmp/monitors.json" <<'EOF'
[{"name":"eDP-1","description":"BOE 0x0BCA","width":2880,"height":1800,"scale":1.5,"transform":0,
  "x":0,"y":0,"disabled":false,"mirrorOf":"none","availableModes":["2880x1800@120.00Hz"]},
 {"name":"DP-3","description":"Dell Inc. DELL U2720Q 7Z1QK13","width":3840,"height":2160,"scale":2,"transform":0,
  "x":1920,"y":0,"disabled":false,"mirrorOf":"none","availableModes":["3840x2160@60.00Hz"]},
 {"name":"DP-4","description":"Dell Inc. DELL \"P2419H\" AB12","width":1920,"height":1080,"scale":1,"transform":1,
  "x":3840,"y":0,"disabled":false,"mirrorOf":"none","availableModes":["1920x1080@60.00Hz"]}]
EOF
dsp="$repo/home/.local/bin/clave-displays"
lua="$XDG_CONFIG_HOME/clave/monitors.lua"
json="$XDG_CONFIG_HOME/clave/displays.json"

# Migration: per-set layouts become one position per screen, from the
# largest set.
cat > "$json" <<'EOF'
{"displays": {"Dell Inc. DELL U2720Q 7Z1QK13": {"scale": 1.5, "mode": "3840x2160@60"}},
 "layouts": {"BOE 0x0BCA|Dell Inc. DELL U2720Q 7Z1QK13": {"BOE 0x0BCA": [0, 200], "Dell Inc. DELL U2720Q 7Z1QK13": [1920, 0]},
             "Dell Inc. DELL U2720Q 7Z1QK13": {"Dell Inc. DELL U2720Q 7Z1QK13": [0, 0]}}}
EOF
"$dsp" migrate
has "$json" '"version": 2' "migrated to version 2"
hasnt "$json" '"layouts"' "per-set layouts dropped"
jq -e '.displays["Dell Inc. DELL U2720Q 7Z1QK13"].position == [1920, 0]' "$json" >/dev/null \
    && ok "position from the largest set" || fail "position of the Dell screen"
jq -e '.displays["Dell Inc. DELL U2720Q 7Z1QK13"].scale == 1.5' "$json" >/dev/null \
    && ok "other settings kept" || fail "scale lost"
has "$lua" '^hl\.monitor\(\{ output = "desc:Dell Inc\. DELL U2720Q 7Z1QK13", mode = "3840x2160@60", position = "1920x0", scale = 1\.5, transform = 0, disabled = false, mirror = "" \}\)$' "desc: rule written"
has "$lua" 'output = "desc:BOE 0x0BCA".*position = "0x200"' "built-in screen rule"
[ ! -e "$tmp/evals" ] && ok "migrate applies nothing" || fail "migrate ran hyprctl eval"
"$dsp" migrate
cp "$json" "$tmp/once.json"; "$dsp" migrate
cmp -s "$json" "$tmp/once.json" && ok "migrate twice changes nothing" || fail "second migrate changed displays.json"

# Arrange and a quote in a description (EDID text goes into Lua).
"$dsp" arrange '{"BOE 0x0BCA": [100, 300], "Dell Inc. DELL U2720Q 7Z1QK13": [1980, 100], "Dell Inc. DELL \"P2419H\" AB12": [3900, 100]}'
has "$lua" 'desc:BOE 0x0BCA", mode = "preferred", position = "0x200"' "arrange normalizes to 0,0 at the top left"
has "$lua" 'output = "desc:Dell Inc\. DELL \\"P2419H\\" AB12"' "quotes escaped for Lua"
[ "$(wc -l < "$tmp/evals")" -ge 3 ] && ok "arrange applies with hyprctl eval" || fail "no evals after arrange"

# Use as: mirror and off
: > "$tmp/evals"
"$dsp" use "Dell Inc. DELL U2720Q 7Z1QK13" "mirror:BOE 0x0BCA"
has "$lua" 'desc:Dell Inc\. DELL U2720Q 7Z1QK13".*disabled = false, mirror = "eDP-1"' "mirror rule names the source's connector"
"$dsp" use "Dell Inc. DELL U2720Q 7Z1QK13" extend
has "$lua" 'desc:Dell Inc\. DELL U2720Q 7Z1QK13".*mirror = "" \}' "back to extended"
"$dsp" use "BOE 0x0BCA" off
has "$lua" 'desc:BOE 0x0BCA".*disabled = true' "built-in screen off"
tail -n1 "$tmp/evals" | grep -q 'desc:BOE 0x0BCA' && ok "the screen that goes off is applied last" || fail "order of evals: $(tail -n1 "$tmp/evals")"
"$dsp" use "BOE 0x0BCA" extend
if "$dsp" use "BOE 0x0BCA" "mirror:BOE 0x0BCA" 2>/dev/null; then fail "a screen cannot mirror itself"; else ok "a screen cannot mirror itself"; fi
if "$dsp" use "Nope" extend 2>/dev/null; then fail "unknown screen refused"; else ok "unknown screen refused"; fi

# Control Center: mirror toggle
"$dsp" mirror on
[ "$(grep -c 'mirror = "eDP-1"' "$lua")" = 2 ] && ok "mirror on: both external screens mirror the built-in one" || fail "mirror on"
"$dsp" mirror off
hasnt "$lua" 'mirror = "eDP-1"' "mirror off"

# Lid: closed with other screens on turns the panel off, without saving it.
: > "$tmp/evals"
"$dsp" lid closed
grep -q 'output = "eDP-1", disabled = true' "$tmp/evals" && ok "lid closed: panel off" || fail "lid closed"
hasnt "$lua" 'desc:BOE 0x0BCA".*disabled = true' "lid state is not saved"
"$dsp" lid open
grep -q 'desc:BOE 0x0BCA.*disabled = false' "$tmp/evals" && ok "lid open: rules applied again" || fail "lid open"

# The rules load in Hyprland's Lua config.
if command -v Hyprland >/dev/null && [ "$(id -u)" -ne 0 ]; then
    printf 'pcall(dofile, "%s")\n' "$lua" > "$tmp/hyprland.lua"
    if XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$tmp}" Hyprland --verify-config -c "$tmp/hyprland.lua" 2>&1 | grep -q 'config ok'; then
        ok "Hyprland accepts monitors.lua"
    else
        dofile_out=$(XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$tmp}" Hyprland --verify-config -c "$lua" 2>&1 | tail -5)
        fail "Hyprland --verify-config: $dofile_out"
    fi
fi

echo
if [ "$fails" -eq 0 ]; then echo "All display tests passed."; else echo "$fails failed."; exit 1; fi
