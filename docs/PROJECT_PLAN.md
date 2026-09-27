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

- **BR-1 Project name.** The project is called **Clave** (Spanish for keystone). All names use the prefix
  `clave`: commands `clave-*`, directories `~/.config/clave`, `~/.local/share/clave`,
  `~/.local/state/clave` and `~/.cache/clave`, the SDDM and Plymouth themes `clave`, and polkit actions
  `org.clave.*`. The installer moves an existing install from the old names (see BR-9).
- **BR-2 Logo.** A solid, one-color keystone: a flat, wide top, sides that taper to about 60% of the top
  width, and a concave arc for the bottom edge. It is used in the menu bar, the About window, the boot
  splash and the terminal.
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
- **BR-4 Files icon.** The Dock shows a neutral folder icon for the file manager, not a face.
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

  The repo never contains these files. `branding/` is user-owned, so updates keep it. The choice is stored in
  `~/.local/state/clave/personal`, so updates keep it too. Code: `lib/personal.sh`.

### 5.2 Security

- **SEC-1 Hardened by default.** This is final. The installer installs the hardening layer unless the user
  passes `--no-harden`. `--yes` also installs it. `--harden` is still accepted and does nothing extra.
- **SEC-2 Lockout warnings.** USBGuard and faillock can lock a user out. Before they are turned on, the
  installer shows what they do and how to recover. With `--yes` the warning is printed but not asked.
  The README links to a recovery guide.
- **SEC-3 Offline by default.** Nothing contacts the network unless the user asks for it. Online features
  (web search in Search, album art, currency rates) are off by default.
- **SEC-4 Keyring.** GNOME Keyring unlocks at login and apps that store secrets use it with full
  encryption. See ISSUE-2.

### 5.3 Performance and background work

- **PERF-1 Background budget.** No listeners or services beyond what a normal Arch install needs, plus the
  ones in the inventory below. Each entry has a written purpose.
- **PERF-2 Inventory.** Keep this list current. Today it is:

  | Unit or process | Layer | Purpose |
  |---|---|---|
  | Quickshell (shell, Dock) | look | The shell itself |
  | `sddm.service` | look | Login screen |
  | `home-cleanup.timer` (user) | desktop | Weekly cache cleanup |
  | `paccache.timer` | desktop | Package cache cleanup |
  | `cups.socket`, `avahi-daemon.service` | desktop | Printing and printer discovery |
  | `bluetooth.service` | desktop | Bluetooth |
  | `nftables`, `opensnitchd`, `usbguard` (+ user `usbguard-notifier`) | harden | Inbound firewall, outbound control, USB control |
  | `apparmor`, `auditd` | harden | Mandatory access control, audit log |
  | `arch-audit.timer` | harden | Daily CVE check |
  | `aidecheck.timer`, `aide-refresh.service` | harden | File integrity check, baseline refresh after upgrades |

  Question each desktop entry against PERF-1. For example, `avahi-daemon` listens on the network and is only
  needed for printer discovery.

  Count Quickshell `Process` and `Timer` objects too. Polling timers should be replaced with events where
  Hyprland or the system offers them.
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

### 5.6 Software footprint

- **SW-1** The public release ships only what the visual layer, the built features and the hardening need.
- **SW-2** Convenience apps (for example Spotify or virtual machine managers) never ship by default. They
  stay in `packages/extras*.txt`.
