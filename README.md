# arch-macos-hyprland

A macOS Sonoma desktop for [Hyprland](https://hypr.land) on Arch Linux, with tiling kept. It has a menu bar,
a Dock with the genie effect, Mission Control, Control Center, System Settings and traffic-light title bars.
Everything is built with [Quickshell](https://quickshell.org) and Hyprland's Lua config. It is standalone: it
needs no other dotfiles pack.

<!-- Screenshots: assets/screenshots/ -->

[![CI](https://github.com/Andrew-most-likely/arch-macos-hyprland/actions/workflows/ci.yml/badge.svg)](https://github.com/Andrew-most-likely/arch-macos-hyprland/actions/workflows/ci.yml)
![Hyprland 0.55+](https://img.shields.io/badge/Hyprland-0.55%2B-58e1ff)
![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)

## Install

On Arch Linux (or an Arch-based distribution), as your normal user:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/Andrew-most-likely/arch-macos-hyprland/main/setup.sh)
```

The script clones the latest release to `~/.local/share/arch-macos-hyprland` and runs `install.sh`. The installer
shows a summary and asks before it changes anything. [Read `setup.sh`](setup.sh) first if you like. It is 40 lines.

You can also install by hand:

```sh
git clone https://github.com/Andrew-most-likely/arch-macos-hyprland ~/.local/share/arch-macos-hyprland
cd ~/.local/share/arch-macos-hyprland
./install.sh --dry-run   # preview
./install.sh
```

Then log out, and pick Hyprland on the login screen.

| Option | What it does |
|---|---|
| `--yes` | No questions. The hardening layer stays off. |
| `--harden` | Also install the security hardening layer (asks again first) |
| `--extras` | Also install the optional apps in `packages/extras*.txt` |
| `--user-only` | Only install files in `$HOME`. No sudo, no login screen or boot splash. |
| `--no-packages` | Skip pacman, AUR and Flatpak |
| `--dry-run` | Show what would happen and change nothing |

**Coming from ML4W or another setup?** The installer moves `~/.config/hypr` and `~/.config/quickshell` to
`<dir>.bak-<date>`. It turns config directories that were links into `~/.mydotfiles` into real copies, so it never
writes into another project's files. It keeps your `monitors.lua`, wallpapers, current wallpaper and pinned Dock
apps. `./uninstall.sh` puts everything back.

## What you get

**Desktop**
- Menu bar with the Apple menu, the app menu, battery, Wi-Fi, sound and the clock. There is one menu bar per screen.
- Control Center (Wi-Fi, Bluetooth, Focus, brightness, volume, Night Shift, media) and Notification Center
- Dock with magnification, running indicators, pinning, and the genie minimize animation. The animation uses
  GLSL shaders and a small Hyprland plugin, `hypr-minimize`.
- Traffic-light title bars from `hyprbars`, built from source for your Hyprland version
- Mission Control, hot corners, Spotlight, Launchpad and Force Quit
- System Settings (`Super+,`) with panes for Wi-Fi & Bluetooth, Displays, Sound, Battery, Appearance (light or
  dark, text size), Desktop & Dock, Wallpaper, Control Center, Notifications, Lock Screen, Login Items,
  Printers & Scanners, Date & Time, Trackpad, Mouse, Keyboard, and Privacy & Security
- macOS screenshots: `Shift+Super+3/4/5` save the image to `~/Pictures/Screenshots` and copy it to the clipboard.
  Click the notification to mark up the image.
- Clipboard history (`Super+V`), emoji picker (`Ctrl+Super+Space`), Night Shift, and a keyboard shortcut list
  (`Super+/`)
- A lock screen and idle timeouts, an SDDM login screen, a Plymouth boot splash, and a startup chime

**Trackpad:** swipe left or right with 3 fingers to switch Spaces. Swipe up for Mission Control. Pinch with 4
fingers for Launchpad, and spread 4 fingers for full screen.

**Theme:** WhiteSur GTK, icons, Kvantum and Firefox themes, the macOS cursor, and SF Pro and SF Mono. Qt5, Qt6,
GTK4/libadwaita and Flatpak apps all follow the theme.

**Desktop essentials:** GNOME Keyring, printing (CUPS and mDNS discovery), Bluetooth, exFAT and NTFS support,
common GNOME apps, CJK and emoji fonts, zram, a journald size cap, and weekly cache cleanup.

**Hardening** (optional, `--harden`)
- The `linux-hardened` kernel with lockdown, IOMMU and init_on_free flags
- sysctl lockdown, AppArmor (`apparmor.d`) and auditd
- An nftables firewall that drops all inbound traffic by default, with OpenSnitch for outbound traffic
- USBGuard, faillock, a stricter sudo configuration, `umask 027` at login, and a `noexec` `/tmp`
- An AIDE baseline and daily `arch-audit` CVE checks

## Keyboard shortcuts

`Super` is the Command key. Press `Super+/` to see all of them.

| Keys | Action | Keys | Action |
|---|---|---|---|
| `Super+Space` or tap `Super` | Spotlight | `Super+Q` | Close window |
| `Super+A` | Launchpad | `Super+H` | Minimize to the Dock |
| `Super+Tab` | Mission Control | `Super+F` / `Super+M` | Full screen / Zoom |
| `Alt+Tab` | Switch windows | `Super+T` | Float or tile the window |
| `Super+Return` | Terminal (kitty) | `Super+1…0` | Go to a Space |
| `Super+E` | Files | `Super+Shift+1…0` | Move the window to a Space |
| `Super+B` | Web browser | `Super+Arrows` | Move focus |
| `Super+,` | System Settings | `Super+Alt+Arrows` | Swap windows |
| `Super+N` | Notification Center | `Super+Shift+Arrows` | Resize the window |
| `Super+Ctrl+N` | Control Center | `Super+S` | Scratchpad |
| `Super+V` | Clipboard history | `Shift+Super+3/4/5` | Screenshot: screen / area / window |
| `Ctrl+Super+Space` | Emoji & Symbols | `Shift+Super+6` | Copy text from the screen (OCR) |
| `Super+L` | Lock screen | `Super+Alt+Esc` | Force Quit |
| `Super+P` | Display mode | `Super+Alt+G` | Game mode (turns effects off) |

## Customize

The installer never replaces files you own:

| File | For |
|---|---|
| `~/.config/hypr/custom.lua` | Any Hyprland setting, shortcut or autostart. It loads last, so it wins. |
| `~/.config/hypr/monitors.lua` | Screens. `nwg-displays` and System Settings can write this file. |
| `~/.config/hypr/hypridle.conf` | Idle timeouts. System Settings > Lock Screen edits this file. |
| `~/.config/kitty/custom.conf` | Terminal settings |
| `~/.config/macos-look/` | Everything System Settings saves, including Dock pins and the current wallpaper |

See [`examples/`](examples/) for a 2-in-1 laptop setup. Put wallpapers in `~/Pictures/Wallpapers`.

## Update

Open System Settings > General > Software Update, or run `macos-update`. The command updates the system packages
and Flatpaks, then pulls the newest release of this desktop and reinstalls only the files that changed. Hyprland
plugins are rebuilt automatically after every Hyprland upgrade by a pacman hook. If a plugin still fails to load at
login, it is rebuilt then.

## Uninstall

```sh
~/.local/share/arch-macos-hyprland/uninstall.sh            # files in $HOME
~/.local/share/arch-macos-hyprland/uninstall.sh --system   # also the login screen, boot splash, hardening
```

Every file that the installer replaced comes back from the copy it kept in `~/.local/state/macos-look/backups`. The config directories that were moved
aside come back too. Packages stay installed.

## Not included, on purpose

- **Apple fonts, cursor and icons** come from the AUR (`apple-fonts`, `apple_cursor`, `whitesur-icon-theme`).
  **Wallpapers and the GTK/Firefox theme** are downloaded from the WhiteSur repositories at install time.
- **macOS system sounds** belong to Apple, so this project does not download them. Copy the `.aiff` files from
  `/System/Library/Sounds` on a Mac into `~/.local/share/sounds/macOS/source/`, then run `macos-sounds-build`.
- **Hardened `/etc/fstab` options** must be merged by hand. See `extra/fstab-hardening.txt`.

## Things to know

- **Hardening risks:** USBGuard blocks USB devices that were not plugged in during the install. Three wrong passwords
  lock the account for 15 minutes. Keep a recovery USB.
- **SDDM reads every file in `/etc/sddm.conf.d`, backups included.** The installer moves `*.bak*` files to
  `/etc/sddm.conf.d.backup`.
- **Logs:** the installer writes `~/.cache/macos-look/install.log`, and the plugin build writes
  `~/.cache/macos-look/rebuild-plugins.log`. Attach them to bug reports.

## Development

```
install.sh / uninstall.sh / setup.sh
lib/common.sh           installer functions
home/                   files installed into $HOME (__HOME__ is filled in)
system/<group>/         root files, grouped look | desktop | harden
packages/<group>*.txt   pacman, -aur and -flatpak lists per group
scripts/system.sh       root half of the installer
scripts/fetch-themes.sh WhiteSur GTK/Firefox/wallpapers
scripts/capture.sh      copy a live system's files back into home/ and system/
tests/install-test.sh   install, check, uninstall in a scratch home (CI runs it)
```

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Credits and license

Parts of this project started from [ML4W dotfiles](https://github.com/mylinuxforwork/dotfiles) by mylinuxforwork,
so this project is under the same license, [GPL-3.0](LICENSE). The WhiteSur themes are by
[vinceliuice](https://github.com/vinceliuice). `hyprbars` comes from
[hyprwm/hyprland-plugins](https://github.com/hyprwm/hyprland-plugins) (BSD-3-Clause) and is downloaded at build
time.

Apple, macOS and San Francisco are trademarks of Apple Inc. This project is not affiliated with Apple.
