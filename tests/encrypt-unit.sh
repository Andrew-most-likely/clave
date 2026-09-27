#!/usr/bin/env bash
# Unit tests for clave-encrypt (SEC-5): the status parser on saved lsblk
# output, and the config writers (HOOKS, boot entries for GRUB, systemd-boot
# and Limine, finish, reapply) on scratch copies of /etc and /boot.
# Needs no root and changes nothing outside a temp folder.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
tool="$repo/home/.local/bin/clave-encrypt"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
ok()   { echo "ok:   $*"; }
eq()   { if [ "$1" = "$2" ]; then ok "$3"; else fail "$3: got '$1', want '$2'"; fi; }
has()  { if grep -qE -- "$2" "$1"; then ok "$3"; else fail "$3: /$2/ not in $1"; sed 's/^/      /' "$1"; fi; }
hasnt() { if grep -qE -- "$2" "$1"; then fail "$3: /$2/ in $1"; else ok "$3"; fi; }

# --- status ---------------------------------------------------------------
status_of() { printf '%s' "$1" > "$tmp/lsblk.json"; CLAVE_LSBLK_JSON="$tmp/lsblk.json" "$tool" status; }

eq "$(status_of '{"blockdevices":[
  {"name":"zram0","type":"disk","fstype":"swap","mountpoints":["[SWAP]"]},
  {"name":"nvme0n1","type":"disk","fstype":null,"mountpoints":[null],"children":[
    {"name":"nvme0n1p1","type":"part","fstype":"vfat","mountpoints":["/boot"]},
    {"name":"nvme0n1p2","type":"part","fstype":"ext4","mountpoints":["/var/tmp","/"]},
    {"name":"nvme0n1p3","type":"part","fstype":"ext4","mountpoints":["/home"]}]}]}')" Off "plain ext4, zram"

eq "$(status_of '{"blockdevices":[
  {"name":"sda","type":"disk","mountpoints":[null],"children":[
    {"name":"sda1","type":"part","mountpoints":["/boot"]},
    {"name":"sda2","type":"part","fstype":"crypto_LUKS","mountpoints":[null],"children":[
      {"name":"croot","type":"crypt","fstype":"btrfs","mountpoints":["/home","/"]}]}]}]}')" On "LUKS btrfs, /home subvolume"

eq "$(status_of '{"blockdevices":[
  {"name":"sda","type":"disk","mountpoints":[null],"children":[
    {"name":"sda1","type":"part","mountpoints":["/boot"]},
    {"name":"sda2","type":"part","mountpoints":[null],"children":[
      {"name":"croot","type":"crypt","mountpoints":["/"]}]},
    {"name":"sda3","type":"part","mountpoints":["/home"]}]}]}')" Partly "/ encrypted, /home not"

eq "$(status_of '{"blockdevices":[
  {"name":"sda","type":"disk","mountpoints":[null],"children":[
    {"name":"sda1","type":"part","mountpoints":["/boot"]},
    {"name":"sda2","type":"part","mountpoints":[null],"children":[
      {"name":"croot","type":"crypt","mountpoints":["/"]}]},
    {"name":"sda3","type":"part","fstype":"swap","mountpoints":["[SWAP]"]}]}]}')" Partly "plain swap partition"

eq "$(status_of '{"blockdevices":[
  {"name":"sda","type":"disk","mountpoints":[null],"children":[
    {"name":"sda1","type":"part","mountpoints":["/boot"]},
    {"name":"sda2","type":"part","mountpoints":[null],"children":[
      {"name":"cryptlvm","type":"crypt","mountpoints":[null],"children":[
        {"name":"vg-root","type":"lvm","mountpoints":["/"]},
        {"name":"vg-home","type":"lvm","mountpoints":["/home"]},
        {"name":"vg-swap","type":"lvm","mountpoints":["[SWAP]"]}]}]}]}]}')" On "LVM on LUKS"

# --- config writers ---------------------------------------------------------
# lib: source the functions without running a command.
lib() { CLAVE_ENCRYPT_LIB=1 CLAVE_ENCRYPT_ROOT="$1" CLAVE_PROC_CMDLINE="$1/proc-cmdline" CLAVE_BOOT_UUID=BOOT-UUID \
        bash -c 'set -euo pipefail; . "$0"; "$@"' "$tool" "${@:2}"; }

