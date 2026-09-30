# Changelog

## Unreleased

- Helper launchers stay hidden in Apps and Search when their desktop file starts with comments, as hwloc's
  Hardware Locality launcher does. Advanced Network Configuration is hidden too; Wi-Fi Settings in the menu bar
  and Control Center still open it.
- `scripts/name-check.sh` fails again when it finds a name. Before, it printed the matches and still passed.
- The README shortcut table matches the real keys: `Super+W` closes a window, `Super+Q` quits the app,
  `Super+M` minimizes, `Super+H` hides the app and `Super+Ctrl+M` zooms.
- A project website (`docs/index.html`), screenshots, a short video tour and the logo files in `docs/assets/`.
- The repository's top level is shorter, so the README shows sooner. Guides, the changelog, examples and brand files
  are in `docs/`; the contributing and security notes and the upstream watch are in `.github/`; installer data is in
  `scripts/`. `install.sh`, `setup.sh`, `uninstall.sh`, `packages/` and `compat.json` stay where they were, so
  installs and updates work as before.
- The README and the website are easier to scan: one short idea per section, with the details folded away until
  you open them.

## v1.1.2 (2026-09-29)

- **The screen locks when idle again.** Installs from before the rename to Clave kept an old lock command in
  `~/.config/hypr/hypridle.conf`. The screen then never locked when idle, and the computer went to sleep
  unlocked, whatever System Settings > Lock Screen said. The update fixes the file (a copy is kept in the
  backups folder), and `clave-doctor` checks it.
- The display no longer turns off before the screen locks. A shorter display time is raised to the lock time.
- **System Settings search** finds the settings inside panes, not only pane names: try "24-hour", "tap to
  click" or "night light". The matching rows show under each pane, and a click goes to the row.
- **Lock screen picture.** System Settings > Lock Screen > Background chooses between the blurred wallpaper and
  a picture of your own. Before, the lock screen always showed the blurred wallpaper, and the only picture
  setting (Login Window) changed the login screen.
- **Choose Picture… opens again.** The picture and icon choosers in System Settings (lock screen, login
  background, profile picture, app icons) never opened: Qt's file dialog has no backend in the shell. They now
  use the desktop's file chooser through the portal (`clave-choose-file`).
- Changing one Lock Screen timeout could set the other two to Never when System Settings had not read them yet.
  Each row now changes only its own timeout (`clave-idle set-one`).
- **Ethernet** shows up: the menu bar shows a wired icon in place of Wi-Fi while a cable is connected. Its menu
  always has an Ethernet line (Connected, Not Connected or No Adapter) and names the connection. Control Center
  has an Ethernet row on computers with a port (click to connect or disconnect). The Wi-Fi & Bluetooth pane in
  System Settings is now Network & Bluetooth, and always shows the wired status.
- With two keyboard layouts (for example U.S. + Spanish), Alt+Shift switches between them.
- `qs ipc call settings set` applies keyboard, mouse, window and accessibility settings at once, and light or
  dark mode and the accent color reach GTK and Qt apps too.
- `clave-doctor` lists launchers in Apps that belong to no app Clave knows.
- Screenshots move to `Print` (toolbar) and `Shift+Print` (copy text). `Shift+Super+3/4/5/6` are gone, so
  `Shift+Super+1..0` move windows to Spaces again.
- Removed: the unused `xsettingsd` config, and the packages the audit found unused (`cmake`, `meson`, `ninja`,
  `alsa-utils`, `cups-pdf`). `lynis` and the Office fonts moved to `--extras`.

## v1.1.1 (not tagged; released in v1.1.2)

- **`clave-doctor`** says whether this Clave still works with the software installed now: the Hyprland config, the
  plugins, the shell's log, the GTK4 theme, and each package Clave talks to (OK, Untested, or Update Clave).
  `--fetch` also reads the known problems from the newest signed release. `clave-update` runs it at the end.
- After an upgrade of a package Clave talks to, a pacman hook warns when this release was not tested with it, and
  one notification at the next login says when a newer Clave is needed. The hook never stops an upgrade.
- On GitHub, a daily check notices when an Arch update breaks Clave and opens an issue.

## v1.1.0 (not tagged; released in v1.1.2)

- **Disk Encryption.** Clave says when the disk is not encrypted: in the installer, in System Settings >
  Privacy & Security, and once at the first login. `clave-encrypt setup` explains a reinstall with LUKS2, or
  encrypts this install in place (systemd-boot, GRUB or Limine; ext4 or btrfs) with a recovery key. The boot
  splash asks for the passphrase in the lock screen's style. See [docs/ENCRYPTION.md](ENCRYPTION.md).
