#!/usr/bin/env bash
# Root half of the installer. Run through install.sh, or directly:
#   sudo scripts/system.sh [look] [desktop] [harden]   (default: look desktop)
# Every file it replaces is kept as <file>.bak-<date>. Files it wrote are
# listed in /var/lib/macos-look/installed-files for uninstall.sh.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }

repo="$(cd "$(dirname "$0")/.." && pwd)"
user="${SUDO_USER:-${TARGET_USER:-}}"
[ -n "$user" ] && [ "$user" != root ] || { echo "Run with sudo from your normal user account."; exit 1; }
home="$(getent passwd "$user" | cut -d: -f6)"
uid="$(id -u "$user")"
stamp="$(date +%F)"
state=/var/lib/macos-look
mkdir -p "$state"
groups=("$@"); [ ${#groups[@]} -gt 0 ] || groups=(look desktop)

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
has() { local g; for g in "${groups[@]}"; do [ "$g" = "$1" ] && return 0; done; return 1; }
backup() { [ -e "$1" ] && [ ! -e "$1.bak-$stamp" ] && cp -a "$1" "$1.bak-$stamp"; return 0; }
record() { grep -qxF "$1" "$state/installed-files" 2>/dev/null || echo "$1" >> "$state/installed-files"; }

place() {  # place SRC DEST [MODE]: install one file with backup and placeholders filled in
    local src="$1" dest="$2" mode="${3:-}"
    [ -n "$mode" ] || { [ -x "$src" ] && mode=755 || mode=644; }
    backup "$dest"
    install -Dm"$mode" "$src" "$dest"
    grep -Iq . "$dest" && sed -i -e "s|__HOME__|$home|g" -e "s|__USER__|$user|g" -e "s|__UID__|$uid|g" "$dest"
    record "$dest"
}

place_group() {  # place_group GROUP: install every file of system/GROUP
    local base="$repo/system/$1" f
    [ -d "$base" ] || return 0
    while IFS= read -r -d '' f; do
        local dest="${f#"$base"}"
        case "$dest" in
            /etc/sudoers.d/*)
                visudo -cqf "$f" || { echo "  $dest failed visudo check, skipped"; continue; }
                place "$f" "$dest" 440 ;;
            /etc/pam.d/*|/etc/login.defs|/etc/security/*|/etc/usbguard/*)
                place "$f" "$dest" 644
                [[ "$dest" == /etc/usbguard/* ]] && chmod 600 "$dest" ;;
            *) place "$f" "$dest" ;;
        esac
        echo "  $dest"
    done < <(find "$base" -type f -print0 | sort -z)
}

add_cmdline() {  # add_cmdline FLAG...: append missing kernel flags to /etc/kernel/cmdline (UKI setups)
    local f=/etc/kernel/cmdline flag
    if [ ! -f "$f" ]; then
        echo "  /etc/kernel/cmdline not found (not a UKI setup). Add these flags to your bootloader by hand:"
        echo "    $*"
        return 1
    fi
    backup "$f"
    for flag in "$@"; do
        grep -qw -- "${flag%%=*}" "$f" || sed -i "s|\$| $flag|" "$f"
    done
    return 0
}

need_initramfs=0

# --------------------------------------------------------------------------
if has look; then
    say "macOS look: system files"
    place_group look

    say "Plymouth boot splash"
    install -d /usr/share/plymouth/themes/macos
    install -m644 "$repo"/home/.local/share/macos-look/plymouth-macos/* /usr/share/plymouth/themes/macos/
    record /usr/share/plymouth/themes/macos
    backup /etc/mkinitcpio.conf
    if ! grep -qE '^HOOKS=.*\bplymouth\b' /etc/mkinitcpio.conf; then
        if grep -qE '^HOOKS=.*\bsystemd\b' /etc/mkinitcpio.conf || grep -qE '^HOOKS=.*\bkms\b' /etc/mkinitcpio.conf; then
            sed -i -E '/^HOOKS=/ s/\b(kms)\b/\1 plymouth/' /etc/mkinitcpio.conf
        else
            sed -i -E '/^HOOKS=/ s/\b(udev|systemd)\b/\1 plymouth/' /etc/mkinitcpio.conf
        fi
        echo "  added plymouth to mkinitcpio HOOKS"
    fi
    add_cmdline $(cat "$repo/extra/kernel-cmdline-look.txt") || true
    need_initramfs=1

    say "SDDM login theme"
    rm -rf /usr/share/sddm/themes/macos
    cp -r "$repo/home/.local/share/macos-look/sddm-macos" /usr/share/sddm/themes/macos
    walls="$home/.local/share/macos-look/wallpapers"
    bg=$(find "$walls" -maxdepth 1 -iname '*sonoma*dark*' 2>/dev/null | head -n1)
    [ -n "$bg" ] || bg=$(find "$walls" -maxdepth 1 \( -iname '*.jpg' -o -iname '*.png' \) 2>/dev/null | head -n1)
    if [ -n "$bg" ]; then magick "$bg" /usr/share/sddm/themes/macos/background.png
    else magick -size 16x16 xc:'#1e1e22' /usr/share/sddm/themes/macos/background.png; fi
    chmod -R u=rwX,go=rX /usr/share/sddm/themes/macos
    record /usr/share/sddm/themes/macos
    for face in "$home/.face" "$home/.face.icon"; do
        [ -f "$face" ] && install -Dm644 "$face" "/usr/share/sddm/faces/$user.face.icon" && break
    done
    # SDDM reads every file in sddm.conf.d, backups included: keep them elsewhere.
    mkdir -p /etc/sddm.conf.d.backup
    find /etc/sddm.conf.d -maxdepth 1 \( -name '*.bak*' -o -name '*~' \) -exec mv -t /etc/sddm.conf.d.backup/ {} +
    systemctl is-enabled -q display-manager.service 2>/dev/null || systemctl enable sddm.service

    say "Boot chime"
    install -Dm644 "$repo/home/.local/share/macos-look/boot-chime/chime.wav" /usr/local/share/sounds/macos-boot-chime.wav
    record /usr/local/share/sounds/macos-boot-chime.wav
    systemctl daemon-reload
    systemctl enable macos-boot-chime.service
fi

# --------------------------------------------------------------------------
if has desktop; then
    say "Desktop essentials: system files"
    place_group desktop

    # pacman: colors, parallel downloads and the multilib repo (Steam, Wine).
    # Edited in place so other repos and options stay as they are.
    backup /etc/pacman.conf
    sed -i -e 's/^#Color$/Color/' -e 's/^#ParallelDownloads = .*/ParallelDownloads = 5/' /etc/pacman.conf
    if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
        sed -i '/^#\[multilib\]$/{s/^#//;n;s/^#//}' /etc/pacman.conf
    fi
    systemctl daemon-reload
    systemctl enable --now cups.socket avahi-daemon.service bluetooth.service paccache.timer
    systemctl restart systemd-resolved.service 2>/dev/null || true
    systemctl restart systemd-journald.service
fi

# --------------------------------------------------------------------------
if has harden; then
    say "Hardening: system files"
    place_group harden
    chmod 755 /usr/local/sbin/strip-suid
    systemctl daemon-reload

    say "Kernel command line"
    flags=$(cat "$repo/extra/kernel-cmdline-hardening.txt")
    grep -q GenuineIntel /proc/cpuinfo && flags="$flags intel_iommu=on"
    grep -q AuthenticAMD /proc/cpuinfo && flags="$flags amd_iommu=force_isolation"
    add_cmdline $flags && need_initramfs=1 || true

    say "USBGuard policy"
    # Allow every device plugged in right now, so keyboard/mouse keep working.
    if [ ! -s /etc/usbguard/rules.conf ]; then
        usbguard generate-policy > /etc/usbguard/rules.conf
        chmod 600 /etc/usbguard/rules.conf
        echo "  generated /etc/usbguard/rules.conf from the devices plugged in now"
    fi

    say "Services"
    sysctl --system >/dev/null
    systemctl enable --now nftables.service apparmor.service auditd.service usbguard.service \
        opensnitchd.service arch-audit.timer
    augenrules --load >/dev/null 2>&1 || true
    /usr/local/sbin/strip-suid
    if [ ! -f /var/lib/aide/aide.db.gz ]; then
        echo "  building AIDE baseline in the background (takes a few minutes)"
        systemd-run --unit=aide-init --nice=19 sh -c 'aide --init && mv -f /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz'
    fi
    systemctl enable aidecheck.timer 2>/dev/null || true
    gpasswd -a "$user" proc >/dev/null 2>&1 || true
    echo
    echo "  Not applied automatically: hardened /etc/fstab options, see extra/fstab-hardening.txt"
fi

if [ "$need_initramfs" -eq 1 ]; then
    say "Rebuilding initramfs / UKI (mkinitcpio -P)"
    mkinitcpio -P
fi

say "System part done. Reboot to see the boot splash and login screen."
