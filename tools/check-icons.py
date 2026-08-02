#!/usr/bin/env python3
"""Fail if anything that should carry an icon carries a space instead.

This exists because the same bug shipped three separate times:

  * every format-prefix in polybar's config.ini was a string of spaces, so the
    launcher button, calendar, CPU, RAM, volume and power icons were all blank;
  * nine of fastfetch's thirteen keys were a bare space, while four had icons,
    which made the missing ones look like a deliberately plain style;
  * every icon in the on-screen display and the power menu was an empty string.

None of it is visible in a diff - "  " and " " look identical - and none of it
breaks anything, so nothing complains. The only way to catch it is to go
looking, which is what this does.

    python3 tools/check-icons.py [--list]

Exits non-zero if any known icon slot is glyph-free.
"""
from __future__ import annotations

import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "airootfs")


def is_glyph(ch: str) -> bool:
    """Private use area: where both Nerd Fonts and Font Awesome live."""
    return 0xE000 <= ord(ch) <= 0xF8FF or 0xF0000 <= ord(ch) <= 0xFFFFD


# (path, description, regex whose group(1) is the string that needs a glyph)
#
# Each pattern is deliberately narrow. A rule that matched every quoted string
# would flag the labels, the colours and the commands too, and a check that
# cries wolf is one nobody runs.
SLOTS = [
    ("etc/skel/.config/polybar/config.ini", "bar icon",
     re.compile(r'^\s*(?:format|format-prefix|format-volume-prefix|'
                r'format-muted-prefix)\s*=\s*"([^"]*)"', re.M)),
    ("etc/skel/.config/fastfetch/config.jsonc", "fastfetch key",
     re.compile(r'"key"\s*:\s*"([^"]*)"')),
    ("etc/skel/.config/i3/scripts/osd.sh", "on-screen display icon",
     re.compile(r'^ICON_\w+=\'([^\']*)\'', re.M)),
    ("etc/skel/.config/rofi/powermenu.sh", "power menu entry",
     re.compile(r'^(?:lock|logout|suspend|reboot|shutdown)="([^"]*)"', re.M)),
]

# Files whose icons are inline in printf strings rather than in a named slot.
# A count is the honest check there: naming every one would mean a regex per
# line, and the failure being guarded against is "they all vanished", not
# "this particular one changed".
COUNTS = [
    ("etc/skel/.config/polybar/scripts/battery.sh", 6),
    ("etc/skel/.config/polybar/scripts/bluetooth.sh", 3),
    ("etc/skel/.config/polybar/scripts/network.sh", 4),
    ("etc/skel/.config/polybar/scripts/media.sh", 2),
    ("etc/skel/.config/polybar/scripts/power-profile.sh", 4),
    ("etc/skel/.config/rofi/network-menu.sh", 4),
    ("etc/skel/.config/rofi/bluetooth-menu.sh", 4),
    ("etc/skel/.config/i3/scripts/battery-watch.sh", 2),
    ("etc/skel/.config/i3/scripts/disk-watch.sh", 1),
]

# The console has no Nerd Font at all (ter-116n), so an icon there is a blank
# box. This file must contain none.
NO_GLYPHS = ["root/.config/fastfetch/config.jsonc"]


def main() -> int:
    listing = "--list" in sys.argv
    problems = []
    checked = 0

    for rel, what, pattern in SLOTS:
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            problems.append("%s: missing" % rel)
            continue
        text = open(path, encoding="utf-8").read()
        found = pattern.findall(text)
        if not found:
            problems.append("%s: no %s slots matched - has the file changed shape?"
                            % (rel, what))
            continue
        for value in found:
            checked += 1
            if not any(is_glyph(c) for c in value):
                problems.append("%s: %s is blank: %r" % (rel, what, value))
            elif listing:
                print("  %-46s %s  %s" % (rel, " ".join(
                    "U+%04X" % ord(c) for c in value if is_glyph(c)), value.strip()))

    for rel, least in COUNTS:
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            problems.append("%s: missing" % rel)
            continue
        n = sum(1 for c in open(path, encoding="utf-8").read() if is_glyph(c))
        checked += 1
        if n < least:
            problems.append("%s: %d glyphs, expected at least %d" % (rel, n, least))
        elif listing:
            print("  %-46s %d glyphs" % (rel, n))

    for rel in NO_GLYPHS:
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            continue
        n = sum(1 for c in open(path, encoding="utf-8").read() if is_glyph(c))
        checked += 1
        if n:
            problems.append("%s: %d glyph(s), but this renders on the Linux "
                            "console where they are blank boxes" % (rel, n))

    if problems:
        print("icons: %d problem(s)" % len(problems))
        for p in problems:
            print("  !! %s" % p)
        return 1
    print("==> icons: %d slots checked, all present" % checked)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
