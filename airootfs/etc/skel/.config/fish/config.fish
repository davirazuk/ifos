# IFOS fish config

set fish_greeting ""

# ── Prompt ───────────────────────────────────────────────────────────────────
function fish_prompt
    set_color blue
    echo -n (prompt_pwd)
    set_color normal
    echo -n " λ "
end

# ── Aliases ──────────────────────────────────────────────────────────────────
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias grep='grep --color=auto'
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'
alias update='sudo pacman -Syu'
alias install='sudo pacman -S'
alias search='pacman -Ss'
alias apps='ifos-software'

# ── Environment ──────────────────────────────────────────────────────────────
# Session-wide values live in ~/.xprofile; these cover terminal-launched apps.
set -x EDITOR vim
set -x VISUAL vim
set -x QT_QPA_PLATFORMTHEME qt5ct

# ── Greeting ─────────────────────────────────────────────────────────────────
if status is-interactive; and type -q fastfetch
    fastfetch
end
