#!/usr/bin/env bash
# Disk Encryption, offline stage (SEC-5). Run from the Arch live USB, as
# root, after `clave-encrypt prepare`. prepare puts a copy on the boot
# partition with the settings for this machine written above this line.
#
# For each partition: shrink the filesystem by HEADER_MIB, then
# `cryptsetup reencrypt --encrypt` it in place and enroll a recovery key.
# LUKS2 re-encryption survives interruption: run this script again and it
# resumes (cryptsetup reencrypt --resume-only).
# shellcheck disable=SC2154  # settings come from the lines above
set -euo pipefail

say()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root (the live USB logs in as root)."
[ -n "${ROOT_PARTUUID:-}" ] || die "No settings in this file: run clave-encrypt prepare first."
for t in cryptsetup systemd-cryptenroll blkid findmnt; do
    command -v "$t" >/dev/null || die "Missing $t: use the Arch live USB."
done
if [ "$(readlink -f "/dev/disk/by-partuuid/$ROOT_PARTUUID")" = "$(findmnt -nvo SOURCE /)" ]; then
    die "This is the installed system. Boot the Arch live USB and run it from there."
fi

part() { echo "/dev/disk/by-partuuid/$1"; }
MNT=$(mktemp -d /tmp/clave-encrypt.XXXXXX)
cleanup() {
    mountpoint -q "$MNT/root" && umount -R "$MNT/root"
    mountpoint -q "$MNT/tmp" && umount "$MNT/tmp"
    [ -e /dev/mapper/croot ] && cryptsetup close croot
    return 0
}
trap cleanup EXIT

# in_progress DEV: a LUKS2 re-encryption was interrupted.
in_progress() { cryptsetup luksDump "$1" 2>/dev/null | sed -n '/^Requirements:/,/^[A-Z]/p' | grep -q reencrypt; }

# shrink DEV FSTYPE: free HEADER_MIB at the end of the partition.
shrink() {
    local dev=$1 fs=$2 size target
    size=$(blockdev --getsize64 "$dev")
    target=$(( (size - HEADER_MIB * 1024 * 1024) / 1024 ))
    case "$fs" in
        ext4)
            e2fsck -f -p "$dev" || [ $? -le 1 ] || die "e2fsck found errors on $dev. Fix them with e2fsck -f $dev first."
            resize2fs "$dev" "${target}K" ;;
        btrfs)
            mkdir -p "$MNT/tmp"
            mount -t btrfs "$dev" "$MNT/tmp"
            local cur
            cur=$(btrfs filesystem show --raw "$MNT/tmp" | awk '/devid/ {print $4; exit}')
            [ "$cur" -le $((target * 1024)) ] || btrfs filesystem resize "$((target * 1024))" "$MNT/tmp"
            umount "$MNT/tmp" ;;
        *) die "Unsupported filesystem $fs on $dev." ;;
    esac
}

# encrypt NAME PARTUUID FSTYPE LUKS_UUID [KEYFILE]
encrypt() {
    local name=$1 dev fs=$3 uuid=$4 key=${5:-}
    dev=$(part "$2")
    [ -e "$dev" ] || die "$dev not found. Is this the right machine?"
    if cryptsetup isLuks "$dev"; then
        if in_progress "$dev"; then
            say "$name: resuming the interrupted encryption"
            # After a crash or power loss LUKS2 first checks the area that was
            # being written (repair), then carries on.
            cryptsetup repair ${key:+--key-file "$key"} "$dev"
            cryptsetup reencrypt --resume-only ${key:+--key-file "$key"} "$dev"
        else
            say "$name: already encrypted"
        fi
        return 0
    fi
    say "$name: shrinking the filesystem by $HEADER_MIB MiB"
    shrink "$dev" "$fs"
    say "$name: encrypting (this takes a while; an interruption can be resumed)"
    [ -n "$key" ] || echo "Choose the disk passphrase. You type it at every startup."
    cryptsetup reencrypt --encrypt --type luks2 --reduce-device-size "${HEADER_MIB}M" \
        --uuid "$uuid" ${key:+--key-file "$key"} "$dev"
}

# recovery DEV [KEYFILE]: a recovery key, shown once and never stored.
recovery() {
    local dev=$1 key=${2:-}
    if cryptsetup luksDump "$1" | grep -q 'systemd-recovery'; then return 0; fi
    echo
    echo "A recovery key opens the disk when the passphrase is forgotten."
    echo "Write it down now and keep it away from the computer. It is not saved anywhere."
    systemd-cryptenroll --recovery-key ${key:+--unlock-key-file="$key"} "$dev"
    read -rp "Press Enter when the recovery key is written down. " _
}

