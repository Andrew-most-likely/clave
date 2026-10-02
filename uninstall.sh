#!/usr/bin/env bash
# Undoes install.sh.
#   - every file it wrote is restored from the copy taken before the first
#     install (~/.local/state/clave/backups), or removed when there was none
#   - config directories it moved aside (an earlier ML4W or other setup) come
#     back, and directories it turned from links into copies become links again
#   - with --system, also undoes scripts/system.sh (sudo)
# Packages stay installed.
set -euo pipefail
repo="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$repo/lib/common.sh"

# An install under the old names is moved first, so one path undoes both.
migrate_home
[ "${1:-}" != "--system" ] || sudo "$repo/scripts/system.sh" migrate

restore() {  # restore FILE [sudo]: oldest backup = the state before the first install
    # One shell does the whole swap, and a file is replaced by rename, so a
    # PAM or sudoers file is never missing while the next sudo call runs.
    local s="${2:-}"
    # shellcheck disable=SC2016
    $s sh -c '
        f=$1 bak=$(ls -1d "$1".bak-* 2>/dev/null | sort | head -n1)
        if [ -n "$bak" ]; then
            if [ -d "$bak" ] && [ ! -L "$bak" ]; then rm -rf "$f"; fi
            mv -fT "$bak" "$f"; echo "  restored $f"
        else rm -rf "$f"; echo "  removed  $f"; fi' sh "$1"
}

restore_home() {  # restore_home FILE: put back the pre-install copy, or remove
    local f="$1" b="$BACKUPS/${1#"$HOME/"}"
    if [ -e "$b" ] || [ -L "$b" ]; then rm -rf "$f"; mv "$b" "$f"; echo "  restored $f"
    elif compgen -G "$f.bak-*" >/dev/null; then restore "$f"   # installs before backups/ existed
    else rm -rf "$f"; echo "  removed  $f"; fi
}

if [ -f "$STATE/installed-files" ]; then
    say "Files in $HOME"
    while IFS= read -r f; do restore_home "$f"; done < "$STATE/installed-files"
    # Directories the install created and that are now empty.
    while IFS= read -r f; do dirname "$f"; done < "$STATE/installed-files" | sort -ru \
        | while IFS= read -r d; do rmdir -p --ignore-fail-on-non-empty "$d" 2>/dev/null || true; done
    rm -f "$STATE/installed-files"
    rm -rf "$BACKUPS"
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
                [ -e "$other" ] || continue
                rm -rf "$path"
                ln -s "$other" "$path"
                echo "  relinked $path -> $other" ;;
        esac
    done
    rm -f "$STATE/moved-aside"
fi
rm -f "$STATE/installed-commit" "$STATE/repo"

if [ "${1:-}" = "--system" ]; then
    sys_files=/var/lib/clave/installed-files
    if sudo test -f "$sys_files"; then
        # Network Identity first, while its helper is still there: it puts
        # back dhcpcd.conf and removes the files it rendered (SEC-7).
        if [ -f /etc/clave/netid/state ] && [ -x /usr/local/bin/clave-netid ]; then
            say "Network Identity off"
            sudo /usr/local/bin/clave-netid reset
        fi
        say "System files"
        while IFS= read -r f; do restore "$f" sudo; done < <(sudo cat "$sys_files")
        sudo rm -f "$sys_files"
        for f in /etc/mkinitcpio.conf /etc/kernel/cmdline /etc/default/grub /etc/pacman.conf; do
            b=$(ls -1 "$f".bak-[0-9]* 2>/dev/null | sort | head -n1) && [ -n "$b" ] && sudo cp -a "$b" "$f" && echo "  restored $f"
        done
        # Those copies are from before the install. An encrypted disk still
        # needs its unlock hook and kernel parameters, or it no longer boots.
        if [ "$("$repo/home/.local/bin/clave-encrypt" status)" != Off ]; then
            say "Disk Encryption stays: unlock settings kept"
            sudo "$repo/home/.local/bin/clave-encrypt" reapply
        fi
        sudo sysctl --system >/dev/null
        say "Rebuilding initramfs"
        sudo mkinitcpio -P
        if [ ! -f /etc/kernel/cmdline ] && [ -f /boot/grub/grub.cfg ] && command -v grub-mkconfig >/dev/null; then
            say "Boot menu (grub-mkconfig)"
            sudo grub-mkconfig -o /boot/grub/grub.cfg
        fi
        echo "Services enabled by the installer (nftables, apparmor, usbguard, ...) are left on."
        echo "Disable any you don't want with: sudo systemctl disable --now <name>"
    fi
fi
echo "Done. Log out and back in."
