# IFOS shell environment.
# conf.d is sourced before config.fish, and every file here is loaded
# automatically — drop your own file in beside this one rather than editing it.

# ── Colours (Catppuccin-ish, tuned to the IFOS green) ────────────────────────
set -g fish_color_normal        cdd6f4
set -g fish_color_command       00a86b
set -g fish_color_keyword       cba6f7
set -g fish_color_quote         a6e3a1
set -g fish_color_redirection   7ed957
set -g fish_color_end           f9e2af
set -g fish_color_error         f38ba8
set -g fish_color_param         cdd6f4
set -g fish_color_comment       6c8f80
set -g fish_color_operator      94e2d5
set -g fish_color_autosuggestion 45604f
set -g fish_color_search_match  --background=14503f
set -g fish_pager_color_prefix  00a86b --bold
set -g fish_pager_color_completion cdd6f4
set -g fish_pager_color_description 6c8f80
set -g fish_pager_color_selected_background --background=14503f

# ── Abbreviations (expand as you type, so you still learn the real command) ──
if status is-interactive
    abbr -a -- g      git
    abbr -a -- gs     'git status --short --branch'
    abbr -a -- ga     'git add'
    abbr -a -- gaa    'git add --all'
    abbr -a -- gc     'git commit -m'
    abbr -a -- gp     'git push'
    abbr -a -- gl     'git pull'
    abbr -a -- glog   'git log --oneline --graph --decorate'
    abbr -a -- gd     'git diff'

    abbr -a -- pi     'sudo pacman -S'
    abbr -a -- pr     'sudo pacman -Rns'
    abbr -a -- ps-    'pacman -Ss'
    abbr -a -- pu     'sudo pacman -Syu'
    abbr -a -- pq     'pacman -Q'

    abbr -a -- sys    systemctl
    abbr -a -- sysu   'systemctl --user'
    abbr -a -- jc     'journalctl -xe'

    abbr -a -- ..     'cd ..'
    abbr -a -- ...    'cd ../..'
    abbr -a -- ....   'cd ../../..'
end

# ── Aliases ──────────────────────────────────────────────────────────────────
alias ls='ls --color=auto --group-directories-first'
alias ll='ls -lah --color=auto --group-directories-first'
alias la='ls -A --color=auto'
alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias ip='ip -color=auto'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'
alias apps='ifos-software'
alias launcher='ifos-launcher'
alias moodle='ifos-launcher --category escola-online'

# ── Environment ──────────────────────────────────────────────────────────────
set -gx EDITOR vim
set -gx VISUAL vim
set -gx QT_QPA_PLATFORMTHEME qt5ct
set -gx MANROFFOPT -c
set -gx LESS '-R --use-color'

fish_add_path -g ~/.local/bin 2>/dev/null

# ── Keys ─────────────────────────────────────────────────────────────────────
if status is-interactive
    # Ctrl+F accepts the autosuggestion, like a shell should
    bind \cf forward-char
    bind \ce edit_command_buffer
end
