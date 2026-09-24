#!/usr/bin/env bash
# Usage: set-wallpaper.sh <image path or file:// URI>
# Copies the image into the ML4W wallpaper folder and applies it (wallpaper + theme colors).
src="$1"
[[ "$src" == file://* ]] && src=$(python3 -c 'import sys,urllib.parse as u; print(u.unquote(u.urlparse(sys.argv[1]).path))' "$src")
[ -f "$src" ] || exit 1
dest="$HOME/.config/ml4w/wallpapers/$(basename "$src")"
[ "$src" -ef "$dest" ] || cp -f "$src" "$dest"
exec "$HOME/.config/ml4w/scripts/ml4w-wallpaper" "$dest" --notifications
