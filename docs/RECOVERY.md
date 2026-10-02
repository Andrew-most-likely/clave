# Recovery

Clave installs a hardening layer by default (`./install.sh --no-harden` skips it). This page explains how to
get back into your machine when it locks you out. Keep a recovery USB with the Arch Linux ISO at hand.

## Getting to a shell

Most fixes need a root shell. Try these in order:

1. **Another console.** Press `Ctrl+Alt+F3`, log in, and use `sudo`. This works if only the desktop is broken.
2. **The recovery target.** In the boot menu, edit the entry and add `systemd.unit=rescue.target` to the kernel
   command line. You get a root shell after the root password.
3. **The Arch ISO.** Boot the USB, mount your root partition on `/mnt` (unlock it first with
   `cryptsetup open` if it is encrypted), then run `arch-chroot /mnt`.

## Account locked after wrong passwords (faillock)

Three wrong passwords lock the account for 15 minutes. Wait, or reset the counter from a root shell:

```sh
faillock --user YOUR_NAME --reset
```

## USB keyboard, mouse or dock not working (USBGuard)

USBGuard only allows the USB devices that were plugged in during the install. A new device is blocked until
you allow it:

- **From the desktop:** System Settings > Privacy & Security lists blocked devices. Allowing one asks for
  your password.
- **From a console:** `sudo usbguard list-devices --blocked`, then
  `sudo usbguard allow-device -p ID` (`-p` keeps the rule after a reboot).
- **No working keyboard at all:** add `systemd.mask=usbguard.service` to the kernel command line in the boot
  menu. USBGuard stays off for that boot. Allow the device, then reboot normally.

## No network (firewall and OpenSnitch)

The firewall drops incoming connections and does not block outgoing ones. OpenSnitch asks before an app
connects out; if you missed the question, the app stays blocked.

- Open the OpenSnitch window from the tray and change the rule for the app.
- To check whether OpenSnitch is the cause: `sudo systemctl stop opensnitchd`, try again, then
  `sudo systemctl start opensnitchd`.
- The inbound firewall is the nftables table `inet hardening`. List it with
  `sudo nft list table inet hardening`.

## Network Identity

Network Identity (Privacy & Security) changes DHCP, the firewall's answers and how TCP connections start.
If the network stops working after you chose a profile or turned on Stealth:

- `sudo clave-netid reset` turns it off: it restores `/etc/dhcpcd.conf`, removes every file it wrote, empties
  its firewall chains, stops the SYN rewriter and restarts NetworkManager.
- To check only the SYN rewriter: `sudo systemctl stop clave-synshape`. Its firewall rule uses `bypass`, so
  connections go out unchanged while it is stopped. `sudo clave-netid selftest` tests it again.
- Stealth drops everything new from the network, printer discovery included. Turn it off in Control Center.

## An app fails to start (AppArmor)

Look for denials: `sudo journalctl -k | grep -i apparmor | tail`. Put the profile that blocks the app in
complain mode, which logs instead of blocking:

```sh
sudo aa-complain /etc/apparmor.d/PROFILE_NAME
```

## The machine does not boot after the install

The hardening layer adds kernel flags to `/etc/kernel/cmdline` and rebuilds the initramfs. The installer keeps
the old files as `<file>.bak-<date>`.

1. In the boot menu, pick another kernel (for example `linux` instead of `linux-hardened`) if you have one.
2. Or from the Arch ISO in `arch-chroot`: copy `/etc/kernel/cmdline.bak-<date>` back to
   `/etc/kernel/cmdline`, then run `mkinitcpio -P`.

## Disk Encryption

See [ENCRYPTION.md](ENCRYPTION.md) for how the setup works. `/boot` is never encrypted: it holds the kernel
and the unlock prompt, so the machine can ask for the passphrase. Someone with the laptop could change those
files. Secure Boot would stop that, and it is not part of Clave yet.

**Forgotten passphrase.** Type the recovery key at the passphrase prompt instead. It is the 64-character
key shown once during the setup. After logging in, set a new passphrase:

```sh
sudo cryptsetup luksChangeKey /dev/disk/by-partuuid/ROOT_PARTUUID
```

Without the passphrase and the recovery key, the files cannot be read. This is the point of the encryption,
and there is no way around it.

**Encryption was interrupted** (power cut, closed lid, crash). LUKS2 re-encryption can be resumed. Boot the
Arch live USB, mount the boot partition, and run the same script again:

```sh
mount /dev/BOOT_PARTITION /mnt
bash /mnt/clave-encrypt-offline.sh
```

The script sees the unfinished encryption and continues it with `cryptsetup reencrypt --resume-only`. Do not
run `mkfs`, `fsck` or a partition editor on that partition in between.

**Stopped after the prepare step.** Nothing on the disk has changed yet. The normal boot entry starts the
system as before. The extra entry "Clave (encrypted)" does not work until the offline step has run. To undo
the prepare step, restore `/etc/mkinitcpio.conf.bak-encrypt`, remove the extra entry (GRUB:
`/etc/grub.d/41_clave-encrypted`, then `grub-mkconfig -o /boot/grub/grub.cfg`; systemd-boot:
`loader/entries/clave-encrypted.conf`; Limine: the `/Clave (encrypted)` block in `limine.conf`), and delete
`/var/lib/clave/encrypt.conf` and `/boot/clave-encrypt-offline.sh`.

**"Clave (encrypted)" does not start after the offline step.** Use the Arch live USB:

```sh
cryptsetup open /dev/disk/by-partuuid/ROOT_PARTUUID croot
mount /dev/mapper/croot /mnt          # btrfs: add -o subvol=@ (or your root subvolume)
mount /dev/BOOT_PARTITION /mnt/boot
arch-chroot /mnt
grep ^HOOKS /etc/mkinitcpio.conf      # needs "encrypt" or "sd-encrypt" after "block"
mkinitcpio -P
```

The boot entry needs `root=/dev/mapper/croot` plus `cryptdevice=UUID=LUKS_UUID:croot` (`encrypt` hook) or
`rd.luks.name=LUKS_UUID=croot` (`sd-encrypt` hook), and `systemd.gpt_auto=0` so that only `/etc/crypttab`
unlocks `/home` and swap. `cryptsetup luksUUID /dev/disk/by-partuuid/ROOT_PARTUUID` prints the LUKS UUID. `clave-encrypt finish` writes these into every entry, so after it has run, the normal
entries work again.

## `su` does not work

`su` is limited to members of the `wheel` group. Use `sudo`, or add the user with `gpasswd -a NAME wheel`.

## Removing the hardening layer

`./uninstall.sh --system` restores every file the installer replaced. Services it turned on (nftables,
AppArmor, USBGuard, OpenSnitch) stay on; turn off the ones you do not want with
`sudo systemctl disable --now NAME`.
