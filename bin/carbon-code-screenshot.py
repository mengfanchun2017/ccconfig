#!/usr/bin/env python3
"""Generate carbon-style code screenshots using Pygments + PIL."""
import sys
import argparse
from pathlib import Path
from pygments import highlight
from pygments.lexers import guess_lexer, get_lexer_by_name
from pygments.formatters import ImageFormatter
# PIL no longer needed — ImageFormatter writes PNG directly


def generate_screenshot(code: str, output: str, language: str = None, bg: str = "#1e1e1e"):
    lexer = get_lexer_by_name(language) if language else guess_lexer(code)

    # Render syntax-highlighted code to PNG with padding
    formatter = ImageFormatter(
        style="monokai",
        line_numbers=False,
        font_name="DejaVu Sans Mono",
        font_size=26,
        line_pad=10,
        image_pad=56,
        background_color=bg,
        hl_lines=[],
    )
    img_data = highlight(code, lexer, formatter)
    with open(output, "wb") as f:
        f.write(img_data)
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
