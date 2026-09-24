#!/usr/bin/env bash
# macOS look + desktop essentials + hardening for ML4W Hyprland on Arch.
#
#   ./install.sh                 macOS look + desktop essentials (user + system)
#   ./install.sh --harden        also the hardening layer (asks first)
#   ./install.sh --extras        also the optional apps from packages/extras*.txt
#   ./install.sh --user-only     only files in $HOME, no sudo
#   ./install.sh --no-packages   skip pacman/AUR/flatpak installs
#   ./install.sh --dry-run       show what would happen, change nothing
#
# Needs ML4W dotfiles (https://github.com/mylinuxforwork/dotfiles) installed
# first, Hyprland Lua config. Built on ML4W 2.12.3.
set -euo pipefail
repo="$(cd "$(dirname "$0")" && pwd)"
stamp="$(date +%F)"
state="${XDG_STATE_HOME:-$HOME/.local/state}/macos-look"

harden=0 extras=0 user_only=0 packages=1 dry=0
for a in "$@"; do
    case "$a" in
        --harden) harden=1 ;;
        --extras) extras=1 ;;
        --user-only) user_only=1 ;;
        --no-packages) packages=0 ;;
        --dry-run) dry=1 ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) echo "Unknown option: $a"; exit 1 ;;
    esac
done

say()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
run()  { if [ "$dry" -eq 1 ]; then echo "  [dry-run] $*"; else "$@"; fi; }
pkgs() { grep -vhE '^\s*(#|$)' "$@" | tr -s ' \n' '\n' | grep -v '^$'; }

# --- checks ----------------------------------------------------------------
[ "$(id -u)" -ne 0 ] || { echo "Run as your normal user, not root."; exit 1; }
[ -f /etc/arch-release ] || { echo "This pack is for Arch Linux."; exit 1; }
if [ ! -f "$HOME/.config/ml4w/version.json" ]; then
    echo "ML4W dotfiles not found. Install them first:"
    echo "  https://github.com/mylinuxforwork/dotfiles"
    exit 1
fi
ml4w=$(sed -n 's/.*"Version": *"\([^"]*\)".*/\1/p' "$HOME/.config/ml4w/version.json")
[ "$ml4w" = "2.12.3" ] || warn "ML4W $ml4w found; this pack was made on 2.12.3. Overridden ML4W files may differ."
[ -f "$HOME/.config/hypr/hyprland.lua" ] || warn "No hyprland.lua: this pack needs ML4W's Lua Hyprland config."

# --- packages --------------------------------------------------------------
if [ "$packages" -eq 1 ]; then
    say "Packages (pacman)"
    lists=("$repo/packages/look.txt" "$repo/packages/desktop.txt")
    [ "$harden" -eq 1 ] && lists+=("$repo/packages/harden.txt")
    [ "$extras" -eq 1 ] && lists+=("$repo/packages/extras.txt")
    mapfile -t list < <(pkgs "${lists[@]}")
    [ "$user_only" -eq 1 ] || run sudo pacman -S --needed --noconfirm "${list[@]}"

    say "Packages (AUR, via yay)"
    aur=("$repo/packages/look-aur.txt")
    [ "$harden" -eq 1 ] && aur+=("$repo/packages/harden-aur.txt")
    mapfile -t list < <(pkgs "${aur[@]}")
    if command -v yay >/dev/null; then run yay -S --needed --noconfirm "${list[@]}"
    else warn "yay not found; install these AUR packages yourself: ${list[*]}"; fi

    say "Flatpaks (user)"
    fl=("$repo/packages/flatpak.txt"); [ "$extras" -eq 1 ] && fl+=("$repo/packages/extras-flatpak.txt")
    mapfile -t list < <(pkgs "${fl[@]}")
    run flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    run flatpak install --user -y --noninteractive flathub "${list[@]}"
fi

# --- files in $HOME --------------------------------------------------------
say "Config files in $HOME"
run mkdir -p "$state"
while IFS= read -r -d '' src; do
    rel="${src#"$repo/home/"}"
    dest="$HOME/$rel"
    if [ "$dry" -eq 1 ]; then echo "  [dry-run] ~/$rel"; continue; fi
    mkdir -p "$(dirname "$dest")"
    if [ -e "$dest" ] && ! cmp -s "$src" "$dest" && [ ! -e "$dest.bak-$stamp" ]; then
        cp -a "$dest" "$dest.bak-$stamp"
    fi
    cp "$src" "$dest"
    grep -Iq . "$dest" && sed -i "s|__HOME__|$HOME|g" "$dest"
    [ -x "$src" ] && chmod +x "$dest"
    grep -qxF "$dest" "$state/installed-files" 2>/dev/null || echo "$dest" >> "$state/installed-files"
done < <(find "$repo/home" -type f -print0 | sort -z)

say "Third-party themes (WhiteSur GTK, Firefox, wallpapers)"
run "$repo/scripts/fetch-themes.sh"
# GTK4/libadwaita assets come from the WhiteSur theme that was just installed.
run ln -sfn "$HOME/.local/share/themes/WhiteSur-Dark/gtk-4.0/assets" "$HOME/.config/gtk-4.0/assets"
for prof in "$HOME"/.config/mozilla/firefox/*.default* "$HOME"/.mozilla/firefox/*.default*; do
    [ -d "$prof" ] || continue
    grep -qs 'legacyUserProfileCustomizations' "$prof/user.js" || run sh -c "cat '$repo/extra/firefox-user.js' >> '$prof/user.js'"
done

say "Genie shaders and Hyprland plugins"
run "$HOME/.config/quickshell/DockApp/shaders/build.sh"
run "$HOME/.local/share/macos-look/rebuild-plugins.sh" || warn "Plugin build failed; see ~/.cache/macos-look/rebuild-plugins.log"

say "macOS sounds"
if ls "$HOME/.local/share/sounds/macOS/source/"* >/dev/null 2>&1; then
    run "$HOME/.local/bin/macos-sounds-build"
else
    echo "  No source sounds. Copy the .aiff files from a Mac's /System/Library/Sounds"
    echo "  into ~/.local/share/sounds/macOS/source/ and run macos-sounds-build."
fi
run fc-cache -f >/dev/null

say "User services"
run systemctl --user daemon-reload
run systemctl --user enable --now home-cleanup.timer gnome-keyring-daemon.socket
[ "$harden" -eq 1 ] && run systemctl --user enable usbguard-notifier.service || true

# --- system part -----------------------------------------------------------
if [ "$user_only" -eq 0 ]; then
    groups=(look desktop)
    if [ "$harden" -eq 1 ]; then
        warn "
The hardening layer changes how the machine boots and who may log in:
  - linux-hardened kernel flags, AppArmor, auditd, sysctl lockdown
  - default-drop inbound firewall (nftables table 'inet hardening') + OpenSnitch
  - USBGuard: only USB devices plugged in NOW stay allowed
  - faillock: 3 wrong passwords lock the account for 15 minutes
  - login umask 027, su limited to group wheel
Keep a recovery USB at hand."
        read -rp "Apply hardening? [y/N] " ans
        [[ "$ans" =~ ^[Yy]$ ]] && groups+=(harden)
    fi
    say "System part (sudo): ${groups[*]}"
    run sudo "$repo/scripts/system.sh" "${groups[@]}"
fi

say "Done."
echo "Log out and back in (or reboot) to load everything."
echo "Undo: ./uninstall.sh"
