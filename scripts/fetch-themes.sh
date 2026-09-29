#!/usr/bin/env bash
# Downloads the third-party theme pieces that this repo does not ship:
#   - WhiteSur GTK theme and its Firefox theme (GTK4 apps get it through
#     ~/.config/gtk-4.0/gtk.css and the assets link that install.sh makes)
#     https://github.com/vinceliuice/WhiteSur-gtk-theme
#   - WhiteSur wallpapers (only WhiteSur's own designs)
#     https://github.com/vinceliuice/WhiteSur-wallpapers
# The cursor and WhiteSur icons/Kvantum come from the AUR (packages/look-aur.txt).
set -euo pipefail
# WhiteSur's installer stops without a terminal type (scripted installs, CI).
export TERM="${TERM:-dumb}"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/clave/src"
mkdir -p "$cache"

fetch() {  # fetch NAME URL: shallow clone or update
    if [ -d "$cache/$1/.git" ]; then git -C "$cache/$1" pull -q --ff-only
    else git clone -q --depth 1 "$2" "$cache/$1"; fi
}

echo "==> WhiteSur GTK theme"
fetch WhiteSur-gtk-theme https://github.com/vinceliuice/WhiteSur-gtk-theme
(cd "$cache/WhiteSur-gtk-theme" && ./install.sh -d "$HOME/.local/share/themes" -c dark -c light </dev/null 2>&1 | tail -n 3)
# Its installer always adds a theme switcher app; Clave Settings does that job (APP-10).
rm -f "$HOME/.local/bin/gnome-theme-switcher" \
      "${XDG_DATA_HOME:-$HOME/.local/share}/applications/org.gnome.GTK4ThemeSwitcher.desktop"

echo "==> WhiteSur Firefox theme"
if [ -d "$HOME/.config/mozilla/firefox" ] || [ -d "$HOME/.mozilla/firefox" ]; then
    if pgrep -x firefox >/dev/null; then
        echo "  skipped: Firefox is open. Close it and run install.sh again for the Firefox theme."
    else
        (cd "$cache/WhiteSur-gtk-theme" && ./tweaks.sh -f 2>&1 | tail -n 3) || echo "  Firefox theme skipped (start Firefox once, then re-run)"
    fi
else
    echo "  no Firefox profile yet, skipped"
fi

echo "==> Wallpapers"
fetch WhiteSur-wallpapers https://github.com/vinceliuice/WhiteSur-wallpapers
wp="$HOME/.local/share/clave/wallpapers"
mkdir -p "$wp"
find "$cache/WhiteSur-wallpapers" -path '*4k*' -iname 'WhiteSur*' \
     \( -iname '*.jpg' -o -iname '*.png' \) -exec cp -n {} "$wp/" \; 2>/dev/null || true
n=$(find "$wp" -maxdepth 1 -type f | wc -l)
echo "  $n wallpapers in $wp"
