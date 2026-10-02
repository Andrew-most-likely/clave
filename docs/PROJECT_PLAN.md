# Project plan

This plan sets the target for Clave before more features are added. It turns the ideas in `Notes.md` into
requirements, a roadmap and release criteria. New work should point to a requirement in this file. If a
change does not fit any requirement, update this plan first.

## 1. Purpose and scope

Clave is a polished desktop for Hyprland on Arch Linux. It keeps tiling and adds a menu bar, a Dock, an
Overview of windows and Spaces, Control Center, System Settings, a login screen, a boot splash and
traffic-light title bars. It is built with Quickshell and Hyprland's Lua config. The project was called
arch-macos-hyprland until it was renamed (see BR-1).

This plan covers:

- the public release and how it differs from a personal build
- the visual layer (`home/`, `system/look`, `system/desktop`)
- the hardening layer (`system/harden`)
- the installer and the packages it installs

## 2. Project goals

1. **Polished experience.** A refined, consistent desktop with a menu bar, a Dock and window controls that
   people already know how to use.
2. **Lightweight.** No more background work than a normal Arch install reasonably needs.
3. **Secure.** Hardened by default. A small attack surface. Offline where possible.
4. **Legally clean.** The public release ships no third-party trademarks or copyrighted assets that it has
   no right to use, and does not present itself as another company's software.
5. **Maintainable.** Simple architecture, one settings file, CI that tests the install round trip.

## 3. Architecture principle

> **Do not add complexity solely to reproduce an appearance.**

Every feature must answer these questions before work starts. Put the answers in the pull request.

1. Does it improve the intended experience?
2. Does it require a background service?
3. Does it introduce additional listeners?
4. Does it increase the attack surface?
5. Does it consume meaningful resources?
6. Can it be implemented locally?
7. Can it be implemented more simply?
8. Does it belong in the core system or as an optional setting?

If the answer to 2, 3, 4 or 5 is yes, the pull request must say why the cost is worth it. A feature that is
only visual and needs a new service should be optional and off by default.

## 4. Visual goals

| Surface | Target |
|---|---|
| Menu bar | Logo menu, app name and menus, status items, clock. One bar per screen. |
| Dock | Magnification, running indicators, pinning, genie minimize. |
| Window chrome | One set of traffic lights per window, never two. The lights can be turned off. |
| Login screen | Clean, evenly spaced, customizable background and profile picture. |
| Lock screen and boot | Consistent with the login screen. |
| Desktop | Clean. No files or icons on the desktop (tabled, see section 13). |
| Sounds | The default freedesktop sound theme. |
| Theme | Light and dark, accent color, followed by GTK, Qt, libadwaita and Flatpak apps. |

## 5. Requirements

Each requirement has an ID. Cite the ID in issues, commits and pull requests.

### 5.1 Legal and branding

The public build contains no name, word or image that Apple holds a trademark or copyright on. This applies
to what users see and to internal names: commands, paths, files, settings keys, IPC targets, theme names
and code identifiers. The only places that name Apple are the README (trademark disclaimer, note on the old
name), the changelog, this plan, and the code for the migration (BR-9) and the personal option (BR-10).
`scripts/name-check.sh` enforces this in CI. The ⌘ glyph is a Unicode symbol, not a trademark (see BR-5).
One exception, decided on 2026-10-01: Network Identity (SEC-7) names the systems it makes the laptop look like,
because a profile is useless if the user cannot tell what it imitates (nominative use, no logo or style). The
names appear only in its profile files (`/usr/share/clave/netid/`), its helper, their test and its help page
(`~/.local/share/clave/docs/network-identity.html`); System Settings,
the menu bar and Control Center read the labels from `clave-netid status`, so the shell code names no product.

- **BR-1 Project name.** The project is called **Clave** (Spanish for keystone). All names use the prefix
  `clave`: commands `clave-*`, directories `~/.config/clave`, `~/.local/share/clave`,
  `~/.local/state/clave` and `~/.cache/clave`, the SDDM and Plymouth themes `clave`, and polkit actions
  `org.clave.*`. The installer moves an existing install from the old names (see BR-9).
- **BR-2 Logo.** A solid, one-color keystone: a top that arches gently upward, straight sides that taper to
  about half the top width, and a concave arc for the bottom edge. The drawing is
  `docs/assets/brand/clave.svg` (path `M12 20 Q50 -2 88 20 L70 92 Q50 80 30 92 Z`); every copy uses that path.
  It is used in the menu bar, the About window, the boot splash, the login and lock screens and the terminal.
- **BR-3 Feature names.** Use neutral names:

  | Old name | New name |
  |---|---|
  | Mission Control | Overview |
  | Spotlight | Search |
  | Launchpad | Apps |
  | Night Shift | Night Light |
  | Finder | Files |
  | About This Mac | About This Computer |
  | Apple menu | System menu |

  Dock, Control Center, Hot Corners and Force Quit stay. They are generic terms.
- **BR-4 Files icon.** The file manager shows a folder, not a face, everywhere: Dock, Apps, Search, the
  app switcher and the app's own windows. The icon is Clave's own (BR-12).
- **BR-5 Modifier key glyph.** The ⌘ glyph appears in menus, the shortcut list and the menu bar. Add a
  setting to show ⌘ or a Super/Windows glyph, since most target machines have a Windows key.
- **BR-6 No Apple assets in the repo.** Remove `apple.svg`, `apple-rainbow.png` and the Plymouth logo.
  Nothing replaces them except the Clave logo.
- **BR-7 Fonts and cursor.** The public build uses Inter and JetBrains Mono instead of SF Pro and SF Mono,
  and the Bibata Modern Classic cursor instead of the Apple-style cursor.
- **BR-8 Sounds.** The public build uses the default freedesktop sound theme
  (`/usr/share/sounds/freedesktop/stereo`). No Apple sounds are shipped.
- **BR-9 Migration.** An existing install under the old names (`macos-look`, `macos-*` commands, the
  `macos` SDDM and Plymouth themes) moves to the new names on update. User settings and user-owned files
  are kept. `uninstall.sh` handles both layouts.
- **BR-10 Personal option.** `./install.sh --personal` lets a user restore assets they supply themselves.
  It changes only assets, never wording:
  - the logo, from `~/.config/clave/branding/logo.svg` if the file exists (this works in every build, see
    FEAT-6)
  - SF fonts and the Apple-style cursor, installed from the AUR (`packages/personal-aur.txt`)
  - sounds built from the user's own files with `clave-sounds-build`
  - the WhiteSur app icons, which redraw the other company's app icons (BR-12): the icon theme is
    `WhiteSur`/`WhiteSur-dark` instead of `Clave-icons`/`Clave-icons-dark`

  The repo never contains these files. `branding/` is user-owned, so updates keep it. The choice is stored in
  `~/.local/state/clave/personal`, so updates keep it too. Code: `lib/personal.sh`.
- **BR-12 App icons.** The public build draws every app icon in the default app set with Clave's own
  artwork. The WhiteSur icon theme redraws the other company's app icons and logos (its file manager face,
  photo flower, podcast and voice memo icons), and it gives some apps a third party's logo (a PDF viewer
  logo for the document viewer, a password manager logo for the keyring). Neither may reach a public
  install or screenshot.
  - Clave ships two icon themes in `~/.local/share/icons`: `Clave-icons` (inherits `WhiteSur`) and
    `Clave-icons-dark` (inherits `WhiteSur-dark`). Both read the same SVG files in
    `Clave-icons/scalable/apps`, so WhiteSur still supplies folders, file types and status icons.
  - Each icon is a rounded square with a flat color and a simple glyph of a generic idea (folder, clock,
    chess knight). It never copies the composition, color scheme or glyph of the other company's icon for
    the same app.
  - Icons are named by the icon names the apps ask for (desktop file `Icon=` and the app ID), so windows,
    notifications and About dialogs show them too, not only the Dock and Apps.
  - `tests/icons-test.sh` checks that every app in APP-1 and SW-3 has an icon in the theme, that each SVG
    renders, and that GTK finds it through `Clave-icons-dark`.
  - Apps the user adds keep their theme icon. Extras (`--extras`) show those apps' own logos, which is
    their owners' use, not another company's.
- **BR-11 Layout, not identity.** Clave's own interfaces (section 5.8, System Settings, the shell) may match
  the layout and behavior of the desktop they are modeled on. They always use Clave's own icons, artwork and
  names (BR-3), and never the other company's. Every surface that closely matches the original layout is
  listed here with a short description, so it can be reviewed before a public release:

  | Surface | What it matches |
  |---|---|
  | Screenshot toolbar (SHELL-1) | Toolbar layout, floating thumbnail |
  | Displays pane (SHELL-2) | Pane layout, arrangement canvas |
  | Activity Monitor (SHELL-3) | Tabs, process list, Quit and Force Quit |
  | Calendar and Contacts (APP-8) | Views, sidebar, event popover, contact cards |
  | Notes (APP-9) | Folder sidebar, note list, editor |

  Before v1.1.0 is published, check whether a close layout match is a trade-dress risk and record the
  result here.

  Review status (2026-09-27): **open, needs Andrew's review, and a lawyer's if in doubt.** This note makes
  no legal judgment. Items flagged for that review:
  - The five surfaces in the table above. Each uses Clave's own icons (`home/.config/quickshell/Clave/icons`),
    colors from the Clave theme and no artwork from the other company. The layouts are close by design.
  - GTK4 traffic-light window buttons on the left (APP-3), drawn in CSS with Clave's own colors.
  - Four "Shown as" names in APP-1 are the same words as product names of the company Clave is modeled on:
    Stickies, Voice Memos, Keychain, and Freeform (shown as "Freeform board"). The other names are generic
    words. `scripts/name-check.sh` does not flag these four, because they are also ordinary words. Each
    name is one entry in `clave-prefs` (`APP_NAMES`) and can be changed there without other changes.
    Decision 2026-10-01: the four names stay. "App Store" (the menu and System Settings entry for Bazaar) is
    a product name, not an ordinary word: it is now **Software**, and `scripts/name-check.sh` flags it.
  - The screenshot shortcuts are on Print, because Shift+Super+1..0 move windows between Spaces.
