#!/usr/bin/env bash
# Tests for the standard-app helpers in clave-prefs (APP-4): desktop file
# overrides with Clave's names and custom icons, and the image checks. Uses a
# scratch XDG_CONFIG_HOME, XDG_DATA_HOME and XDG_DATA_DIRS; changes nothing
# else. Needs python and ImageMagick (magick) or skips the icon cases.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
ok()   { echo "ok:   $*"; }
has()  { if grep -qE -- "$2" "$1" 2>/dev/null; then ok "$3"; else fail "$3: /$2/ not in $1"; fi; }

export XDG_CONFIG_HOME="$tmp/config" XDG_DATA_HOME="$tmp/data" XDG_DATA_DIRS="$tmp/sys"
mkdir -p "$XDG_CONFIG_HOME/clave" "$XDG_DATA_HOME" "$tmp/sys/applications"
echo '{"appearance":{"mode":"dark"}}' > "$XDG_CONFIG_HOME/clave/settings.json"
cat > "$tmp/sys/applications/org.example.Viewer.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Example Viewer
Name[de]=Beispiel
Exec=example-viewer %U
Icon=org.example.Viewer

[Desktop Action new-window]
Name=New Window
Exec=example-viewer --new-window
EOF
prefs="$repo/home/.local/bin/clave-prefs"
dst="$XDG_DATA_HOME/applications/org.example.Viewer.desktop"

echo notapicture > "$tmp/fake.png"
if "$prefs" icon set org.example.Viewer "$tmp/fake.png" 2>/dev/null; then fail "a text file named .png is refused"
else ok "a text file named .png is refused"; fi
if "$prefs" icon set '../evil' "$tmp/fake.png" 2>/dev/null; then fail "a bad app id is refused"
else ok "a bad app id is refused"; fi

if command -v magick >/dev/null; then
    magick -size 64x64 xc:red "$tmp/red.png"
    "$prefs" icon set org.example.Viewer "$tmp/red.png"
    has "$XDG_CONFIG_HOME/clave/settings.json" '"org.example.Viewer"' "icon saved in settings.json"
    has "$XDG_CONFIG_HOME/clave/settings.json" '"mode": "dark"' "other settings kept"
    has "$dst" "^Icon=$XDG_DATA_HOME/clave/icons/org.example.Viewer.png$" "override points at the converted icon"
    has "$dst" '^Exec=example-viewer %U$' "Exec stays the package's own"
    has "$dst" '^Name\[de\]=Beispiel$' "Name kept when only the icon changes"
    has "$dst" '^Name=New Window$' "action groups kept"
    has "$dst" '^X-Clave-Override=true$' "override is marked"
    [ "$(grep -c '^Icon=' "$dst")" = 1 ] && ok "one Icon= line" || fail "Icon= lines: $(grep -c '^Icon=' "$dst")"
    file --brief --mime-type "$XDG_DATA_HOME/clave/icons/org.example.Viewer.png" | grep -q image/png \
        && ok "icon is a PNG" || fail "icon is not a PNG"
    "$prefs" icon reset org.example.Viewer
    [ ! -e "$dst" ] && ok "reset removes the override" || fail "override still there after reset"
    [ ! -e "$XDG_DATA_HOME/clave/icons/org.example.Viewer.png" ] && ok "reset removes the icon" || fail "icon still there"
else
    echo "skip: magick not installed"
fi

# The user's own desktop file is never replaced.
mkdir -p "$XDG_DATA_HOME/applications"
printf '[Desktop Entry]\nType=Application\nName=Mine\nExec=mine\n' > "$dst"
if command -v magick >/dev/null; then
    "$prefs" icon set org.example.Viewer "$tmp/red.png"
    has "$dst" '^Name=Mine$' "the user's own file wins"
fi

# Helper launchers are hidden, and their copy still opens files (APP-10).
cat > "$tmp/sys/applications/org.gnome.FileRoller.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=File Roller
Exec=file-roller %U
MimeType=application/zip;
NoDisplay=false
EOF
roller="$XDG_DATA_HOME/applications/org.gnome.FileRoller.desktop"
"$prefs" apps names
has "$roller" '^NoDisplay=true$' "helper launcher hidden"
[ "$(grep -c '^NoDisplay=' "$roller")" = 1 ] && ok "one NoDisplay= line" || fail "NoDisplay= lines: $(grep -c '^NoDisplay=' "$roller")"
has "$roller" '^MimeType=application/zip;$' "hidden helper keeps its file types"
has "$roller" '^X-Clave-Override=true$' "hidden helper override is marked"
rm "$tmp/sys/applications/org.gnome.FileRoller.desktop"
"$prefs" apps names
[ ! -e "$roller" ] && ok "override removed when the helper is gone" || fail "override left after the helper is gone"

# gtk.css keeps loading clave.css after a light/dark switch.
python3 - "$prefs" "$tmp" <<'EOF'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("prefs", sys.argv[1])
spec = importlib.util.spec_from_loader("prefs", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
for mode in ("light", "dark"):
    css = m.gtk4_css(mode)
    assert "clave.css" in css and "WhiteSur" in css, css
print("ok:   gtk.css imports clave.css in light and dark")
EOF

echo
if [ "$fails" -eq 0 ]; then echo "All app tests passed."; else echo "$fails failed."; exit 1; fi
