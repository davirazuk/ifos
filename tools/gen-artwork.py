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

# 4x5 pixel-art glyphs, so no font file is needed for the wordmark.
GLYPHS = {
    "I": [(1, 0), (1, 1), (1, 2), (1, 3), (1, 4), (0, 0), (2, 0), (0, 4), (2, 4)],
    "F": [(0, 0), (1, 0), (2, 0), (0, 1), (0, 2), (1, 2), (0, 3), (0, 4)],
    "O": [(1, 0), (2, 0), (0, 1), (3, 1), (0, 2), (3, 2), (0, 3), (3, 3), (1, 4), (2, 4)],
    "S": [(1, 0), (2, 0), (3, 0), (0, 1), (1, 2), (2, 2), (3, 3), (0, 4), (1, 4), (2, 4)],
}

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
    step = 4 * scale + 10
    total = len(chars) * step - 10
    x0 = (W - total) // 2
    y0 = H // 2 - 2 * scale
    colours = [pal["accent"], pal["accent2"], pal["accent3"], pal["accent"]]

    for i, ch in enumerate(chars):
        ox = x0 + i * step
        for dx, dy, colour in ((4, 4, (0, 0, 0, 110)), (0, 0, (*colours[i], 255))):
            for px, py in GLYPHS[ch]:
                x = ox + px * scale + dx
                y = y0 + py * scale + dy
                d.rectangle([x, y, x + scale - 3, y + scale - 3], fill=colour)

    # Accent dots under the wordmark
    dots = [pal["accent"], pal["accent2"], pal["accent3"], pal["accent"], pal["accent2"]]
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


def wallpaper(name: str) -> Image.Image:
    pal = PALETTES[name]
    img = gradient(pal)
    img = overlay_grid(img, pal)
    img = overlay_glows(img, pal)
    img = overlay_rings(img, pal)
    img = draw_wordmark(img, pal)
    img = vignette(img)
    return img.convert("RGB")


def boot_logo(name: str) -> Image.Image:
    """Transparent wordmark for the Plymouth splash."""
    pal = PALETTES[name]
    scale = 18
    chars = "IFOS"
    step = 4 * scale + 8
    width = len(chars) * step - 8
    height = 5 * scale
    img = Image.new("RGBA", (width, height + 4), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    colours = [pal["accent"], pal["accent2"], pal["accent3"], pal["accent"]]
    for i, ch in enumerate(chars):
        ox = i * step
        for px, py in GLYPHS[ch]:
            x = ox + px * scale
            y = py * scale
            d.rectangle([x, y, x + scale - 3, y + scale - 3], fill=(*colours[i], 255))
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

    logo = boot_logo(args.default_theme)
    logo_path = os.path.join(plymouth, "logo.png")
    logo.save(logo_path, "PNG", optimize=True)
    print(f"  boot logo  {logo_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
