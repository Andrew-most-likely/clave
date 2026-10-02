# Clave's bash setup, loaded by ~/.bashrc. Clave updates this file; put your
# own settings in ~/.bashrc after the line that loads it.
# Tools from packages/extras.txt (eza, bat, fzf, zoxide, starship) are used
# when they are installed.

[[ $- == *i* ]] || return 0

case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$PATH:$HOME/.local/bin" ;; esac
export PATH

HISTSIZE=10000
HISTCONTROL=ignoreboth
shopt -s histappend checkwinsize

# --- aliases ---------------------------------------------------------------
alias grep='grep --color=auto'
alias ..='cd ..'
alias c='clear'
alias ff='fastfetch'
if command -v eza >/dev/null; then
    alias ls='eza -a --icons=always'
    alias ll='eza -al --icons=always'
    alias lt='eza -a --tree --level=1 --icons=always'
else
    alias ls='ls --color=auto'
    alias ll='ls -al --color=auto'
fi
alias wifi='nmtui'
alias lock='clave-power -l'
alias apps='clave-apps'
alias search='clave-search'
alias settings='qs ipc call settings open general'
alias screenshot='qs ipc call screenshot toolbar'
alias wallpaper='clave-wallpaper'
alias updates='clave-update --here'

# --- prompt ----------------------------------------------------------------
if command -v starship >/dev/null; then
    eval "$(starship init bash)"
else
    PS1='\[\e[1;34m\]\W\[\e[0m\] \$ '
fi
[ -f /usr/share/bash-completion/bash_completion ] && . /usr/share/bash-completion/bash_completion
command -v fzf >/dev/null && eval "$(fzf --bash)"

# A new terminal window shows the Clave logo and system info. Set
# CLAVE_FASTFETCH=0 before this file is loaded to turn it off.
if [[ ${CLAVE_FASTFETCH:-1} != 0 && $(tty) == /dev/pts/* ]] && command -v fastfetch >/dev/null; then
    fastfetch
fi
