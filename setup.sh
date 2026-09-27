#!/usr/bin/env bash
# One-line install:
#   bash <(curl -fsSL https://raw.githubusercontent.com/Andrew-most-likely/arch-macos-hyprland/main/setup.sh)
#
# Clones the repo to ~/.local/share/arch-macos-hyprland (latest release tag,
# or main with --main) and runs install.sh. Extra arguments go to install.sh,
# for example: ... setup.sh) --harden
set -euo pipefail

url=https://github.com/Andrew-most-likely/arch-macos-hyprland.git
dest=${XDG_DATA_HOME:-$HOME/.local/share}/arch-macos-hyprland
branch=""
args=()
for a in "$@"; do
    case "$a" in
        --main) branch=main ;;
        *) args+=("$a") ;;
    esac
done

[ "$(id -u)" -ne 0 ] || { echo "Run as your normal user, not root."; exit 1; }
[ -f /etc/arch-release ] || { echo "This needs Arch Linux."; exit 1; }
command -v git >/dev/null || sudo pacman -S --needed --noconfirm git

if [ -d "$dest/.git" ]; then
    git -C "$dest" fetch -q --tags origin
else
    git clone -q "$url" "$dest"
fi

if [ -z "$branch" ]; then
    branch=$(git -C "$dest" describe --tags --abbrev=0 origin/main 2>/dev/null || echo main)
fi
git -C "$dest" checkout -q "$branch"
[ "$branch" = main ] && git -C "$dest" pull -q --ff-only origin main
echo "arch-macos-hyprland $branch in $dest"

exec "$dest/install.sh" "${args[@]}"
