#!/usr/bin/env bash
# Undoes install.sh.
#   - every file it wrote is restored from its oldest <file>.bak-<date>, or
#     removed when there was no earlier version
#   - config directories it moved aside (an earlier ML4W or other setup) come
#     back, and directories it turned from links into copies become links again
#   - with --system, also undoes scripts/system.sh (sudo)
# Packages stay installed.
set -euo pipefail
repo="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$repo/lib/common.sh"

restore() {  # restore FILE [sudo]: oldest backup = the state before the first install
    local f="$1" s="${2:-}" bak
    bak=$($s sh -c "ls -1d '$f'.bak-* 2>/dev/null | sort | head -n1")
    if [ -n "$bak" ]; then $s rm -rf "$f"; $s mv "$bak" "$f"; echo "  restored $f"
    else $s rm -rf "$f"; echo "  removed  $f"; fi
}

if [ -f "$STATE/installed-files" ]; then
    say "Files in $HOME"
    while IFS= read -r f; do restore "$f"; done < "$STATE/installed-files"
    rm -f "$STATE/installed-files"
    systemctl --user disable --now home-cleanup.timer 2>/dev/null || true
else
    echo "Nothing recorded in $STATE/installed-files"
fi

if [ -f "$STATE/moved-aside" ]; then
    say "Earlier setup"
    # Newest first, so a directory moved twice ends up as it was originally.
    tac "$STATE/moved-aside" | while IFS=$'\t' read -r kind path other; do
        case "$kind" in
            moved)
                [ -e "$other" ] || [ -L "$other" ] || continue
                rm -rf "$path"
                mv "$other" "$path"
                echo "  restored $path" ;;
            unlinked)
                [ -d "$other" ] || continue
                rm -rf "$path"
                ln -s "$other" "$path"
                echo "  relinked $path -> $other" ;;
        esac
    done
    rm -f "$STATE/moved-aside"
fi
rm -f "$STATE/installed-commit" "$STATE/repo"

if [ "${1:-}" = "--system" ]; then
    list=/var/lib/macos-look/installed-files
    if sudo test -f "$list"; then
        say "System files"
        sudo systemctl disable macos-boot-chime.service 2>/dev/null || true
        while IFS= read -r f; do restore "$f" sudo; done < <(sudo cat "$list")
        sudo rm -f "$list"
        for f in /etc/mkinitcpio.conf /etc/kernel/cmdline /etc/pacman.conf; do
            b=$(ls -1 "$f".bak-* 2>/dev/null | sort | head -n1) && [ -n "$b" ] && sudo cp -a "$b" "$f" && echo "  restored $f"
        done
        sudo sysctl --system >/dev/null
        say "Rebuilding initramfs"
        sudo mkinitcpio -P
        echo "Services enabled by the installer (nftables, apparmor, usbguard, ...) are left on."
        echo "Disable any you don't want with: sudo systemctl disable --now <name>"
    fi
fi
echo "Done. Log out and back in."
