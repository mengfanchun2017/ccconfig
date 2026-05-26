#!/usr/bin/env python3
"""从 PDF 提取图片。支持 PyMuPDF（优先）和纯 Python zlib 回退。"""

import os
import sys
import zlib
import struct
from pathlib import Path

MIN_IMAGE_BYTES = 2048
MIN_IMAGE_PIXELS = 100
MIN_IMAGE_AREA = 30000


def extract_with_pymupdf(pdf_path: str, output_dir: str) -> list[str]:
    """PyMuPDF 方式提取（推荐，支持更多格式）。"""
    import fitz

    doc = fitz.open(pdf_path)
    extracted = []
    seen = set()

    for i, page in enumerate(doc, 1):
        for j, img in enumerate(page.get_images(full=True)):
            xref = img[0]
            base_image = doc.extract_image(xref)
            image_bytes = base_image["image"]
            ext = base_image["ext"]

            if len(image_bytes) < MIN_IMAGE_BYTES:
                continue

            img_hash = hash(image_bytes)
            if img_hash in seen:
                continue
            seen.add(img_hash)

            out_name = f"p{i:02d}_{j:02d}.{ext}"
            out_path = os.path.join(output_dir, out_name)
            with open(out_path, "wb") as f:
                f.write(image_bytes)
            extracted.append(out_path)
            print(f"  [OK] {out_name} ({len(image_bytes)} bytes)")

    doc.close()
    return extracted


def extract_pure_python(pdf_path: str, output_dir: str) -> list[str]:
    """纯 Python 方式提取（无 PyMuPDF 回退）。DCTDecode→jpg, FlateDecode→png。"""
    extracted = []
    seen = set()

    with open(pdf_path, "rb") as f:
        data = f.read()

    # 查找 stream/endstream 对并解析
    import re

    obj_pattern = re.compile(rb'/(Type|Subtype)\s*/\w+\s*/\w+\s*/\w+')
    stream_pattern = re.compile(rb'stream\r?\n(.*?)endstream', re.DOTALL)
    filter_pattern = re.compile(rb'/Filter\s*/(\w+)')
    width_pattern = re.compile(rb'/Width\s+(\d+)')
    height_pattern = re.compile(rb'/Height\s+(\d+)')

    for i, match in enumerate(stream_pattern.finditer(data)):
        stream_data = match.group(1).rstrip(b'\r\n')

        # 找最近的前一个对象的 filter
        pre_data = data[max(0, match.start() - 500):match.start()]
        filter_match = filter_pattern.search(pre_data)
        w_match = width_pattern.search(pre_data)
        h_match = height_pattern.search(pre_data)

        if not filter_match:
            continue

        filt = filter_match.group(1).decode()
        w = int(w_match.group(1)) if w_match else 0
        h = int(h_match.group(1)) if h_match else 0

        if w < MIN_IMAGE_PIXELS or h < MIN_IMAGE_PIXELS:
            continue
        if w * h < MIN_IMAGE_AREA:
            continue

        try:
            if filt == "DCTDecode":
                ext = "jpg"
                img_data = stream_data
            elif filt == "FlateDecode":
                ext = "png"
                img_data = zlib.decompress(stream_data)
            else:
                continue
        except Exception:
            continue

        if len(img_data) < MIN_IMAGE_BYTES:
            continue

        img_hash = hash(img_data)
        if img_hash in seen:
            continue
        seen.add(img_hash)

        out_name = f"img_{i:03d}.{ext}"
        out_path = os.path.join(output_dir, out_name)
        with open(out_path, "wb") as f:
            f.write(img_data)
        extracted.append(out_path)
        print(f"  [OK] {out_name} {w}x{h} {filt} ({len(img_data)} bytes)")

    return extracted


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <input.pdf> <output_dir>")
        sys.exit(1)

    pdf_path = sys.argv[1]
    output_dir = sys.argv[2]
    os.makedirs(output_dir, exist_ok=True)

    try:
        import fitz
        print("[INFO] 使用 PyMuPDF 提取图片...")
        extracted = extract_with_pymupdf(pdf_path, output_dir)
    except ImportError:
        print("[INFO] PyMuPDF 未安装，使用纯 Python 回退...")
        extracted = extract_pure_python(pdf_path, output_dir)

    print(f"\n提取完成: {len(extracted)} 张图片 → {output_dir}")
    return extracted


if __name__ == "__main__":
    main()
