#!/usr/bin/env bash
# Builds one test system for tests/vm-encrypt.py on DISK (the second disk of
# the builder VM). Runs inside the builder VM as root. UEFI, /boot on the EFI
# partition, a user "tester" with the builder's SSH key and passwordless sudo,
# Plymouth in the initramfs like Clave's installer puts it, and clave-encrypt
# in ~/.local like install.sh puts it.
#   vm-encrypt-build.sh grub|sdboot|limine DISK FILES_DIR
# Variants (together they cover every supported boot loader, both HOOKS
# styles, ext4 and btrfs, a separate /home and a swap partition):
#   grub     ext4 / and ext4 /home, systemd HOOKS (sd-encrypt)
#   sdboot   btrfs @ and @home on one partition, busybox HOOKS (encrypt)
#   limine   ext4 / and a swap partition, systemd HOOKS (sd-encrypt)
set -euo pipefail
v=$1 d=$2 files=$3
m=/mnt/target

pacman -Sy --noconfirm --needed arch-install-scripts dosfstools btrfs-progs gptfdisk >/dev/null

umount -R "$m" 2>/dev/null || true
wipefs -aq "$d"
sgdisk -Z "$d" >/dev/null
sgdisk -n1:0:+512M -t1:ef00 "$d" >/dev/null
case "$v" in
    grub)   sgdisk -n2:0:+5G -t2:8304 -n3:0:0 -t3:8302 "$d" >/dev/null ;;
    sdboot) sgdisk -n2:0:0 -t2:8304 "$d" >/dev/null ;;
    limine) sgdisk -n2:0:-256M -t2:8304 -n3:0:0 -t3:8200 "$d" >/dev/null ;;
    *) echo "unknown variant $v"; exit 1 ;;
esac
partx -u "$d" 2>/dev/null || blockdev --rereadpt "$d"
udevadm settle
p() { echo "${d}$1"; }

mkfs.fat -F32 -n EFI "$(p 1)" >/dev/null
case "$v" in
    grub)
        mkfs.ext4 -qF "$(p 2)"; mkfs.ext4 -qF "$(p 3)"
        mount "$(p 2)" "$m" --mkdir; mount "$(p 3)" "$m/home" --mkdir ;;
    sdboot)
        mkfs.btrfs -qf "$(p 2)"
        mount "$(p 2)" "$m" --mkdir
        btrfs -q subvolume create "$m/@"; btrfs -q subvolume create "$m/@home"
        umount "$m"
        mount -o subvol=@ "$(p 2)" "$m"; mount -o subvol=@home "$(p 2)" "$m/home" --mkdir ;;
    limine)
        mkfs.ext4 -qF "$(p 2)"; mkswap -q "$(p 3)"
        mount "$(p 2)" "$m" --mkdir; swapon "$(p 3)" ;;
esac
mount "$(p 1)" "$m/boot" --mkdir

pkgs=(base linux mkinitcpio plymouth openssh sudo jq cryptsetup e2fsprogs btrfs-progs util-linux less)
case "$v" in
    grub) pkgs+=(grub efibootmgr) ;;
    limine) pkgs+=(limine) ;;
esac
pacstrap -K "$m" "${pkgs[@]}" >/dev/null
genfstab -U "$m" >> "$m/etc/fstab"
[ "$v" != limine ] || swapoff "$(p 3)"

install -Dm755 "$files/clave-encrypt" "$m/home/tester/.local/bin/clave-encrypt"
install -Dm755 "$files/clave-encrypt-offline.sh" "$m/home/tester/.local/share/clave/clave-encrypt-offline.sh"
install -Dm600 /home/tester/.ssh/authorized_keys "$m/home/tester/.ssh/authorized_keys"

rootuuid=$(blkid -s UUID -o value "$(p 2)")
cmdline="root=UUID=$rootuuid rw console=tty0 console=ttyS0,115200 quiet splash"
[ "$v" != sdboot ] || cmdline+=" rootflags=subvol=@"

arch-chroot "$m" /bin/bash -s "$v" "$cmdline" <<'EOF'
set -euo pipefail
v=$1 cmdline=$2
echo clave-enc > /etc/hostname
echo KEYMAP=us > /etc/vconsole.conf
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
printf '[Match]\nName=en*\n[Network]\nDHCP=yes\n' > /etc/systemd/network/20-wired.network
systemctl enable -q systemd-networkd systemd-resolved sshd
useradd -m -G wheel tester 2>/dev/null || true
chown -R tester: /home/tester
echo 'tester ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/tester
chmod 440 /etc/sudoers.d/tester

# HOOKS: systemd style is the Arch default; sdboot uses the busybox style.
if [ "$v" = sdboot ]; then
    sed -i -E 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)/' /etc/mkinitcpio.conf
fi
# Plymouth after kms, as scripts/system.sh does.
sed -i -E '/^HOOKS=/ s/\b(kms)\b/\1 plymouth/' /etc/mkinitcpio.conf
mkinitcpio -P >/dev/null 2>&1

case "$v" in
    grub)
        sed -i -E "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${cmdline#root=UUID=* }\"|" /etc/default/grub
        sed -i -E 's|^GRUB_DEFAULT=.*|GRUB_DEFAULT=saved|; s|^GRUB_TIMEOUT=.*|GRUB_TIMEOUT=1|' /etc/default/grub
        echo 'GRUB_TERMINAL="console serial"' >> /etc/default/grub
        grub-install --target=x86_64-efi --efi-directory=/boot --removable >/dev/null 2>&1
        grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 ;;
    sdboot)
        bootctl install --esp-path=/boot --no-variables >/dev/null 2>&1
        printf 'default arch.conf\ntimeout 1\n' > /boot/loader/loader.conf
        printf 'title   Arch Linux\nlinux   /vmlinuz-linux\ninitrd  /initramfs-linux.img\noptions %s\n' "$cmdline" > /boot/loader/entries/arch.conf
        printf 'title   Arch Linux (fallback)\nlinux   /vmlinuz-linux\ninitrd  /initramfs-linux-fallback.img\noptions %s\n' "$cmdline" > /boot/loader/entries/arch-fallback.conf ;;
    limine)
        install -Dm644 /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/BOOTX64.EFI
        cat > /boot/limine.conf <<CONF
timeout: 1
serial: yes

/Arch Linux
    protocol: linux
    path: boot():/vmlinuz-linux
    cmdline: $cmdline
    module_path: boot():/initramfs-linux.img

/Arch Linux (fallback)
    protocol: linux
    path: boot():/vmlinuz-linux
    cmdline: $cmdline
    module_path: boot():/initramfs-linux-fallback.img
CONF
        ;;
esac
EOF

# pacstrap -K leaves pacman's gpg-agent running on the target.
gpgconf --homedir "$m/etc/pacman.d/gnupg" --kill all 2>/dev/null || true
sleep 1
umount -R "$m" || { sync; umount -lR "$m"; }
sync
echo "BUILD-OK $v"
