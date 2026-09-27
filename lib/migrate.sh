# Moves an install made under the project's old names to the Clave names
# (PROJECT_PLAN.md BR-9). Sourced by lib/common.sh and scripts/system.sh.
# This file and the README disclaimer are the only places that still spell
# out the old names; the release name check skips them.
# shellcheck shell=bash
# shellcheck disable=SC2154  # repo, HOME, STATE, BACKUPS: set by the caller

OLD=macos-look

# Files that mark a config directory as one of ours, in the old layout.
# shellcheck disable=SC2034  # read by is_ours in lib/common.sh
OLD_OURS=(macos/binds.lua MacOS/MenuBar.qml)

# Old name -> new name, for text the user wrote: commands and the layer
# names that window rules match.
OLD_NAMES=(
    macos-mission-control:clave-overview macos-notification-center:clave-notification-center
    macos-control-center:clave-control-center macos-menubar:clave-menubar
    macos-hotcorner:clave-hotcorner macos-genie:clave-genie macos-dock:clave-dock
    macos-launchpad:clave-apps
    macos-spotlight:clave-search
    macos-nightshift:clave-nightlight
    macos-app-info:clave-app-info macos-clipboard:clave-clipboard
    macos-displays:clave-displays macos-emoji:clave-emoji
    macos-gtk-apply:clave-gtk-apply macos-idle:clave-idle
    macos-keybinds:clave-keybinds macos-power:clave-power
    macos-prefs:clave-prefs macos-screenshot:clave-screenshot
    macos-sounds-build:clave-sounds-build macos-sound:clave-sound
    macos-update:clave-update macos-wallpaper:clave-wallpaper
)

# move_dir OLD NEW: rename a directory, or merge it into NEW without
# replacing anything already there.
move_dir() {
    [ -d "$1" ] || return 0
    if [ -e "$2" ]; then
        run cp -an "$1/." "$2/"
        run rm -rf "$1"
    else
        run mkdir -p "$(dirname "$2")"
        run mv "$1" "$2"
    fi
    echo "  ${1#"$HOME/"} -> ${2#"$HOME/"}"
}

# edit_json FILE JQ_FILTER: rewrite a settings file when the filter changes it.
edit_json() {
    local f=$1 tmp
    [ -f "$f" ] || return 0
    tmp=$(mktemp)
    if jq --indent 4 "$2" "$f" > "$tmp" 2>/dev/null; then
        cmp -s "$tmp" "$f" || { run cp "$tmp" "$f"; echo "  updated ${f#"$HOME/"}"; }
    else
        warn "  ${f#"$HOME/"} could not be read; left as it is"
    fi
    rm -f "$tmp"
}

