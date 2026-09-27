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

## `su` does not work

`su` is limited to members of the `wheel` group. Use `sudo`, or add the user with `gpasswd -a NAME wheel`.

## Removing the hardening layer

`./uninstall.sh --system` restores every file the installer replaced. Services it turned on (nftables,
AppArmor, USBGuard, OpenSnitch) stay on; turn off the ones you do not want with
`sudo systemctl disable --now NAME`.