- **BR-13 One logo, one icon set (added 2026-10-01).** Everything Clave ships shows one matching set:
  - **Logo.** The BR-2 keystone, or the user's own logo (FEAT-6), on every surface that shows a logo:

    | Surface | Source |
    |---|---|
    | Menu bar and About This Computer | `quickshell/Clave/icons/logo.svg`, in the text color |
    | Boot splash and login screen | `plymouth-clave/logo.png`, copied into the SDDM theme by `scripts/system.sh` |
    | Lock screen | `~/.cache/clave/lock-logo.png`, drawn by `install.sh` |
    | Terminal | `fastfetch/assets/clave.txt` (keystone only) |
    | App icon of About This Computer | `clave-logo` in Clave-icons |

  - **Icons.** Every app in APP-1, SW-3 and the default Dock pins, every Clave window and the Software
    Update notice use a Clave-icons icon (BR-12). Clave's own windows share the app id `org.quickshell`, so
    the Dock and Overview pick the icon by window title (`ClaveSettings.windowAppId`).
  - **Names.** One name per feature, the same in menus, window titles, the Dock, the README and the site.
  - `tests/icons-test.sh` reads the apps from `clave-prefs`, the Dock pins and the window table, and fails on
    an app without an icon or an icon without an app. `scripts/name-check.sh` checks the names.

### 5.2 Security

- **SEC-1 Hardened by default.** This is final. The installer installs the hardening layer unless the user
  passes `--no-harden`. `--yes` also installs it. `--harden` is still accepted and does nothing extra.
- **SEC-2 Lockout warnings.** USBGuard and faillock can lock a user out. Before they are turned on, the
  installer shows what they do and how to recover. With `--yes` the warning is printed but not asked.
  The README links to a recovery guide. Done: [RECOVERY.md](RECOVERY.md).
- **SEC-3 Offline by default.** Nothing contacts the network unless the user asks for it. Online features
  (web search in Search, album art, currency rates) are off by default.
- **SEC-4 Keyring.** GNOME Keyring unlocks at login and apps that store secrets use it with full
  encryption. See ISSUE-2.