- **Standard apps.** Reminders, Stickies, Weather, Clock, Maps, Photos, Books, Podcasts, Music, Videos, Voice
  Memos, Camera, Fonts, Chess, Freeform board, Scanner, Screen Sharing, Console, System Information, Disk
  Utility, Keychain and Backups, all from the Arch repositories and none with a background service. An update
  offers to install them. Mail and Dictionary are in `--extras`. Any app's icon can be changed in System
  Settings > Appearance.
- **Notes, Calendar and Contacts**, drawn in the shell's style. Notes are Markdown files in
  `~/Documents/Notes`; calendars and contacts are `.ics` and `.vcf` files in `~/.local/share/clave`. No
  accounts, no sync.
- **Activity Monitor** with CPU, Memory, Disk and Network. Force Quit (`Super+Alt+Esc`) opens it too.
- **Screenshot toolbar** on `Shift+Super+5`: capture a window you click, a screen or an area, record the screen,
  set a timer, choose where to save. A thumbnail in the corner opens markup. `Shift+Super+3/4` work as before.
- **Displays** remembers each screen's settings by the screen itself, and Hyprland applies them as soon as it
  is plugged in. Each screen can extend the desktop, mirror another screen or be off. Control Center's
  Mirroring button mirrors the built-in screen. The `Super+P` menu is gone.
- GTK4 apps get traffic-light window buttons on the left, and rounder corners.
- Weather, Clock and Maps never look up the location online; they ask for a city.
- `htop` is no longer installed (Activity Monitor replaces it); an update says it can be removed.
- Fix: uninstalling after an update no longer puts the previous release's files back.
- Fix: System Settings no longer waits forever for Bluetooth on a computer without it, which kept some
  values from showing.
- Fix: without an audio output, each notification no longer comes with a "Failed to run script" notice.

First standalone release, and the first under the name Clave. Earlier versions were an overlay for ML4W
dotfiles, published as arch-macos-hyprland.

- Renamed to Clave. Commands, folders, themes and settings use the `clave` prefix, and features have neutral
  names: Overview, Search, Apps, Night Light, Files, About This Computer and the System menu. An existing install
  moves to the new names on update and keeps its settings.
- A new logo, the Clave keystone, in the menu bar, the About window, the boot splash and the terminal. Put your own
  at `~/.config/clave/branding/logo.svg`.
- Inter, JetBrains Mono, the Bibata cursor and the freedesktop sounds by default. `install.sh --personal` uses
  fonts, a cursor and sounds that you supply.
- The terminal logo is text now, so it no longer stays on screen after a full-screen program exits.
- The startup chime is gone.
- The hardening layer is installed by default. `--no-harden` skips it, and `--yes` includes it. The installer
  explains it first, and [docs/RECOVERY.md](RECOVERY.md) explains how to recover from a lockout.
- `uninstall.sh --system` no longer removes `/etc/pam.d/system-auth` while restoring it, which broke sudo and
  login, and it now removes the kernel flags from the GRUB boot menu.
- Disks, Disk Usage Analyzer, Snapshot and Passwords and Keys moved to `--extras`.
- Search has a calculator (`Ctrl+Tab`), which never downloads exchange rates.
- Optional editing shortcuts on the Super key (System Settings > Keyboard).
- The lock screen clock follows the 12- or 24-hour setting.
- The Wi-Fi and Trash icons react to changes instead of checking every few seconds.
- Updating from the old names also fixes paths in your settings, such as the wallpaper.
- System Settings: login screen background and profile picture, Space numbers in the menu bar (off by default),
  the Super key symbol (⌘ or ❖), and a list of apps that draw their own title bar buttons. VS Code and Bazaar
  no longer show two sets of buttons.

- Standalone Hyprland config: `hyprland.lua` plus `clave/*.lua`, with `custom.lua` and `monitors.lua` left to you
- `clave-*` commands replace the ML4W scripts: power, wallpaper, screenshot, clipboard, emoji, keyboard shortcuts,
  Night Light, software update
- Screenshot shortcuts (`Shift+Super+3/4/5`), text recognition (`Shift+Super+6`), keyboard shortcut list (`Super+/`)
- One-line install (`setup.sh`), `install.sh --update`, and an updater that follows releases
- The installer moves an earlier setup aside and `uninstall.sh` restores it; ML4W wallpapers, current wallpaper and
  Dock pins are carried over
- Apps in `~/.config/autostart` now start at login
- Fixes: the wallpaper portal, Apps entry and System Settings helpers are now part of the install; `pacman.conf`
  is edited in place instead of replaced
- CI: shellcheck, Lua and QML syntax, `Hyprland --verify-config`, an install/uninstall round trip, and an
  update from the old names
- License is now GPL-3.0, the license of ML4W, which parts of this project started from
