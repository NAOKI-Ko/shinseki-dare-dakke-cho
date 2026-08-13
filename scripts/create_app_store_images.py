#!/usr/bin/env python3
"""Compose App Store screenshots from unmodified app captures.

The app UI remains the source of truth. This script only adds the store-listing
background, copy hierarchy, and a consistent device presentation.
"""

from __future__ import annotations

import argparse
import glob
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


CANVAS_SIZE = (1320, 2868)
PAPER = (247, 244, 235)
PAPER_RAISED = (253, 251, 245)
INK = (42, 42, 40)
INK_SOFT = (110, 106, 92)
INDIGO = (44, 68, 103)
ATTENTION = (179, 58, 47)
FOREST = (61, 107, 82)
PLUM = (107, 61, 94)
GOLD = (201, 162, 75)


SLIDES = [
    {
        "raw": "01_memory-summary.png",
        "final": "01_memory-summary.png",
        "tag": "記憶をたどる",
        "title": "「あの人誰だっけ？」を、\nすぐ確認。",
        "subtitle": "自分とのつながりや、前に会った記憶をひと目で。",
        "accent": ATTENTION,
        "device_width": 1000,
        "device_y": 690,
        "device_x": 8,
        "motif": "left",
    },
    {
        "raw": "02_family-graph.png",
        "final": "02_family-graph.png",
        "tag": "つながり",
        "title": "親戚のつながりが、\nひと目でわかる。",
        "subtitle": "配偶者や共同子まで、家族の関係を見やすく整理。",
        "accent": INDIGO,
        "device_width": 1110,
        "device_y": 680,
        "device_x": -34,
        "motif": "constellation",
    },
    {
        "raw": "03_gathering-prep.png",
        "final": "03_gathering-prep.png",
        "tag": "集まり前の予習",
        "title": "法事や結婚式の前に、\n会う人だけ予習。",
        "subtitle": "集まりに参加する親族を、順番に確認できます。",
        "accent": PLUM,
        "device_width": 1015,
        "device_y": 650,
        "device_x": 24,
        "motif": "right",
    },
    {
        "raw": "04_search.png",
        "final": "04_search.png",
        "tag": "手がかり検索",
        "title": "名前を忘れても、\n手がかりから探せる。",
        "subtitle": "続柄、地域、集まり、記憶情報からすばやく検索。",
        "accent": FOREST,
        "device_width": 1060,
        "device_y": 700,
        "device_x": -22,
        "motif": "left",
    },
    {
        "raw": "05_person-memory.png",
        "final": "05_person-memory.png",
        "tag": "会話の記録",
        "title": "前に話したことまで、\n思い出せる。",
        "subtitle": "居住地、会話メモ、最後に会った場所や日付も記録。",
        "accent": ATTENTION,
        "device_width": 1080,
        "device_y": 675,
        "device_x": 22,
        "motif": "right",
    },
    {
        "raw": "06_backup.png",
        "final": "06_backup.png",
        "tag": "端末中心の管理",
        "title": "大切な記録は、\n自分でバックアップ。",
        "subtitle": "データは端末中心。必要なときだけ自分で保存できます。",
        "accent": INDIGO,
        "device_width": 1040,
        "device_y": 700,
        "device_x": -12,
        "motif": "constellation",
    },
]


def font_path(pattern: str) -> str:
    matches = glob.glob(f"/System/Library/Fonts/{pattern}")
    if not matches:
        raise FileNotFoundError(pattern)
    return matches[0]


MINCHO_PATH = font_path("*明朝 ProN.ttc")
SANS_PATH = font_path("*角*シック W6.ttc")
SANS_REGULAR_PATH = font_path("*角*シック W3.ttc")


def font(path: str, size: int, index: int = 0) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size=size, index=index)