newroot() {  # newroot DIR HOOKSTYLE: scratch /etc and /boot
    local d=$1
    mkdir -p "$d/etc/default" "$d/etc/kernel" "$d/boot"
    if [ "$2" = systemd ]; then
        echo 'HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block filesystems fsck)' > "$d/etc/mkinitcpio.conf"
    else
        echo 'HOOKS=(base udev autodetect microcode modconf kms plymouth keymap consolefont block filesystems fsck)' > "$d/etc/mkinitcpio.conf"
    fi
    sed -i '/^HOOKS=(base systemd/ s/kms/kms plymouth/' "$d/etc/mkinitcpio.conf"
    echo 'BOOT_IMAGE=/vmlinuz-linux root=UUID=1111-fs rw rootflags=subvol=@ quiet splash loglevel=3' > "$d/proc-cmdline"
}

# HOOKS, both styles
r="$tmp/hooks-sd"; newroot "$r" systemd
lib "$r" hooks_add; lib "$r" hooks_add
has "$r/etc/mkinitcpio.conf" 'plymouth .*block sd-encrypt filesystems' "systemd HOOKS: sd-encrypt after block, after plymouth"
eq "$(grep -o sd-encrypt "$r/etc/mkinitcpio.conf" | wc -l)" 1 "hooks_add is idempotent"
eq "$(lib "$r" crypt_params LUKS-1)" "rd.luks.name=LUKS-1=croot root=/dev/mapper/croot" "systemd params"

r="$tmp/hooks-udev"; newroot "$r" udev
sed -i 's/ keymap consolefont//' "$r/etc/mkinitcpio.conf"
lib "$r" hooks_add
has "$r/etc/mkinitcpio.conf" 'keyboard block encrypt filesystems' "udev HOOKS: keyboard added, encrypt after block"
eq "$(lib "$r" crypt_params LUKS-1)" "cryptdevice=UUID=LUKS-1:croot root=/dev/mapper/croot" "udev params"

eq "$(lib "$r" patch_cmdline 'initrd=\x root=UUID=a rw cryptdevice=old quiet' 'root=/dev/mapper/croot')" \
   "rw quiet root=/dev/mapper/croot" "patch_cmdline drops old root/crypt/initrd"

# GRUB
r="$tmp/grub"; newroot "$r" systemd
mkdir -p "$r/etc/grub.d" "$r/boot/grub"; : > "$r/boot/grub/grub.cfg"; : > "$r/boot/intel-ucode.img"
printf 'GRUB_DEFAULT=0\nGRUB_CMDLINE_LINUX_DEFAULT="quiet"\nGRUB_CMDLINE_LINUX=""\n' > "$r/etc/default/grub"
eq "$(lib "$r" detect_loader)" grub "detect GRUB"
p=$(lib "$r" crypt_params LUKS-G)
lib "$r" entry_add grub "$p"
g="$r/etc/grub.d/41_clave-encrypted"
has "$g" "menuentry 'Clave \(encrypted\)'" "GRUB entry title"
has "$g" 'search --no-floppy --fs-uuid --set=root BOOT-UUID' "GRUB entry finds /boot"
has "$g" 'linux /vmlinuz-linux rw rootflags=subvol=@ quiet splash loglevel=3 rd.luks.name=LUKS-G=croot root=/dev/mapper/croot' "GRUB entry cmdline"
has "$g" 'initrd /intel-ucode.img /initramfs-linux.img' "GRUB entry initrd with microcode"
out=$(sh "$g"); case "$out" in "menuentry"*"}") ok "GRUB script prints only the entry" ;; *) fail "GRUB script output: $out" ;; esac
lib "$r" entries_finish grub "$p"
has "$r/etc/default/grub" '^GRUB_CMDLINE_LINUX="rd.luks.name=LUKS-G=croot"$' "GRUB finish: unlock param in GRUB_CMDLINE_LINUX"
[ ! -e "$g" ] && ok "GRUB finish removes the extra entry" || fail "GRUB extra entry still there"

