#!/usr/bin/env python3
"""Compose generated storyboard panels into a page with captions and bubbles."""

import argparse
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


FONT_CANDIDATES = [
    Path(r"C:\Windows\Fonts\msyh.ttc"),
    Path("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"),
    Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
]
BOLD_FONT_CANDIDATES = [
    Path(r"C:\Windows\Fonts\msyhbd.ttc"),
    Path("/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"),
    Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"),
]


def pick_font(explicit, candidates):
    if explicit:
        path = Path(explicit)
        if not path.exists():
            raise SystemExit(f"font not found: {path}")
        return path
    for path in candidates:
        if path.exists():
            return path
    raise SystemExit("no usable font found; pass --font and --bold-font")


def load_font(path, size):
    return ImageFont.truetype(str(path), size)


def measure(draw, text, font):
    if hasattr(draw, "textbbox"):
        box = draw.textbbox((0, 0), text, font=font)
        return box[2] - box[0], box[3] - box[1]
    return draw.textsize(text, font=font)


def wrap_text(draw, text, font, max_width):
    lines = []
    current = ""
    for character in text:
        candidate = current + character
        if not current or measure(draw, candidate, font)[0] <= max_width:
            current = candidate
        else:
            lines.append(current)
            current = character
    if current:
        lines.append(current)
    return lines


def draw_lines(draw, lines, font, x, y, line_height, fill):
    for index, line in enumerate(lines):
        draw.text((x, y + index * line_height), line, font=font, fill=fill)


def draw_caption(draw, text, font, cell, position):
    x, y, width, height = cell
    max_width = width - 48
    lines = wrap_text(draw, text, font, max_width)
    line_height = int(font.size * 1.35)
    text_width = max(measure(draw, line, font)[0] for line in lines)
    box_width = min(width - 24, text_width + 40)
    box_height = len(lines) * line_height + 26
    if position == "bottom":
        box_y = y + height - box_height - 18
    else:
        box_y = y + 18
    if position in ("top_right", "bottom_right"):
        box_x = x + width - box_width - 18
    else:
        box_x = x + 18
    draw.rounded_rectangle(
        (box_x, box_y, box_x + box_width, box_y + box_height),
        radius=8,
        fill=(8, 10, 16, 224),
        outline=(210, 32, 48, 255),
        width=3,
    )
    draw.rectangle(
        (box_x, box_y, box_x + 6, box_y + box_height),
        fill=(210, 32, 48, 255),
    )
    draw_lines(
        draw,
        lines,
        font,
        box_x + 22,
        box_y + 13,
        line_height,
        (245, 245, 248, 255),
    )


