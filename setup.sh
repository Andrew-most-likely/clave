#!/usr/bin/env bash
# One-line install:
#   bash <(curl -fsSL https://raw.githubusercontent.com/Andrew-most-likely/arch-macos-hyprland/main/setup.sh)
#
# Clones the repo to ~/.local/share/arch-macos-hyprland (latest release tag,
# or main with --main) and runs install.sh. Extra arguments go to install.sh,
# for example: ... setup.sh) --harden
set -euo pipefail

url=https://github.com/Andrew-most-likely/arch-macos-hyprland.git
# Releases are signed with this key; setup refuses anything it did not sign.
key="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMFbpQJHvTvtcU3WbHR719NH3/4ZWWAPaRkc3CrhnC8N"
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
signers=$(mktemp)
trap 'rm -f "$signers"' EXIT
printf 'arch-macos-hyprland namespaces="git" %s\n' "$key" > "$signers"
signed() { git -C "$dest" -c gpg.format=ssh -c gpg.ssh.allowedSignersFile="$signers" "$@" >/dev/null 2>&1; }

if [ "$branch" = main ]; then
    git -C "$dest" fetch -q origin main
    signed verify-commit origin/main || { echo "origin/main is not signed by the project key. Stopping."; exit 1; }
    git -C "$dest" checkout -q main && git -C "$dest" merge -q --ff-only origin/main
else
    signed verify-tag "$branch" || { echo "Release $branch is not signed by the project key. Stopping."; exit 1; }
    git -C "$dest" checkout -q "$branch"
fi
echo "arch-macos-hyprland $branch in $dest"

exec "$dest/install.sh" "${args[@]}"