# systemd-boot
r="$tmp/sdboot"; newroot "$r" udev
mkdir -p "$r/boot/loader/entries"
printf 'title   Arch Linux\nlinux   /vmlinuz-linux\ninitrd  /initramfs-linux.img\noptions root=UUID=1111-fs rw rootflags=subvol=@ quiet splash loglevel=3\n' > "$r/boot/loader/entries/arch.conf"
printf 'title   Arch Linux (fallback)\nlinux   /vmlinuz-linux\ninitrd  /initramfs-linux-fallback.img\noptions root=UUID=1111-fs rw rootflags=subvol=@\n' > "$r/boot/loader/entries/arch-fallback.conf"
eq "$(lib "$r" detect_loader)" systemd-boot "detect systemd-boot"
p=$(lib "$r" crypt_params LUKS-S)
lib "$r" entry_add systemd-boot "$p"
e="$r/boot/loader/entries/clave-encrypted.conf"
has "$e" '^title   Clave \(encrypted\)$' "systemd-boot entry title"
has "$e" '^initrd  /initramfs-linux.img$' "systemd-boot entry copies the normal (not fallback) entry"
has "$e" '^options rw rootflags=subvol=@ quiet splash loglevel=3 cryptdevice=UUID=LUKS-S:croot root=/dev/mapper/croot$' "systemd-boot entry options"
lib "$r" entries_finish systemd-boot "$p"
has "$r/boot/loader/entries/arch.conf" 'cryptdevice=UUID=LUKS-S:croot root=/dev/mapper/croot$' "systemd-boot finish: normal entry"
has "$r/boot/loader/entries/arch-fallback.conf" 'cryptdevice=UUID=LUKS-S:croot root=/dev/mapper/croot$' "systemd-boot finish: fallback entry"
[ ! -e "$e" ] && ok "systemd-boot finish removes the extra entry" || fail "systemd-boot extra entry still there"

# Limine
r="$tmp/limine"; newroot "$r" systemd
cat > "$r/boot/limine.conf" <<'EOF'
timeout: 3

/Arch Linux
    protocol: linux
    path: boot():/vmlinuz-linux
    cmdline: root=UUID=1111-fs rw rootflags=subvol=@ quiet
    module_path: boot():/initramfs-linux.img

/Arch Linux (fallback)
    protocol: linux
    path: boot():/vmlinuz-linux
    cmdline: root=UUID=1111-fs rw rootflags=subvol=@
    module_path: boot():/initramfs-linux-fallback.img
EOF
eq "$(lib "$r" detect_loader)" limine "detect Limine"
p=$(lib "$r" crypt_params LUKS-L)
lib "$r" entry_add limine "$p"
c="$r/boot/limine.conf"
has "$c" '^/Clave \(encrypted\)$' "Limine entry title"
eq "$(grep -c 'rd.luks.name=LUKS-L=croot' "$c")" 1 "Limine: only the new entry has the unlock param"
has "$c" '^    cmdline: rw rootflags=subvol=@ quiet rd.luks.name=LUKS-L=croot root=/dev/mapper/croot$' "Limine entry cmdline"
lib "$r" entries_finish limine "$p"
hasnt "$c" 'Clave \(encrypted\)' "Limine finish removes the extra entry"
eq "$(grep -c 'rd.luks.name=LUKS-L=croot root=/dev/mapper/croot' "$c")" 2 "Limine finish: both entries unlock"
has "$c" '^timeout: 3$' "Limine finish keeps global options"

# UKI is not supported in place
r="$tmp/uki"; newroot "$r" systemd; echo 'root=UUID=x rw' > "$r/etc/kernel/cmdline"
eq "$(lib "$r" detect_loader)" uki "detect UKI"

# reapply after uninstall restored the pre-install files
r="$tmp/reapply"; newroot "$r" systemd
printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"\nGRUB_CMDLINE_LINUX=""\n' > "$r/etc/default/grub"
echo 'BOOT_IMAGE=/vmlinuz-linux rd.luks.name=LUKS-R=croot root=/dev/mapper/croot rw' > "$r/proc-cmdline"
lib "$r" reapply >/dev/null
has "$r/etc/mkinitcpio.conf" 'block sd-encrypt' "reapply: hook back"
has "$r/etc/default/grub" '^GRUB_CMDLINE_LINUX="rd.luks.name=LUKS-R=croot"$' "reapply: GRUB unlock param back"

# A folder that is not a mount point (no separate /home) gives an empty
# device, not an exit under set -e and pipefail.
if out=$(lib "$r" dev_of "$r/etc"); then
    if [ -z "$out" ]; then ok "dev_of: not a mount point is empty"; else fail "dev_of: not a mount point gave $out"; fi
else fail "dev_of: not a mount point exits"; fi

echo
if [ "$fails" -eq 0 ]; then echo "All encryption unit tests passed."; else echo "$fails failed."; exit 1; fi
