#!/usr/bin/env python3
"""Generate IFOS artwork: wallpapers, the SDDM background and the boot logo.

    python3 tools/gen-artwork.py [--out AIROOTFS]

Two palettes are produced:
    ifms   institutional green - the default, IFOS is built for students at
           IFMS Campus Dourados
    mocha  the Catppuccin Mocha palette the desktop is themed around

Everything is drawn on an RGBA canvas and composited, so alpha actually does
something. The earlier version drew RGBA fills straight onto an RGB image,
where PIL silently discards the alpha channel and "subtle" grid lines came out
fully opaque.
"""
from __future__ import annotations

import argparse
import math
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
except ImportError:
    sys.exit("Pillow is required:  pip install --user Pillow")

W, H = 1920, 1080

PALETTES = {
    "mocha": {
        "crust": (17, 17, 27),
        "base": (30, 30, 46),
        "surface": (49, 50, 68),
        "accent": (137, 180, 250),      # blue
        "accent2": (203, 166, 247),     # mauve
        "accent3": (180, 190, 254),     # lavender
        "text": (205, 214, 244),
        "caption": "IFOS Linux",
    },
    "ifms": {
        "crust": (5, 26, 20),
        "base": (10, 46, 35),
        "surface": (20, 74, 56),
        "accent": (0, 168, 107),        # institutional green
        "accent2": (126, 217, 87),      # light green
        "accent3": (232, 245, 233),     # near-white
        "text": (232, 245, 233),
        "caption": "IFMS · Campus Dourados",
    },
}

# Pixel-art glyphs, five rows tall, so no font file is needed for the wordmark.
#
# The blocks are drawn with a gutter between them, which means a stroke only
# reads as a stroke where blocks touch edge to edge - diagonally adjacent
# blocks read as two separate dots. The S used to have a middle bar of
# `.XX.` that touched nothing: the left stroke above it and the right stroke
# below it were both diagonal neighbours, so at wallpaper size the letter came
# apart into scattered squares and looked more like a 5 with a piece missing.
# Its middle bar spans the full width now, so it meets the stroke above on the
# left and the one below on the right.
GLYPHS = {
    "I": [(1, 0), (1, 1), (1, 2), (1, 3), (1, 4), (0, 0), (2, 0), (0, 4), (2, 4)],
    "F": [(0, 0), (1, 0), (2, 0), (0, 1), (0, 2), (1, 2), (0, 3), (0, 4)],
    "O": [(1, 0), (2, 0), (0, 1), (3, 1), (0, 2), (3, 2), (0, 3), (3, 3), (1, 4), (2, 4)],
    "S": [(1, 0), (2, 0), (3, 0), (0, 1), (0, 2), (1, 2), (2, 2), (3, 2), (3, 3),
          (0, 4), (1, 4), (2, 4)],
}
# How many columns each glyph actually occupies. I and F are three wide; a
# fixed four-column advance left them floating with a blank column each, so
# "IF" sat noticeably looser than "OS" in the same word.
GLYPH_W = {ch: max(px for px, _py in cells) + 1 for ch, cells in GLYPHS.items()}
GLYPH_H = 5


def wordmark_colours(pal) -> dict[str, tuple[int, int, int]]:
    """IF in the institutional green, OS in the lighter one.

    Every piece of artwork used to colour the four letters
    accent / accent2 / accent3 / accent, which put a near-white O between two
    greens for no reason anyone could name - it read as a mistake rather than
    a design. Splitting it IF | OS matches how the mark is already stacked in
    the fastfetch logo, and it means the same two colours everywhere.
    """
    return {"I": pal["accent"], "F": pal["accent"],
            "O": pal["accent2"], "S": pal["accent2"]}


# Space between letters, in glyph columns. One column is barely wider than the
# gutter between two blocks inside a letter, which ran the four letters
# together into one shape; 1.6 reads as a word.
LETTER_GAP = 1.6


