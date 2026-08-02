#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  repair-dotfiles.sh — repair known-broken files in a home directory
#
#      repair-dotfiles.sh              repair the account running it
#      repair-dotfiles.sh --check      say what is broken, change nothing
#      repair-dotfiles.sh --all-users  repair every account in /home (as root)
#      repair-dotfiles.sh --home DIR   repair one specific home directory
#
#  /etc/skel only seeds *new* accounts. A fix to the shipped defaults therefore
#  never reaches a machine that is already set up - the copy in $HOME keeps the
#  bug forever. ifos-update runs this afterwards to close that gap.
#
#  Every repair here is narrow, idempotent and keeps the colours the account is
#  currently running, so it is safe to run at any time. That is the difference
#  from `ifos-update --dotfiles`, which replaces ~/.config wholesale and hands
#  back the default look.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

c_reset=$'\033[0m'; c_grn=$'\033[1;32m'; c_yel=$'\033[1;33m'; c_blue=$'\033[1;34m'
info()  { printf '%s==>%s %s\n' "$c_blue" "$c_reset" "$*"; }
fixed() { printf '%s  ✓%s %s\n' "$c_grn"  "$c_reset" "$*"; FIXED=$((FIXED + 1)); }
found() { printf '%s  !%s %s\n' "$c_yel"  "$c_reset" "$*"; FOUND=$((FOUND + 1)); }

CHECK=0
ALL_USERS=0
HOMES=()

while (( $# )); do
    case $1 in
        -h|--help)   sed -n '3,17p' "$0" | sed 's/^# \?//'; exit 0 ;;
        --check)     CHECK=1 ;;
        --all-users) ALL_USERS=1 ;;
        --home)      shift; HOMES+=("${1:-}") ;;
        *) echo "repair-dotfiles: unknown option '$1' (try --help)" >&2; exit 1 ;;
    esac
    shift
done

FOUND=0
FIXED=0

# Editing another user's file as root must not hand it to root.
edit() {    # edit <file> <sed-expression>
    local file=$1 expr=$2 owner
    owner=$(stat -c '%u:%g' "$file" 2>/dev/null)
    sed -i "$expr" "$file" || return 1
    [[ -n $owner ]] && chown "$owner" "$file" 2>/dev/null
    return 0
}

# ── Repair: rofi refuses to parse the whole theme ────────────────────────────
#  rofi's grammar wants a literal colour after `highlight`, not an @property
#  reference. The theme shipped `highlight: bold @mauve;`, and a single bad
#  property makes rofi throw the entire file away: "failed to parse theme", and
#  the menu comes back in rofi's stock black-and-white look.
rofi_highlight() {
    local rasi="$1/.config/rofi/ifos.rasi" var hex
    [[ -f $rasi ]] || return 0
    grep -qE '^[[:space:]]*highlight:[^;]*@' "$rasi" || return 0

    found "$rasi — 'highlight' points at an @property, which rofi cannot parse"
    (( CHECK )) && return 0

    # Resolve the variable to the hex it holds, so the current palette survives.
    var=$(sed -n 's/^[[:space:]]*highlight:[^;]*@\([A-Za-z0-9_-]\{1,\}\).*/\1/p' "$rasi" | head -1)
    hex=""
    [[ -n $var ]] &&
        hex=$(sed -n "s/^[[:space:]]*$var:[[:space:]]*\(#[0-9A-Fa-f]\{3,8\}\)[[:space:]]*;.*/\1/p" \
              "$rasi" | head -1)

    if [[ -n $hex ]]; then
        edit "$rasi" "/^[[:space:]]*highlight:/ s/@$var\\b/$hex/" &&
            fixed "rofi theme: highlight now uses $hex (was @$var)"
    else
        # Nothing to resolve it to; keep the styles and drop the colour.
        edit "$rasi" "/^[[:space:]]*highlight:/ s/[[:space:]]*@[A-Za-z0-9_-]\\{1,\\}//" &&
            fixed "rofi theme: dropped the unresolvable colour from highlight"
    fi
}

# ── Repair: fastfetch still shows the Arch logo ──────────────────────────────
#  The logo moved from the built-in "arch" art to the IFOS wordmark in
#  /usr/share/ifos/logo.txt. branding-sync updates /etc/skel, but a home
#  directory created before that keeps its own copy - so the machine goes on
#  introducing itself as Arch in every new terminal.
fastfetch_logo() {
    local cfg="$1/.config/fastfetch/config.jsonc"
    [[ -f $cfg ]] || return 0
    [[ -f /usr/share/ifos/logo.txt ]] || return 0
    grep -qE '"source"[[:space:]]*:[[:space:]]*"arch"' "$cfg" || return 0

    found "$cfg — fastfetch is still drawing the Arch logo"
    (( CHECK )) && return 0

    # Narrow edits: the logo source and the two colours that feed its $1/$2
    # placeholders. Everything else in the file - modules, keys, ordering - is
    # whatever the account chose.
    edit "$cfg" '
        s|"type"[[:space:]]*:[[:space:]]*"builtin"|"type": "file"|
        s|"source"[[:space:]]*:[[:space:]]*"arch"|"source": "/usr/share/ifos/logo.txt"|
        s|"1"[[:space:]]*:[[:space:]]*"blue"|"1": "green"|
        s|"2"[[:space:]]*:[[:space:]]*"cyan"|"2": "white"|
    ' && fixed "fastfetch now uses the IFOS logo"
}

