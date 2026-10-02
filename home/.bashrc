#
# ~/.bashrc
#
# Installed once by Clave and then yours: Clave never replaces this file.
# Clave's own setup (aliases, prompt, the terminal logo) is in
# ~/.local/share/clave/clave.bash, which Clave updates.

[[ $- != *i* ]] && return

# shellcheck source=/dev/null
[ -f ~/.local/share/clave/clave.bash ] && . ~/.local/share/clave/clave.bash

# Your own settings go here.


# zoxide (extras) must be set up last.
command -v zoxide >/dev/null && eval "$(zoxide init bash)"
