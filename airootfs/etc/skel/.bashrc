#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias grep='grep --color=auto'
alias update='sudo pacman -Syu'
alias install='sudo pacman -S'
alias search='pacman -Ss'

PS1='[\u@\h \W]\$ '

# Qt applications follow the same dark theme as GTK ones.
# Session-wide values live in ~/.xprofile; these cover terminal-launched apps.
export QT_QPA_PLATFORMTHEME=qt5ct
export EDITOR=vim
export VISUAL=vim

[[ -f /usr/share/bash-completion/bash_completion ]] && . /usr/share/bash-completion/bash_completion

command -v fastfetch >/dev/null && fastfetch
