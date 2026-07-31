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

# rofi falls back to its default theme rather than failing, so the exit status
# says nothing; the warning on stderr is the only evidence.
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
