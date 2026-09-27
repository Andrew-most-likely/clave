# Contributing

Bug reports and pull requests are welcome.

## Reporting a bug

Use the bug report form. Include the output of `hyprctl version` and `qs --version`, and attach
`~/.cache/macos-look/install.log` if the problem is with the install.

## Working on the desktop

1. Clone the repo, run `./install.sh --user-only --no-packages`, and log in to Hyprland.
2. Change files on your live system: Quickshell reloads on save, and `hyprctl reload` applies Hyprland changes.
3. Run `./scripts/capture.sh` to copy the changed files back into `home/` (it replaces your home path with
   `__HOME__`), then `git diff`.

Or edit `home/` directly and run `./install.sh --update`.

## Before you open a pull request

```sh
shellcheck -S warning -x install.sh uninstall.sh setup.sh lib/*.sh scripts/*.sh home/.local/bin/macos-*
Hyprland --verify-config -c "$PWD/home/.config/hypr/hyprland.lua"
tests/install-test.sh     # installs into a scratch home, checks, uninstalls
```

CI runs the same checks.

## Rules

- Keep files that users own out of updates: `hypr/custom.lua`, `hypr/monitors.lua`, `hypr/hypridle.conf`,
  `kitty/custom.conf` and `macos-look/*` (see `USER_OWNED` in `lib/common.sh`).
- Do not commit Apple assets (fonts, sounds, icons) or anything personal (paths, device names, network names).
- New settings go into `~/.config/macos-look/settings.json` through `MacOS/MacSettings.qml`, not into new files.
- Every Hyprland shortcut needs a `description`: `Super+/` lists them.
- Contributions are licensed under GPL-3.0.