def draw_wordmark_glyphs(draw, chars: str, x0: int, y0: int, scale: int,
                         colours, gutter: int = 3, gap: float = LETTER_GAP,
                         shadow: tuple[int, int] | None = None) -> int:
    """Draw `chars` as pixel blocks. Returns the total width drawn.

    One implementation for the wallpaper, the boot logo, the BIOS splash and
    the GRUB background, which each had their own copy of this loop and had
    already drifted apart on spacing.
    """
    radius = max(1, scale // 6)
    passes = []
    if shadow is not None:
        passes.append((shadow[0], shadow[1], None))
    passes.append((0, 0, colours))

    for dx, dy, palette in passes:
        x = float(x0)
        for i, ch in enumerate(chars):
            for px, py in GLYPHS[ch]:
                left = round(x) + px * scale + dx
                top = y0 + py * scale + dy
                fill = (0, 0, 0, 110) if palette is None else (*palette[ch], 255)
                draw.rounded_rectangle(
                    [left, top, left + scale - gutter, top + scale - gutter],
                    radius=radius, fill=fill,
                )
            x += (GLYPH_W[ch] + gap) * scale
    return wordmark_width(chars, scale, gap)


def wordmark_width(chars: str, scale: int, gap: float = LETTER_GAP) -> int:
    return round((sum(GLYPH_W[c] for c in chars) + gap * (len(chars) - 1)) * scale)

FONT_CANDIDATES = [
    "/usr/share/fonts/jetbrains-mono-nerd/JetBrainsMonoNerdFont-Regular.ttf",
    "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf",
    "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/TTF/DejaVuSans.ttf",
    "/usr/share/fonts/liberation-sans/LiberationSans-Regular.ttf",
]


def load_font(size: int):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return None


def gradient(pal) -> Image.Image:
    img = Image.new("RGB", (W, H), pal["base"])
    d = ImageDraw.Draw(img)
    top, bottom = pal["crust"], pal["base"]
    for y in range(H):
        t = y / H
        d.line(
            [(0, y), (W, y)],
            fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)),
        )
    return img


def overlay_grid(img: Image.Image, pal) -> Image.Image:
    """Faint 60px grid. Drawn on its own RGBA layer so the alpha is honoured."""
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    colour = (*pal["surface"], 26)
    for x in range(0, W, 60):
        d.line([(x, 0), (x, H)], fill=colour)
    for y in range(0, H, 60):
        d.line([(0, y), (W, y)], fill=colour)
    return Image.alpha_composite(img.convert("RGBA"), layer)