def make_background(accent: tuple[int, int, int], motif: str) -> Image.Image:
    width, height = CANVAS_SIZE
    image = Image.new("RGB", CANVAS_SIZE, PAPER)
    base_draw = ImageDraw.Draw(image)
    for y in range(height):
        blend = y / max(1, height - 1)
        warm = int(4 * (1.0 - blend))
        shade = int(2 * blend)
        color = tuple(max(0, channel + warm - shade) for channel in PAPER)
        base_draw.line((0, y, width, y), fill=color)

    decoration = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(decoration)
    if motif == "left":
        draw.arc((-390, -360, 900, 930), 4, 138, fill=(*GOLD, 58), width=5)
        draw.arc((-295, -290, 820, 825), 4, 138, fill=(*accent, 42), width=4)
        points = [(1030, 60), (1175, 205), (1250, 430)]
    elif motif == "right":
        draw.arc((700, -520, 1680, 460), 70, 248, fill=(*GOLD, 58), width=5)
        draw.arc((770, -430, 1600, 400), 70, 248, fill=(*accent, 42), width=4)
        points = [(90, 72), (210, 210), (280, 430)]
    else:
        draw.arc((-230, -430, 910, 710), 12, 138, fill=(*GOLD, 55), width=5)
        draw.arc((760, -280, 1540, 500), 110, 292, fill=(*accent, 44), width=4)
        points = [(1030, 68), (1168, 218), (1242, 420)]
    draw.line(points, fill=(*GOLD, 48), width=4)
    for index, (x, y) in enumerate(points):
        radius = 10 - index
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=(*GOLD, 84))
    decoration = decoration.filter(ImageFilter.GaussianBlur(0.35))
    image = Image.alpha_composite(image.convert("RGBA"), decoration)

    # Deterministic, nearly invisible paper grain.
    noise = Image.effect_noise(CANVAS_SIZE, 7).convert("L")
    grain = Image.new("RGBA", CANVAS_SIZE, (120, 105, 76, 0))
    grain.putalpha(noise.point(lambda value: max(0, min(10, (value - 96) // 8))))
    return Image.alpha_composite(image, grain)


def draw_header(
    canvas: Image.Image,
    title: str,
    subtitle: str,
    tag: str,
    accent: tuple[int, int, int],
) -> None:
    draw = ImageDraw.Draw(canvas)
    tag_font = font(SANS_PATH, 31)
    main_font = font(MINCHO_PATH, 104)
    subtitle_font = font(SANS_REGULAR_PATH, 43)

    tag_box = draw.textbbox((0, 0), tag, font=tag_font)
    tag_width = tag_box[2] - tag_box[0]
    capsule = (84, 58, 84 + tag_width + 82, 128)
    draw.rounded_rectangle(capsule, radius=32, fill=(*accent, 255), outline=(*accent, 255), width=2)
    draw.text((125, 76), tag, font=tag_font, fill=PAPER_RAISED)
    draw.line((84, 154, 1236, 154), fill=(*GOLD, 118), width=3)

    draw.multiline_text(
        (82, 186),
        title,
        font=main_font,
        fill=INK,
        spacing=5,
    )
    title_box = draw.multiline_textbbox((82, 186), title, font=main_font, spacing=5)
    subtitle_y = title_box[3] + 23
    words: list[str] = []
    line = ""
    for character in subtitle:
        candidate = line + character
        if draw.textlength(candidate, font=subtitle_font) > 1145 and line:
            words.append(line)
            line = character
        else:
            line = candidate
    if line:
        words.append(line)
    draw.multiline_text(
        (86, subtitle_y),
        "\n".join(words),
        font=subtitle_font,
        fill=INK_SOFT,
        spacing=7,
    )


def paste_device(
    canvas: Image.Image,
    screenshot: Image.Image,
    accent: tuple[int, int, int],
    screen_width: int,
    device_y: int,
    device_x: int,
) -> None:
    screen_height = round(screen_width * CANVAS_SIZE[1] / CANVAS_SIZE[0])
    screen = screenshot.convert("RGB").resize((screen_width, screen_height), Image.Resampling.LANCZOS)
    screen_mask = Image.new("L", screen.size, 0)
    ImageDraw.Draw(screen_mask).rounded_rectangle(
        (0, 0, screen_width - 1, screen_height - 1), radius=66, fill=255
    )

    frame_padding = 22
    frame_size = (screen_width + frame_padding * 2, screen_height + frame_padding * 2)
    frame = Image.new("RGBA", frame_size, (0, 0, 0, 0))
    frame_draw = ImageDraw.Draw(frame)
    frame_draw.rounded_rectangle(
        (0, 0, frame_size[0] - 1, frame_size[1] - 1),
        radius=84,
        fill=(27, 31, 38, 255),
        outline=(*GOLD, 220),
        width=3,
    )
    frame.paste(screen, (frame_padding, frame_padding), screen_mask)

    x = (CANVAS_SIZE[0] - frame_size[0]) // 2 + device_x
    y = device_y
    shadow = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (x - 10, y + 22, x + frame_size[0] + 10, y + frame_size[1] + 42),
        radius=96,
        fill=(*accent, 62),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(30))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(frame, (x, y))


def compose_slide(raw_path: Path, output_path: Path, slide: dict[str, object]) -> None:
    screenshot = Image.open(raw_path)
    if screenshot.size != CANVAS_SIZE:
        raise ValueError(f"Unexpected screenshot size {screenshot.size}: {raw_path}")
    accent = slide["accent"]
    assert isinstance(accent, tuple)
    canvas = make_background(accent, str(slide["motif"]))
    draw_header(
        canvas,
        str(slide["title"]),
        str(slide["subtitle"]),
        str(slide["tag"]),
        accent,
    )
    paste_device(
        canvas,
        screenshot,
        accent,
        int(slide["device_width"]),
        int(slide["device_y"]),
        int(slide["device_x"]),
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(output_path, "PNG", optimize=True, compress_level=9)


def make_contact_sheet(final_dir: Path, output_path: Path) -> None:
    size = (3840, 2160)
    canvas = Image.new("RGB", size, (235, 230, 217))
    draw = ImageDraw.Draw(canvas)
    heading = font(MINCHO_PATH, 62)
    label_font = font(SANS_PATH, 26)
    draw.text((110, 72), "親戚だれだっけ帳 — App Store画像", font=heading, fill=INK)
    draw.line((110, 165, 3730, 165), fill=GOLD, width=3)

    thumb_width = 500
    thumb_height = round(thumb_width * CANVAS_SIZE[1] / CANVAS_SIZE[0])
    gap = 102
    start_x = (size[0] - (thumb_width * 6 + gap * 5)) // 2
    top = 275
    for index, slide in enumerate(SLIDES):
        image = Image.open(final_dir / str(slide["final"])).convert("RGB")
        image.thumbnail((thumb_width, thumb_height), Image.Resampling.LANCZOS)
        x = start_x + index * (thumb_width + gap)
        shadow = Image.new("RGBA", size, (0, 0, 0, 0))
        ImageDraw.Draw(shadow).rounded_rectangle(
            (x - 9, top + 15, x + thumb_width + 9, top + thumb_height + 30),
            radius=34,
            fill=(35, 35, 30, 50),
        )
        shadow = shadow.filter(ImageFilter.GaussianBlur(14))
        canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow).convert("RGB")
        canvas.paste(image, (x, top))
        draw = ImageDraw.Draw(canvas)
        draw.text((x, top + thumb_height + 28), f"{index + 1:02d}", font=label_font, fill=INDIGO)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output_path, "PNG", optimize=True, compress_level=9)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw-dir", type=Path, required=True)
    parser.add_argument("--final-dir", type=Path, required=True)
    parser.add_argument("--preview", type=Path, required=True)
    args = parser.parse_args()

    for slide in SLIDES:
        compose_slide(
            args.raw_dir / str(slide["raw"]),
            args.final_dir / str(slide["final"]),
            slide,
        )
    make_contact_sheet(args.final_dir, args.preview)


if __name__ == "__main__":
    main()