def draw_bubble(draw, text, font, cell, position):
    x, y, width, height = cell
    max_text_width = int(width * 0.62)
    lines = wrap_text(draw, text, font, max_text_width)
    line_height = int(font.size * 1.35)
    text_width = max(measure(draw, line, font)[0] for line in lines)
    padding_x = 22
    padding_y = 16
    bubble_width = min(width - 28, text_width + padding_x * 2)
    bubble_height = len(lines) * line_height + padding_y * 2

    if position == "top_right":
        bubble_x = x + width - bubble_width - 16
        bubble_y = y + 16
        center = bubble_x + bubble_width // 2
        tail = [(center + 44, bubble_y + bubble_height),
                (center - 42, bubble_y + bubble_height + 32),
                (center - 8, bubble_y + bubble_height)]
    elif position == "bottom":
        bubble_x = x + (width - bubble_width) // 2
        bubble_y = y + height - bubble_height - 18
        tail = [(bubble_x + bubble_width // 2, bubble_y),
                (bubble_x + bubble_width // 2 + 40, bubble_y - 30),
                (bubble_x + bubble_width // 2 + 70, bubble_y)]
    else:
        bubble_x = x + 16
        bubble_y = y + 16
        center = bubble_x + bubble_width // 2
        tail = [(center - 44, bubble_y + bubble_height),
                (center + 42, bubble_y + bubble_height + 32),
                (center + 8, bubble_y + bubble_height)]

    draw.polygon(tail, fill=(252, 252, 250, 246), outline=(14, 14, 18, 255))
    draw.rounded_rectangle(
        (bubble_x, bubble_y, bubble_x + bubble_width, bubble_y + bubble_height),
        radius=24,
        fill=(252, 252, 250, 246),
        outline=(14, 14, 18, 255),
        width=4,
    )
    draw_lines(
        draw,
        lines,
        font,
        bubble_x + padding_x,
        bubble_y + padding_y,
        line_height,
        (16, 16, 20, 255),
    )


def find_panel_image(images_dir, name):
    matches = sorted(images_dir.glob(f"{name}_*.png"))
    if not matches:
        matches = sorted(images_dir.glob(f"*{name}*.png"))
    if not matches:
        raise SystemExit(f"no image found for panel {name} in {images_dir}")
    return matches[0]


def render_panel(panel, images_dir, cell_size, body_font):
    image_path = find_panel_image(images_dir, panel["name"])
    with Image.open(image_path) as source:
        panel_image = ImageOps.fit(
            source.convert("RGB"),
            cell_size,
            method=Image.LANCZOS,
            centering=(0.5, float(panel.get("focus_y", 0.35))),
        ).convert("RGBA")

    overlay = Image.new("RGBA", panel_image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    cell = (0, 0, cell_size[0], cell_size[1])
    if panel.get("caption"):
        draw_caption(
            draw,
            panel["caption"],
            body_font,
            cell,
            panel.get("caption_position", "top"),
        )
    if panel.get("dialogue"):
        draw_bubble(
            draw,
            panel["dialogue"],
            body_font,
            cell,
            panel.get("dialogue_position", "top_left"),
        )
    panel_image = Image.alpha_composite(panel_image, overlay)
    return panel_image.convert("RGB")


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--storyboard", required=True)
    parser.add_argument("--images-dir", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--font")
    parser.add_argument("--bold-font")
    parser.add_argument("--title")
    parser.add_argument("--subtitle")
    return parser.parse_args()


def main():
    args = parse_args()
    storyboard_path = Path(args.storyboard)
    storyboard = json.loads(storyboard_path.read_text(encoding="utf-8"))
    panels = storyboard.get("panels", [])
    if not panels:
        raise SystemExit("storyboard has no panels")

    font_path = pick_font(args.font, FONT_CANDIDATES)
    bold_font_path = pick_font(args.bold_font, BOLD_FONT_CANDIDATES)
    body_font = load_font(font_path, 26)
    title_font = load_font(bold_font_path, 48)
    subtitle_font = load_font(font_path, 20)
    footer_font = load_font(font_path, 17)

    columns = 3 if len(panels) >= 5 else 2
    rows = math.ceil(len(panels) / columns)
    cell_size = (520, 693)
    margin = 32
    gutter = 18
    title_height = 120
    footer_height = 52
    page_width = margin * 2 + columns * cell_size[0] + (columns - 1) * gutter
    page_height = (
        margin * 2
        + title_height
        + rows * cell_size[1]
        + (rows - 1) * gutter
        + footer_height
    )
    page = Image.new("RGB", (page_width, page_height), (10, 12, 18))
    draw = ImageDraw.Draw(page)

    title = args.title or storyboard.get("title", "AI COMIC")
    subtitle = args.subtitle or storyboard.get("subtitle", "")
    draw.text((margin, margin), title, font=title_font, fill=(246, 246, 248))
    draw.rectangle(
        (margin, margin + 68, margin + 96, margin + 74),
        fill=(210, 32, 48),
    )
    if subtitle:
        draw.text((margin, margin + 86), subtitle, font=subtitle_font, fill=(165, 172, 188))

    images_dir = Path(args.images_dir)
    for index, panel in enumerate(panels):
        row, column = divmod(index, columns)
        x = margin + column * (cell_size[0] + gutter)
        y = margin + title_height + row * (cell_size[1] + gutter)
        panel_image = render_panel(panel, images_dir, cell_size, body_font)
        page.paste(panel_image, (x, y))
        draw.rectangle(
            (x - 1, y - 1, x + cell_size[0], y + cell_size[1]),
            outline=(48, 54, 68),
            width=2,
        )

    footer = storyboard.get("footer", "AI COMIC / COMFYUI / 168")
    draw.text(
        (margin, page_height - margin - 24),
        footer,
        font=footer_font,
        fill=(122, 130, 148),
    )

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    page.save(output)
    print(f"saved {output} ({page_width}x{page_height})")


if __name__ == "__main__":
    main()
