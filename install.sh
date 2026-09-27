#!/usr/bin/env bash
# arch-macos-hyprland installer. A macOS desktop on Hyprland for Arch Linux.
#
#   ./install.sh                 packages + desktop + system parts (asks first)
#   ./install.sh --yes           same, without questions (hardening stays off)
#   ./install.sh --harden        also the security hardening layer (asks first)
#   ./install.sh --extras        also the optional apps in packages/extras*.txt
#   ./install.sh --update        only refresh changed desktop files (macos-update)
#   ./install.sh --user-only     only files in $HOME, no sudo
#   ./install.sh --no-packages   skip pacman/AUR/Flatpak
#   ./install.sh --dry-run       show what would happen, change nothing
#
# Files you own are installed once and never replaced: hypr/custom.lua,
# hypr/monitors.lua, hypr/hypridle.conf, kitty/custom.conf, macos-look/*.
# Every other file that is replaced is first copied to
# ~/.local/state/macos-look/backups.
# An existing ML4W or other Hyprland setup is moved aside, not deleted.
# Undo with ./uninstall.sh.
set -euo pipefail
repo="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$repo/lib/common.sh"

harden=0 extras=0 user_only=0 packages=1 update=0
for a in "$@"; do
    case "$a" in
        --harden) harden=1 ;;
        --extras) extras=1 ;;
        --update) update=1; packages=0; user_only=1 ;;
        --user-only) user_only=1 ;;
        --no-packages) packages=0 ;;
        --dry-run) DRY=1 ;;
        --yes|-y) YES=1 ;;
        -h|--help) sed -n '2,18p' "$0" | cut -c3-; exit 0 ;;
        *) die "Unknown option: $a (see --help)" ;;
    esac
done

log_start
preflight
[ "$update" -eq 1 ] || show_plan

# --- packages --------------------------------------------------------------
if [ "$packages" -eq 1 ]; then
    lists=(core look desktop)
    [ "$harden" -eq 1 ] && lists+=(harden)
    [ "$extras" -eq 1 ] && lists+=(extras)
    install_packages "${lists[@]}"
fi

# --- files in $HOME --------------------------------------------------------
[ "$update" -eq 1 ] || move_aside_old_setup
install_home_files
[ "$update" -eq 1 ] || fetch_themes

say "Genie shaders and Hyprland plugins"
if [ "$update" -eq 0 ] || changed_since_last_install 'DockApp/shaders|hypr-minimize|hyprbars'; then
    run "$HOME/.config/quickshell/DockApp/shaders/build.sh" || warn "Shader build failed: the genie effect falls back to a plain fade"
    run "$HOME/.local/share/macos-look/rebuild-plugins.sh" || warn "Plugin build failed; see ~/.cache/macos-look/rebuild-plugins.log"
else
    echo "  unchanged"
fi

if [ "$update" -eq 0 ]; then
    say "macOS sounds"
    if compgen -G "$HOME/.local/share/sounds/macOS/source/*" >/dev/null; then
        run "$HOME/.local/bin/macos-sounds-build"
    else
        echo "  No source sounds. Copy the .aiff files from a Mac's /System/Library/Sounds"
        echo "  into ~/.local/share/sounds/macOS/source/ and run macos-sounds-build."
    fi

    say "User services"
    run fc-cache -f
    run update-desktop-database -q "$HOME/.local/share/applications" || true
    run xdg-user-dirs-update || true
    run systemctl --user daemon-reload || true
    run systemctl --user enable --now home-cleanup.timer gnome-keyring-daemon.socket || true
    [ "$harden" -eq 1 ] && { run systemctl --user enable usbguard-notifier.service || true; }
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
    echo "Log out and back in (or reboot) to start the macOS desktop."
    echo "Log: $LOG"
    echo "Undo: $repo/uninstall.sh"
fi
