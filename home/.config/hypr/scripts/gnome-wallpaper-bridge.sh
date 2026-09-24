#!/usr/bin/env bash
# Forward the GNOME background setting (org.gnome.desktop.background picture-uri)
# to ML4W, for apps that write it directly.
last=""
gsettings monitor org.gnome.desktop.background | while read -r key value; do
    case "$key" in picture-uri:|picture-uri-dark:) ;; *) continue ;; esac
    uri=$(eval echo "$value")            # strip gsettings quoting
    [ "$uri" != "$last" ] || continue
    last="$uri"
    "$HOME/.config/hypr/scripts/set-wallpaper.sh" "$uri"
done
