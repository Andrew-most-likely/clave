#!/usr/bin/env bash
# Clave installer. A polished desktop for Hyprland on Arch Linux.
#
#   ./install.sh                 packages, desktop, system parts and the
#                                security hardening layer (asks first)
#   ./install.sh --yes           same, without questions
#   ./install.sh --no-harden     everything except the hardening layer
#   ./install.sh --extras        also the optional apps in packages/extras*.txt
#   ./install.sh --personal      fonts, cursor and sounds you supply (see README)
#   ./install.sh --update        only refresh changed desktop files (clave-update)
#   ./install.sh --user-only     only files in $HOME, no sudo
#   ./install.sh --no-packages   skip pacman/AUR/Flatpak
#   ./install.sh --dry-run       show what would happen, change nothing
#
# Files you own are installed once and never replaced: hypr/custom.lua,
# hypr/monitors.lua, hypr/hypridle.conf, kitty/custom.conf, clave/*.
# Every other file that is replaced is first copied to
# ~/.local/state/clave/backups.
# An existing ML4W or other Hyprland setup is moved aside, not deleted.
# Undo with ./uninstall.sh.
set -euo pipefail
repo="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$repo/lib/common.sh"

harden=1 extras=0 personal=0 user_only=0 packages=1 update=0 encrypt=0 no_packages=0
for a in "$@"; do
    case "$a" in
        --harden) harden=1 ;;   # the default; kept for old scripts
        --no-harden) harden=0 ;;
        --extras) extras=1 ;;
        --personal) personal=1 ;;
        --update) update=1; packages=0; user_only=1 ;;
        --user-only) user_only=1 ;;
        --no-packages) packages=0; no_packages=1 ;;
        --dry-run) DRY=1 ;;
        --yes|-y) YES=1 ;;
        -h|--help) sed -n '2,20p' "$0" | cut -c3-; exit 0 ;;
        *) die "Unknown option: $a (see --help)" ;;
    esac
done
# The hardening layer is part of the system half.
[ "$user_only" -eq 0 ] || harden=0

log_start
preflight
[ "$update" -eq 1 ] || show_plan
# --personal is remembered, so updates keep the personal fonts and cursor.
if [ "$personal" -eq 1 ] && [ "$DRY" -eq 0 ]; then touch "$STATE/personal"; fi

# --- packages --------------------------------------------------------------
# First, so a failure here leaves the desktop as it was.
if [ "$packages" -eq 1 ]; then
    lists=(core look desktop apps)
    [ "$harden" -eq 1 ] && lists+=(harden)
    [ "$extras" -eq 1 ] && lists+=(extras)
    { [ "$personal" -eq 1 ] || personal_on "$HOME"; } && lists+=(personal)
    install_packages "${lists[@]}"
elif [ "$update" -eq 1 ] && [ "$no_packages" -eq 0 ]; then
    # A release can add standard apps (SW-4); an update brings them too. It
    # asks first, so only from a terminal (clave-update opens one).
    # shellcheck disable=SC2046  # one package per word
    missing=$(pacman -T $(pkgs "$repo/packages/apps.txt") 2>/dev/null || true)
    if [ -n "$missing" ]; then
        say "New standard apps: $(echo "$missing" | tr '\n' ' ')"
        if [ -t 0 ]; then ask "Install them?" y && install_packages apps
        else echo "  Install them with: sudo pacman -S --needed $(echo "$missing" | tr '\n' ' ')"; fi
    fi
    report_replaced_packages
fi

migrate_home

