# Changelog

## v1.0.0 (unreleased)

First standalone release. Earlier versions were an overlay for ML4W dotfiles.

- Standalone Hyprland config: `hyprland.lua` plus `macos/*.lua`, with `custom.lua` and `monitors.lua` left to you
- `macos-*` commands replace the ML4W scripts: power, wallpaper, screenshot, clipboard, emoji, keyboard shortcuts,
  Night Shift, software update
- macOS screenshot shortcuts (`Shift+Super+3/4/5`), text recognition (`Shift+Super+6`), keyboard shortcut list (`Super+/`)
- One-line install (`setup.sh`), `install.sh --update`, and an updater that follows releases
- The installer moves an earlier setup aside and `uninstall.sh` restores it; ML4W wallpapers, current wallpaper and
  Dock pins are carried over
- Apps in `~/.config/autostart` now start at login
- Fixes: the wallpaper portal, Launchpad entry and System Settings helpers are now part of the install; `pacman.conf`
  is edited in place instead of replaced
- CI: shellcheck, Lua and QML syntax, `Hyprland --verify-config`, and an install/uninstall round trip
- License is now GPL-3.0, the license of ML4W, which parts of this project started from
