#!/usr/bin/env python3
"""Render the 1024 px app icon (no alpha, as App Store Connect requires).

Run:  python Tools/appicon/make_icon.py
Out:  App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png

Navigation arrow standing on the curve of the globe Atlas carries, on a graphite field.
Drawn at 4x and downsampled for clean anti-aliased edges.
"""
import math
import pathlib

from PIL import Image, ImageDraw

SIZE = 1024
SCALE = 4
OUT = pathlib.Path(__file__).resolve().parents[2] / "App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

TOP, BOTTOM = (0x1E, 0x23, 0x2B), (0x10, 0x13, 0x19)
ARROW = (0xF5, 0xF6, 0xF8)
ACCENT = (0x4C, 0x8D, 0xFF)


def s(v):
    return v * SCALE


def main():
    big = SIZE * SCALE
    img = Image.new("RGB", (big, big))
    draw = ImageDraw.Draw(img)
    for y in range(big):  # quiet vertical tone shift, not a colour gradient
        t = y / (big - 1)
        draw.line([(0, y), (big, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))

    # Horizon: the top of a large circle centred below the icon, with round caps.
    cx0, cy0, radius, width = 512, 1560, 860, 30
    box = [s(cx0 - radius), s(cy0 - radius), s(cx0 + radius), s(cy0 + radius)]
    start, end = 240, 300  # PIL angles: clockwise from 3 o'clock, 270 = top
    draw.arc(box, start, end, fill=ACCENT, width=s(width))
    for angle in (start, end):
        cx = cx0 + (radius - width / 2) * math.cos(math.radians(angle))
        cy = cy0 + (radius - width / 2) * math.sin(math.radians(angle))
        r = width / 2
        draw.ellipse([s(cx - r), s(cy - r), s(cx + r), s(cy + r)], fill=ACCENT)

    # Navigation arrow (tip, right base, notch, left base).
    arrow = [(512, 236), (700, 676), (512, 586), (324, 676)]
    draw.polygon([(s(x), s(y)) for x, y in arrow], fill=ARROW)

    icon = img.resize((SIZE, SIZE), Image.LANCZOS)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    icon.save(OUT, "PNG", optimize=True)
    assert Image.open(OUT).mode == "RGB" and Image.open(OUT).size == (SIZE, SIZE)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