# --- files in $HOME --------------------------------------------------------
[ "$update" -eq 1 ] || move_aside_old_setup
install_home_files
remove_orphans
# GTK apps and portals read gsettings, which clave-gtk-apply sets from the
# installed settings.ini; otherwise the old font and cursor stay until login.
[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || [ "$DRY" -eq 1 ] || "$HOME/.local/bin/clave-gtk-apply" || true
[ "$update" -eq 1 ] || fetch_themes

# Displays (SHELL-2): an older displays.json gets one position per screen,
# and ~/.config/clave/monitors.lua is written from it.
run "$HOME/.local/bin/clave-displays" migrate || warn "Display settings not converted; run: clave-displays migrate"

# Standard apps (APP-4, APP-5, APP-6): the names shown in the Dock, Apps and
# Search, custom icons, and default apps. Written again on every update, so
# the copies follow the packages' own desktop files.
say "Standard apps"
run "$HOME/.local/bin/clave-prefs" apps names || warn "App names not set; run: clave-prefs apps names"
if [ "$update" -eq 1 ]; then run "$HOME/.local/bin/clave-prefs" apps defaults --missing-only || true
else run "$HOME/.local/bin/clave-prefs" apps defaults || true; fi
# Mail (extras) checks for new mail only while open.
run gsettings set org.gnome.Geary run-in-background false 2>/dev/null || true

say "Genie shaders and Hyprland plugins"
if [ "$update" -eq 0 ] || changed_since_last_install 'DockApp/shaders|hypr-minimize|hyprbars'; then
    run "$HOME/.config/quickshell/DockApp/shaders/build.sh" || warn "Shader build failed: the genie effect falls back to a plain fade"
    run "$HOME/.local/share/clave/rebuild-plugins.sh" || warn "Plugin build failed; see ~/.cache/clave/rebuild-plugins.log"
else
    echo "  unchanged"
fi

if [ "$update" -eq 0 ]; then
    if personal_on "$HOME"; then
        say "Personal sounds"
        if compgen -G "$HOME/.local/share/sounds/clave/source/*" >/dev/null; then
            run "$HOME/.local/bin/clave-sounds-build"
        else
            echo "  No source sounds: the freedesktop sounds are used. Put your own files in"
            echo "  ~/.local/share/sounds/clave/source/ and run clave-sounds-build."
        fi
    fi

    say "User services"
    run fc-cache -f
    run update-desktop-database -q "$HOME/.local/share/applications" || true
    run xdg-user-dirs-update || true
    run systemctl --user daemon-reload || true
    run systemctl --user enable --now home-cleanup.timer gnome-keyring-daemon.socket || true
    # Calculator works offline: no weekly download of currency rates.
    run gsettings set org.gnome.calculator refresh-interval 0 2>/dev/null || true
    # System Settings tells about blocked USB devices itself; earlier versions
    # also ran usbguard-notifier, which repeated every message.
    run systemctl --user disable --now usbguard-notifier.service 2>/dev/null || true
fi

# The upgrade check (COMP-9) reads root-owned copies of compat.json and
# clave-compat. An update that changed them refreshes them, which needs sudo:
# only from a terminal, and only where the system part was installed.
compat_current() {
    local hook=/etc/pacman.d/hooks/clave-doctor.hook
    cmp -s "$repo/compat.json" /usr/share/clave/compat.json &&
        cmp -s "$repo/home/.local/bin/clave-compat" /usr/local/lib/clave/clave-compat &&
        [ "$(awk '$1 == "repo" || $1 == "aur" { print $2 }' "$repo/.github/ci/watched.txt")" = "$(sed -n 's/^Target = //p' "$hook" 2>/dev/null)" ]
}
if [ "$update" -eq 1 ] && [ -e /var/lib/clave/installed-files ] && ! compat_current; then
    if [ -t 0 ]; then
        say "Upgrade check (sudo): compatibility list and pacman hook"
        run sudo "$repo/scripts/system.sh" compat || warn "Not updated; run: sudo $repo/scripts/system.sh compat"
    else
        warn "The upgrade check is out of date; run: sudo $repo/scripts/system.sh compat"
    fi
fi

# --- system part -----------------------------------------------------------
if [ "$user_only" -eq 0 ]; then
    groups=(look desktop)
    [ "$harden" -eq 1 ] && confirm_harden && groups+=(harden)
    say "System part (sudo): ${groups[*]}"
    run sudo "$repo/scripts/system.sh" "${groups[@]}"
    [ "$update" -eq 1 ] || { confirm_encryption && encrypt=1; } || true
fi

record_install
say "Done."
if [ "$update" -eq 1 ]; then
    # Quickshell reloads changed files by itself; Hyprland needs a nudge.
    [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || run hyprctl reload >/dev/null 2>&1 || true
    echo "Desktop files updated."
else
    echo "Log out and back in (or reboot) to start Clave."
    echo "Log: $LOG"
    echo "Undo: $repo/uninstall.sh"
    [ "$encrypt" -eq 0 ] || [ "$DRY" -eq 1 ] || "$HOME/.local/bin/clave-encrypt" setup
fi
