# Optional: source this from ~/.bashrc for the Apple logo in fastfetch.
# fastfetch draws the Apple logo as an image, which only kitty can show.
# - Other terminals (text console, VS Code, ...) get the built-in text Apple.
# - Kitty windows under 90 columns are too narrow for logo + info side by side
#   (long lines wrap into the logo), and fastfetch's own "logo on top" mode
#   misplaces the box border. So there the logo is drawn above the info with
#   kitten icat, scaled to 8 text rows of the current font size.
fastfetch() {
    if [[ -z "$KITTY_WINDOW_ID" ]]; then
        command fastfetch --logo macos --logo-type builtin "$@"
        return
    fi
    local cols=${COLUMNS:-$(tput cols)} lines=${LINES:-$(tput lines)}
    if (( cols >= 90 )) || (( $# > 0 )); then
        command fastfetch "$@"
        return
    fi
    local src="$HOME/.config/fastfetch/assets/apple-rainbow.png" size h px img
    size=$(kitten icat --print-window-size 2>/dev/null)   # e.g. 930x1140
    h=${size#*x}
    if [[ "$h" =~ ^[0-9]+$ ]] && (( lines > 0 )); then
        px=$(( h * 8 / lines ))
        img="$HOME/.cache/fastfetch/apple-rainbow-$px.png"
        if [[ ! -f "$img" ]]; then
            mkdir -p "${img%/*}"
            magick "$src" -resize "x$px" "$img" 2>/dev/null || img="$src"
        fi
        echo
        kitten icat --align left --stdin no "$img"
        command fastfetch --logo none
    else
        command fastfetch --logo-position top
    fi
}
