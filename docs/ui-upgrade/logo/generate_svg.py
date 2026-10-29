"""Emit SVG masters matching the rasterised logo candidates.

Usage: python generate_svg.py
"""

from __future__ import annotations

import os

HERE = os.path.dirname(os.path.abspath(__file__))
BG = "#171A20"
STRIP = "#2A2F3A"
EDGE = "#404756"
FRAME = "#343A48"
FRAME_EDGE = "#5E677A"
ACCENT = "#8B7CF6"
ACCENT_LIGHT = "#A9A0FA"
SHEEN = "#BCB2FF"


def rect(x, y, w, h, r, fill, stroke=None, sw=0.0, opacity=None):
    s = f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}"'
    if stroke:
        s += f' stroke="{stroke}" stroke-width="{sw}"'
    if opacity is not None:
        s += f' opacity="{opacity}"'
    return s + " />"


def sprockets(left, right, top_y, bottom_y, hole_w, hole_h, gap):
    out = []
    x = left
    while x + hole_w <= right + 0.01:
        out.append(rect(x, top_y, hole_w, hole_h, 2, BG))
        out.append(rect(x, bottom_y, hole_w, hole_h, 2, BG))
        x += hole_w + gap
    return "\n    ".join(out)


def frame(x, y, w, h, r, highlighted):
    if not highlighted:
        return rect(x, y, w, h, r, FRAME, FRAME_EDGE, 1.2)
    inner = rect(x + 3, y + 3, w - 6, h - 6, max(1, r * 0.6), SHEEN, opacity=0.35)
    return rect(x, y, w, h, r, ACCENT, ACCENT_LIGHT, 2.4) + "\n    " + inner


def doc(parts) -> str:
    body = "\n  ".join(parts)
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" '
        'width="256" height="256" role="img"\n'
        '     aria-label="Video Clip Manager film strip icon">\n'
        f"  {body}\n</svg>\n"
    )


def candidate_a() -> str:
    frames = [
        frame(26 + i * 52, 94, 44, 68, 5, i == 1) for i in range(4)
    ]
    return doc(
        [
            rect(0, 0, 256, 256, 56, BG),
            rect(16, 68, 224, 120, 12, STRIP, EDGE, 1.6),
            sprockets(24, 232, 76, 172, 12, 8, 8),
            "\n  ".join(frames),
        ]
    )


def candidate_b() -> str:
    frames = [frame(30, 94, 56, 68, 7, False), frame(100, 94, 56, 68, 7, True)]
    frames.append(frame(170, 94, 56, 68, 7, False))
    return doc(
        [
            rect(0, 0, 256, 256, 56, BG),
            rect(16, 68, 224, 120, 14, STRIP, EDGE, 1.6),
            sprockets(24, 232, 76, 172, 12, 8, 8),
            "\n  ".join(frames),
        ]
    )


def candidate_c() -> str:
    return doc(
        [
            rect(0, 0, 256, 256, 56, BG),
            rect(14, 60, 228, 136, 12, STRIP, EDGE, 1.6),
            sprockets(22, 234, 68, 180, 13, 9, 9),
            frame(22, 88, 90, 80, 6, False),
            frame(144, 88, 90, 80, 6, True),
        ]
    )


def candidate_d() -> str:
    boxes = [(14, 66), (74, 126), (134, 186), (194, 246)]
    frames = [frame(l, 98, r - l, 58, 4, i == 2) for i, (l, r) in enumerate(boxes)]
    strip = "\n  ".join(
        [
            rect(4, 74, 248, 108, 12, STRIP, EDGE, 1.6),
            sprockets(12, 244, 82, 166, 11, 7, 7),
            "\n  ".join(frames),
        ]
    )
    return doc(
        [
            rect(0, 0, 256, 256, 56, BG),
            '<g transform="matrix(1 0.02 -0.02 1 3 -4)">',
            strip,
            "</g>",
        ]
    )


def main() -> None:
    builders = {
        "candidate_a.svg": candidate_a,
        "candidate_b.svg": candidate_b,
        "candidate_c.svg": candidate_c,
        "candidate_d.svg": candidate_d,
    }
    for name, builder in builders.items():
        with open(os.path.join(HERE, name), "w", encoding="utf-8") as fh:
            fh.write(builder())
        print("wrote", name)


if __name__ == "__main__":
    main()