home_line="on /"
[ -z "${HOME_PARTUUID:-}" ] || home_line="$(part "$HOME_PARTUUID") ($HOME_FSTYPE)"
swap_line="none (zram or a swap file)"
[ -z "${SWAP_PARTUUID:-}" ] || swap_line="$(part "$SWAP_PARTUUID"): new random key at each boot"
cat <<EOF
Clave Disk Encryption, offline stage
  /      $(part "$ROOT_PARTUUID") ($ROOT_FSTYPE)
  /home  $home_line
  swap   $swap_line
Keep the power supply connected.
EOF
read -rp "Type ENCRYPT to start: " go
[ "$go" = ENCRYPT ] || exit 0

encrypt / "$ROOT_PARTUUID" "$ROOT_FSTYPE" "$ROOT_LUKS"
recovery "$(part "$ROOT_PARTUUID")"

say "Opening / to write its settings"
[ -e /dev/mapper/croot ] || cryptsetup open "$(part "$ROOT_PARTUUID")" croot
mkdir -p "$MNT/root"
if [ "$ROOT_FSTYPE" = btrfs ] && [ "${ROOT_SUBVOL:-/}" != / ]; then
    mount -o "subvol=${ROOT_SUBVOL#/}" /dev/mapper/croot "$MNT/root"
else
    mount /dev/mapper/croot "$MNT/root"
fi
[ -f "$MNT/root/etc/fstab" ] || die "No /etc/fstab on the root partition."
cp -a "$MNT/root/etc/crypttab" "$MNT/root/etc/crypttab.bak-encrypt" 2>/dev/null || true
cp -a "$MNT/root/etc/fstab" "$MNT/root/etc/fstab.bak-encrypt"

# /home unlocks with a key file inside the encrypted root, so there is one
# prompt at startup. The key is made here, after / is encrypted, so it is
# never written to the disk in the clear.
if [ -n "${HOME_PARTUUID:-}" ]; then
    key="$MNT/root/etc/cryptsetup-keys.d/chome.key"
    if [ ! -s "$key" ]; then
        install -d -m 700 "$MNT/root/etc/cryptsetup-keys.d"
        (umask 077; dd if=/dev/urandom of="$key" bs=512 count=8 status=none)
        chmod 400 "$key"
    fi
    encrypt /home "$HOME_PARTUUID" "$HOME_FSTYPE" "$HOME_LUKS" "$key"
    recovery "$(part "$HOME_PARTUUID")" "$key"
    grep -q '^chome ' "$MNT/root/etc/crypttab" 2>/dev/null \
        || echo "chome UUID=$HOME_LUKS /etc/cryptsetup-keys.d/chome.key luks" >> "$MNT/root/etc/crypttab"
fi

# A swap partition gets a new random key at every boot. Hibernation to it
# stops working; zram needs nothing.
if [ -n "${SWAP_PARTUUID:-}" ]; then
    say "swap: random key at each boot"
    grep -q '^cswap ' "$MNT/root/etc/crypttab" 2>/dev/null \
        || echo "cswap PARTUUID=$SWAP_PARTUUID /dev/urandom swap,cipher=aes-xts-plain64,size=512" >> "$MNT/root/etc/crypttab"
    # No sector-size=4096: it fails on a partition whose size is not a
    # multiple of 4 KiB ("Device size is not aligned to requested sector size").
    swapuuid=$(blkid -s UUID -o value "$(part "$SWAP_PARTUUID")" || true)
    awk -v u="UUID=$swapuuid" -v p="PARTUUID=$SWAP_PARTUUID" -v d="$(readlink -f "$(part "$SWAP_PARTUUID")")" '
        $3 == "swap" && ($1 == u || $1 == p || $1 == d) { $1 = "/dev/mapper/cswap" } { print }' \
        "$MNT/root/etc/fstab" > "$MNT/root/etc/fstab.new"
    mv "$MNT/root/etc/fstab.new" "$MNT/root/etc/fstab"
fi

sync
say "Encryption done."
cat <<EOF
  Reboot, remove the USB stick and choose "Clave (encrypted)" in the boot menu.
  Type the disk passphrase, log in, then run:  clave-encrypt finish
  The normal entry cannot start this system any more: it does not unlock the
  disk. If "Clave (encrypted)" does not start either, see docs/RECOVERY.md,
  "Disk Encryption".
EOF
