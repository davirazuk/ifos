# IFOS prompt — two lines, so long paths never squeeze what you are typing.
#
#   ╭─ ifos ~/projeto  main ●  1.2s
#   ╰─λ

function fish_prompt --description 'IFOS prompt'
    set -l last_status $status

    set -l ifos_green   (set_color 00a86b)
    set -l ifos_light   (set_color 7ed957)
    set -l ifos_text    (set_color cdd6f4)
    set -l ifos_dim     (set_color 6c8f80)
    set -l ifos_red     (set_color f38ba8)
    set -l ifos_yellow  (set_color f9e2af)
    set -l reset        (set_color normal)

    # ── top line ─────────────────────────────────────────────────────────────
    echo -n -s $ifos_dim '╭─ ' $reset

    if set -q SSH_CONNECTION
        echo -n -s $ifos_yellow (whoami) '@' (prompt_hostname) ' ' $reset
    else
        echo -n -s $ifos_light (whoami) ' ' $reset
    end

    echo -n -s $ifos_text (prompt_pwd) ' ' $reset

    # git branch and whether the tree is dirty
    if command -sq git
        set -l branch (command git symbolic-ref --short HEAD 2>/dev/null; or command git rev-parse --short HEAD 2>/dev/null)
        if test -n "$branch"
            echo -n -s $ifos_green ' ' $branch $reset
            if not command git diff-index --quiet HEAD -- 2>/dev/null
                echo -n -s $ifos_yellow ' ●' $reset
            end
        end
    end

    # how long the last command took, when it was slow enough to care
    if test $CMD_DURATION -gt 2000
        echo -n -s $ifos_dim '  ' (math -s1 $CMD_DURATION/1000) 's' $reset
    end

    echo

    # ── bottom line ──────────────────────────────────────────────────────────
    echo -n -s $ifos_dim '╰─' $reset
    if test $last_status -ne 0
        echo -n -s $ifos_red 'λ ' $reset
    else
        echo -n -s $ifos_green 'λ ' $reset
    end
end
