#!/usr/bin/env bash
# Root half of the installer. Run through install.sh, or directly:
#   sudo scripts/system.sh [look] [desktop] [harden]   (default: look desktop)
# Every file it replaces is kept as <file>.bak-<date>. Files it wrote are
# listed in /var/lib/clave/installed-files for uninstall.sh.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }

repo="$(cd "$(dirname "$0")/.." && pwd)"
user="${SUDO_USER:-${TARGET_USER:-}}"
[ -n "$user" ] && [ "$user" != root ] || { echo "Run with sudo from your normal user account."; exit 1; }
home="$(getent passwd "$user" | cut -d: -f6)"
uid="$(id -u "$user")"
stamp="$(date +%F)"
state=/var/lib/clave
mkdir -p "$state"
groups=("$@"); [ ${#groups[@]} -gt 0 ] || groups=(look desktop)

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
# shellcheck source=lib/migrate.sh
source "$repo/lib/migrate.sh"
# shellcheck source=lib/personal.sh
source "$repo/lib/personal.sh"
# An install under the old names moves first. `system.sh migrate` does only this.
migrate_system "$state"
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

# add_cmdline FLAG...: add missing kernel flags. UKI setups read
# /etc/kernel/cmdline; GRUB setups read /etc/default/grub, and grub.cfg is
# written again at the end (it also picks up a newly installed kernel).
need_grub=0
add_cmdline() {
    local f flag
    if [ -f /etc/kernel/cmdline ]; then
        f=/etc/kernel/cmdline
        backup "$f"
        for flag in "$@"; do
            grep -qw -- "${flag%%=*}" "$f" || sed -i "s|\$| $flag|" "$f"
        done
    elif [ -f /etc/default/grub ] && command -v grub-mkconfig >/dev/null; then
        f=/etc/default/grub
        backup "$f"
        for flag in "$@"; do
            grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=.*[\" ]${flag%%=*}[=\" ]" "$f" \
                || sed -i -E "s|^(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)\"|\1 $flag\"|" "$f"
        done
        need_grub=1
    else
        echo "  No /etc/kernel/cmdline (UKI) or GRUB found. Add these flags to your bootloader by hand:"
        echo "    $*"
        return 1
    fi
    return 0
}

need_initramfs=0
# After a kernel update without a reboot, the running kernel's modules are
# gone and services such as nftables cannot start. Then services are only
# enabled, and start at the next boot.
if [ -d "/usr/lib/modules/$(uname -r)" ]; then now=--now; else
    now=
    echo "  The running kernel was updated and its modules are gone: services start after a reboot."
fi

# --------------------------------------------------------------------------
# compat_files: the upgrade check (COMP-9). Part of the look group; also its
# own group "compat", which install.sh --update runs when these changed.
compat_files() {
    say "Upstream compatibility check (pacman hook)"
    # After an upgrade of a package Clave talks to, a pacman hook says
    # whether this Clave release works with it. It runs a root-owned copy of
    # clave-compat and reads a copy of compat.json, never the checkout.
    place "$repo/compat.json" /usr/share/clave/compat.json 644
    place "$repo/home/.local/bin/clave-compat" /usr/local/lib/clave/clave-compat 755
    local hook=/etc/pacman.d/hooks/clave-doctor.hook
    install -d /etc/pacman.d/hooks
    backup "$hook"
    {
        echo "# Written by Clave (scripts/system.sh) from ci/watched.txt. PROJECT_PLAN.md COMP-9."
        echo "# Warns after an upgrade that this Clave release was not tested with; never"
        echo "# stops the transaction."
        echo "[Trigger]"
        echo "Operation = Install"
        echo "Operation = Upgrade"
        echo "Type = Package"
        awk '($1 == "repo" || $1 == "aur") { print "Target = " $2 }' "$repo/ci/watched.txt"
        echo
        echo "[Action]"
        echo "Description = Checking Clave compatibility..."
        echo "When = PostTransaction"
        echo "NeedsTargets"
        echo "Exec = /usr/local/lib/clave/clave-compat --hook"
    } > "$hook"
    chmod 644 "$hook"
    record "$hook"
    echo "  $hook"
}

if has look; then
    say "Clave look: system files"
    place_group look

    say "Plymouth boot splash"
    install -d /usr/share/plymouth/themes/clave
    install -m644 "$repo"/home/.local/share/clave/plymouth-clave/* /usr/share/plymouth/themes/clave/
    # A logo the user supplies (FEAT-6) replaces the keystone. Converted as
    # the user, so root never parses the file.
    logo="$home/.config/clave/branding/logo.svg"
    if [ -f "$logo" ] && png=$(runuser -u "$user" -- sh -c 't=$(mktemp) && rsvg-convert -h 394 "$1" -o "$t" && echo "$t"' sh "$logo"); then
        install -m644 "$png" /usr/share/plymouth/themes/clave/logo.png
        rm -f "$png"
        echo "  boot logo from ~/.config/clave/branding/logo.svg"
    fi
    record /usr/share/plymouth/themes/clave
    backup /etc/mkinitcpio.conf
    if ! grep -qE '^HOOKS=.*\bplymouth\b' /etc/mkinitcpio.conf; then
        if grep -qE '^HOOKS=.*\bsystemd\b' /etc/mkinitcpio.conf || grep -qE '^HOOKS=.*\bkms\b' /etc/mkinitcpio.conf; then
            sed -i -E '/^HOOKS=/ s/\b(kms)\b/\1 plymouth/' /etc/mkinitcpio.conf
        else
            sed -i -E '/^HOOKS=/ s/\b(udev|systemd)\b/\1 plymouth/' /etc/mkinitcpio.conf
        fi
        echo "  added plymouth to mkinitcpio HOOKS"
    fi
    # shellcheck disable=SC2046  # one flag per word
    add_cmdline $(cat "$repo/extra/kernel-cmdline-look.txt") || true
    need_initramfs=1

    say "SDDM login theme"
    rm -rf /usr/share/sddm/themes/clave
    cp -r "$repo/home/.local/share/clave/sddm-clave" /usr/share/sddm/themes/clave
    walls="$home/.local/share/clave/wallpapers"
    # The folder is missing when the wallpaper download failed.
    bg=$(find "$walls" -maxdepth 1 -iname 'whitesur-dark*' 2>/dev/null | head -n1 || true)
    [ -n "$bg" ] || bg=$(find "$walls" -maxdepth 1 \( -iname '*.jpg' -o -iname '*.png' \) 2>/dev/null | head -n1 || true)
    # A background chosen in System Settings (clave-admin) wins.
    if [ -f "$state/login-background.png" ]; then install -m644 "$state/login-background.png" /usr/share/sddm/themes/clave/background.png
    elif [ -n "$bg" ]; then magick "$bg" /usr/share/sddm/themes/clave/background.png
    else magick -size 16x16 xc:'#1e1e22' /usr/share/sddm/themes/clave/background.png; fi
    if personal_on "$home"; then
        personal_fill /usr/share/sddm/themes/clave/Main.qml
        personal_fill /usr/share/plymouth/themes/clave/clave.script
        personal_fill /usr/share/icons/default/index.theme
    fi
    chmod -R u=rwX,go=rX /usr/share/sddm/themes/clave
    record /usr/share/sddm/themes/clave
    for face in "$home/.face" "$home/.face.icon"; do
        [ -f "$face" ] && install -Dm644 "$face" "/usr/share/sddm/faces/$user.face.icon" && break
    done
    # SDDM reads every file in sddm.conf.d, backups included: keep them elsewhere.
    mkdir -p /etc/sddm.conf.d.backup
    find /etc/sddm.conf.d -maxdepth 1 \( -name '*.bak*' -o -name '*~' \) -exec mv -t /etc/sddm.conf.d.backup/ {} +
    systemctl is-enabled -q display-manager.service 2>/dev/null || systemctl enable sddm.service

    compat_files
fi

if has compat && ! has look; then
    compat_files
fi
if [ "${groups[*]}" = compat ]; then
    say "Done."
    exit 0
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
    systemctl enable $now cups.socket avahi-daemon.service bluetooth.service paccache.timer
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
    # Your account may watch and list USB devices (the notifier and System
    # Settings need that) but not change the policy: allowing a device goes
    # through clave-usb, which asks for the password.
    install -d -m 755 /etc/usbguard/IPCAccessControl.d
    printf 'Devices=list,listen\nExceptions=listen\n' > "/etc/usbguard/IPCAccessControl.d/$user"
    chmod 600 "/etc/usbguard/IPCAccessControl.d/$user"
    record "/etc/usbguard/IPCAccessControl.d/$user"

    say "Services"
    sysctl --system >/dev/null
    systemctl enable $now nftables.service apparmor.service auditd.service usbguard.service \
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

if [ "$need_grub" -eq 1 ]; then
    say "Boot menu (grub-mkconfig)"
    grub-mkconfig -o /boot/grub/grub.cfg
fi

say "System part done. Reboot to see the boot splash and login screen."
