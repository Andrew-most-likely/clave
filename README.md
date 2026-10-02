<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/brand/wordmark-dark.png">
    <img src="docs/assets/brand/wordmark-light.png" alt="Clave" width="240">
  </picture>
</p>

<p align="center">A complete, security-hardened Hyprland desktop for Arch Linux.</p>

<p align="center">
  <a href="https://github.com/Andrew-most-likely/clave/releases/latest"><img src="https://img.shields.io/badge/release-v1.1.4-0a6fe0" alt="Release v1.1.4"></a>
  <a href="https://github.com/Andrew-most-likely/clave/actions/workflows/ci.yml"><img src="https://github.com/Andrew-most-likely/clave/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/Arch_Linux-1793d1?logo=archlinux&logoColor=white" alt="Arch Linux">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="License: GPL-3.0"></a>
</p>

<p align="center">
  <img src="docs/assets/screenshots/desktop.webp" alt="The Clave desktop: menu bar, a terminal and Files side by side, and the Dock" width="100%">
</p>

Clave turns a plain Hyprland install into a full desktop: menu bar, Dock, Overview, Control Center and System
Settings, with tiling kept. It applies a security hardening layer by default and works offline.

Clave is a student project. More screenshots and a video tour are on the
[website](https://andrew-most-likely.github.io/clave/).

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Configuration](#configuration)
- [Security hardening](#security-hardening)
- [Updating](#updating)
- [Uninstalling](#uninstalling)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Features

**Desktop**
- Menu bar on every screen, with the app menu, battery, Wi-Fi, sound and clock
- Control Center (Wi-Fi, Bluetooth, Focus, brightness, volume, Night Light, media) and Notification Center
- Dock with magnification, running indicators, pinning and a minimize animation (`hypr-minimize` plugin)
- Window title bar buttons from `hyprbars`, built for your Hyprland version
- Overview, hot corners, app search with a built-in calculator, and an Apps grid
- Activity Monitor and Force Quit
- System Settings (`Super+,`) for network, displays, sound, power, appearance, Dock, wallpaper, notifications,
  lock screen, login items, printers, date and time, input devices, and privacy
- Screenshots and screen recording (`Print`), and text capture from the screen (`Shift+Print`)
- Calendar based on plain `.ics` files, with no accounts or sync
- Clipboard history, emoji picker and Night Light
- Lock screen, idle timeouts, SDDM login screen and Plymouth boot splash
- Trackpad gestures for Spaces, Overview, Apps and full screen

**Theme:** Clave app icons on top of the WhiteSur icon, GTK, Kvantum and Firefox themes, the Bibata cursor, and
Inter and JetBrains Mono fonts. Qt5, Qt6, GTK4/libadwaita and Flatpak apps follow the theme.

**Apps** (`packages/apps.txt`, from the Arch repositories): Clock, Videos, Camera, Console, System Information,
Disk Utility, Keychain, Backups, Files, Text Editor, Calculator, and image and archive viewers.

**System:** GNOME Keyring, printing (CUPS with mDNS discovery), Bluetooth, exFAT and NTFS support, CJK and emoji
fonts, zram, a journald size limit and weekly cache cleanup. Clave also warns when the disk is not encrypted; see
[docs/ENCRYPTION.md](docs/ENCRYPTION.md).

## Requirements

- Arch Linux
- A user account with `sudo`
- An internet connection during installation

## Installation

Run as your normal user:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/Andrew-most-likely/clave/main/setup.sh)
```

Or clone the repository and run the installer:

```sh
git clone https://github.com/Andrew-most-likely/clave ~/.local/src/clave
cd ~/.local/src/clave
./install.sh --dry-run   # preview the changes
./install.sh
```

The installer asks before it changes anything. When it finishes, log out and choose **Hyprland** on the login
screen.

| Option | Description |
|---|---|
| `--yes` | Do not ask questions. The hardening layer is included. |
| `--no-harden` | Skip the security hardening layer |
| `--extras` | Also install the optional apps in `packages/extras*.txt` |
| `--personal` | Use fonts, a cursor, icons and sounds that you supply (see [Configuration](#configuration)) |
| `--user-only` | Install files in `$HOME` only. No sudo, login screen or boot splash. |
| `--no-packages` | Skip pacman, AUR and Flatpak packages |
| `--dry-run` | Show what would change, and change nothing |

### Existing configurations

The installer moves `~/.config/hypr` and `~/.config/quickshell` to `<dir>.bak-<date>`. Links into
`~/.mydotfiles` (from ML4W) are replaced with real copies, so `~/.mydotfiles` can be deleted. A `~/.bashrc`
that is a link (ML4W's) is moved to `~/.bashrc.bak-<date>` and replaced by Clave's; a `~/.bashrc` of your own
is left alone. Your `monitors.lua`, wallpapers and Dock pins are kept. `./uninstall.sh` restores
everything.

Installs made under the old name, arch-macos-hyprland, are migrated automatically. Settings and your own files
are kept.

## Keyboard shortcuts

Press `Super+/` to show all shortcuts.

| Keys | Action | Keys | Action |
|---|---|---|---|
| `Super+Space` | Search | `Super+W` / `Super+Q` | Close window / Quit app |
| `Super+A` | Apps | `Super+M` / `Super+H` | Minimize / Hide app |
| `Super+Tab` | Overview | `Super+F` | Full screen |
| `Alt+Tab` | Switch windows | `Super+T` | Float or tile the window |
| `Super+Return` | Terminal | `Super+1…0` | Go to a Space |
| `Super+E` | Files | `Super+Shift+1…0` | Move the window to a Space |
| `Super+B` | Web browser | `Super+Arrows` | Move focus |
| `Super+,` | System Settings | `Super+Alt+Arrows` | Swap windows |
| `Super+N` | Notification Center | `Super+Shift+Arrows` | Resize the window |
| `Super+Ctrl+N` | Control Center | `Super+S` | Scratchpad |
| `Super+V` | Clipboard history | `Print` | Screenshot and recording |
| `Ctrl+Super+Space` | Emoji picker | `Shift+Print` | Copy text from the screen |
| `Super+L` | Lock screen | `Super+Alt+G` | Game mode (effects off) |
| `Super+Alt+Esc` | Force Quit | `Super+/` | All shortcuts |

## Configuration

Most settings are in System Settings. The installer never overwrites these files:

| File | Purpose |
|---|---|
| `~/.config/hypr/custom.lua` | Your own Hyprland settings, shortcuts and autostart. Loaded last. |
| `~/.config/hypr/monitors.lua` | Monitor layout. System Settings > Displays writes this file. |
| `~/.config/hypr/hypridle.conf` | Idle timeouts. System Settings > Lock Screen writes this file. |
| `~/.config/kitty/custom.conf` | Terminal settings |
| `~/.bashrc` | Your shell settings. Loads Clave's aliases and prompt from `~/.local/share/clave/clave.bash` |
| `~/.config/clave/` | Settings saved by System Settings |
| `~/.config/clave/branding/logo.svg` | Custom logo for the menu bar, About window and boot splash |

A user guide for every part of Clave is installed locally: System Settings > General > User Guide, or
`~/.local/share/clave/docs/guide.html`.

Put wallpapers in `~/Pictures/Wallpapers`. See [`docs/examples/`](docs/examples/) for example configurations.

**Personal assets:** `./install.sh --personal` uses the fonts and cursor in `packages/personal-aur.txt`, the
WhiteSur app icons, and sound files that you put in `~/.local/share/sounds/clave/source/` (then run
`clave-sounds-build`). To go back, delete `~/.local/state/clave/personal` and run `./install.sh` again.

## Security hardening

Hardening is on by default. Use `--no-harden` to skip it.

- `linux-hardened` kernel with lockdown, IOMMU and `init_on_free`
- sysctl hardening, AppArmor (`apparmor.d`) and auditd
- nftables firewall that drops inbound traffic, and OpenSnitch for outbound traffic
- USBGuard, faillock, stricter sudo settings, `umask 027` and a `noexec` `/tmp`
- AIDE baseline and daily `arch-audit` CVE checks
- Network Identity (off by default): changes how the device appears on shared networks.
  System Settings > Privacy & Security.

**Before you install:** USBGuard blocks USB devices that were not connected during installation; allow or
block them later in System Settings > Privacy & Security > USB accessories. Three wrong
passwords lock the account for 15 minutes. Keep a recovery USB. See [docs/RECOVERY.md](docs/RECOVERY.md).

Hardened `/etc/fstab` options are not applied automatically. See `scripts/extra/fstab-hardening.txt`.

## Updating

Use System Settings > General > Software Update, or run:

```sh
clave-update
```

This updates system packages and Flatpaks, then installs the latest Clave release. Hyprland plugins are rebuilt
after each Hyprland upgrade.

`clave-doctor` checks that the installed packages are compatible with this Clave release (see `compat.json` and
[docs/UPSTREAM.md](docs/UPSTREAM.md)).

## Uninstalling

```sh
~/.local/src/clave/uninstall.sh            # files in $HOME
~/.local/src/clave/uninstall.sh --system   # also the login screen, boot splash and hardening
```

Replaced files are restored from `~/.local/state/clave/backups`. Installed packages are not removed.

## Troubleshooting

- Run `clave-doctor` to check the installation.
- Read the local User Guide (System Settings > General > User Guide).
- Installer log: `~/.cache/clave/install.log`
- Plugin build log: `~/.cache/clave/rebuild-plugins.log`
- Locked out after hardening: see [docs/RECOVERY.md](docs/RECOVERY.md)

Attach the logs when you report a bug.

## Contributing

Contributions are welcome, including testing, bug reports and documentation fixes. See
[CONTRIBUTING.md](.github/CONTRIBUTING.md) and [Discussions](https://github.com/Andrew-most-likely/clave/discussions).
The roadmap is in [docs/PROJECT_PLAN.md](docs/PROJECT_PLAN.md).

```
install.sh / uninstall.sh / setup.sh
compat.json             tested package versions and known issues
home/                   files installed into $HOME
system/<group>/         system files: look | desktop | harden
packages/<group>*.txt   pacman, AUR and Flatpak package lists
lib/                    installer functions
scripts/                system installer, theme download and checks
tests/                  install, migration, app and compatibility tests
docs/                   guides, changelog, project plan and website
```

## License

[GPL-3.0](LICENSE).

Parts of this project are based on [ML4W dotfiles](https://github.com/mylinuxforwork/dotfiles) by
mylinuxforwork. WhiteSur themes are by [vinceliuice](https://github.com/vinceliuice). `hyprbars` is from
[hyprwm/hyprland-plugins](https://github.com/hyprwm/hyprland-plugins) (BSD-3-Clause) and is downloaded at build
time. The Clave app icons are generated by `scripts/make-icons.py`.

Apple, macOS and San Francisco are trademarks of Apple Inc. This project is not affiliated with or endorsed by
Apple.
