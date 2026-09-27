# Shared by install.sh and uninstall.sh. Expects $repo.
# shellcheck shell=bash
# shellcheck disable=SC2154  # repo, packages, user_only, harden: set by install.sh

GITHUB_REPO="Andrew-most-likely/arch-macos-hyprland"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/macos-look"
# Copies of files as they were before the first install, by path under $HOME.
# Kept out of ~/.config: a stray copy in autostart/ or a *.d/ folder would be
# read as a live file.
BACKUPS="$STATE/backups"
LOG="${XDG_CACHE_HOME:-$HOME/.cache}/macos-look/install.log"
STAMP="$(date +%F)"
DRY=${DRY:-0}
YES=${YES:-0}

# Files the user owns: installed when missing, never replaced.
USER_OWNED=(
    .config/hypr/custom.lua
    .config/hypr/monitors.lua
    .config/hypr/hypridle.conf
    .config/kitty/custom.conf
    ".config/macos-look/*"
)

# Directories that are replaced as a whole on first install. An existing one
# (ML4W, another dotfiles pack, your own) is moved to <dir>.bak-<date>.
FRESH_DIRS=(.config/hypr .config/quickshell)

say()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }
run()  { if [ "$DRY" -eq 1 ]; then echo "  [dry-run] $*"; else "$@"; fi; }
ask()  {  # ask "Question" default(y|n): returns 0 for yes
    local q=$1 def=${2:-y} ans
    [ "$YES" -eq 1 ] && [ "$def" = y ] && return 0
    [ "$YES" -eq 1 ] && return 1
    read -rp "$q [$([ "$def" = y ] && echo Y/n || echo y/N)] " ans
    ans=${ans:-$def}
    [[ "$ans" =~ ^[Yy] ]]
}
pkgs() { grep -vhE '^\s*(#|$)' "$@" 2>/dev/null | tr -s ' \n' '\n' | grep -v '^$' || true; }

log_start() {
    [ "$DRY" -eq 1 ] && return
    mkdir -p "$(dirname "$LOG")" "$STATE"
    exec > >(tee -a "$LOG") 2>&1
    echo "---- $(date '+%F %T') install.sh $(git -C "$repo" describe --always --dirty 2>/dev/null || echo '?')"
}

preflight() {
    [ "$(id -u)" -ne 0 ] || die "Run as your normal user, not root."
    [ -f /etc/arch-release ] || die "This needs Arch Linux (or an Arch-based distribution)."
    local v
    v=$(pacman -Q hyprland 2>/dev/null | awk '{print $2}' | sed 's/^[0-9]*://; s/[-+].*//' || true)
    if [ -n "$v" ] && [ "$(printf '%s\n0.55.0\n' "$v" | sort -V | head -n1)" != "0.55.0" ]; then
        die "Hyprland $v is too old: this config needs 0.55 or newer (Lua config). Update with: sudo pacman -Syu"
    fi
}

aur_helper() { command -v paru || command -v yay || true; }

bootstrap_aur_helper() {
    [ -n "$(aur_helper)" ] && return
    say "No AUR helper found: installing paru"
    run sudo pacman -S --needed --noconfirm base-devel git
    local tmp
    tmp=$(mktemp -d)
    run git clone -q --depth 1 https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
    (cd "$tmp/paru-bin" && run makepkg -si --noconfirm)
    rm -rf "$tmp"
}

show_plan() {
    local helper old=""
    helper=$(aur_helper)
    for d in "${FRESH_DIRS[@]}"; do
        [ -e "$HOME/$d" ] || [ -L "$HOME/$d" ] || continue
        is_ours "$HOME/$d" || old+=" ~/$d"
    done
    cat <<EOF

  arch-macos-hyprland
  -------------------
  Repo:        $repo
  Packages:    $([ "$packages" -eq 1 ] && echo "yes (AUR helper: ${helper:-paru, installed first})" || echo no)
  System part: $([ "$user_only" -eq 1 ] && echo "no (--user-only)" || echo "yes (sudo): login screen, boot splash, services")
  Hardening:   $([ "$harden" -eq 1 ] && echo "yes, asked again before it runs" || echo no)
  Moved aside:${old:- nothing}
  Log:         $LOG
EOF
    [ -d "$HOME/.mydotfiles" ] && echo "  ML4W was found. It stays in ~/.mydotfiles, unused; remove it later if you like."
    echo
    ask "Continue?" y || exit 0
}

