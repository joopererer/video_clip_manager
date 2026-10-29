"""Build the review sheet for the logo candidates.

Shows every candidate at 256 / 64 / 48 / 32 / 16 px on the app background plus a
simulated Windows taskbar, so the 16 px legibility requirement can be judged
before any icon is wired into the Windows runner.

Usage: python generate_preview.py
"""

from __future__ import annotations

import os

from PIL import Image, ImageDraw, ImageFont

from generate_candidates import (
    BG,
    C,
    HERE,
    STRIP_EDGE,
    WHITE,
    candidate_a,
    candidate_b,
    candidate_c,
    candidate_d,
)

SIZES = (256, 64, 48, 32, 16)
ROW_LABELS = {
    "candidate_a": "A · 四帧胶片 + 高亮成片帧",
    "candidate_b": "B · 三帧胶片 + 居中选中帧",
    "candidate_c": "C · 双帧极简 + 右侧高亮",
    "candidate_d": "D · 微透视胶片带",
}


def load_font(size: int):
    for name in ("msyh.ttc", "simhei.ttf", "arial.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def main() -> None:
    factories = {
        "candidate_a": candidate_a,
        "candidate_b": candidate_b,
        "candidate_c": candidate_c,
        "candidate_d": candidate_d,
    }

    pad = 24
    label_h = 28
    row_h = 256 + label_h + pad
    width = pad * 2 + 256 + 40 + sum(SIZES[1:]) + 20 * 4 + 24
    height = pad * 2 + row_h * len(factories) + 60

    sheet = Image.new("RGBA", (width, height), BG)
    draw = ImageDraw.Draw(sheet)
    font_title = load_font(22)
    font_label = load_font(15)
    font_small = load_font(12)

    draw.text(
        (pad, pad),
        "Video Clip Manager v1.1 · Logo / Icon 候选（电影胶片主题）",
        font=font_title,
        fill=WHITE,
    )
    draw.text(
        (pad, pad + 30),
        "深色背景 + 紫色强调 · 无文字 · 无剪刀/播放按钮/AI 星星堆叠",
        font=font_small,
        fill=(165, 172, 186, 255),
    )

    y = pad + 60
    for name, factory in factories.items():
        img = factory().resize((256, 256), Image.LANCZOS)
        draw.text((pad, y), ROW_LABELS[name], font=font_label, fill=WHITE)
        sheet.alpha_composite(img, (pad, y + label_h))

        x = pad + 256 + 40
        for size in SIZES[1:]:
            small = img.resize((size, size), Image.LANCZOS)
            cell_top = y + label_h + (256 - size) // 2
            sheet.alpha_composite(small, (x, cell_top))
            draw.text(
                (x, y + label_h + 256 + 2),
                f"{size}px",
                font=font_small,
                fill=(140, 147, 162, 255),
            )
            x += size + 20

        # simulated Windows taskbar row
        bar_h = 34
        bar = Image.new("RGBA", (width - pad * 2, bar_h), (32, 33, 36, 255))
        bd = ImageDraw.Draw(bar)
        bd.line([(0, 0), (bar.width, 0)], fill=STRIP_EDGE, width=1)
        taskbar_icon = img.resize((22, 22), Image.LANCZOS)
        bar.alpha_composite(taskbar_icon, (18, 6))
        bd.rounded_rectangle([14, 3, 44, 31], radius=6, outline=(88, 94, 108, 200), width=2)
        bd.text(
            (54, 9),
            "Video Clip Manager",
            font=font_small,
            fill=(230, 232, 238, 255),
        )
        sheet.alpha_composite(bar, (pad, y + label_h + 256 + 18))
        y += row_h

    out = os.path.join(HERE, "logo_candidates_preview.png")
    sheet.convert("RGB").save(out)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
