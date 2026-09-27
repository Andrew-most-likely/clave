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

harden=1 extras=0 personal=0 user_only=0 packages=1 update=0
for a in "$@"; do
    case "$a" in
        --harden) harden=1 ;;   # the default; kept for old scripts
        --no-harden) harden=0 ;;
        --extras) extras=1 ;;
        --personal) personal=1 ;;
        --update) update=1; packages=0; user_only=1 ;;
        --user-only) user_only=1 ;;
        --no-packages) packages=0 ;;
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
    lists=(core look desktop)
    [ "$harden" -eq 1 ] && lists+=(harden)
    [ "$extras" -eq 1 ] && lists+=(extras)
    { [ "$personal" -eq 1 ] || personal_on "$HOME"; } && lists+=(personal)
    install_packages "${lists[@]}"
fi

migrate_home

# --- files in $HOME --------------------------------------------------------
[ "$update" -eq 1 ] || move_aside_old_setup
install_home_files
remove_orphans
[ "$update" -eq 1 ] || fetch_themes

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

# --- system part -----------------------------------------------------------
if [ "$user_only" -eq 0 ]; then
    groups=(look desktop)
    [ "$harden" -eq 1 ] && confirm_harden && groups+=(harden)
    say "System part (sudo): ${groups[*]}"
    run sudo "$repo/scripts/system.sh" "${groups[@]}"
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
fi