- **SEC-5 Disk encryption.** A laptop without disk encryption gives its files to anyone who takes it,
  whatever the rest of the hardening does. Clave warns when the disk is not encrypted and offers a guided
  setup. The name everywhere is **Disk Encryption** (BR-3).
  - **Status.** `clave-encrypt status` reads `lsblk -J` as the user, with no root: *On* when `/` and `/home`
    are on LUKS, *Partly* when only one is, *Off* otherwise. A swap partition that is not encrypted also
    counts as *Partly*. zram needs nothing.
  - **Where the warning shows.**
    1. The installer, the same way as SEC-2: printed with `--yes`, otherwise a question that offers the setup.
    2. System Settings > Privacy & Security > Disk Encryption: the status, what it protects against, and a
       **Set Up Disk Encryption…** button.
    3. One notification at the first login after the install, with *Set Up…*, *Not Now* and *Don't Ask Again*.
       The shell checks once at login and never again (PERF-1). No timer, no repeat.
  - **Setup.** `clave-encrypt setup` runs in a terminal with `sudo`, which asks for the password. There is no
    passwordless polkit rule for it. It offers two paths:
    1. **Reinstall with encryption (recommended on a new machine).** It opens the guide in
       `docs/ENCRYPTION.md`: Arch install with LUKS2 (for example `archinstall`'s disk encryption option), then
       Clave's installer.
    2. **Encrypt in place.** For an existing install. It runs in three stages:
       - **Checks.** Stops when any of these fails: power supply connected and battery at 50% or more;
         the user types a confirmation that a full backup exists and where it is; the filesystems are ext4
         or btrfs on plain partitions (not LVM or RAID); each has 64 MiB free (32 MiB for the LUKS2 header,
         plus room); `/boot` is its own partition with the kernels, so it stays readable before the unlock;
         the boot loader is systemd-boot, GRUB or Limine (unified kernel images and anything else: reinstall
         path only).
       - **Prepare, in the running system.** Choose the LUKS UUIDs in advance (`cryptsetup reencrypt
         --uuid`). Add the unlock hook after `block` to the mkinitcpio hooks (after `plymouth`, so the prompt
         is graphical) and rebuild the initramfs: `sd-encrypt` with `rd.luks.name=…` for systemd-based
         HOOKS (the Arch default since 2024), `encrypt` with `cryptdevice=UUID=…` otherwise. Write a
         **second** boot entry, "Clave (encrypted)". The old entry stays the default, so the machine still
         boots if the user stops here. When `/home` is on its own partition, it unlocks with a key file inside
         the encrypted root (`/etc/cryptsetup-keys.d/chome.key`), so there is one prompt at boot. The offline
         stage makes that key and writes `/etc/crypttab`, after `/` is encrypted: the key is never on the
         disk in the clear, and a stop after this stage leaves no crypttab entry that waits for a missing
         device. A swap partition gets a random key at each boot (hibernation to it stops working).
       - **Encrypt, offline.** Boot the Arch live USB and run the copy of the script that stage 2 put on
         the boot partition (`/boot/clave-encrypt-offline.sh`, root-owned, printed with its SHA-256 so the
         user can compare). It shrinks each filesystem by 32 MiB (`e2fsck`, `resize2fs`), runs
         `cryptsetup reencrypt --encrypt --type luks2 --reduce-device-size 32M` with the chosen UUID, and
         enrolls a recovery key with `systemd-cryptenroll --recovery-key`. The recovery key is shown once and
         never stored: the user writes it down. LUKS2 re-encryption survives interruption: `cryptsetup
         reencrypt --resume-only` continues it, and the script says so.
       - **Finish.** Boot the new entry. `clave-encrypt finish` checks that the status is *On*, writes the
         unlock parameters into every existing entry (so the fallback entry works too) and removes the extra
         one. For GRUB this goes into `GRUB_CMDLINE_LINUX`, so kernel updates keep it.
  - **Uninstall.** `uninstall.sh --system` restores the pre-install `mkinitcpio.conf` and `/etc/default/grub`.
    On an encrypted disk it then puts the unlock hook and parameters back (`clave-encrypt reapply`), or the
    machine would no longer boot.
  - **Engines.** Only upstream tools do the work: `cryptsetup`, `systemd-cryptenroll`, `e2fsprogs` or
    `btrfs-progs`, `mkinitcpio`, and the boot loader's own tool. Clave's script checks, guides and writes
    config (section 5.8). It never logs or stores a passphrase and makes no network calls.
  - **Boot prompt.** The Clave Plymouth theme draws the passphrase prompt in the same style as the lock
    screen (`Plymouth.SetDisplayPasswordFunction`). Wrong passphrases show the standard message.
  - **Not offered by default.** TPM2 unlock without a passphrase: weaker against someone who has the laptop,
    and without Secure Boot it does not stop a changed boot partition. Secure Boot itself is out of scope
    for now; `/boot` stays unencrypted, which RECOVERY.md explains.
  - **Recovery.** RECOVERY.md gets a section: forgotten passphrase (use the recovery key), interrupted
    encryption (resume from the live USB), and booting the old entry if the new one fails before *Finish*.
  - **Tests.** `tests/encrypt-unit.sh` (CI): the status on saved `lsblk` output and every config writer on
    scratch files. `tests/vm-encrypt.sh` (qemu, UEFI): in-place encryption of `/` alone and of `/` plus
    `/home`, with each supported boot loader, and one run where the VM is powered off during `reencrypt`
    and then resumed.

- **SEC-6 Signed updates (added 2026-10-01).** `setup.sh` and `clave-update` install only releases signed by
  a trusted key, and never one older than the installed release. The project key ships in
  `~/.local/share/clave/allowed_signers`, so a signed release can replace it; the user's own
  `~/.config/clave/allowed_signers` only adds keys. Root helpers never decode a picture the user chose, and
  USBGuard gives the user list and listen rights only (`IPCAllowedUsers=root`). See `.github/SECURITY.md`.

- **SEC-7 Network Identity (added 2026-10-01).** On a shared network (campus, café), DHCP, the IP TTL, the TCP
  SYN, ping replies and the captive portal's user agent tell everyone on the LAN that the laptop runs Linux.
  Network Identity makes the laptop look like a common device instead: **Windows 11**, **macOS**, **iPhone**,
  **Android** or **Linux** (the native look). A separate **Stealth** switch makes it answer as little as
  possible. It is optional and off by default (FEAT-10).
  - **Limits, said in the pane.** The access point always sees a device that transmits. 802.11 probe and
    association fields and the radio's own signal look like Linux on an Intel radio in every profile; only a
    kernel driver change could alter them. Windows is the believable profile on Intel hardware. The other
    profiles fool DHCP fingerprinting, OS detection in routers and `nmap`, and captive portals, but not a
    passive 802.11 classifier. Traffic inside a VPN tunnel is not affected.
  - **What a profile sets.** One root-owned file per profile in `/usr/share/clave/netid/`. Values from the p0f
    and satori fingerprint databases, checked on the wire before release:

    | | Windows 11 | macOS | iPhone | Android | Linux |
    |---|---|---|---|---|---|
    | IP TTL | 128 | 64 | 64 | 64 | 64 |
    | TCP timestamps | off | on | on | on | on |
    | SYN options | mss,nop,ws,nop,nop,sok | mss,nop,ws,nop,nop,ts,sok,eol | as macOS | kernel order | kernel order |
    | SYN window | kernel (64240) | 65535 | 65535 | kernel | kernel |
    | DHCP option 55 | 1,3,6,15,31,33,43,44,46,47,119,121,249,252 | 1,121,3,6,15,108,114,119,252,95,44,46 | 1,121,3,6,15,108,114,119,252 | 1,3,6,15,26,28,51,58,59,43,114,108 | dhcpcd default |
    | DHCP option 60 | MSFT 5.0 | none | none | android-dhcp-14 | none |
    | DHCP hostname | DESKTOP-XXXXXXX, new each connect | MacBook-Pro | iPhone | none | none |
    | Ping replies | no | yes | yes | yes | yes |
    | Portal user agent | Firefox on Windows | Safari on macOS | Safari on iOS | Chrome on Android | Firefox on Linux |

    In every profile while the feature is on: a random MAC address for each connection (no vendor prefix, which
    would not match the Intel radio), the DHCP client id is that MAC, and leases are forgotten on disconnect.
    **Stealth** adds: no ping or timestamp replies, all new inbound traffic dropped without a reply (instead
    of the default reject), ARP answers only for the laptop's own address, and no DHCP hostname.
  - **Root helper.** `/usr/local/bin/clave-netid apply PROFILE STEALTH`, `status` and `reset`, run through
    pkexec (polkit action `org.clave.netid`, `auth_admin_keep`, the same as `clave-usb`, so a program running
    as the user cannot turn Stealth off without the password). It accepts only the five profile names and
    renders every file from the profile data; nothing the user types reaches a config file. State is in
    `/etc/clave/netid/state`. `reset` removes every file it wrote and returns the laptop to the install
    defaults. `clave-netid.service` applies the saved state at boot, before NetworkManager.
  - **Engines.** NetworkManager with `dhcp=dhcpcd` (dhcpcd's config sets options 55 and 60), sysctl for TTL,
    timestamps and ARP, and two chains inside the existing `inet hardening` nftables table (`netid_in`,
    `netid_out`; an accept in another table cannot undo a drop in this one). Two things need more:
    - The DHCP TTL and the exact order of option 55. dhcpcd sends DHCP through a raw socket that bypasses
      netfilter, always with TTL 64, and it sorts option 55 by number. An optional dhcpcd build with a small
      patch (`scripts/extra/dhcpcd-netid/`) reads both from `/etc/clave/netid/dhcp`. Without that build the
      pane says that the DHCP TTL stays 64 and the option order is dhcpcd's.
    - The SYN option order. `clave-synshape` reorders the options of the laptop's own outgoing SYNs and sets
      the SYN window. It never adds an option and never changes the MSS or window-scale value, so the
      connection itself is unchanged. It is Python with only the standard library (netlink, no compiled
      code), runs only when the profile needs it, as a `DynamicUser` with `CAP_NET_ADMIN` only, and the queue
      rule uses `bypass`, so traffic flows unchanged if it stops. It sees IPv4 SYNs leaving through an
      Ethernet-type interface (Wi-Fi or wired), not tunnel or VM traffic.
  - **Answers to the section 3 questions.** (1) Yes: privacy on shared networks, which the user asked for.
    (2) One optional service, `clave-synshape`, only for Windows, macOS and iPhone. (3) No listeners; the
    service reads a netfilter queue, not a socket on the network. (4) A little: root-side code parses the
    laptop's own outbound SYN headers only, bounded by the header length, with no other input. The helper
    takes a fixed set of words. (5) No: SYNs only, one per new connection. (6) Yes, fully local. (7) The
    simpler parts (TTL, DHCP, ping) use existing engines; only the SYN order needs new code. (8) Optional,
    off by default.
  - **Tests.** `tests/netid-unit.sh` (CI, no root) renders every profile into a scratch root and compares the
    files, checks every rendered ruleset with `nft -c` when nft is present, and runs the SYN rewriter on saved
    packets. On the laptop: a `tshark` capture of DHCP, SYNs and ICMP for each profile, `nmap -O` from a second
    device, and `reset` restoring the files.

### 5.3 Performance and background work

- **PERF-1 Background budget.** No listeners or services beyond what a normal Arch install needs, plus the
  ones in the inventory below. Each entry has a written purpose.
- **PERF-2 Inventory.** Keep this list current. Checked against a live install on 2026-09-27:

  | Unit or process | Layer | Purpose |
  |---|---|---|
  | Quickshell (shell, Dock) | look | The shell itself |
  | `sddm.service` | look | Login screen |
  | swaync, swayosd-server, hypridle, awww-daemon, polkit-gnome agent | look | Notifications, volume and brightness pop-ups, idle timeouts, wallpaper, password prompts |
  | `clave-clipboard watch` | look | Clipboard history. Off in System Settings stops it. |
  | `home-cleanup.timer` (user) | desktop | Weekly cache cleanup |
  | `paccache.timer` | desktop | Package cache cleanup |
  | `cups.socket`, `avahi-daemon.service` | desktop | Printing and printer discovery |
  | `bluetooth.service` | desktop | Bluetooth |
  | `nftables`, `opensnitchd`, `usbguard` | harden | Inbound firewall, outbound control, USB control |
  | `apparmor`, `auditd` | harden | Mandatory access control, audit log |
  | `arch-audit.timer` | harden | Daily CVE check |
  | `aidecheck.timer`, `aide-refresh.service` | harden | File integrity check, baseline refresh after upgrades |
  | `clave-netid.service` (oneshot, only while Network Identity is on) | harden | Loads the saved profile at boot (SEC-7) |
  | `clave-synshape.service` (only for profiles that reorder SYN options) | harden | Reorders the options of the laptop's own outgoing SYNs (SEC-7) |
  | `geoclue` (D-Bus activated, v1.1.0) | apps | Location for Weather, Clock and Maps. Starts only when one of them asks and stops after; its network sources are off (APP-6) |

  Listeners inside the shell, all event-driven, none polling:

  | Listener | Purpose |
  |---|---|
  | `nmcli monitor` (one per menu bar) | Wi-Fi icon |
  | `gio monitor` on the Trash | Dock's Trash icon |
  | `swaync-client -s` | Notification Center state |
  | `journalctl -k -f`, only while USBGuard runs | Notice about blocked USB devices |

  Timers and processes added in v1.1.0, none of which run when their window is closed (PERF-3):

  | Timer or process | Runs only |
  |---|---|
  | Activity Monitor's 2-second refresh (SHELL-3) | While Activity Monitor or Force Quit is open |
  | Calendar's reminder check (APP-8) | While Calendar is open |
  | `wf-recorder` and the menu bar's stop button (SHELL-1) | While recording |
  | `qs -p` for Notes, Calendar and Contacts (APP-8, APP-9) | While the app is open |
  | `clave-displays lid` (SHELL-2) | Once, when the lid opens or closes |

  Removed in this check: two polling timers (Wi-Fi every 10 seconds, Trash every 5 seconds), and
  `usbguard-notifier`, which repeated the shell's own USB notice. The startup chime went in phase 2.

  Everything else that ran on the test machine came from Arch itself (systemd, the pacman keyring sockets,
  `fstrim.timer`, `logrotate.timer`, `thermald`, `iio-sensor-proxy`) or from apps the user installed
  (Mullvad, libvirt), not from Clave. `avahi-daemon` stays: printer discovery needs it. It listens on the
  local network, and the firewall lets in only its mDNS multicast (UDP 5353) and drops other inbound traffic.

- **PERF-3 Optional features cost nothing when off.** A disabled feature starts no process, timer or watcher.

### 5.4 Offline

- **OFF-1 Calculator.** The calculator works with no network. The calculator app is `gnome-calculator`
  (`packages/desktop.txt`), which downloads currency rates once a week. The installer sets its
  `refresh-interval` to 0. The calculator in Search must be fully local too.

### 5.5 Compatibility

- **COMP-1** Hyprland 0.55 or later. Plugins build against the running Hyprland.
- **COMP-2** Arch Linux and Arch-based distributions.
- **COMP-3** GTK3, GTK4/libadwaita, Qt5, Qt6 and Flatpak apps follow the theme.
- **COMP-4** Laptops and desktops, one or more screens, with no assumptions about panel names.

Arch is a rolling release, so Clave cannot pin the versions of the software it depends on. Hyprland,
Quickshell, the hyprbars plugin, WhiteSur, GTK4 and libadwaita can each break Clave in an ordinary update.
COMP-5 to COMP-9 tell the maintainer on GitHub when that happens, and tell the user whether a Clave update
is needed. The rule is: the cheapest checks that work, no paid services, and nothing new running on the
user's machine.

- **COMP-5 Upstream watch (GitHub).** A workflow, `.github/workflows/upstream.yml`, runs once a day.
  - It finds the current version of everything Clave depends on: repo packages with `pacman -Sy` and
    `pacman -Si` in an `archlinux` container (no `-Syu`), AUR packages through the AUR RPC `info` call,
    and WhiteSur with `git ls-remote`.
  - It compares them with the last green manifest, kept on an orphan branch `ci-state`. Users never follow
    that branch, so its commits need no signature.
  - `.github/ci/watched.txt` lists the packages Clave talks to directly: for example hyprland, quickshell,
    hyprlock, hypridle, swaync, rofi, sddm, plymouth, gtk4, libadwaita, qt6-declarative and WhiteSur. When
    one of them changes, the workflow runs the lint and install jobs of `ci.yml` (made reusable with
    `workflow_call`). Any other change only updates the manifest.
  - This replaces the weekly `schedule` in `ci.yml`, which is removed.
- **COMP-6 Result as an issue.** When the run fails, the workflow opens or updates one issue with the label
  `upstream-break`. The issue lists the version changes and the step that failed. That issue is the signal
  that Clave needs an update. When the run passes, the new versions become the last known good manifest
  on `ci-state`.
- **COMP-7 Compatibility file.** `compat.json` in the repo root. Only signed maintainer commits change it.
  It lists the versions each Clave release was tested with, and the known breaks as
  `{package, from, fixed_in_clave, issue}`. It reaches users inside the signed checkout that `clave-update`
  already verifies: no new download and no new trust path. The workflow never commits to `main`, because
  `clave-update` requires the newest commit to be signed.
- **COMP-8 `clave-doctor`.** A command on the user's machine, not a service.
  - Local checks, always run: `Hyprland --verify-config` on the user's config; the hyprbars plugin was
    built for the running Hyprland; the last Quickshell log has no QML errors; the WhiteSur and GTK4
    assets link exists; no Clave user unit has failed; and the installed watched packages against
    `compat.json` in the local checkout.
  - Each package gets one of three results: *OK*; *Untested* (newer than tested, no known break); or
    *Update Clave* (inside a known break that a later release fixes, so run `clave-update`). A known break
    with no fix yet shows the issue link.
  - `clave-doctor --fetch` fetches the repo, verifies the tag with the same `verify()` as `clave-update`,
    and then compares against the newest signed `compat.json`. This is the only part that uses the
    network, and only when asked (SEC-3).
  - `clave-update` runs `clave-doctor` at the end.
- **COMP-9 Pacman hook.** `/etc/pacman.d/hooks/clave-doctor.hook` runs after a transaction that changes a
  watched package (`NeedsTargets`).
  - It reads only `/usr/share/clave/compat.json`, a copy that the installer writes.
  - It prints warnings and never stops the transaction: a stopped upgrade leaves a partial upgrade, which
    is worse on Arch.
  - It leaves a flag in `/var/lib/clave/`. The shell shows one notification at the next login and clears
    the flag, the same pattern as SEC-5.

Answers to the section 3 questions for COMP-5 to COMP-9: they improve reliability and tell the user what to
do; no service, listener or timer runs on the user's machine (PERF-1); the network is used only with
`--fetch`; the attack surface grows by one root hook that reads JSON and prints text, and never runs code
from the checkout; everything on the user's side is local.

### 5.6 Software footprint

- **SW-1** The public release ships only what the visual layer, the built features, the hardening and the
  standard app set (SW-4) need. Changed on 2026-09-27: the standard apps of the desktop Clave is modeled on
  are part of the experience, so they ship by default.
- **SW-2** Convenience apps (for example Spotify or virtual machine managers) never ship by default. They
  stay in `packages/extras*.txt`. An app is a convenience app when it is not in the standard app set (APP-1).
- **SW-3** Audit `packages/desktop.txt` against SW-1. Each GNOME app either backs a feature (for example
  Nautilus for the Dock's Trash) or moves to extras. Done: Nautilus, Text Editor and Calculator back Files and the Dock's
  default pins; Loupe and File Roller open pictures and archives from Files. Disks, Disk Usage Analyzer,
  Snapshot and Passwords and Keys moved to extras. Partly reversed by SW-4: Disks, Snapshot and Passwords
  and Keys come back as standard apps. Disk Usage Analyzer stays in extras.
- **SW-4 Standard app set.** The apps in APP-1 ship by default in a new `packages/apps.txt`. They come from
  the Arch repositories (signed packages), not the AUR or Flathub, unless APP-1 says otherwise. There is no
  opt-out flag.
- **SW-5 Package audit (2026-09-28).** Every package in the default lists was checked against the files
  that use it. Removed: `cmake`, `meson` and `ninja` (the plugin builds use only `g++` and
  `pkg-config`), `alsa-utils` (sounds play through `pw-play`) and `cups-pdf` (GTK's Print to File
  covers it). Moved to extras: `lynis` (a hand-run audit that nothing calls) and `ttf-carlito`,
  `ttf-caladea` (Office fonts, useful only with an office suite). Kept with a comment: `sassc` and
  `gnome-themes-extra`, which the WhiteSur GTK theme's installer needs.
  - `xsettingsd`: its config shipped and `clave-prefs` signaled it, but no list installed it and
    nothing started it. Removed the config, the signal and nwg-look's export, instead of adding a
    process (PERF-1). GTK apps read the theme from `settings.ini` and gsettings.
  - `scripts/manifest-home.txt` missed 26 shipped files (for example `clave-doctor` and the ClaveApps QML),
    so `scripts/capture.sh` did not copy live changes to them back. They are listed now. The user's
    own files (`clave/*`, `hypr/custom.lua`, `hypr/monitors.lua`, `hypr/hypridle.conf`,
    `kitty/custom.conf`) stay out on purpose.

### 5.7 Standard apps

The target is the set of apps a new user of this kind of desktop expects to find: calendar, notes, photos and
so on. The rule for every app (decision 2026-09-27): **no background service, no Flatpak runtime, and no
network use unless the app's purpose needs it.** An app runs only while its window is open. Where a stock
open-source app meets the rule, Clave ships it and themes it (APP-3). Where none does, Clave draws the app in
Quickshell on top of open-source libraries (section 5.8).

- **APP-1 App set.** One app per role. All are in the Arch `extra` repository. Names are what the Dock,
  Apps and Search show (APP-4).

  | Role | Shown as | Package | Toolkit | Notes |
  |---|---|---|---|---|
  | Calendar | Calendar | Clave app (APP-8) | QML | `gnome-calendar` rejected: evolution-data-server stays running |
  | Contacts | Contacts | Clave app (APP-8) | QML | `gnome-contacts` rejected: evolution-data-server and gnome-online-accounts |
  | Reminders | Reminders | `errands` | GTK4 | Local lists. CalDAV sync off by default |
  | Notes | Notes | Clave app (APP-9) | QML | `iotas` rejected: it embeds WebKitGTK to show Markdown |
  | Sticky notes | Stickies | `sticky` | GTK4 | |
  | Terminal | Terminal | `kitty` | OpenGL | Pinned in the Dock; `Super+Return` |
  | Weather | Weather | `gnome-weather` | GTK4 | Online only while open (APP-6) |
  | Clock, alarms, timers | Clock | `gnome-clocks` | GTK4 | Depends on geoclue; no network location (APP-6) |
  | Maps | Maps | `gnome-maps` | GTK4 | Online only while open (APP-6) |
  | Photo library | Photos | `shotwell` | GTK3 | Loupe stays the default image viewer |
  | E-books | Books | `foliate` | GTK4 | Embeds WebKitGTK, only while open. Accepted: EPUB needs a real layout engine |
  | Podcasts | Podcasts | `gnome-podcasts` | GTK4 | Online only while open (APP-6) |
  | Music | Music | `amberol` | GTK4 | `gnome-music` rejected: it needs the `localsearch` indexer (PERF-1) |
  | Video | Videos | `showtime` | GTK4 | Decoders in APP-11. VLC stays in extras |
  | Voice recording | Voice Memos | `gnome-sound-recorder` | GTK4 | |
  | Camera | Camera | `snapshot` | GTK4 | Back from extras (SW-4) |
  | Fonts | Fonts | `gnome-font-viewer` | GTK4 | |
  | Chess | Chess | `gnome-chess`, `gnuchess` | GTK4 | GNU Chess is the computer opponent; without an engine, Chess only allows two human players. Stockfish is stronger but only in the AUR |
  | Whiteboard | Freeform board | `rnote` | GTK4 | |
  | Scanner | Scanner | `simple-scan` | GTK3 | SANE starts no service |
  | Remote screen (client only) | Screen Sharing | `gnome-connections` | GTK4 | No listener |
  | System log | Console | `gnome-logs` | GTK4 | |
  | Hardware report | System Information | `hardinfo2` | GTK3 | Benchmark sync only when Synchronize is pressed (step 1) |
  | Disks | Disk Utility | `gnome-disk-utility` | GTK4 | Back from extras (SW-4) |
  | Keys and certificates | Keychain | `seahorse` | GTK3 | Back from extras (SW-4). Keyserver lookups only on request; no connection at start (step 1) |
  | Backups | Backups | `timeshift` | GTK3 | Installed, not configured. Nothing runs until the user sets it up |

  Already shipped and unchanged: Files (`nautilus`), Text Editor, Calculator, Loupe, File Roller, and
  Evince for PDFs (pulled in by `sushi`, so no second PDF app). The character viewer stays
  `clave-emoji` (`rofi-emoji`), which already uses the Clave theme.

  No equivalent, out of scope: messaging, video calls, device finding, home automation, TV, news, stocks,
  automation, voice assistant and phone mirroring. They depend on Apple services.

- **APP-2 Replaced and duplicate software.** When an APP-1 app or a section 5.8 engine replaces something,
  the replaced item leaves the package lists. On update, the installer removes the Clave files it replaces
  (the BR-9 pattern). It never uninstalls a package the user may have installed themselves; it prints a
  list the user can remove instead.

  | Removed from the lists | Replaced by |
  |---|---|
  | `htop` (`packages/extras.txt`) | Activity Monitor (SHELL-3); `btop` stays in extras for the terminal |
  | `clave-screenshot`, the Print binds that call it | SHELL-1 |
  | `clave-displays`, `scripts/display-mode.sh`, `rofi/clave-display.rasi`, the Super+P menu | SHELL-2 |
  | `Clave/ForceQuit.qml` as a separate window | SHELL-3 (Force Quit stays as a dialog of the same component) |

- **APP-3 Theme.** Every APP-1 app follows the Clave theme in light and dark with the accent color (COMP-3).
  GTK3 apps use WhiteSur. GTK4/libadwaita apps use `home/.config/gtk-4.0/gtk.css`. That file is extended
  so the window buttons of libadwaita apps look like the traffic lights, on the left, and header bars,
  sidebars and corner radius match the shell. A theme can change colors, fonts, spacing and radius. It
  cannot move widgets: the layout of each app stays its own. That limit is accepted (decision 2026-09-27).
  Every APP-1 app that draws its own title bar goes in the default `windows.noBarApps` list, so each window
  has exactly one set of traffic lights (ISSUE-1).

- **APP-4 Names and icons.** The Dock, Apps and Search show the "Shown as" names from APP-1. The names are
  generic words (BR-3, BR-11). Clave sets them with `.desktop` overrides in
  `~/.local/share/applications`. It does not patch packages. Icons come from the icon theme (`Clave-icons`, BR-12). Any app's
  icon can be changed in `~/.config/clave/settings.json`:

  ```json
  "icons": { "org.gnome.Weather": "~/Pictures/icons/weather.png" }
  ```

  `clave-prefs` writes the override `.desktop` file with that `Icon=`. It accepts only local PNG and SVG
  files and copies them to `~/.local/share/clave/icons/`. The logo has no such checks yet (FEAT-6), so
  `clave-prefs icon set ID FILE` has its own: the path must resolve to a regular file, `file --mime-type`
  must say PNG or SVG, and the picture is re-encoded (PNG with `magick`, 256×256, metadata stripped).
  `clave-prefs icon reset ID` goes back to the theme icon. System Settings > Appearance has an App Icons
  row for both.

- **APP-5 Default apps.** The installer sets the MIME defaults: Calendar for `text/calendar`, Contacts for
  `text/vcard`, Videos for video types, Music for audio types, Books for EPUB, and Maps for `geo:` links.

- **APP-6 Offline defaults (SEC-3).** Only Weather, Maps and Podcasts use the network, because their
  data exists only online (forecasts, map tiles, feeds). They connect only while open, and OpenSnitch asks
  before each one's first connection (hardening layer). Without the hardening layer they connect when
  opened. Every other app makes no network calls. Nothing syncs in the background.
  - geoclue: the network location sources (Wi-Fi, cell) are off in
    `/etc/geoclue/conf.d/90-clave.conf`. Weather, Clock and Maps ask the user for a city instead.
  - Reminders: CalDAV sync stays off. Calendar, Contacts and Notes (APP-8, APP-9) have no sync at all.
  - Weather and Podcasts: no refresh while closed. Check whether either one has a background mode; turn
    it off if it does.

- **APP-7 Background cost (PERF-1).** The app set adds no service that stays running. One dependency is
  D-Bus activated: `geoclue`, pulled in by Weather, Clock and Maps. It starts only when one of them asks for
  the location, and with its network sources off (APP-6) it has nothing to look up online. Record it in
  PERF-2 after the clean-VM check.

- **APP-8 Calendar and Contacts.** Clave apps drawn in Quickshell (section 5.8).
  - Each one runs as its own process (`clave-app calendar`, `clave-app contacts`, which run
    `qs -n -p ~/.config/quickshell/clave-NAME.qml`). `qs -c` does not work: Quickshell ignores
    subfolders of a config that has a `shell.qml`. It starts when opened and exits when its window closes, so a crash cannot take the shell down. No new runtime:
    Quickshell and Python are already required.
  - Data is plain files: one `.ics` file per calendar in `~/.local/share/clave/calendars/`, and one `.vcf`
    file per contact in `~/.local/share/clave/contacts/`. Importing a file means copying it there. Other apps
    and backups can read them.
  - Open-source libraries read and write the files: `python-icalendar` (recurrence through
    `python-dateutil`) and `python-vobject`. Clave code never parses the formats itself. The QML calls
    `clave-pim`, which reads and writes the files with these libraries and prints JSON.
  - Views: Calendar has day, week, month and year views, a sidebar with calendars and a mini month, and
    event details in a popover. Contacts has a list with an index and a card view. Both use the 1:1
    layout (BR-11).
  - Reminders from events: a notification appears only if the event starts while Calendar is open. There
    is no alarm service (PERF-1). The Clock app is for alarms.
  - No sync, no accounts, no network.

- **APP-9 Notes.** A Clave app like APP-8 (`clave-app notes`). Notes are Markdown files in
  `~/Documents/Notes`, one folder per folder in the sidebar. Formatting shows in a QML `TextEdit` (Qt's
  Markdown reader and writer, `TextDocument`), with no web engine. Search looks only inside that folder.

- **APP-10 Helper launchers stay out of Apps (added 2026-09-28).** Apps, Search and the Dock show only
  apps a user opens on purpose: the APP-1 set, the Clave apps and the apps of SW-3. A package in the
  package lists often installs a launcher that only backs a feature, configures a theme, or comes with
  a dependency. `clave-prefs apps names` hides each of those launchers with a copy in
  `~/.local/share/applications` that adds `NoDisplay=true` (the APP-4 pattern; packages are never
  patched). The copy keeps `Exec` and `MimeType`, so `xdg-open` and MIME defaults still work. Clave Settings,
  Control Center and the menu bar stay the way to reach the tools that have a use.

  | Hidden launcher | Package | Why |
  |---|---|---|
  | Volume Control | `pavucontrol` | Opened from Sound in Clave Settings and the menu bar |
  | Bluetooth Manager, Bluetooth Adapters | `blueman` | Opened from Bluetooth in Clave Settings and Control Center |
  | Print Settings | `system-config-printer` | Opened from Printers in Clave Settings |
  | Manage Printing | `cups` | The CUPS web page; Print Settings covers it |
  | OpenSnitch | `opensnitch` | Opened from Clave Settings; the prompts need no launcher |
  | Qt5 Settings, Qt6 Settings, Kvantum Manager | `qt5ct`, `qt6ct`, `kvantum` | Theme backends; Clave Settings writes their files |
  | GTK Settings | `nwg-look` | Theme backend; Clave ships its config |
  | Rofi, Rofi Theme Selector | `rofi` | Engine of Apps, Search and the emoji picker |
  | Avahi Zeroconf Browser, Avahi SSH Server Browser, Avahi VNC Server Browser | `avahi` | Dependency of CUPS and `nss-mdns` |
  | Hardware Locality lstopo | `hwloc` | Dependency |
  | Qt V4L2 test Utility, Qt V4L2 video capture utility | `v4l-utils` | Dependency of `ffmpeg` |
  | File Roller | `file-roller` | Opens archives from Files; a helper, not an app a user starts |
  | Advanced Network Configuration | `nm-connection-editor` | Opened from Wi-Fi Settings in the menu bar and from Control Center |

  The WhiteSur GTK theme's installer always adds its own theme switcher app. `scripts/fetch-themes.sh`
  removes it right after, because Clave Settings sets the theme.

  Stays visible: Files, Text Editor, Calculator, Image Viewer, Document Viewer (Evince, the PDF app of
  APP-1), the terminal and the APP-1 set.

  - Hide only with an override. Removing a `.desktop` file breaks `xdg-open` and MIME defaults
    (File Roller must still open archives). `tests/apps-test.sh` checks this.
  - `clave-doctor` lists each launcher that a package in the default lists shows in Apps and that is
    in neither list above (`clave-prefs apps unexpected`). CI does not install the packages, so the
    check runs on the machine.
  - Same pass: `org.libreoffice.LibreOffice` leaves `packages/extras-flatpak.txt` (removed from the
    live machine on 2026-09-28). The comments in `monitors.lua`, `hyprland.lua` and README that say
    `nwg-displays` writes `monitors.lua` are removed, and so is its window rule; section 5.8 rejected it.

- **APP-11 Video decoders (added 2026-10-01).** Videos (`showtime`) plays GStreamer streams, and the
  `gstreamer` packages it pulls in have parsers and demuxers but no H.264, H.265, VP9 or AV1 decoder. Without
  one, common files do not play. `packages/apps.txt` adds `gst-libav` (FFmpeg decoders, already a dependency)
  and `gst-plugin-va` (hardware decoding through VA-API, which Mesa and `intel-media-driver` provide). Both are
  small and start no service (APP-7). VLC in extras gets `vlc-plugin-ffmpeg` for the same reason. An update
  offers the new packages like any new standard app (SW-4).

### 5.8 Clave apps: open-source engines, Clave interface

Some tools are part of the shell, not separate apps: the screenshot toolbar, the Displays settings and the
process monitor. For these, and for the apps in APP-8 and APP-9, stock open-source apps either look like
GNOME apps or break the APP rule.
The rule (decision 2026-09-27): **trusted open-source programs do the work, and Clave draws only the
interface in Quickshell.** Clave's own code is then UI only. It runs no capture code and no display logic,
needs no root, parses no untrusted files, and calls each engine with a fixed argument list, not through
a shell.

- **SHELL-1 Screenshot and screen recording.** A toolbar on Print with capture screen, capture
  window, capture area, record screen, record area, Options (save folder, timer, show mouse pointer,
  floating thumbnail) and Capture. Shift+Print copies the text in an area. After a
  capture, a floating thumbnail in the lower right opens markup on click. The notification is removed.
  - Engines: `grim` (capture), `slurp` (area), `wf-recorder` (recording), `satty` (markup), `tesseract`
    (copy text). All are in the Arch repositories.
  - `wf-recorder` was chosen over `gpu-screen-recorder`, because `gpu-screen-recorder`'s KMS capture needs
    a helper with `cap_sys_admin`. Kooha was rejected: it is a GNOME-style app (APP-3 limit).
  - While recording, the menu bar shows a stop button. Nothing runs when not recording (PERF-3).
  - Removes: `clave-screenshot` (APP-2). The `screenshots.folder` setting is kept.

- **SHELL-2 Displays.** The Displays pane in System Settings stays: it is where this desktop expects the
  settings to be. Its engine changes to Hyprland's own monitor rules.
  - Hyprland applies `desc:` rules (make, model, serial) by itself when a screen is plugged in. So
    per-screen resolution, scale, rotation and position need no Clave script and no daemon. The pane
    keeps its settings in `~/.config/clave/displays.json` (version 2, one entry per screen description)
    and `clave-displays` writes the rules from it to `~/.config/clave/monitors.lua`. `hyprland.lua` loads
    that file right after the user's `monitors.lua`, so the user's file still works and `custom.lua`
    stays the user's own. The rules are applied at once with `hyprctl`.
  - Mirroring: Hyprland's `mirror` monitor option, set from the pane ("Use as: Mirror for …") and from the
    Mirroring button in Control Center. The Super+P menu is removed.
  - Lid closed with a second screen: two switch binds in `clave/binds.lua` run `clave-displays lid
    closed|open`, which turns the built-in panel off and on with `hyprctl`. That is the only glue left.
  - Rejected: `nwg-displays` (a GNOME-style window, and it writes hyprlang, not Lua), `kanshi` (a daemon
    that does what `desc:` rules already do; it also has no mirroring), `wl-mirror` (mirrors into a
    window, not onto a screen).
  - Lost: a separate layout for each set of connected screens. `desc:` rules store one position per screen.
    Check on the dock with the two Dell screens whether this matters in practice.
  - Migration: `clave-displays migrate` converts version 1 of `displays.json` (keyed by connector name)
    to version 2 once, on update. `clave-displays` stays as the pane's engine. Removes: `display-mode.sh`,
    `clave-display.rasi` and the Super+P menu (APP-2).

- **SHELL-3 Activity Monitor.** A Quickshell window, opened from Apps and from Search, with CPU, Memory,
  Disk and Network tabs, a process list, Quit (SIGTERM) and Force Quit (SIGKILL). The Force Quit dialog
  (Super+Alt+Escape) becomes a small mode of the same component.
  - Engines: `ps` and `free` (procps-ng), `ip -s -j link` (iproute2) and `/proc/diskstats`. All come
    with Arch `base`.
  - Refreshes every 2 seconds only while the window is open. Nothing runs when it is closed (PERF-3).
  - Only the user's own processes can be quit. There is no root helper.
  - No Energy tab: Linux has no per-app power figure without root.
  - Rejected: Mission Center and GNOME System Monitor. They are GNOME-style windows (APP-3 limit).

Answers to the section 3 questions for SHELL-1 to SHELL-3: each one improves the experience; none needs a
service or a listener while it is closed; the attack surface gets smaller, because display logic and
capture now run in upstream programs; resources are used only while open; everything is local.

## 6. Features

| ID | Feature | Required or optional | Default | Setting |
|---|---|---|---|---|
| FEAT-1 | Space numbers in the menu bar (the pane indicator from stock Hyprland) | Optional | Off | Desktop & Dock > Spaces (done) |
| FEAT-4 | Login screen background and profile picture | Required | Current look | Lock Screen > Login Window (done) |
| FEAT-5 | Traffic lights on or off for all windows | Optional | On | Desktop & Dock > Windows > Show title bar buttons (done) |
| FEAT-6 | Replaceable logo (BR-2, BR-10) | Required | Clave keystone | `docs/assets/brand/clave.svg` now, a picker later |
| FEAT-7 | Modifier key glyph (BR-5) | Required | ⌘ | Keyboard > Super key symbol (done) |
| FEAT-8 | Editing shortcuts on Super (Super+C, X, V, Z, Shift+Z) sent to the app as Ctrl shortcuts | Optional | Off | Keyboard > Editing shortcuts on the Super key (done) |
| FEAT-9 | Calculator in Search, fully local (OFF-1): no exchange-rate downloads | Required | On | Search > Calculator, Ctrl+Tab (done) |
| FEAT-10 | Network Identity: look like Windows 11, macOS, iPhone, Android or Linux on the network, plus Stealth (SEC-7) | Optional | Off | Privacy & Security > Network Identity; Wi-Fi menu; Control Center |

Notes on the features:

- **FEAT-1.** The numbers come from Quickshell's Hyprland events, with no polling. While the setting is off,
  nothing is created. Click a number to go to that Space.
- **FEAT-4.** SDDM runs as its own user, so settings must be copied to a place SDDM can read. The copy
  happens when the user saves the setting, through the existing polkit helper `clave-admin`. No new service.
  `clave-prefs` converts the picture to PNG as the user and passes the bytes on stdin. Root checks the size
  and the PNG signature and copies them to a fixed place. It never opens a path the user chose and never
  decodes the image. The background is kept in `/var/lib/clave`, so reinstalling keeps it.
- **FEAT-8.** Super+A stays Apps and Super+F full screen. When the setting is on, Super+V pastes and clipboard
  history moves to Super+Shift+V. Terminals get Ctrl+Shift+C and Ctrl+Shift+V, and nothing for cut and undo,
  because Ctrl+C and Ctrl+Z stop programs there. The bindings exist only while the setting is on.
- **FEAT-9.** `rofi-calc` (libqalculate) is a second mode in Search, one Ctrl+Tab away. It cannot show results
  inside the app list (rofi's combined mode drops them). `clave-qalc` runs qalc with exchange-rate updates
  off, so conversions use only rates already on disk. Enter copies the result. History is not kept.
- **FEAT-7.** The choices are ⌘ and ❖. The Windows logo is a Microsoft trademark, so it is not offered.
- **FEAT-10.** The section has the profile choice, the Stealth switch and a row that opens a local help page
  (`~/.local/share/clave/docs/network-identity.html`, opened with `xdg-open`, no network): what each setting
  changes, the files it writes, where the code is, its limits and how to check it. That row names a limit only
  when one applies on this computer (no patched dhcpcd, or the SYN rewriter failed its self-test).
  A section in Privacy & Security, not its own pane: it is a privacy setting, and the pane already
  holds the firewall-adjacent settings. The Wi-Fi menu in the menu bar lists the profiles with a check mark.
  Control Center has a row: the circle turns Stealth on and off, the text shows the profile and opens the
  pane. Changing the profile reconnects Wi-Fi once, so the next DHCP request carries the new identity.
- **FEAT-5.** The setting already exists and is on by default. When it is off, the hyprbars plugin is
  unloaded. Separately, a fixed list in `plugins.lua` (`no-bar-csd` rule) hides the bar for apps that draw
  their own. See ISSUE-1.

## 7. Personal build

One repo. The public build is neutral. `./install.sh --personal` is the personal option (BR-10). It changes
assets only: logo, fonts, cursor and sounds. Wording is the same in every build, which keeps the code
simple. The user supplies all files that the project cannot ship.

## 8. Known issues and investigations

- **ISSUE-1 Two sets of window controls.** Some apps draw their own title bar and buttons, for example
  VS Code and Bazaar. hyprbars then adds a second set. Do not remove traffic lights for all apps.
  Next steps:
  1. Find a general way to tell that a window draws its own decorations (xdg-decoration protocol state,
     or the client-side decoration hint) and skip hyprbars for it.
  2. For apps that can use a system title bar, prefer that. VS Code has `window.titleBarStyle`.
  3. If no general fix works, keep the list and consider making it editable in System Settings.

  Outcome: Hyprland does not expose whether a window draws its own decorations. The xdg-decoration state is
  private to Hyprland, and GTK4 apps never use that protocol. Reading it would need a hook into Hyprland
  internals that breaks with Hyprland updates, which fails section 3. So the list stays. VS Code and Bazaar
  are added to it, and users add more in System Settings > Desktop & Dock > Windows. The list is saved in
  `settings.json` (`windows.noBarApps`). VS Code users who prefer the system title bar can set
  `window.titleBarStyle` to `native` and remove `code` from the list.
- **ISSUE-2 VS Code asks for weaker encryption.** Cause found: `~/.vscode/argv.json` contained
  `"password-store": "basic"`, which forces the weak store. GNOME Keyring already unlocks at login through
  PAM. Fix: set `"password-store": "gnome-libsecret"`. The Flatpak build of VS Code also needs access to
  `org.freedesktop.secrets`. VS Code is not shipped by Clave, so this is documented in the README.
- **ISSUE-3 Terminal logo stays on screen.** fastfetch drew the logo with the kitty graphics protocol. After
  leaving a full-screen program such as Claude Code, the image could stay drawn over the text. Fixed: the logo
  is now text (`home/.config/fastfetch/assets/clave.txt`), which works in every terminal and is cleared with
  the screen. `extra/fastfetch.bash` is no longer needed and is removed.
- **ISSUE-5 Lock screen clock format.** `hyprlock.conf` printed `%-I:%M` whatever the locale or the menu bar's
  24-hour setting. Fixed: `clave-lock-clock` reads the setting, or the locale when it is not set. It runs only
  while the screen is locked, in place of the `date` call that ran there before.
- **ISSUE-4 Login screen button spacing.** The Sleep, Restart and Shut Down buttons were not evenly
  spaced, because each button column was as wide as its label. Each column now has the same width.
- **ISSUE-6 The screen never locked when idle (v1.1.2).** `hypridle.conf` belongs to the user, so updates do
  not replace it, and the rename did not change the old command names in it. Installs from before the rename
  kept `lock_cmd = macos-power -l`, a program that no longer exists. The Lock Screen timeouts had no effect,
  and the computer went to sleep without locking. Fixed: the update changes the old names in `hypridle.conf`
  and `monitors.lua` too and starts hypridle again. `clave-idle set` and `clave-idle repair` put the lock
  command back when it is wrong. The shipped file calls `~/.local/bin/clave-power`, so `PATH` does not matter.
  `clave-doctor` checks that the screen locks when idle.
- **ISSUE-7 The display could turn off before the lock (v1.1.2).** A dark screen hid an unlocked session.
  Fixed: `clave-idle` raises the display timeout to the lock timeout when it is shorter, and the pane shows
  the saved value.
- **ISSUE-10 Search found pane titles only (v1.1.2).** Searching for a setting such as "24-hour" or "tap to
  click" found nothing. Fixed: the search looks at section titles, row labels and descriptions, short choice
  lists and keywords for each pane. Up to three matching rows show under each pane. Clicking one opens the
  pane, scrolls to the row and highlights it. Enter opens the first result, and Esc clears the search.
  `qs ipc call settings search TEXT` opens the window with a search, and `… find TEXT` prints the results.

- **ISSUE-8 Alt+Shift did not switch keyboard layouts (v1.1.2).** `input.lua` set no `grp:` option, so
  with two layouts (for example U.S. + Spanish) there was no way to switch. Fixed: with two layouts,
  `input.lua` adds `grp:alt_shift_toggle` to the Caps Lock option.
- **ISSUE-9 Settings changed through IPC did not apply (v1.1.2).** `qs ipc call settings set` reloaded
  Hyprland only for the trackpad, and appearance changes did not reach GTK and Qt apps. Fixed: every group
  that the Hyprland config reads reloads Hyprland, and `appearance mode` and `appearance accent` go through
  `clave-prefs` as the window does.

APP-10 (helper launchers hidden from Apps) and the SW-5 package audit are built for v1.1.2. v1.1.2 is
tagged without the check of every pane on the live machine and in the desktop VM; that check moves to the
next release.

## 9. Competitive research

Study similar projects and record what is worth adopting. Start with:

- [pearOS Arch Linux](https://github.com/pearOS-archlinux/iso)
- [gnomintosh](https://github.com/jothi-prasath/gnomintosh)

Add other similar Linux desktop projects with at least 200 GitHub stars. For each one, fill in this table:

| Project | Features | Visual approach | Architecture | Customization | Security | Bundled apps | Quality of life | We do better | We lack |
|---|---|---|---|---|---|---|---|---|---|
| [pearOS](https://github.com/pearOS-archlinux/iso) (361★) | Full distribution: ISO, installer (Calamares), own bootloader, settings app, theme switcher, sound scheme, own browser | KDE Plasma with themes and a blur effect | Arch base, built as an ISO with its own package repository | Light/dark switcher | No hardening layer described | Many, including its own browser | Rolling updates keep the branding | Works on an existing Arch install; hardened by default; one small repo | An installable ISO |
| [Gnomintosh](https://github.com/jothi-prasath/gnomintosh) (286★) | Theme, icons, cursor, wallpapers, fonts, dconf settings | GNOME with Dash to Dock and other extensions | Shell script that applies themes and dconf keys | Through GNOME Tweaks and extensions | None | None | One script; last updated 2024 | Tiling; own shell, menu bar and settings; uninstall | Works on GNOME, which many users already run |
| [GNOME-macOS-Tahoe](https://github.com/kayozxo/GNOME-macOS-Tahoe) (1107★) | GTK3/GTK4/Shell theme, 16 accent colors, libadwaita override, GDM theme | GNOME theme plus recommended extensions | Theme generator and interactive installer (gum) | Accent colors, light/dark | None | None | Interactive installer menu | A whole desktop, not a theme; accent follows one setting everywhere | 16 accents (we have 8) |
| [eqSh](https://github.com/eq-desktop/eqsh) (263★) | Quickshell shell for Hyprland: panel, notch, launcher, notifications, lock screen, OSDs, control center, dock, widgets, screenshots, AI chatbot, settings app | Own shell drawn in Quickshell | Quickshell config plus a CLI (`au`) | JSON settings and a settings app | Not described | None | curl installer | Dock magnification, genie minimize, app menus, window title bars; hardening; offline by default | Desktop widgets, notch |
| [KOS / NextKde](https://github.com/SuceV587/NextKde) (245★) | Quickshell shell on KDE Plasma: top bar, dock, launcher, search, notifications, settings, KWin effects, window decoration, optional lock screen | Quickshell over Plasma, KWin effects | Quickshell plus a C++ platform service and KWin plugins | Settings app | Not described | None | `kosctl` installs and removes parts | No extra platform service; lighter than Plasma | Desktop files; a global search with more sources |

Decisions:

- **Adopt as requirements:** a local calculator in Search (FEAT-9; most launchers above have one). Optional
  editing shortcuts on the Super key, since users of this layout expect Super+C and Super+V (FEAT-8; the
  `gnome-macos-remap` scripts, 542★, show the demand).
- **Reject:** an ISO (out of scope: Clave installs on Arch), desktop widgets and a notch (only visual, section
  3), an AI chatbot (network, SEC-3), an interactive installer menu (the flags and `--dry-run` already cover it
  without a new dependency), more accent colors (eight cover the common choices), a platform service like
  KOS's (PERF-1).
- **Already tabled:** desktop files (section 13).

## 10. Quality-of-life review

Walk through each area as a new user and write down every point of friction:

- first run and install
- login
- window management
- desktop interaction
- System Settings
- app behavior
- customization
- authentication and the keyring
- system sounds
- visual consistency

Each finding becomes an issue with a requirement ID, or a new requirement in this plan.

Findings from updating a live machine on 2026-09-27:

| Area | Finding | Outcome |
|---|---|---|
| First run | A package already installed was upgraded alone and failed (partial upgrade), after the migration had started | Fixed: only missing packages, packages first |
| First run | Old system files were left because early installs kept no record; the cleanup then stopped on a missing backup | Fixed: cleanup by name, error fixed |
| First run | The wallpaper setting still pointed at the old folder | Fixed: paths in `~/.config/clave` are rewritten |
| First run | GTK font and cursor stayed old until the next login | Fixed: the installer applies them in a running session |
| First run | The Firefox theme was skipped with a wrong reason ("start Firefox once") while Firefox was open | Fixed: says to close Firefox |
| First run | Hyprland plugins do not load on a config reload after their folder moved | Accepted: they load at the next login, which the installer asks for |
| Login | Login screen, profile picture and background work. `~/.face` was missing | Set through Lock Screen > Login Window (FEAT-4) |
| Authentication | VS Code used the weak password store (ISSUE-2) | Fixed on the test machine; documented in the README |
| System Settings | The `search` settings (calculator, files, web) were read by nothing | Removed |
| Search | No calculator | FEAT-9 (done) |
| Lock screen | The clock is always 12-hour, while the menu bar follows the locale and the 24-hour setting | ISSUE-5 (fixed) |
| Window management | No Super+C / Super+V for copy and paste | FEAT-8 (done, optional) |
| Sounds, visual consistency, customization | No new friction found | — |

## 11. Roadmap

Each phase ends when its exit criteria are met.

| Phase | Work | Exit criteria |
|---|---|---|
| 0 | This plan. One issue per requirement. | Plan merged. Issues open. |
| 1 | Small fixes: ISSUE-4, OFF-1, ISSUE-3, ISSUE-2 | Each fix tested on a live install. |
| 2 | Rename and assets: BR-1 to BR-4, BR-6 to BR-10 | The trademark check (section 12) passes. The migration test passes. |
| 3 | Settings: FEAT-4, FEAT-1, FEAT-7 (BR-5), ISSUE-1 | Each setting works and costs nothing when off. |
| 4 | Release model: SEC-1, SEC-2, SW-3, PERF-2 | Hardened install round trip passes. Inventory matches the system. |
| 5 | Sections 9 and 10 | Findings added to this plan as requirements or rejected with a reason. (done) |
| 6 | Standard apps and shell tools (v1.1.0): see the steps below | All APP and SHELL requirements met on the clean VM. Inventory updated (APP-7). BR-11 review recorded. (built; waiting on the dock check and the BR-11 review) |
| 7 | Disk encryption (SEC-5) | Status and warnings work. The VM tests pass for every supported boot loader, including the interrupted run. RECOVERY.md and ENCRYPTION.md are written. (done in the VM: `tests/vm-encrypt.py` passes for GRUB, systemd-boot, Limine and the interrupted run) |
| 8 | Upstream compatibility (COMP-5 to COMP-9): see the steps below | A test change to a watched package opens an `upstream-break` issue. `clave-doctor` shows all three results on the live machine and the clean VM. Actions use stays under 300 minutes a month. (steps 1 to 5 built; the issue check waits for the merge to main) |
| 9 | Network Identity (SEC-7, FEAT-10) | `tests/netid-unit.sh` passes in CI. On the laptop, each profile passes the wire check, and `reset` restores the files. |

Phase 4 must finish before the public release. Phase 6 comes after v1.0.0, so it does not block that release.
Phase 7 is security work and does not depend on phase 6: start it first. The status check and the warnings
(the first two items of SEC-5) can ship in a v1.0.x update before the setup tool.

Phase 6 steps, in order:

1. **Checks before building.** On the clean VM: `desc:` monitor rules on hotplug with the dock (SHELL-2);
   `wf-recorder` on Hyprland with the portal and without it (SHELL-1); that geoclue stops after use and
   makes no network calls (APP-7); that Hardinfo2 and Seahorse make no network calls unless asked (APP-1);
   a round trip of a real `.ics` and `.vcf` export through the Python libraries (APP-8); how much of each GTK4 app `gtk.css` can
   reach (APP-3). Write each result in this plan. If a check fails, change the requirement first.

   Results on 2026-09-27 (desktop test VM `tests/vm-desktop.py`, Hyprland with software rendering,
   one QEMU screen):
   - `wf-recorder` without the portal: records the screen on Hyprland (screencopy). With the portal:
     not checked; SHELL-1 does not use it.
   - geoclue: started when Clock opened (D-Bus activation) and stopped by itself after 60 seconds unused.
     All its sources are off in `90-clave.conf`, so it has nothing to look up online.
   - Hardinfo2 and Seahorse: no network connection after opening (only the test's SSH sessions in
     `ss`). Hardinfo2's Synchronize button connects only when pressed.
   - `.ics` and `.vcf`: `tests/pim-test.sh` passes with the Arch packages (python-icalendar 7.3.0,
     python-vobject 0.9.9, python-dateutil 2.9.0), including an export with time zones, RRULE, EXDATE
     and an overridden repeat.
   - GTK4 (`gtk-4.0/clave.css`): Clock shows one set of traffic lights on the left. The dimmer yellow
     button needs a look on real hardware.
   - Names and defaults: all 22 "Shown as" names from APP-1 appear, and the MIME defaults of APP-5 are
     set. `org.gnome.*` in the built-in no-bar list already covers Scanner, Keychain and Photos;
     Hardinfo2 has no title bar of its own and keeps Clave's.
   - Not possible in a VM: `desc:` rules on dock hotplug and the lid (SHELL-2). They are on the release
     checklist, on the real laptop with the two Dell screens.
   - Found and fixed in this check: Activity Monitor's column header took half the table; process
     names were cut at 15 characters; Calendar was taller than an 800-pixel screen; Contacts showed an
     empty card at start; System Settings waited forever for `bluetoothctl` without Bluetooth, and
     so never showed the Disk Encryption status; `clave-sound` without an audio output made swaync
     report every notification as a failed script.
2. **Packages.** Create `packages/apps.txt` (APP-1). Move Disks, Snapshot and Passwords and Keys from
   extras. Remove `htop`. Add the geoclue config (APP-6) to `system/desktop`.
3. **Theme and names.** Extend `gtk-4.0/gtk.css` (APP-3), the `.desktop` name overrides and the `icons`
   setting (APP-4), MIME defaults (APP-5), and `windows.noBarApps` entries.
4. **Clave apps.** SHELL-3 first (smallest), then SHELL-1, then SHELL-2 (needs the migration), then
   Notes (APP-9), then Calendar and Contacts (APP-8).
5. **Migration and cleanup.** Remove the replaced files on update (APP-2) and convert `displays.json`.
   Extend `tests/migrate-test.sh`.
6. **Docs.** README feature list, CHANGELOG, PERF-2, BR-11 review.

Phase 8 does not depend on phases 6 and 7. Steps 1 to 3 can ship in a v1.0.x update. Steps, in order:

1. **Watch.** `.github/ci/watched.txt`, the `ci-state` branch and `upstream.yml`. Make `ci.yml` reusable and
   remove its weekly schedule (COMP-5).
2. **Issue.** The issue step with `gh`, `GITHUB_TOKEN` and `issues: write` (COMP-6).
3. **Compatibility file.** `compat.json` and its format. The installer copies it to `/usr/share/clave/`
   (COMP-7).
4. **Doctor.** The local checks, then `--fetch`, then the call at the end of `clave-update` (COMP-8).
5. **Hook.** The pacman hook and the notification at the next login (COMP-9).
6. **Trial, not a requirement yet.** A headless Hyprland and Quickshell start, and a screenshot compared
   with saved baselines, on GitHub's runners. They have no GPU, so try `LIBGL_ALWAYS_SOFTWARE=1`. If it
   is reliable, add it as COMP-10. If not, run it in the VM before each release.

Progress on 2026-09-27 (branch `v1.1.1`), steps 1 to 5 built; details in `docs/UPSTREAM.md`:
- Steps 1 and 2: `.github/ci/watched.txt`, `.github/ci/upstream.sh` and `upstream.yml`; `ci.yml` is reusable and has no weekly
  schedule. Scheduled workflows run only on the default branch, so the first real run, and the check that a watched
  change opens an issue, can only happen after the merge.
- Step 3: `compat.json`, with the versions of the live machine and the desktop VM as tested for 1.1.1.
- Step 4: `clave-doctor` runs as planned. It showed OK for every watched package on the live machine and in the
  desktop VM. `tests/compat-test.sh` covers Untested, Update Clave and `--fetch` with SSH-signed tags.
- Step 5: the hook runs `clave-compat --hook`, a root-owned copy in `/usr/local/lib/clave/`. The flag file belongs
  to root, so the shell does not delete it: it keeps a copy in `~/.local/state/clave/` and shows each notice once.
  Only Update Clave and known breaks lead to the login notice; Untested is a warning in pacman's output only,
  or every Hyprland update would bring a notification. `install.sh --update` does not run the system part, so it
  refreshes these copies with `sudo scripts/system.sh compat` when a release changed them. Checked in the desktop
  VM: a reinstall of `grim` ran the hook, and a simulated known break printed the warning and showed the notice.
- Step 6: tried in the desktop VM. A second Hyprland started with `AQ_BACKENDS=headless` from SSH exited without a
  log. Not reliable yet, so the look is checked in the VM before each release (`tests/vm-desktop.py shot`).

Cost: the repo is private, and GitHub Pro includes 3,000 Actions minutes a month. The daily version check
takes about 2 minutes, about 60 minutes a month. The full suite runs only when a watched package changes:
about 10 runs of 10 minutes, about 100 minutes a month. Public repos use standard runners for free.

## 12. Release criteria for v1.0.0

- No Apple names or assets in the repo or in a default install. `scripts/name-check.sh` passes (section 5.1).
- CI passes: the name check, shellcheck, Lua and QML syntax, `Hyprland --verify-config`,
  `tests/install-test.sh` and `tests/migrate-test.sh`.
- A hardened install and uninstall round trip passes on a clean Arch system.
- An update from an old `macos-look` install to Clave keeps the user's settings.
- The background inventory (PERF-2) matches what runs on a fresh install.
- The desktop works offline, including the calculator.
- README, CHANGELOG and this plan are up to date.

Status on 2026-09-27, after phases 0 to 5:

| Criterion | Status |
|---|---|
| No Apple names or assets | Passes (`scripts/name-check.sh`) |
| CI checks | Pass on GitHub Actions |
| Hardened install and uninstall on a clean Arch system | Passes on a clean Arch VM (`tests/vm-check.sh`): no failed units after the install or after `uninstall.sh --system`, and the uninstall restores PAM, the boot menu flags and the themes. The first run found that the uninstall deleted `/etc/pam.d/system-auth` and left the kernel flags in GRUB; both are fixed |
| Update from `macos-look` keeps settings | Passes (`tests/migrate-test.sh`, and the live machine) |
| Inventory matches a fresh install | Passes on the live machine and the clean VM (PERF-2) |
| Works offline, including the calculator | Calculator app and Search calculator make no downloads (OFF-1, FEAT-9). Online features are off by default (SEC-3) |
| README, CHANGELOG, plan | Up to date |

v1.0.0 was published on 2026-09-27: signed tag, CI green, clean-VM round trip passed.

## 13. Tabled

These ideas are on hold. They are not part of v1.0.0.

- Files and icons on the desktop, and drag-to-select with a selection rectangle.
- A sound audit: which events need sounds, and a custom, freely licensed sound set.
- A picker in System Settings for the logo, with size and format checks.

## 14. Open questions

Resolved on 2026-09-27:

- **Mail.** Geary is in `--extras` only, not in the default install. The installer turns its
  `run-in-background` setting off, so it keeps no process for new-mail notices (PERF-1).
- **Dictionary.** `gnome-dictionary` is in `--extras` only. It looks words up online when asked and does
  nothing in the background.
- **One password or two with Disk Encryption.** Keep both prompts: the disk passphrase at boot, then the
  login password, which unlocks GNOME Keyring (SEC-4). No automatic login.

Still open:

- **Per-set display layouts.** Does losing them (SHELL-2) matter? Check on the dock with the two Dell
  screens; it is on the release checklist for the next tag.

Resolved on 2026-10-01:

- **Terminal name.** kitty shows as "Terminal" through an APP-4 override (`APP_NAMES` in `clave-prefs`).

## Appendix: source notes

Every item in `Notes.md` maps to this plan:

| Notes.md | Plan |
|---|---|
| 1 Branding, command key symbol | BR-1 to BR-10, FEAT-6, FEAT-7, section 7 |
| 2 Calculator | OFF-1 |
| 3 Login screen | ISSUE-4, FEAT-4 |
| 4 Pane indicator | FEAT-1 |
| 5 Background processes | PERF-1 to PERF-3 |
| 6 VS Code authentication | SEC-4, ISSUE-2 |
| 7 Formal project plan | This document |
| 8 Traffic lights | FEAT-5, ISSUE-1 |
| 9 System sounds | BR-8, section 13 |
| 10 Included software | SW-1 to SW-3, SEC-1 |
| 11 Similar projects | Section 9 |
| 12 Quality of life | Section 10 |
| 13 Desktop files | Section 13 |
| 14 Drag-to-select | Section 13 |
| 15 Login screen work | FEAT-4, ISSUE-4 |
| 16 Architecture principle | Section 3 |
| Terminal logo bug | ISSUE-3 |
| 17 Upstream compatibility | COMP-5 to COMP-9, phase 8 |
