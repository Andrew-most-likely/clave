# arch-macos-hyprland

A macOS Sonoma look for [ML4W](https://github.com/mylinuxforwork/dotfiles) Hyprland on Arch Linux, with
tiling kept. The pack also adds everyday desktop services and an optional security hardening layer.

It is an overlay: install ML4W dotfiles first (Lua config, tested with ML4W 2.12.3), then run `./install.sh`.

## What you get

**macOS look**
- Quickshell menu bar with Apple menu, Control Center and Notification Center
- Dock with running indicators and a genie minimize animation. The animation uses GLSL shaders
  and a small Hyprland plugin, `hypr-minimize`.
- Traffic-light window buttons from `hyprbars`, built from source for your Hyprland version
- Mission Control and hot corners. Top left opens Mission Control, top right opens Notification Center, and
  bottom left opens Launchpad.
- A System Settings app (`qs ipc call settings open [pane]`) for the clock, battery, hot corners, dock, trackpad,
  sounds and lock screen
- Force Quit (Super+Alt+Esc), About/Help windows for apps, and Quick Look through `sushi`
- Spotlight and Launchpad built with rofi, a macOS theme for swaync, and a macOS layout for hyprlock
- macOS trackpad gestures:
  - 3 fingers left/right: switch Spaces
  - 3 fingers up/down: Mission Control
  - 4-finger pinch in: Launchpad
  - 4-finger pinch out: fullscreen
- WhiteSur GTK, icons, Kvantum and Firefox theme, the macOS cursor, and SF Pro and SF Mono fonts. Qt5, Qt6,
  GTK4 and Flatpak apps all follow the theme.
- A custom Plymouth boot splash (Apple logo and progress bar), an SDDM login screen, and a synthesized startup chime
- A fastfetch config that shows the Apple logo

**Desktop essentials**: GNOME Keyring, printing (CUPS and mDNS discovery), exFAT and NTFS support, common GNOME
utilities, CJK and emoji fonts, a journald size cap, weekly cache cleanup for `$HOME`, and `paccache`.

**Hardening** (optional, `--harden`)
- The `linux-hardened` kernel, with extra flags for lockdown, IOMMU and init_on_free
- sysctl lockdown and blacklisted kernel modules
- AppArmor (profiles from `apparmor.d`) and auditd watch rules
- An nftables firewall that drops all inbound traffic by default, plus OpenSnitch for outbound traffic
- USBGuard
- A faillock policy and a stricter sudo configuration
- Login `umask 027`, `su` limited to group `wheel`, and core dumps turned off
- A `noexec` `/tmp` and Wi-Fi MAC randomization while scanning
- An AIDE baseline that refreshes after each pacman transaction
- Daily `arch-audit` CVE checks and a pacman hook that removes SUID bits the system does not need

## Install

```sh
git clone https://github.com/<you>/arch-macos-hyprland
cd arch-macos-hyprland
./install.sh --dry-run      # preview
./install.sh                # macOS look + desktop essentials
./install.sh --harden       # also the hardening layer (asks for confirmation)
```

Options: `--extras` (the other apps from the original machine), `--user-only` (no sudo), `--no-packages`.

Each file that the installer replaces is kept as `<file>.bak-<date>`. To undo the changes in `$HOME`, run
`./uninstall.sh`. Add `--system` to also undo the root-level changes.

### Not included, on purpose

- **Apple fonts, cursor and icons** come from the AUR (`apple-fonts`, `apple_cursor`, `whitesur-icon-theme`).
  **Wallpapers and the GTK/Firefox theme** are downloaded from the WhiteSur repos at install time.
- **macOS system sounds** belong to Apple and are not downloaded. Copy the `.aiff` files from
  `/System/Library/Sounds` on a Mac into `~/.local/share/sounds/macOS/source/`, then run `macos-sounds-build`.
- **Hardened `/etc/fstab` options** (`hidepid`, `noexec` on `/dev/shm` and `/var/tmp`) must be merged by hand.
  See `extra/fstab-hardening.txt`.
- Host-specific settings are left out: the monitor layout, VPN and VM definitions, USBGuard device rules (the
  installer generates these from the devices plugged in during install), and the root partition UUID.

## Things to know

- **Hyprland updates:** plugins only load into the exact Hyprland version they were built against. A pacman
  hook (`macos-look-plugins.hook`) runs `~/.local/share/macos-look/rebuild-plugins.sh` after each Hyprland
  upgrade. If a plugin still fails to load at login, `custom.lua` starts a rebuild.
- **Your overrides** belong in `~/.config/hypr/custom.lua`, which loads last. Gestures are in `gestures.lua`
  because Hyprland keeps the first gesture defined for each finger count.
- The pack overwrites a few ML4W files: `hypr/conf/autostart.lua`, `ml4w.lua`, several `hypr/scripts`,
  `quickshell/shell.qml`, `DockApp`, `StatusbarApp/UpdatesModule.qml`, and the waybar modules. If you update
  ML4W, re-run `./install.sh --no-packages`.
- **SDDM reads every file in `/etc/sddm.conf.d`, including backups.** The installer moves `*.bak*` files to
  `/etc/sddm.conf.d.backup`.
- **Hardening risks:** USBGuard blocks USB devices that were not plugged in during install. Three wrong
  passwords lock the account for 15 minutes. Keep a recovery USB.

## Keeping the repo current

After you change something on the machine this pack came from, run:

```sh
./scripts/capture.sh   # copy live files listed in manifest-*.txt back into home/ and system/
git diff
```

`capture.sh` replaces your home path and user name with placeholders. `install.sh` fills them back in.

## Layout

```
install.sh / uninstall.sh
manifest-home.txt       files under $HOME in the pack
manifest-system.txt     root files in the pack, tagged look | desktop | harden
home/                   captured $HOME files
system/<group>/         captured root files
packages/*.txt          pacman / AUR / flatpak lists per group
extra/                  Firefox prefs, kernel flags, fstab example
scripts/system.sh       root half of the installer
scripts/fetch-themes.sh WhiteSur GTK/Firefox/wallpapers
scripts/capture.sh      refresh the repo from a live system
```

## Credits

WhiteSur themes by [vinceliuice](https://github.com/vinceliuice). `hyprbars` comes from
[hyprwm/hyprland-plugins](https://github.com/hyprwm/hyprland-plugins) (BSD-3-Clause) and is downloaded at build
time. ML4W dotfiles are by [mylinuxforwork](https://github.com/mylinuxforwork/dotfiles). Apple, macOS and
San Francisco are trademarks of Apple Inc. This project is not affiliated with Apple.