- **SW-3** Audit `packages/desktop.txt` against SW-1. Each GNOME app either backs a feature (for example
  Nautilus for the Dock's Trash) or moves to extras.

## 6. Features

| ID | Feature | Required or optional | Default | Setting |
|---|---|---|---|---|
| FEAT-1 | Space numbers in the menu bar (the pane indicator from stock Hyprland) | Optional | Off | Desktop & Dock > Spaces (done) |
| FEAT-4 | Login screen background and profile picture | Required | Current look | Lock Screen > Login Window (done) |
| FEAT-5 | Traffic lights on or off for all windows | Optional | On | Desktop & Dock > Windows > Show title bar buttons (done) |
| FEAT-6 | Replaceable logo (BR-2, BR-10) | Required | Clave keystone | `branding/logo.svg` now, a picker later |
| FEAT-7 | Modifier key glyph (BR-5) | Required | ⌘ | Keyboard > Super key symbol (done) |

Notes on the features:

- **FEAT-1.** The numbers come from Quickshell's Hyprland events, with no polling. While the setting is off,
  nothing is created. Click a number to go to that Space.
- **FEAT-4.** SDDM runs as its own user, so settings must be copied to a place SDDM can read. The copy
  happens when the user saves the setting, through the existing polkit helper `clave-admin`. No new service.
  `clave-prefs` converts the picture to PNG as the user and passes the bytes on stdin. Root checks the size
  and the PNG signature and copies them to a fixed place. It never opens a path the user chose and never
  decodes the image. The background is kept in `/var/lib/clave`, so reinstalling keeps it.
- **FEAT-7.** The choices are ⌘ and ❖. The Windows logo is a Microsoft trademark, so it is not offered.
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
- **ISSUE-4 Login screen button spacing.** The Sleep, Restart and Shut Down buttons were not evenly
  spaced, because each button column was as wide as its label. Each column now has the same width.

## 9. Competitive research

Study similar projects and record what is worth adopting. Start with:

- [pearOS Arch Linux](https://github.com/pearOS-archlinux/iso)
- [gnomintosh](https://github.com/jothi-prasath/gnomintosh)

Add other similar Linux desktop projects with at least 200 GitHub stars. For each one, fill in this table:

| Project | Features | Visual approach | Architecture | Customization | Security | Bundled apps | Quality of life | We do better | We lack |
|---|---|---|---|---|---|---|---|---|---|

Adopt a feature only if it passes section 3, does not weaken security, does not add a background service
without reason, and does not add unneeded software. The goal is completeness where it helps, not a copy
of every feature.

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

## 11. Roadmap

Each phase ends when its exit criteria are met.

| Phase | Work | Exit criteria |
|---|---|---|
| 0 | This plan. One issue per requirement. | Plan merged. Issues open. |
| 1 | Small fixes: ISSUE-4, OFF-1, ISSUE-3, ISSUE-2 | Each fix tested on a live install. |
| 2 | Rename and assets: BR-1 to BR-4, BR-6 to BR-10 | The trademark check (section 12) passes. The migration test passes. |
| 3 | Settings: FEAT-4, FEAT-1, FEAT-7 (BR-5), ISSUE-1 | Each setting works and costs nothing when off. |
| 4 | Release model: SEC-1, SEC-2, SW-3, PERF-2 | Hardened install round trip passes. Inventory matches the system. |
| 5 | Sections 9 and 10 | Findings added to this plan as requirements or rejected with a reason. |

Phase 4 must finish before the public release.

## 12. Release criteria for v1.0.0

- No Apple names or assets in the repo or in a default install. `scripts/name-check.sh` passes (section 5.1).
- CI passes: the name check, shellcheck, Lua and QML syntax, `Hyprland --verify-config`,
  `tests/install-test.sh` and `tests/migrate-test.sh`.
- A hardened install and uninstall round trip passes on a clean Arch system.
- An update from an old `macos-look` install to Clave keeps the user's settings.
- The background inventory (PERF-2) matches what runs on a fresh install.
- The desktop works offline, including the calculator.
- README, CHANGELOG and this plan are up to date.

## 13. Tabled

These ideas are on hold. They are not part of v1.0.0.

- Files and icons on the desktop, and drag-to-select with a selection rectangle.
- A sound audit: which events need sounds, and a custom, freely licensed sound set.
- A picker in System Settings for the logo, with size and format checks.

## 14. Open questions

- None at the moment. Add new ones here.

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
