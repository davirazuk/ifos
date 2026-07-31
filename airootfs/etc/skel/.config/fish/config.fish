# IFOS — fish configuration
#
# Most of the setup lives in conf.d/ifos.fish (colours, abbreviations, aliases,
# environment) and functions/ (prompt, `ifos` command, helpers). This file is
# yours to change.

set fish_greeting ""

if status is-interactive
    # System information on a new terminal, IFOS style.
    if type -q fastfetch
        fastfetch
    end
end
