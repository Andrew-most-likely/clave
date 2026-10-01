# The personal option (PROJECT_PLAN.md BR-10): ./install.sh --personal swaps
# the public fonts and cursor for the ones in packages/personal-aur.txt, which
# the user installs from the AUR, and Clave's app icons for WhiteSur's (BR-12).
# It changes assets only, never wording. The
# logo and sounds need no switch: the user's own files in ~/.config/clave/
# branding/ and ~/.local/share/sounds/clave/source/ are used when present.
# Sourced by lib/common.sh and scripts/system.sh.
# shellcheck shell=bash

# personal_on HOME: was --personal chosen for this home?
personal_on() { [ -e "$1/.local/state/clave/personal" ]; }

# personal_fill FILE: rewrite one installed text file for the personal build.
personal_fill() {
    grep -Iq . "$1" || return 0
    sed -i -e 's/Inter Display/SF Pro Display/g' -e 's/\bInter\b/SF Pro Text/g' \
        -e 's/JetBrains Mono/SF Mono/g' -e 's/Bibata-Modern-Classic/macOS/g' \
        -E -e 's/(gtk-icon-theme-name=|icon_theme=|icon-theme: *"|"icons": ")Clave-icons/\1WhiteSur/g' "$1"
}
