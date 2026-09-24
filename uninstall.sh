#!/usr/bin/env bash
# Undoes install.sh: every file it wrote is restored from its newest
# <file>.bak-<date>, or removed when there was no earlier version.
# Packages stay installed. With --system also undoes scripts/system.sh (sudo).
set -euo pipefail
state="${XDG_STATE_HOME:-$HOME/.local/state}/macos-look"

restore() {  # restore FILE [sudo]
    local f="$1" s="${2:-}" bak
    bak=$($s sh -c "ls -1d '$f'.bak-* 2>/dev/null | sort | tail -n1")
    if [ -n "$bak" ]; then $s rm -rf "$f"; $s mv "$bak" "$f"; echo "  restored $f"
    else $s rm -rf "$f"; echo "  removed  $f"; fi
}

if [ -f "$state/installed-files" ]; then
    echo "==> Files in $HOME"
    while IFS= read -r f; do restore "$f"; done < "$state/installed-files"
    rm -f "$state/installed-files"
    systemctl --user disable --now home-cleanup.timer 2>/dev/null || true
else
    echo "Nothing recorded in $state/installed-files"
fi

if [ "${1:-}" = "--system" ]; then
    list=/var/lib/macos-look/installed-files
    if sudo test -f "$list"; then
        echo "==> System files"
        sudo systemctl disable macos-boot-chime.service 2>/dev/null || true
        while IFS= read -r f; do restore "$f" sudo; done < <(sudo cat "$list")
        sudo rm -f "$list"
        for f in /etc/mkinitcpio.conf /etc/kernel/cmdline; do
            b=$(ls -1 "$f".bak-* 2>/dev/null | sort | head -n1) && [ -n "$b" ] && sudo cp -a "$b" "$f" && echo "  restored $f"
        done
        sudo sysctl --system >/dev/null
        echo "==> Rebuilding initramfs"
        sudo mkinitcpio -P
        echo "Services enabled by the installer (nftables, apparmor, usbguard, ...) are left on."
        echo "Disable any you don't want with: sudo systemctl disable --now <name>"
    fi
fi
echo "Done. Log out and back in."
