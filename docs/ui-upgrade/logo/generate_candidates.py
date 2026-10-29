"""Generate film-strip logo candidates for Video Clip Manager v1.1.

The candidates follow the requested brief: a horizontal piece of film with
sprocket holes top and bottom, several consecutive frames where one frame is
highlighted as the selected clip, dark background and purple accent, no text and
no stacked scissors / play buttons / AI sparkles.

Everything is drawn at 4x and downsampled with LANCZOS so the 16 px and 32 px
renders stay legible. Outputs land in this folder only; the production
windows/runner/resources/app_icon.ico is never touched.

Usage: python generate_candidates.py
"""

from __future__ import annotations

import os
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))

SS = 4  # supersampling factor
S = 256  # logical canvas size
C = S * SS

BG = (23, 26, 32, 255)  # #171A20
BG_GLOW = (60, 52, 104, 255)  # purple-ish glow
STRIP = (42, 47, 58, 255)  # #2A2F3A
STRIP_EDGE = (64, 71, 86, 255)  # #404756
FRAME = (52, 58, 72, 255)  # #343A48
FRAME_EDGE = (94, 103, 122, 255)
ACCENT = (139, 124, 246, 255)  # #8B7CF6
ACCENT_LIGHT = (170, 158, 250, 255)
WHITE = (241, 242, 246, 255)
SHADOW = (8, 9, 12, 120)


def px(value: float) -> float:
    return value * SS


def new_canvas() -> Image.Image:
    img = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle(
        [0, 0, C - 1, C - 1], radius=px(56), fill=BG
    )
    glow = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    gdraw.ellipse(
        [px(20), px(40), px(240), px(240)], fill=(88, 74, 150, 60)
    )
    glow = glow.filter(ImageFilter.GaussianBlur(px(26)))
    mask = Image.new("L", (C, C), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, C - 1, C - 1], radius=px(56), fill=255
    )
    img.paste(glow, (0, 0), Image.composite(glow.split()[3], Image.new("L", (C, C), 0), mask))
    return img


def rounded(draw: ImageDraw.ImageDraw, box, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(
        [px(box[0]), px(box[1]), px(box[2]), px(box[3])],
        radius=px(radius),
        fill=fill,
        outline=outline,
        width=max(1, int(px(width))),
    )


def sprockets(
    draw: ImageDraw.ImageDraw,
    *,
    left: float,
    right: float,
    top_y: float,
    bottom_y: float,
    hole_w: float = 10.0,
    hole_h: float = 8.0,
    gap: float = 6.5,
):
    x = left
    while x + hole_w <= right + 0.01:
        rounded(draw, (x, top_y, x + hole_w, top_y + hole_h), 2.0, BG)
        rounded(draw, (x, bottom_y, x + hole_w, bottom_y + hole_h), 2.0, BG)
        x += hole_w + gap


def frame_box(
    draw: ImageDraw.ImageDraw,
    box,
    *,
    highlighted: bool,
    radius: float = 4.0,
    inset: float = 0.0,
):
    left, top, right, bottom = box
    left, top, right, bottom = (
        left + inset,
        top + inset,
        right - inset,
        bottom - inset,
    )
    if highlighted:
        rounded(
            draw,
            (left, top, right, bottom),
            radius,
            ACCENT,
            outline=ACCENT_LIGHT,
            width=2.4,
        )
        # inner sheen so the selected frame reads as "bright" even at 16 px
        rounded(
            draw,
            (left + 3, top + 3, right - 3, bottom - 3),
            radius * 0.6,
            (188, 178, 255, 90),
        )
    else:
        rounded(
            draw,
            (left, top, right, bottom),
            radius,
            FRAME,
            outline=FRAME_EDGE,
            width=1.2,
        )


def candidate_a() -> Image.Image:
    """Four consecutive frames, the second one selected."""
    img = new_canvas()
    d = ImageDraw.Draw(img)
    rounded(d, (16, 68, 240, 188), 12, STRIP, outline=STRIP_EDGE, width=1.6)
    sprockets(
        d, left=24, right=232, top_y=76, bottom_y=172, hole_w=12, hole_h=8, gap=8
    )
    width = 44
    gap = 8
    xs = 26
    for i in range(4):
        left = xs + i * (width + gap)
        frame_box(
            d,
            (left, 94, left + width, 162),
            highlighted=(i == 1),
            radius=5,
        )
    return img


def candidate_b() -> Image.Image:
    """Three frames, the centre one selected (closest to a film negative)."""
    img = new_canvas()
    d = ImageDraw.Draw(img)
    rounded(d, (16, 68, 240, 188), 14, STRIP, outline=STRIP_EDGE, width=1.6)
    sprockets(
        d, left=24, right=232, top_y=76, bottom_y=172, hole_w=12, hole_h=8, gap=8
    )
    frames = [(30, 86), (100, 156), (170, 226)]
    for idx, (left, right) in enumerate(frames):
        frame_box(
            d,
            (left, 94, right, 162),
            highlighted=(idx == 1),
            radius=7,
        )
    return img


def candidate_c() -> Image.Image:
    """Two bold frames, the right one selected: maximum 16 px legibility."""
    img = new_canvas()
    d = ImageDraw.Draw(img)
    rounded(d, (14, 60, 242, 196), 12, STRIP, outline=STRIP_EDGE, width=1.6)
    sprockets(
        d, left=22, right=234, top_y=68, bottom_y=180, hole_w=13, hole_h=9, gap=9
    )
    frame_box(d, (22, 88, 112, 168), highlighted=False, radius=6)
    frame_box(d, (144, 88, 234, 168), highlighted=True, radius=6)
    return img


def candidate_d() -> Image.Image:
    """Tilted strip: reads as a clip timeline in mild perspective."""
    layer = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    rounded(d, (4, 74, 252, 182), 12, STRIP, outline=STRIP_EDGE, width=1.6)
    sprockets(
        d, left=12, right=244, top_y=82, bottom_y=166, hole_w=11, hole_h=7, gap=7
    )
    frames = [(14, 66), (74, 126), (134, 186), (194, 246)]
    for idx, (left, right) in enumerate(frames):
        frame_box(
            d,
            (left, 98, right, 156),
            highlighted=(idx == 2),
            radius=4,
        )

    # quad mapping for a mild 3D tilt
    dst = [
        (px(10), px(24)),
        (C - px(4), px(6)),
        (C - px(10), C - px(14)),
        (px(4), C - px(32)),
    ]
    tilted = layer.transform(
        layer.size, Image.QUAD, sum(dst, ()), resample=Image.BICUBIC
    )
    img = new_canvas()
    img.alpha_composite(tilted)
    return img


def export(img: Image.Image, name: str, sizes=(256, 64, 48, 32, 16)):
    for size in sizes:
        out = img.resize((size, size), Image.LANCZOS)
        out.save(os.path.join(HERE, f"{name}_{size}.png"))


def main() -> None:
    candidates = {
        "candidate_a": candidate_a,
        "candidate_b": candidate_b,
        "candidate_c": candidate_c,
        "candidate_d": candidate_d,
    }
    for name, factory in candidates.items():
        img = factory()
        img.save(os.path.join(HERE, f"{name}_1024.png"))
        export(img, name)
        print(f"wrote {name} renders")


if __name__ == "__main__":
    main()