install_packages() {  # install_packages GROUP...: packages/GROUP.txt, GROUP-aur.txt, GROUP-flatpak.txt
    local g lists=() aur=() flat=() list=()
    for g in "$@"; do
        lists+=("$repo/packages/$g.txt")
        aur+=("$repo/packages/$g-aur.txt")
        flat+=("$repo/packages/$g-flatpak.txt")
    done

    say "Packages (pacman): $*"
    mapfile -t list < <(pkgs "${lists[@]}")
    [ ${#list[@]} -eq 0 ] || run sudo pacman -S --needed --noconfirm "${list[@]}"

    mapfile -t list < <(pkgs "${aur[@]}")
    if [ ${#list[@]} -gt 0 ]; then
        bootstrap_aur_helper
        say "Packages (AUR)"
        run "$(aur_helper || echo paru)" -S --needed --noconfirm "${list[@]}"
    fi

    mapfile -t list < <(pkgs "${flat[@]}")
    if [ ${#list[@]} -gt 0 ]; then
        say "Flatpaks (user)"
        run flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        run flatpak install --user -y --noninteractive flathub "${list[@]}"
    fi
}

is_ours() { [ -f "$1/macos/binds.lua" ] || [ -f "$1/MacOS/MenuBar.qml" ]; }

is_user_owned() {
    local rel=$1 p
    for p in "${USER_OWNED[@]}"; do
        # shellcheck disable=SC2053
        [[ "$rel" == $p ]] && return 0
    done
    return 1
}

# Move whole config directories of an earlier setup aside, and turn symlinked
# config directories (ML4W links ~/.config/* into ~/.mydotfiles) into real
# ones, so that installing never writes into another project's files.
move_aside_old_setup() {
    say "Earlier setup"
    local d path dest n target moved=0
    for d in "${FRESH_DIRS[@]}"; do
        path="$HOME/$d"
        { [ -e "$path" ] || [ -L "$path" ]; } || continue
        is_ours "$path" && continue
        dest="$path.bak-$STAMP"; n=1
        while [ -e "$dest" ] || [ -L "$dest" ]; do dest="$path.bak-$STAMP-$n"; n=$((n + 1)); done
        echo "  ~/$d -> ${dest#"$HOME/"}"
        run mv "$path" "$dest"
        [ "$DRY" -eq 1 ] || printf 'moved\t%s\t%s\n' "$path" "$dest" >> "$STATE/moved-aside"
        moved=1
        # Keep the screen setup of the earlier config.
        if [ "$d" = .config/hypr ] && [ -s "$dest/monitors.lua" ]; then
            run mkdir -p "$path"
            run cp -L "$dest/monitors.lua" "$path/monitors.lua"
            echo "  kept your monitors.lua"
        fi
    done

    for d in "$repo"/home/.config/*/; do
        path="$HOME/.config/$(basename "$d")"
        [ -L "$path" ] || continue
        target=$(readlink -f "$path")
        [ -d "$target" ] || continue
        echo "  ~/${path#"$HOME/"} was a link to $target; now a copy"
        run rm "$path"
        run cp -a "$target" "$path"
        [ "$DRY" -eq 1 ] || printf 'unlinked\t%s\t%s\n' "$path" "$target" >> "$STATE/moved-aside"
        moved=1
    done
    [ "$moved" -eq 1 ] || echo "  nothing to move"
    migrate_ml4w_data
}

# Carry over what ML4W users set up: wallpapers, the current picture and the
# pinned Dock apps. Nothing is removed from ML4W's folders.
migrate_ml4w_data() {
    local walls="$HOME/.local/share/macos-look/wallpapers" cur
    if [ -d "$HOME/.config/ml4w/wallpapers" ]; then
        run mkdir -p "$walls"
        run cp -n "$HOME"/.config/ml4w/wallpapers/*.{jpg,jpeg,png,webp} "$walls/" 2>/dev/null || true
        echo "  copied ML4W wallpapers"
    fi
    cur=$(cat "$HOME/.cache/ml4w/hyprland-dotfiles/current_wallpaper" 2>/dev/null || true)
    # Point at the copy, so the picture survives removing ML4W.
    [ -f "$walls/$(basename "$cur")" ] && cur="$walls/$(basename "$cur")"
    if [ -f "$cur" ] && [ ! -e "$HOME/.config/macos-look/wallpaper" ]; then
        run mkdir -p "$HOME/.config/macos-look"
        [ "$DRY" -eq 1 ] || printf '%s\n' "$cur" > "$HOME/.config/macos-look/wallpaper"
        echo "  kept your wallpaper"
    fi
    if [ -f "$HOME/.config/ml4w-dock/dock.json" ] && [ ! -e "$HOME/.config/macos-look/dock.json" ]; then
        run mkdir -p "$HOME/.config/macos-look"
        run cp "$HOME/.config/ml4w-dock/dock.json" "$HOME/.config/macos-look/dock.json"
        echo "  kept your Dock"
    fi
}

fill_placeholders() {
    grep -Iq . "$1" || return 0
    sed -i -e "s|__HOME__|$HOME|g" -e "s|__REPO__|$repo|g" -e "s|__GITHUB_REPO__|$GITHUB_REPO|g" "$1"
}

install_home_files() {
    say "Desktop files in $HOME"
    local src rel dest tmp changed=0 kept=0
    tmp=$(mktemp)
    while IFS= read -r -d '' src; do
        rel="${src#"$repo/home/"}"
        dest="$HOME/$rel"
        if [ -e "$dest" ] && is_user_owned "$rel"; then
            kept=$((kept + 1))
            continue
        fi
        cp "$src" "$tmp"
        fill_placeholders "$tmp"
        cmp -s "$tmp" "$dest" 2>/dev/null && continue
        changed=$((changed + 1))
        if [ "$DRY" -eq 1 ]; then echo "  [dry-run] ~/$rel"; continue; fi
        mkdir -p "$(dirname "$dest")"
        if [ -e "$dest" ] && [ ! -e "$BACKUPS/$rel" ]; then
            mkdir -p "$(dirname "$BACKUPS/$rel")"
            cp -a "$dest" "$BACKUPS/$rel"
        fi
        cp "$tmp" "$dest"
        if [ -x "$src" ]; then chmod 755 "$dest"; else chmod 644 "$dest"; fi
        grep -qxF "$dest" "$STATE/installed-files" 2>/dev/null || echo "$dest" >> "$STATE/installed-files"
    done < <(find "$repo/home" -type f -print0 | sort -z)
    rm -f "$tmp"
    echo "  $changed file(s) written, $kept of your own kept"
}

fetch_themes() {
    say "Third-party themes (WhiteSur GTK, Firefox, wallpapers)"
    run "$repo/scripts/fetch-themes.sh" || warn "Theme download failed; re-run install.sh later"
    # GTK4/libadwaita assets come from the WhiteSur theme just installed.
    local assets="$HOME/.config/gtk-4.0/assets"
    if [ -d "$assets" ] && [ ! -L "$assets" ]; then run mv "$assets" "$assets.bak-$STAMP"; fi
    run ln -sfn "$HOME/.local/share/themes/WhiteSur-Dark/gtk-4.0/assets" "$assets"
    local prof
    for prof in "$HOME"/.config/mozilla/firefox/*.default* "$HOME"/.mozilla/firefox/*.default*; do
        [ -d "$prof" ] || continue
        grep -qs 'legacyUserProfileCustomizations' "$prof/user.js" \
            || run sh -c "cat '$repo/extra/firefox-user.js' >> '$prof/user.js'"
    done
}

# changed_since_last_install REGEX: did files matching REGEX change since the
# commit recorded by the last install? True when unknown.
changed_since_last_install() {
    local last
    last=$(cat "$STATE/installed-commit" 2>/dev/null) || return 0
    git -C "$repo" cat-file -e "$last" 2>/dev/null || return 0
    git -C "$repo" diff --name-only "$last" HEAD | grep -qE "$1"
}

confirm_harden() {
    warn "
The hardening layer changes how the machine boots and who may log in:
  - linux-hardened kernel flags, AppArmor, auditd, sysctl lockdown
  - default-drop inbound firewall (nftables table 'inet hardening') + OpenSnitch
  - USBGuard: only USB devices plugged in NOW stay allowed
  - faillock: 3 wrong passwords lock the account for 15 minutes
  - login umask 027, su limited to group wheel
Keep a recovery USB at hand."
    local ans
    read -rp "Apply hardening? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

record_install() {
    [ "$DRY" -eq 1 ] && return
    printf '%s\n' "$repo" > "$STATE/repo"
    git -C "$repo" rev-parse HEAD > "$STATE/installed-commit" 2>/dev/null || true
}
