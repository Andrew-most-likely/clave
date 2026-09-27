# Disk Encryption

Without disk encryption, anyone who takes the computer can read every file on it. It does not matter how
strong the login password is or what the hardening layer does. Clave warns when the disk is not encrypted
and offers a guided setup (requirement SEC-5 in [PROJECT_PLAN.md](PROJECT_PLAN.md)).

Check the status at any time:

```sh
clave-encrypt status        # On, Partly or Off
```

- **On:** `/` and `/home` are on LUKS, and no swap partition is left unencrypted.
- **Partly:** only one of them is, or a swap partition is not encrypted.
- **Off:** neither is. zram swap lives in memory and needs nothing.

The same status is in System Settings > Privacy & Security > Disk Encryption.

There are two ways to turn it on. Start either one with **Set Up Disk Encryption…** in System Settings, or
run `clave-encrypt setup` in a terminal.

## 1. Reinstall with encryption (recommended on a new machine)

This is the simplest and safest way. Nothing is converted in place.

1. Back up your files.
2. Boot the Arch live USB and run `archinstall`. Under **Disk configuration**, pick a layout. Under **Disk
   encryption**, choose **LUKS** and set the passphrase. Use a separate `/boot` (or the EFI partition as
   `/boot`); `archinstall` does this by default.
3. Install Clave as the README describes. The installer sees the encrypted disk and says nothing more about
   it.
4. Optional: add a recovery key with
   `sudo systemd-cryptenroll --recovery-key /dev/disk/by-partuuid/ROOT_PARTUUID`. Write it down.

## 2. Encrypt this install in place

This keeps your files and settings. It rewrites every block of the partitions, which takes about an hour for
500 GB on an SSD.

**It needs:**

- A **full backup** you can restore from. The setup asks where it is.
- The power supply connected, with the battery at 50% or more.
- `/` and `/home` on plain **ext4** or **btrfs** partitions, each with at least 64 MiB free. LVM and RAID are
  not supported: use the reinstall path for those.
- `/boot` on its own partition with the kernels on it. It stays unencrypted so the machine can ask for the
  passphrase.
- **systemd-boot**, **GRUB** or **Limine** as the boot loader. Unified kernel images (`/etc/kernel/cmdline`)
  and other boot loaders: use the reinstall path.
- The Arch live USB.

**The stages:**

1. **Checks** (`clave-encrypt setup`, option 2). It stops with a reason when anything above is missing.
2. **Prepare**, in the running system, with `sudo`:
   - It chooses the LUKS UUIDs in advance.
   - It adds the unlock hook to `/etc/mkinitcpio.conf`: `sd-encrypt` for systemd-based HOOKS, `encrypt`
     otherwise. The hook goes after `block` and after `plymouth`, so the prompt is graphical. Then it
     rebuilds the initramfs.
   - It adds a second boot entry, **Clave (encrypted)**. The normal entry stays the default, so the
     machine still boots as before if you stop here.
   - It writes `/boot/clave-encrypt-offline.sh` and prints its SHA-256. Write down the first 8 characters.
3. **Encrypt**, offline. Boot the Arch live USB, then:

   ```sh
   mount /dev/BOOT_PARTITION /mnt   # lsblk shows which one
   sha256sum /mnt/clave-encrypt-offline.sh   # compare with what prepare printed
   bash /mnt/clave-encrypt-offline.sh
   ```

   For `/`, and then `/home` if it has its own partition, the script:
   - shrinks the filesystem by 32 MiB to make room for the LUKS2 header;
   - runs `cryptsetup reencrypt --encrypt --type luks2 --reduce-device-size 32M`;
   - enrolls a recovery key with `systemd-cryptenroll --recovery-key`.

   You choose the passphrase for `/`. `/home` unlocks with a key file stored inside the encrypted `/`, so
   there is one prompt at startup. The recovery key is shown once and saved nowhere: write it down. A swap
   partition gets a new random key at every boot, and hibernating to it stops working.
4. **Finish.** Reboot and choose **Clave (encrypted)**. Type the passphrase, log in, and run
   `clave-encrypt finish`. It checks that the status is **On**, writes the unlock parameters into every boot
   entry (the normal one and the fallback), removes the extra entry, and deletes the offline script.

If the encryption is interrupted, run the offline script again: it resumes. See
[RECOVERY.md](RECOVERY.md#disk-encryption).

## At startup

The Clave boot splash asks for the disk passphrase in the same style as the lock screen. After that, the
login screen asks for your login password as before. There are two prompts on purpose: GNOME Keyring unlocks
with the login password (SEC-4), and logging in automatically would leave it locked.

## Not offered

- **Unlocking with the TPM and no passphrase.** Someone who has the laptop could then start it up to the
  login screen. Without Secure Boot, a changed `/boot` would not be noticed either.
- **Secure Boot.** Out of scope for now. `/boot` is not encrypted, and the recovery page explains what that
  means.

## What Clave does and does not do

`clave-encrypt` only checks, guides and writes config. `cryptsetup`, `systemd-cryptenroll`, `e2fsprogs` or
`btrfs-progs`, `mkinitcpio` and the boot loader's own tool do the work. It never logs or stores a passphrase
or a recovery key, and it makes no network calls. It asks for your password through `sudo`. There is no
passwordless rule for it.
