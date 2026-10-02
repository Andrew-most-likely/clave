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

# The icon names each app asks for (desktop file Icon=, app ID, and the generic
# names some versions use). Keys are packages, or Clave's own windows and
# notifications. Every app clave-prefs names (APP_NAMES, VISIBLE) and every
# default Dock pin must be here, every name here must have an icon, and every
# icon must belong to an entry here (BR-12, BR-13).
declare -A want=(
    [gnome-clocks]="org.gnome.clocks"
    [showtime]="org.gnome.Showtime" [snapshot]="org.gnome.Snapshot"
    [gnome-logs]="org.gnome.Logs"
    [hardinfo2]="hardinfo2" [gnome-disk-utility]="org.gnome.DiskUtility gnome-disks"
    [seahorse]="org.gnome.seahorse.Application seahorse" [timeshift]="timeshift"
    [nautilus]="org.gnome.Nautilus system-file-manager" [gnome-text-editor]="org.gnome.TextEditor"
    [gnome-calculator]="org.gnome.Calculator accessories-calculator" [loupe]="org.gnome.Loupe"
    [evince]="org.gnome.Evince org.gnome.Evince-symbolic" [papers]="org.gnome.Papers"
    [kitty]="kitty utilities-terminal" [file-roller]="org.gnome.FileRoller file-roller"
    [bazaar]="io.github.kolunmi.Bazaar"
    [clave-apps]="clave-apps" [clave-screenshot]="clave-screenshot" [clave-activity-monitor]="utilities-system-monitor org.gnome.SystemMonitor"
    [clave-calendar]="x-office-calendar"
    [clave-settings]="preferences-system" [clave-about]="clave-logo" [clave-update]="system-software-update software-update-available"
    [quickshell]="org.quickshell"
)
# Dock pins (desktop IDs) -> key above. Firefox is an extra: it keeps its own logo.
declare -A pin_key=([org.gnome.Nautilus]=nautilus [org.gnome.TextEditor]=gnome-text-editor
    [org.gnome.Calculator]=gnome-calculator [kitty]=kitty [clave-apps]=clave-apps [firefox]=-)

# Every icon name above, one per element.
names=()
for k in "${!want[@]}"; do read -ra v <<< "${want[$k]}"; names+=("${v[@]}"); done

mapfile -t listed < <(python3 - "$repo/home/.local/bin/clave-prefs" <<'PY'
import ast, sys
for node in ast.parse(open(sys.argv[1]).read()).body:
    if isinstance(node, ast.Assign) and node.targets[0].id in ("APP_NAMES", "VISIBLE"):
        v = ast.literal_eval(node.value)
        print("\n".join(v.keys() if isinstance(v, dict) else v))
PY
)
missing=()
for pkg in "${listed[@]}"; do [ -n "${want[$pkg]:-}" ] || missing+=("$pkg (clave-prefs)"); done
mapfile -t pins < <(sed '1,/\*\//d' "$repo/home/.config/quickshell/DockApp/dock.json" | jq -r '.apps.pinned[]')
for id in "${pins[@]}"; do [ -n "${pin_key[$id]:-}" ] || missing+=("$id (dock.json pin)"); done
# Clave's own launchers, and the windows the Dock and Overview map by title.
for d in "$repo"/home/.local/share/applications/*.desktop; do
    n=$(sed -n 's/^Icon=//p' "$d" | head -n1)
    [[ " ${names[*]} " == *" $n "* ]] || missing+=("$n (${d##*/})")
done
for n in $(sed -n '/shellWindows: ({/,/})/p' "$repo/home/.config/quickshell/Clave/ClaveSettings.qml" \
           | grep -oE '": "[a-z.-]+"' | sed 's/": "//; s/"$//'); do
    # A Clave desktop file: its Icon= is checked above.
    [ -f "$repo/home/.local/share/applications/$n.desktop" ] && continue
    [[ " ${names[*]} " == *" $n "* ]] || missing+=("$n (ClaveSettings.shellWindows)")
done
for n in "${names[@]}"; do [ -f "$apps/$n.svg" ] || missing+=("$n.svg"); done
if [ "${#missing[@]}" -eq 0 ]; then ok "every app, pin and Clave window has a Clave icon"
else fail "no Clave icon for: ${missing[*]}"; fi

orphans=()
for f in "$apps"/*.svg; do
    n=${f##*/}; n=${n%.svg}
    [[ " ${names[*]} " == *" $n "* ]] || orphans+=("$n")
done
if [ "${#orphans[@]}" -eq 0 ]; then ok "every icon belongs to an app"
else fail "icons no app asks for: ${orphans[*]}"; fi

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