# Settings that were renamed along with the features.
migrate_settings() {
    edit_json "$HOME/.config/clave/dock.json" \
        'if .apps.pinned then .apps.pinned |= map(if . == "launchpad" then "clave-apps" else . end) else . end'
    edit_json "$HOME/.config/clave/settings.json" '
        def rename(a; b): if has(a) then .[b] = (.[b] // {}) + .[a] | del(.[a]) else . end;
        def corner: {"missioncontrol": "overview", "launchpad": "apps", "spotlight": "search"}[.] // .;
        rename("spotlight"; "search")
        | if .display.nightShiftTemp then
              .display.nightLightTemp = .display.nightShiftTemp | del(.display.nightShiftTemp)
          else . end
        | if .hotCorners then .hotCorners |= map_values(corner) else . end
    '
}

# Old names in files the user owns. A copy of each file is kept in
# the backups folder first.
migrate_user_text() {
    local rel f pair
    for rel in .config/hypr/custom.lua .config/kitty/custom.conf; do
        f="$HOME/$rel"
        [ -f "$f" ] && grep -q 'macos-\|hypr/macos/' "$f" || continue
        [ "$DRY" -eq 1 ] && { echo "  [dry-run] update old names in ~/$rel"; continue; }
        mkdir -p "$(dirname "$BACKUPS/$rel.pre-clave")"
        cp -a "$f" "$BACKUPS/$rel.pre-clave"
        for pair in "${OLD_NAMES[@]}"; do
            sed -i "s/\b${pair%%:*}\b/${pair#*:}/g" "$f"
        done
        sed -i -e "s|$OLD|clave|g" -e 's|hypr/macos/|hypr/clave/|g' -e 's|macos/\*\.lua|clave/*.lua|g' "$f"
        echo "  updated old names in ~/$rel (copy in ${BACKUPS#"$HOME/"}/$rel.pre-clave)"
    done
}

# Files that an earlier version installed and this one no longer has: put
# back what was there before, or remove them. Files the user owns stay.
# Runs after the new files are in place.
remove_orphans() {
    local list="$STATE/installed-files" keep f rel n=0
    [ -f "$list" ] || return 0
    keep=$(mktemp)
    while IFS= read -r f; do
        rel="${f#"$HOME/"}"
        if [ -e "$repo/home/$rel" ] || is_user_owned "$rel"; then
            echo "$f" >> "$keep"
            continue
        fi
        n=$((n + 1))
        [ "$DRY" -eq 1 ] && { echo "  [dry-run] remove ~/$rel"; continue; }
        if [ -e "$BACKUPS/$rel" ]; then mv "$BACKUPS/$rel" "$f"; else rm -f "$f"; fi
        rmdir -p --ignore-fail-on-non-empty "$(dirname "$f")" 2>/dev/null || true
    done < "$list"
    [ "$DRY" -eq 1 ] || mv "$keep" "$list"
    rm -f "$keep"
    [ "$n" -eq 0 ] || echo "  removed $n file(s) from the earlier version"
}

# The home half: config, data, state, cache and the user's sounds.
migrate_home() {
    local found=0 d
    for d in "$HOME/.config/$OLD" "$HOME/.local/share/$OLD" "$HOME/.local/state/$OLD" \
             "$HOME/.local/share/sounds/macOS" "$HOME/.config/hypr/macos"; do
        [ -e "$d" ] && found=1
    done
    if [ "$found" -eq 1 ]; then
        say "Moving the earlier install to the Clave names"
        move_dir "$HOME/.config/$OLD" "$HOME/.config/clave"
        move_dir "$HOME/.local/share/$OLD" "$HOME/.local/share/clave"
        move_dir "$HOME/.local/share/sounds/macOS" "$HOME/.local/share/sounds/clave"
        move_dir "$HOME/.local/state/$OLD" "$STATE"
        run rm -rf "$HOME/.cache/$OLD"
        # The install record and moved-aside list name files by their full path.
        for d in "$STATE/installed-files" "$STATE/moved-aside"; do
            [ -f "$d" ] && run sed -i -e "s|/$OLD/|/clave/|g" -e 's|/sounds/macOS/|/sounds/clave/|g' "$d"
        done
        if [ -d "$BACKUPS/.config/$OLD" ]; then move_dir "$BACKUPS/.config/$OLD" "$BACKUPS/.config/clave"; fi
    fi
    migrate_settings
    migrate_user_text
}

# The system half, run as root by scripts/system.sh. Same idea: files the old
# install placed that this version does not place are restored or removed.
# Paths this version still uses carry over into the new record.
migrate_system() {  # migrate_system NEW_STATE_DIR
    local old=/var/lib/$OLD f
    [ -f "$old/installed-files" ] || return 0
    say "Moving the earlier system install to the Clave names"
    systemctl disable macos-boot-chime.service 2>/dev/null || true
    while IFS= read -r f; do
        if compgen -G "$repo/system/*$f" >/dev/null || [[ "$f" == /etc/usbguard/IPCAccessControl.d/* ]]; then
            grep -qxF "$f" "$1/installed-files" 2>/dev/null || echo "$f" >> "$1/installed-files"
            continue
        fi
        local bak
        bak=$(ls -1d "$f".bak-* 2>/dev/null | sort | head -n1)
        rm -rf "$f"
        if [ -n "$bak" ]; then mv "$bak" "$f"; echo "  restored $f"; else echo "  removed  $f"; fi
    done < "$old/installed-files"
    rm -rf "$old"
    systemctl daemon-reload
}
