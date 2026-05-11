#!/usr/bin/env python3
"""Generate carbon-style code screenshots using Pygments + PIL."""
import sys
import argparse
from pathlib import Path
from pygments import highlight
from pygments.lexers import guess_lexer, get_lexer_by_name
from pygments.formatters import ImageFormatter
from PIL import Image, ImageDraw, ImageFilter


def generate_screenshot(code: str, output: str, language: str = None, bg: str = "#1e1e1e"):
    lexer = get_lexer_by_name(language) if language else guess_lexer(code)

    # Render syntax-highlighted code to PNG with padding
    formatter = ImageFormatter(
        style="monokai",
        line_numbers=False,
        font_name="DejaVu Sans Mono",
        font_size=16,
        line_pad=6,
        image_pad=40,
        background_color=bg,
        hl_lines=[],
    )
    img_data = highlight(code, lexer, formatter)

    # Save to temp then add carbon-style decorations
    tmp = "/tmp/carbon_tmp.png"
    with open(tmp, "wb") as f:
        f.write(img_data)

    img = Image.open(tmp)
    w, h = img.size

    # Add extra top bar (like carbon.sh window controls)
    bar_h = 50
    new_h = h + bar_h
    canvas = Image.new("RGBA", (w, new_h), bg)
    canvas.paste(img, (0, bar_h))

    draw = ImageDraw.Draw(canvas)
    # Window dots
    colors = ["#FF5F56", "#FFBD2E", "#27C93F"]
    for i, c in enumerate(colors):
        draw.ellipse([28 + i * 28, 16, 46 + i * 28, 34], fill=c)

    canvas.save(output)
    Path(tmp).unlink()
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate carbon-style code screenshot")
    parser.add_argument("--code", help="Code string or @filepath to read from")
    parser.add_argument("--lang", default=None, help="Language for syntax highlighting")
    parser.add_argument("--output", default="/tmp/carbon-output.png", help="Output PNG path")
    args = parser.parse_args()

    code = args.code
    if code and code.startswith("@"):
        code = Path(code[1:]).read_text()
    elif not code:
        code = sys.stdin.read()

    output = generate_screenshot(code, args.output, args.lang)
    print(output)
