#!/usr/bin/env bash
# Downloads the third-party theme pieces that this repo does not ship:
#   - WhiteSur GTK theme and its Firefox theme (GTK4 apps get it through
#     ~/.config/gtk-4.0/gtk.css and the assets link that install.sh makes)
#     https://github.com/vinceliuice/WhiteSur-gtk-theme
#   - WhiteSur wallpapers (Sonoma/Ventura/Monterey style)
#     https://github.com/vinceliuice/WhiteSur-wallpapers
# Apple fonts, macOS cursor and WhiteSur icons/Kvantum come from the AUR
# (packages/look-aur.txt). macOS system sounds are Apple's and are never
# downloaded: copy them off a Mac, see README.
set -euo pipefail
cache="${XDG_CACHE_HOME:-$HOME/.cache}/macos-look/src"
mkdir -p "$cache"

fetch() {  # fetch NAME URL: shallow clone or update
    if [ -d "$cache/$1/.git" ]; then git -C "$cache/$1" pull -q --ff-only
    else git clone -q --depth 1 "$2" "$cache/$1"; fi
}

echo "==> WhiteSur GTK theme"
fetch WhiteSur-gtk-theme https://github.com/vinceliuice/WhiteSur-gtk-theme
(cd "$cache/WhiteSur-gtk-theme" && ./install.sh -d "$HOME/.local/share/themes" -c dark -c light </dev/null 2>&1 | tail -n 3)

echo "==> WhiteSur Firefox theme"
if [ -d "$HOME/.config/mozilla/firefox" ] || [ -d "$HOME/.mozilla/firefox" ]; then
    (cd "$cache/WhiteSur-gtk-theme" && ./tweaks.sh -f 2>&1 | tail -n 3) || echo "  Firefox theme skipped (start Firefox once, then re-run)"
else
    echo "  no Firefox profile yet, skipped"
fi

echo "==> Wallpapers"
fetch WhiteSur-wallpapers https://github.com/vinceliuice/WhiteSur-wallpapers
wp="$HOME/.local/share/macos-look/wallpapers"
mkdir -p "$wp"
find "$cache/WhiteSur-wallpapers" -path '*4k*' \( -iname '*sonoma*' -o -iname '*ventura*' -o -iname '*monterey*' -o -iname 'WhiteSur*' \) \
     \( -iname '*.jpg' -o -iname '*.png' \) -exec cp -n {} "$wp/" \; 2>/dev/null || true
n=$(find "$wp" -maxdepth 1 -type f | wc -l)
echo "  $n wallpapers in $wp"
