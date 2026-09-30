#!/usr/bin/env bash
# Copies the live configuration listed in scripts/manifest-home.txt and
# scripts/manifest-system.txt into home/ and system/, so the repo can be refreshed
# after changing something on this machine:  ./scripts/capture.sh && git diff
#
# Personal values are replaced by placeholders that install.sh fills back in:
#   /home/<user> -> __HOME__, <user> in user-name contexts -> __USER__, uid -> __UID__
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
user="$(id -un)"; uid="$(id -u)"

scrub() {  # scrub FILE: replace personal values in text files, in place
    grep -Iq . "$1" 2>/dev/null || return 0   # skip binaries and empty files
    sed -i -e "s|$HOME|__HOME__|g" \
           -e "s|/run/user/$uid|/run/user/__UID__|g" \
           -e "s|runuser -u $user |runuser -u __USER__ |g" -e "s|Runs as $user,|Runs as __USER__,|g" \
           -e "s|IPCAllowedUsers=root $user|IPCAllowedUsers=root __USER__|g" "$1"
}

copy_tree() {  # copy_tree SRC DEST: copy file or directory, skipping backups and build output
    local src="$1" dest="$2"
    if [ -d "$src" ]; then
        rm -rf "$dest"
        mkdir -p "$dest"
        rsync -a --no-links --exclude='*.bak*' --exclude='*.ml4w' --exclude='__pycache__' \
              --exclude='*.so' --exclude='*.qsb' "$src/" "$dest/"
        find "$dest" -type f -print0 | while IFS= read -r -d '' f; do scrub "$f"; done
    else
        mkdir -p "$(dirname "$dest")"
        cp -L "$src" "$dest"
        scrub "$dest"
    fi
}

echo "==> home"
# home/ also holds templates for user-owned files, so only listed paths are replaced.
grep -vE '^\s*(#|$)' "$repo/scripts/manifest-home.txt" | while read -r path; do
    if [ -e "$HOME/$path" ]; then copy_tree "$HOME/$path" "$repo/home/$path"
    else echo "  missing: ~/$path"; fi
done

echo "==> system (needs sudo to read some files)"
# system/ holds only captured files.
rm -rf "$repo/system"
grep -vE '^\s*(#|$)' "$repo/scripts/manifest-system.txt" | while read -r group path; do
    dest="$repo/system/$group$path"
    mkdir -p "$(dirname "$dest")"
    if sudo test -e "$path"; then
        # Only reading needs root; the repo copy belongs to you.
        # shellcheck disable=SC2024
        sudo cat "$path" > "$dest"
        [ -x "$path" ] && chmod +x "$dest"
        scrub "$dest"
    else echo "  missing: $path"; fi
done
chmod -R u+rwX,go+rX "$repo/home" "$repo/system"
echo "Done. Review with: git -C '$repo' status"
