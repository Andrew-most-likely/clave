# Changelog

## v1.0.0 (unreleased)

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