# rofi falls back to its default theme rather than failing, so the exit status
# says nothing; the warning on stderr is the only evidence.
# ── Repair: files that are new, and so cannot have been customised ───────────
#  The repairs above mend a file the account already has. This one covers the
#  opposite case: a file added to /etc/skel after the account was created. It
#  has no counterpart in $HOME to conflict with, so copying it in cannot lose
#  anything the user chose - the account simply never had the chance to have it.
#
#  gtk-4.0/gtk.css is the one that matters today. libadwaita ignores
#  gtk-theme-name entirely, so without this file every GTK4 application - the
#  newer file chooser, the colour and font dialogs - keeps Adwaita's blue while
#  the rest of the desktop is green.
#
#  Only files whose absence is itself the bug belong here. Anything the user
#  may have edited stays the business of `ifos-update --dotfiles`.
NEW_FILES=(
    .config/gtk-4.0/gtk.css
    .config/i3/scripts/screens.sh
    .config/i3/scripts/gpu-watch.sh
    .config/Thunar/thunarrc
    .config/Thunar/uca.xml
    .config/rofi/notifications.sh
    .config/polybar/scripts/notifications.sh
)

missing_new_files() {
    local home=$1 rel src dst owner
    for rel in "${NEW_FILES[@]}"; do
        src="/etc/skel/$rel"
        dst="$home/$rel"
        [[ -f $src ]] || continue
        [[ -e $dst ]] && continue

        found "$dst is missing (added to IFOS after this account was created)"
        (( CHECK )) && continue

        install -d "$(dirname "$dst")" 2>/dev/null || continue
        if cp -a "$src" "$dst" 2>/dev/null; then
            # Root repairing somebody else's home must not leave root's file
            # behind; match the ownership of the home directory itself.
            owner=$(stat -c '%u:%g' "$home" 2>/dev/null)
            [[ -n $owner ]] && chown "$owner" "$dst" 2>/dev/null
            fixed "installed $rel"
        fi
    done
}

# ── Repair: a new autostart that no existing i3 config knows about ───────────
#  Copying a script into ~/.config/i3/scripts/ is half the job; something has to
#  start it. The i3 config in $HOME is the one file nobody should overwrite -
#  it is where people put their own keybindings - so this adds the single line
#  and nothing else, anchored next to the autostarts it belongs with.
#
#  Keyed on the script path, so running twice adds nothing the second time.
# Written with a literal tilde because that is what goes into the i3 config;
# i3 expands it, and the check below expands it against the home being repaired
# rather than against whoever is running this - which is root, under
# --all-users.
# shellcheck disable=SC2088  # the literal tilde is the point; see above
I3_EXECS=(
    '~/.config/i3/scripts/gpu-watch.sh'
)

i3_new_execs() {
    local home=$1
    local cfg="$home/.config/i3/config"
    local script anchor
    [[ -f $cfg ]] || return 0

    for script in "${I3_EXECS[@]}"; do
        grep -qF "$script" "$cfg" && continue
        # Only if the script is actually there to be started; missing_new_files
        # runs first, so on a repaired account it is.
        [[ -x ${script/#\~/$home} ]] || continue

        found "$cfg does not start $(basename "$script")"
        (( CHECK )) && continue

        # After the last autostart line, so it sits with the others rather than
        # at the end of the file, where a mode block might swallow it.
        anchor=$(grep -n '^exec --no-startup-id' "$cfg" | tail -1 | cut -d: -f1)
        [[ -n $anchor ]] || continue

        edit "$cfg" "${anchor}a\\
exec --no-startup-id $script" &&
            fixed "i3 now starts $(basename "$script") at login"
    done
}

verify_rofi() {
    local rasi="$1/.config/rofi/ifos.rasi"
    [[ -f $rasi ]] || return 0
    command -v rofi >/dev/null || return 0
    if rofi -no-config -theme "$rasi" -dump-theme 2>&1 >/dev/null |
       grep -q 'Failed to parse'; then
        found "rofi still cannot parse $rasi — please report this"
    fi
}

repair_home() {
    local home=$1
    [[ -d $home ]] || return 0
    rofi_highlight "$home"
    fastfetch_logo "$home"
    missing_new_files "$home"
    i3_new_execs "$home"
    (( CHECK )) || verify_rofi "$home"
}

# ── Which homes ──────────────────────────────────────────────────────────────
if (( ALL_USERS )); then
    for h in /home/*; do
        [[ -d $h ]] && HOMES+=("$h")
    done
elif (( ${#HOMES[@]} == 0 )); then
    HOMES=("${HOME:-/root}")
fi

(( ${#HOMES[@]} )) || { echo "repair-dotfiles: no home directory to repair" >&2; exit 1; }

for h in "${HOMES[@]}"; do
    repair_home "$h"
done

if (( FOUND == 0 )); then
    info "Nothing to repair."
elif (( CHECK )); then
    info "$FOUND item(s) to repair. Run without --check to fix them."
else
    info "Repaired $FIXED of $FOUND item(s)."
    info "Nothing to restart: rofi reads its theme each time it opens."
fi
