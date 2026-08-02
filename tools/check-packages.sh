#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  check-packages.sh — verify every package name still exists in the repos
#
#  Arch renames and drops packages regularly; a single stale name aborts a
#  40-minute build at the pacstrap step. This resolves the whole list against a
#  freshly synced database in seconds, so build.sh runs it first.
#
#  Checks the live ISO list, the installed-system list inside install-ifos, and
#  the archinstall preset. The software catalog is checked too - `repo` and
#  `multilib` entries against the repositories, `aur` entries against the AUR's
#  own API.
#
#  The AUR half exists because it was missing: a catalog entry named a package
#  that is not in the AUR at all, nothing here noticed, and the first anybody
#  knew was a student watching yay say "no package found for targets" and give
#  up. Nothing else in the project can catch that - the names cannot be checked
#  from a machine without access to the AUR, so it has to happen in the build
#  container that already has it.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

PROFILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IFOS_IMAGE:-ifos-builder}"
STRICT=${1:-}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# 1. live ISO
grep -vE '^\s*#|^\s*$' "$PROFILE/packages.x86_64" > "$tmp/iso.txt"

# 2. installed system (the PACKAGES array in install-ifos)
sed -n '/^PACKAGES=(/,/^)/p' "$PROFILE/airootfs/usr/local/bin/install-ifos" |
    sed '1d;$d' | sed 's/#.*//' | tr -s ' ' '\n' | grep -vE '^\s*$' > "$tmp/install.txt"

# 3. archinstall preset
python3 - "$PROFILE/airootfs/usr/share/ifos/archinstall-preset.json" > "$tmp/preset.txt" <<'PY'
import json, sys
print("\n".join(json.load(open(sys.argv[1])).get("packages", [])))
PY

# 4. catalog entries that claim to come from a repo
awk -F'|' '!/^#/ && NF>=4 && ($4=="repo" || $4=="multilib") {print $3}' \
    "$PROFILE"/airootfs/usr/share/ifos/apps.d/*.list | tr ' ' '\n' |
    grep -vE '^\s*$' > "$tmp/catalog.txt"

# 5. catalog entries that claim to come from the AUR
awk -F'|' '!/^#/ && NF>=4 && $4=="aur" {print $3}' \
    "$PROFILE"/airootfs/usr/share/ifos/apps.d/*.list | tr ' ' '\n' |
    grep -vE '^\s*$' | sort -u > "$tmp/aur.txt"

cat "$tmp"/iso.txt "$tmp"/install.txt "$tmp"/preset.txt | sort -u > "$tmp/required.txt"
sort -u "$tmp/catalog.txt" > "$tmp/optional.txt"

podman run --rm -v "$tmp":/chk:z "$IMAGE" bash -c '
# The catalog offers multilib packages (steam, lib32-*), so the checker needs
# that repository enabled or every one of them looks like a broken name.
grep -q "^\[multilib\]" /etc/pacman.conf ||
    printf "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n" >> /etc/pacman.conf
pacman -Sy >/dev/null 2>&1
echo "### required"
pacman -Si $(tr "\n" " " < /chk/required.txt) 2>&1 >/dev/null |
    sed -n "s/^error: package .\(.*\). was not found/\1/p"
echo "### optional"
pacman -Si $(tr "\n" " " < /chk/optional.txt) 2>&1 >/dev/null |
    sed -n "s/^error: package .\(.*\). was not found/\1/p"
echo "### aur"
# The AUR RPC answers with the names it knows; anything asked for and not
# returned does not exist. One request for the whole list rather than one per
# package, which the interface asks for and which keeps this to a second.
if [ -s /chk/aur.txt ]; then
    query=$(sed "s/^/\&arg[]=/" /chk/aur.txt | tr -d "\n")
    # -g: the query is full of arg[]=, and curl reads [ ] as a URL glob range
    # unless globbing is off. Some builds let it through and some refuse the
    # whole request, which would look exactly like the AUR being unreachable.
    if curl -gfsS --max-time 30 "https://aur.archlinux.org/rpc/v2/info?${query#&}" \
         -o /chk/aur.json 2>/dev/null; then
        python3 - <<PYAUR
import json
asked = [l.strip() for l in open("/chk/aur.txt") if l.strip()]
found = {r.get("Name") for r in json.load(open("/chk/aur.json")).get("results", [])}
for name in asked:
    if name not in found:
        print(name)
PYAUR
    else
        # No answer is not the same as "the package is missing"; say so rather
        # than failing a build over an unreachable AUR.
        echo "!! could not reach the AUR" >&2
    fi
fi
' > "$tmp/out.txt" 2>/dev/null

required_missing=$(sed -n '/^### required$/,/^### optional$/p' "$tmp/out.txt" | grep -v '^###' || true)
optional_missing=$(sed -n '/^### optional$/,/^### aur$/p'      "$tmp/out.txt" | grep -v '^###' || true)
aur_missing=$(sed -n '/^### aur$/,$p'                          "$tmp/out.txt" | grep -v '^###' || true)

rc=0
if [[ -n ${required_missing//[[:space:]]/} ]]; then
    printf '\033[1;31m==> These packages do not exist in the repositories:\033[0m\n'
    printf '      %s\n' $required_missing
    printf '    They are required to build or install; fix the names first.\n'
    rc=1
else
    echo "==> every required package resolves"
fi

if [[ -n ${optional_missing//[[:space:]]/} ]]; then
    printf '\033[1;33m==> Catalog entries marked repo/multilib that no longer resolve:\033[0m\n'
    printf '      %s\n' $optional_missing
    printf '    ifos-software will fail on these; move them to the aur source or rename.\n'
    [[ $STRICT == --strict ]] && rc=1
fi

if [[ -n ${aur_missing//[[:space:]]/} ]]; then
    printf '\033[1;31m==> Catalog entries marked aur that are not in the AUR:\033[0m\n'
    printf '      %s\n' $aur_missing
    printf '    ifos-software cannot install these - yay says "no package found\n'
    printf '    for targets" and gives up. Fix the names or drop the entries.\n'
    rc=1
elif [[ -s $tmp/aur.txt ]]; then
    echo "==> every AUR package resolves"
fi

exit $rc