def overlay_glows(img: Image.Image, pal) -> Image.Image:
    """Large blurred blobs of colour, blurred for real instead of faked with
    concentric ellipses."""
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    blobs = [
        (W // 3, H // 2, 300, (*pal["accent"], 70)),
        (2 * W // 3, H // 3, 240, (*pal["accent2"], 55)),
        (W // 2, 3 * H // 4, 200, (*pal["accent3"], 40)),
    ]
    for cx, cy, r, colour in blobs:
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=colour)
    layer = layer.filter(ImageFilter.GaussianBlur(150))
    return Image.alpha_composite(img, layer)


def overlay_rings(img: Image.Image, pal) -> Image.Image:
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for radius, alpha in ((220, 60), (300, 40), (380, 25)):
        d.ellipse(
            [W // 2 - radius, H // 2 - radius, W // 2 + radius, H // 2 + radius],
            outline=(*pal["surface"], alpha),
            width=2,
        )
    return Image.alpha_composite(img, layer)


def draw_wordmark(img: Image.Image, pal, scale: int = 26) -> Image.Image:
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    chars = "IFOS"
    total = wordmark_width(chars, scale)
    x0 = (W - total) // 2
    y0 = H // 2 - 2 * scale
    draw_wordmark_glyphs(d, chars, x0, y0, scale, wordmark_colours(pal), shadow=(4, 4))

    # Accent dots under the wordmark
    dots = [pal["accent"], pal["accent2"], pal["accent3"], pal["accent2"], pal["accent"]]
    for i, colour in enumerate(dots):
        x = W // 2 - 40 + i * 20
        y = y0 + 6 * scale + 12
        d.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(*colour, 255))

    font = load_font(30)
    if font:
        caption = pal["caption"]
        bbox = d.textbbox((0, 0), caption, font=font)
        d.text(
            ((W - (bbox[2] - bbox[0])) // 2, y0 + 6 * scale + 40),
            caption,
            font=font,
            fill=(*pal["text"], 190),
        )

    return Image.alpha_composite(img, layer)


def vignette(img: Image.Image) -> Image.Image:
    layer = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(layer)
    d.ellipse([-W // 3, -H // 3, W + W // 3, H + H // 3], fill=255)
    layer = layer.filter(ImageFilter.GaussianBlur(220))
    dark = Image.new("RGBA", (W, H), (0, 0, 0, 130))
    dark.putalpha(Image.eval(layer, lambda v: 130 - int(v * 130 / 255)))
    return Image.alpha_composite(img, dark)


def overlay_contours(img: Image.Image, pal) -> Image.Image:
    """Concentric rounded contours, like a topographic map, very faint.

    Something for the eye to find in the corners without competing with the
    wordmark or making icons hard to pick out. Drawn as a set of ellipses on
    one alpha layer and blurred slightly so the lines do not alias.
    """
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = int(W * 0.78), int(H * 0.28)
    for i in range(14):
        rx = 120 + i * 105
        ry = 90 + i * 78
        alpha = max(0, 30 - i * 2)
        d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry],
                  outline=(*pal["accent"], alpha), width=2)
    cx2, cy2 = int(W * 0.16), int(H * 0.82)
    for i in range(10):
        rx = 100 + i * 95
        ry = 80 + i * 70
        alpha = max(0, 22 - i * 2)
        d.ellipse([cx2 - rx, cy2 - ry, cx2 + rx, cy2 + ry],
                  outline=(*pal["accent2"], alpha), width=2)
    layer = layer.filter(ImageFilter.GaussianBlur(1.2))
    return Image.alpha_composite(img, layer)


def wallpaper(name: str) -> Image.Image:
    pal = PALETTES[name]
    img = gradient(pal)
    img = overlay_grid(img, pal)
    img = overlay_glows(img, pal)
    img = overlay_contours(img, pal)
    img = overlay_rings(img, pal)
    img = draw_wordmark(img, pal)
    img = vignette(img)
    return img.convert("RGB")


def boot_logo(name: str) -> Image.Image:
    """Transparent wordmark for the Plymouth splash."""
    pal = PALETTES[name]
    scale = 18
    chars = "IFOS"
    width = wordmark_width(chars, scale)
    height = GLYPH_H * scale
    img = Image.new("RGBA", (width, height + 4), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    draw_wordmark_glyphs(d, chars, 0, 0, scale, wordmark_colours(pal))
    return img


# i3lock does not scale images, so a wallpaper only fills the screen if it
# already matches the resolution exactly. Rendering the common ones at build
# time gives a proper lock screen without putting ImageMagick on the ISO.
LOCK_SIZES = [
    (1920, 1080), (1366, 768), (1280, 1024), (1280, 800), (1440, 900),
    (1600, 900), (1680, 1050), (1920, 1200), (2560, 1440), (2560, 1600),
    (3440, 1440), (3840, 2160),
]


def lock_image(source: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Cover-fit the wallpaper to the screen, then darken it for legibility."""
    target_w, target_h = size
    scale = max(target_w / source.width, target_h / source.height)
    resized = source.resize(
        (max(1, round(source.width * scale)), max(1, round(source.height * scale))),
        Image.LANCZOS,
    )
    left = (resized.width - target_w) // 2
    top = (resized.height - target_h) // 2
    cropped = resized.crop((left, top, left + target_w, top + target_h))
    return Image.blend(cropped, Image.new("RGB", size, (4, 21, 15)), 0.45)


# ── Branding derived from the same glyphs as the wallpaper ───────────────────
# The wordmark as figlet's "ANSI Shadow" draws it: a solid stroke with a
# drop shadow along its right and bottom. Written out rather than generated,
# because it is a typeface, not a bitmap - the 4x5 pixel glyphs used for the
# wallpaper look like a wallpaper, and blown up to text they looked like
# something rendered by mistake.
ANSI_SHADOW = r"""
██╗███████╗ ██████╗ ███████╗
██║██╔════╝██╔═══██╗██╔════╝
██║█████╗  ██║   ██║███████╗
██║██╔══╝  ██║   ██║╚════██║
██║██║     ╚██████╔╝███████║
╚═╝╚═╝      ╚═════╝ ╚══════╝
"""

# The characters that form the shadow rather than the stroke.
SHADOW_CHARS = set("╗╝╔╚║═")


def ascii_logo() -> str:
    """The IFOS wordmark as coloured text, for fastfetch.

    Three colours, switched inline: fastfetch honours $1..$9 anywhere in a
    line, not only at the start, so the solid strokes and the drop shadow can
    be different greens. That is what makes it read as a wordmark with depth
    instead of a wall of blocks.

    The previous version was built from the same 4x5 glyphs as the wallpaper,
    stacked "IF" over "OS" to keep it narrow. It was eighteen columns and it
    looked like it: at text size those glyphs have no strokes, only squares.
    This is twenty-eight columns, which is ten more of indent on every line of
    output - worth it, and still inside 80 columns once the keys and values are
    added.
    """
    lines = [l for l in ANSI_SHADOW.strip("\n").split("\n")]
    width = max(len(l) for l in lines)

    out = ["$1"]
    for line in lines:
        rendered = "  "
        current = None
        for ch in line:
            want = "$2" if ch in SHADOW_CHARS else "$1"
            if ch == " ":
                rendered += ch
                continue
            if want != current:
                rendered += want
                current = want
            rendered += ch
        out.append(rendered.rstrip())
    out.append("$1")
    out.append("$3  " + "IFMS · Campus Dourados".center(width))
    out.append("")
    return "\n".join(out) + "\n"


def svg_logo(name: str) -> str:
    """Scalable icon for os-release LOGO= and desktop about dialogs."""
    pal = PALETTES[name]
    chars = "IFOS"
    gap = 1
    cols = sum(GLYPH_W[c] for c in chars) + gap * (len(chars) - 1)
    unit = 16
    pad = unit
    w = cols * unit + pad * 2
    h = GLYPH_H * unit + pad * 2
    colours = wordmark_colours(pal)

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
        f'viewBox="0 0 {w} {h}">',
        f'  <rect width="{w}" height="{h}" rx="{unit}" fill="rgb{pal["crust"]}"/>',
    ]
    ox = pad
    for ch in chars:
        r, g, b = colours[ch]
        for px, py in sorted(GLYPHS[ch]):
            x = ox + px * unit
            y = py * unit + pad
            parts.append(
                f'  <rect x="{x}" y="{y}" width="{unit - 2}" height="{unit - 2}" '
                f'rx="2" fill="rgb({r},{g},{b})"/>'
            )
        ox += (GLYPH_W[ch] + gap) * unit
    parts.append("</svg>")
    return "\n".join(parts) + "\n"


def boot_splash(name: str, size=(640, 480)) -> Image.Image:
    """Replaces the Arch splash behind the BIOS boot menu."""
    pal = PALETTES[name]
    w, h = size
    img = Image.new("RGB", size, pal["crust"])
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / h
        d.line([(0, y), (w, y)],
               fill=tuple(int(pal["crust"][i] + (pal["base"][i] - pal["crust"][i]) * t)
                          for i in range(3)))

    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.ellipse([w // 2 - 220, h // 2 - 220, w // 2 + 220, h // 2 + 220],
               fill=(*pal["accent"], 45))
    layer = layer.filter(ImageFilter.GaussianBlur(90))
    img = Image.alpha_composite(img.convert("RGBA"), layer)
    d = ImageDraw.Draw(img)

    scale = 9
    chars = "IFOS"
    x0 = (w - wordmark_width(chars, scale)) // 2
    y0 = 40
    draw_wordmark_glyphs(d, chars, x0, y0, scale, wordmark_colours(pal), gutter=2)

    font = load_font(15)
    if font:
        caption = pal["caption"]
        bbox = d.textbbox((0, 0), caption, font=font)
        d.text(((w - (bbox[2] - bbox[0])) // 2, y0 + GLYPH_H * scale + 12), caption,
               font=font, fill=(*pal["text"], 200))
    return img.convert("RGB")


def grub_background(name: str, size=(1920, 1080)) -> Image.Image:
    """Background for the GRUB theme on installed systems - the menu a
    dual-booting student sees every single time the machine starts."""
    pal = PALETTES[name]
    w, h = size
    img = Image.new("RGB", size, pal["crust"])
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / h
        d.line([(0, y), (w, y)],
               fill=tuple(int(pal["crust"][i] + (pal["base"][i] - pal["crust"][i]) * t)
                          for i in range(3)))

    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.ellipse([w // 2 - 520, h // 2 - 420, w // 2 + 520, h // 2 + 620],
               fill=(*pal["accent"], 40))
    layer = layer.filter(ImageFilter.GaussianBlur(200))
    img = Image.alpha_composite(img.convert("RGBA"), layer)
    d = ImageDraw.Draw(img)

    # Wordmark near the top, leaving the middle clear for the menu.
    scale = 16
    chars = "IFOS"
    x0 = (w - wordmark_width(chars, scale)) // 2
    y0 = int(h * 0.10)
    draw_wordmark_glyphs(d, chars, x0, y0, scale, wordmark_colours(pal))

    font = load_font(22)
    if font:
        caption = pal["caption"]
        bbox = d.textbbox((0, 0), caption, font=font)
        d.text(((w - (bbox[2] - bbox[0])) // 2, y0 + GLYPH_H * scale + 18), caption,
               font=font, fill=(*pal["text"], 190))
    return img.convert("RGB")


def main() -> int:
    ap = argparse.ArgumentParser()
    default_root = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "airootfs")
    ap.add_argument("--out", default=default_root,
                    help="airootfs directory to write into (default: %(default)s)")
    ap.add_argument("--default-theme", default="ifms", choices=sorted(PALETTES),
                    help="which palette becomes the shipped wallpaper")
    args = ap.parse_args()

    backgrounds = os.path.join(args.out, "usr/share/backgrounds")
    sddm_theme = os.path.join(args.out, "usr/share/sddm/themes/ifos")
    plymouth = os.path.join(args.out, "usr/share/plymouth/themes/ifos")
    for path in (backgrounds, sddm_theme, plymouth):
        os.makedirs(path, exist_ok=True)

    for name in sorted(PALETTES):
        img = wallpaper(name)
        target = os.path.join(backgrounds, f"ifos-{name}.png")
        img.save(target, "PNG", optimize=True)
        print(f"  wallpaper  {target}")

    chosen = os.path.join(backgrounds, f"ifos-{args.default_theme}.png")
    for target in (os.path.join(backgrounds, "ifos.png"),
                   os.path.join(sddm_theme, "background.png")):
        Image.open(chosen).save(target, "PNG", optimize=True)
        print(f"  default    {target}")

    lock_dir = os.path.join(args.out, "usr/share/ifos/lock")
    os.makedirs(lock_dir, exist_ok=True)
    base = Image.open(chosen).convert("RGB")
    for size in LOCK_SIZES:
        target = os.path.join(lock_dir, "ifos-%dx%d.png" % size)
        lock_image(base, size).save(target, "PNG", optimize=True)
    print("  lock        %d screens in %s" % (len(LOCK_SIZES), lock_dir))

    # fastfetch logo, replacing the Arch one
    share = os.path.join(args.out, "usr/share/ifos")
    os.makedirs(share, exist_ok=True)
    with open(os.path.join(share, "logo.txt"), "w", encoding="utf-8") as fh:
        fh.write(ascii_logo())
    print("  ascii logo %s" % os.path.join(share, "logo.txt"))

    # Icon for os-release LOGO= and about dialogs
    icons = os.path.join(args.out, "usr/share/icons/hicolor/scalable/apps")
    os.makedirs(icons, exist_ok=True)
    with open(os.path.join(icons, "ifos-logo.svg"), "w", encoding="utf-8") as fh:
        fh.write(svg_logo(args.default_theme))
    print("  icon       %s" % os.path.join(icons, "ifos-logo.svg"))

    # GRUB theme background for installed systems
    grub_dir = os.path.join(args.out, "usr/share/grub/themes/ifos")
    os.makedirs(grub_dir, exist_ok=True)
    grub_background(args.default_theme).save(
        os.path.join(grub_dir, "background.png"), "PNG", optimize=True)
    print("  grub bg    %s" % os.path.join(grub_dir, "background.png"))

    # BIOS boot menu splash, replacing the Arch one
    splash_dir = os.path.join(os.path.dirname(args.out.rstrip("/")), "syslinux")
    if os.path.isdir(splash_dir):
        target = os.path.join(splash_dir, "splash.png")
        boot_splash(args.default_theme).save(target, "PNG", optimize=True)
        print("  splash     %s" % target)

    logo = boot_logo(args.default_theme)
    logo_path = os.path.join(plymouth, "logo.png")
    logo.save(logo_path, "PNG", optimize=True)
    print(f"  boot logo  {logo_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
