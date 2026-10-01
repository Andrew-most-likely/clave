#!/usr/bin/env bash
# Tests for Clave's app icons (PROJECT_PLAN.md BR-12, BR-4): the SVG files match
# scripts/make-icons.py, every app of the standard set has an icon, each icon
# renders, the shipped settings use the Clave themes, and the personal option
# maps them back to WhiteSur. With GTK 4 and WhiteSur installed, it also checks
# that GTK finds the icons through Clave-icons-dark. Changes nothing outside a
# temp directory.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
ok()   { echo "ok:   $*"; }
icons="$repo/home/.local/share/icons"
apps="$icons/Clave-icons/scalable/apps"

if "$repo/scripts/make-icons.py" --check; then ok "icons match scripts/make-icons.py"
else fail "icons out of date: run scripts/make-icons.py"; fi

# The icon names the standard apps ask for (desktop file Icon= and app ID),
# APP-1 and SW-3. Update this list when an app is added or its package renames
# its icon.
want=(
    org.gnome.Nautilus clave-apps utilities-system-monitor timeshift com.github.johnfactotum.Foliate
    org.gnome.Calculator x-office-calendar org.gnome.Snapshot org.gnome.Chess org.gnome.clocks
    org.gnome.Logs x-office-address-book org.gnome.DiskUtility org.gnome.Papers org.gnome.Evince
    org.gnome.font-viewer com.github.flxzt.rnote org.gnome.Loupe org.gnome.seahorse.Application
    org.gnome.Maps io.bassi.Amberol accessories-text-editor org.gnome.TextEditor org.gnome.Shotwell
    org.gnome.Podcasts io.github.mrvladus.List org.gnome.SimpleScan org.gnome.Connections sticky
    hardinfo2 org.gnome.Showtime org.gnome.SoundRecorder org.gnome.Weather io.github.kolunmi.Bazaar
    org.quickshell
)
missing=()
for n in "${want[@]}"; do [ -f "$apps/$n.svg" ] || missing+=("$n"); done
# Clave's own launchers too.
for d in "$repo"/home/.local/share/applications/*.desktop; do
    n=$(sed -n 's/^Icon=//p' "$d" | head -n1)
    [ -f "$apps/$n.svg" ] || missing+=("$n (${d##*/})")
done
if [ "${#missing[@]}" -eq 0 ]; then ok "every standard app has a Clave icon"
else fail "no Clave icon for: ${missing[*]}"; fi

if command -v rsvg-convert >/dev/null; then
    bad=()
    for f in "$apps"/*.svg; do
        rsvg-convert -w 64 -h 64 "$f" -o "$tmp/i.png" 2>/dev/null || bad+=("${f##*/}")
    done
    if [ "${#bad[@]}" -eq 0 ]; then ok "every icon renders"; else fail "icons that do not render: ${bad[*]}"; fi
else
    echo "skip: rsvg-convert not installed"
fi

# Both themes read the same files; the dark one through a relative directory.
if grep -qx 'Directories=../Clave-icons/scalable/apps' "$icons/Clave-icons-dark/index.theme" \
    && grep -qx 'Inherits=WhiteSur-dark,hicolor' "$icons/Clave-icons-dark/index.theme" \
    && grep -qx 'Inherits=WhiteSur,hicolor' "$icons/Clave-icons/index.theme"; then
    ok "Clave-icons-dark reads Clave-icons' files, both inherit WhiteSur"
else
    fail "index.theme files"
fi

# The public build sets the Clave themes everywhere an icon theme is named.
for f in .config/gtk-3.0/settings.ini .config/gtk-4.0/settings.ini .config/qt5ct/qt5ct.conf \
         .config/qt6ct/qt6ct.conf .config/rofi/clave-apps.rasi .config/rofi/clave-search.rasi; do
    if grep -qE '(gtk-icon-theme-name=|icon_theme=|icon-theme: *")Clave-icons-dark' "$repo/home/$f"; then ok "$f uses Clave-icons-dark"
    else fail "$f does not use Clave-icons-dark"; fi
done
if grep -q '"icons": "Clave-icons-dark"' "$repo/home/.local/bin/clave-prefs" \
    && grep -q '"icons": "Clave-icons",' "$repo/home/.local/bin/clave-prefs"; then
    ok "clave-prefs switches between the Clave themes"
else
    fail "clave-prefs THEMES does not name the Clave themes"
fi

# The personal option (BR-10) maps them back to WhiteSur, and nothing else.
cp "$repo/home/.config/gtk-3.0/settings.ini" "$tmp/settings.ini"
cp "$repo/home/.local/share/icons/Clave-icons-dark/index.theme" "$tmp/index.theme"
cp "$repo/home/.local/bin/clave-prefs" "$tmp/clave-prefs"
# shellcheck source=../lib/personal.sh
. "$repo/lib/personal.sh"
for f in settings.ini index.theme clave-prefs; do personal_fill "$tmp/$f"; done
if grep -qx 'gtk-icon-theme-name=WhiteSur-dark' "$tmp/settings.ini" \
    && grep -q '"icons": "WhiteSur-dark"' "$tmp/clave-prefs" && grep -q '"icons": "WhiteSur",' "$tmp/clave-prefs"; then
    ok "personal option uses the WhiteSur icons"
else
    fail "personal option did not switch the icon theme"
fi
if cmp -s "$tmp/index.theme" "$repo/home/.local/share/icons/Clave-icons-dark/index.theme"; then
    ok "personal option leaves the theme files alone"
else
    fail "personal option changed index.theme"
fi

# GTK finds the icons through the dark theme, and still gets WhiteSur's folders.
if [ -d /usr/share/icons/WhiteSur-dark ] && python3 -c 'import gi; gi.require_version("Gtk", "4.0")' 2>/dev/null; then
    out=$(python3 - "$icons" 2>/dev/null <<'EOF'
import sys, gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk
t = Gtk.IconTheme()
t.set_search_path([sys.argv[1], "/usr/share/icons"])
t.set_theme_name("Clave-icons-dark")
for n in ("org.gnome.Nautilus", "folder"):
    p = t.lookup_icon(n, None, 64, 1, Gtk.TextDirection.NONE, 0)
    print(n, p.get_file().get_path() if p.get_file() else "")
EOF
) || true
    if grep -q "^org.gnome.Nautilus $apps/org.gnome.Nautilus.svg$" <<<"$out" \
        && grep -q '^folder /usr/share/icons/WhiteSur-dark/' <<<"$out"; then
        ok "GTK: Files from Clave-icons, folders from WhiteSur-dark"
    else
        fail "GTK lookup: $out"
    fi
else
    echo "skip: GTK 4 or WhiteSur-dark not installed"
fi

echo
if [ "$fails" -eq 0 ]; then echo "All icon tests passed."; else echo "$fails failed."; exit 1; fi
