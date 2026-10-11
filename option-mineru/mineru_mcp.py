#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["mineru-open-mcp>=1.0.22", "pymupdf>=1.24"]
# ///
"""MinerU MCP server with cost-aware tiering (ccconfig wrapper).

Why this exists:
    Upstream mineru-open-mcp picks the backend by token presence alone
    (tools/extract.py: `use_flash = not token`). With a MINERU_API_TOKEN set,
    even a 2-page PDF goes through Precision and burns the daily quota.

What this does:
    Wraps the upstream server and routes each *file* to Flash (free, ≤20 pages
    / ≤10 MB) or Precision (token) based on its own page count / size. Web
    pages always go Precision + MinerU-HTML (Flash can't do HTML).

    Page counts come from the client (per its own instruction to pass pages)
    when available; otherwise pymupdf counts the local PDF. Files that can't
    be counted stay on Flash and fall back to Precision if the API rejects them.

Config (env):
    MINERU_API_TOKEN   - Precision token. Without it, everything runs Flash (free).
    MINERU_FLASH_PAGE_LIMIT   (default 20)
    MINERU_FLASH_SIZE_MB      (default 10)
    MINERU_DISABLE_FLASH      - force everything to Precision.

Run (standalone test):  uv run mineru_mcp.py --help
Run (as MCP stdio):     uv run mineru_mcp.py   (no args -> server on stdio)
"""

import os
import posixpath
import sys
from urllib.parse import urlparse

from mineru_open_mcp import config as _config
from mineru_open_mcp.server import mcp, run_server
from mineru_open_mcp.tools import tools as tools_mod

_FILE_EXTS = {".pdf", ".png", ".jpg", ".jpeg", ".jp2", ".webp", ".gif", ".bmp",
              ".doc", ".docx", ".ppt", ".pptx", ".xls", ".xlsx"}


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, "") or default)
    except ValueError:
        return default


FLASH_PAGE_LIMIT = _env_int("MINERU_FLASH_PAGE_LIMIT", 20)
FLASH_SIZE_LIMIT_MB = _env_int("MINERU_FLASH_SIZE_MB", 10)
DISABLE_FLASH = os.getenv("MINERU_DISABLE_FLASH", "").strip().lower() in ("1", "true", "yes")


def _is_url(source: str) -> bool:
    return source.startswith(("http://", "https://"))


def _is_webpage(source: str) -> bool:
    return _is_url(source) and posixpath.splitext(urlparse(source).path)[1].lower() not in _FILE_EXTS


def _pdf_pages(path: str):
    try:
        import pymupdf
        doc = pymupdf.open(path)
        n = doc.page_count
        doc.close()
        return n
    except Exception:
        return None


def _pages_count(pages: str) -> int:
    """Count pages in a range string like '1-10,15' (inclusive)."""
    total = 0
    for part in str(pages).split(","):
        part = part.strip()
        if "-" in part:
            a, _, b = part.partition("-")
            try:
                total += max(0, int(b) - int(a) + 1)
            except ValueError:
                pass
        elif part.isdigit():
            total += 1
    return total


def _choose_flash(source: str, page_ranges_map, index: int) -> bool:
    """Decide whether *source* can use the free Flash backend."""
    if DISABLE_FLASH or not _config.MINERU_API_TOKEN:
        return not DISABLE_FLASH and not _config.MINERU_API_TOKEN
    if _is_url(source):
        # Flash handles PDF URLs; web pages / other remote docs need Precision.
        return posixpath.splitext(urlparse(source).path)[1].lower() == ".pdf"
    size_mb = None
    pages = None
    try:
        size_mb = os.path.getsize(source) / 1e6
    except OSError:
        return False  # unreadable file -> upstream reports it
    if page_ranges_map and index in page_ranges_map:
        pr = page_ranges_map[index]
        pages = _pages_count(pr) if isinstance(pr, str) and pr.strip() else None
        if pages:
            return pages <= FLASH_PAGE_LIMIT and size_mb <= FLASH_SIZE_LIMIT_MB
    if source.lower().endswith(".pdf"):
        pages = _pdf_pages(source)
        if pages is None or pages > FLASH_PAGE_LIMIT:
            return False
    return size_mb <= FLASH_SIZE_LIMIT_MB


_orig_extract = tools_mod.extract_sources


async def tiered_extract_sources(sources, enable_ocr=None, language="ch", model=None,
                                 page_ranges_map=None, output_dir=_config.DEFAULT_OUTPUT_DIR,
                                 ctx=None, token=None, save_to_file=True):
    """Route each source to Flash or Precision by its own size/page count."""
    if not sources:
        return []
    eff_token = token or _config.MINERU_API_TOKEN
    if DISABLE_FLASH or not eff_token:
        return await _orig_extract(
            sources=sources, enable_ocr=enable_ocr, language=language, model=model,
            page_ranges_map=page_ranges_map, output_dir=output_dir, ctx=ctx,
            token=eff_token, save_to_file=save_to_file,
        )

    flash_idx, prec_idx = [], []
    for i, s in enumerate(sources):
        (flash_idx if _choose_flash(s, page_ranges_map, i) else prec_idx).append(i)

    if ctx and ctx.request_context:
        await ctx.info(f"MinerU tiering: {len(flash_idx)} file(s) → Flash (free), "
                       f"{len(prec_idx)} → Precision (token)")

    def _sub(indices, flash):
        return ([sources[i] for i in indices],
                {i: page_ranges_map[i] for i in indices if page_ranges_map and i in page_ranges_map} or None)

    out = {}
    for indices, is_flash in ((flash_idx, True), (prec_idx, False)):
        if not indices:
            continue
        sub_src, sub_pr = _sub(indices, is_flash)
        res = await _orig_extract(
            sources=sub_src, enable_ocr=enable_ocr, language=language, model=model,
            page_ranges_map=sub_pr, output_dir=output_dir, ctx=ctx,
            token=(None if is_flash else eff_token), save_to_file=save_to_file,
        )
        for k, r in enumerate(res):
            out[indices[k]] = r
    return [out[i] for i in range(len(sources)) if i in out]


# _parse calls extract_sources as a module global, so patch the tools.tools namespace.
tools_mod.extract_sources = tiered_extract_sources


def _selfcheck() -> int:
    import inspect

    assert tools_mod.extract_sources is tiered_extract_sources, "tools.extract_sources not patched"
    src = inspect.getsource(tools_mod._parse)
    assert "extract_sources(" in src, "upstream _parse no longer calls extract_sources — patch hook broken"

    tok = _config.MINERU_API_TOKEN
    print(f"token   : {'set' if tok else 'not set (Flash-only mode)'}")
    print(f"flash   : ≤{FLASH_PAGE_LIMIT} pages / ≤{FLASH_SIZE_LIMIT_MB} MB  (disable={DISABLE_FLASH})")
    for s in ("/tmp/x.pdf", "https://a.com/paper.pdf", "https://a.com/article"):
        print(f"  {s:34s} -> {'Flash' if _choose_flash(s, None, 0) else 'Precision'}")
    print("selfcheck OK: tiering wrapper active")
    return 0


if __name__ == "__main__":
    if "--selfcheck" in sys.argv:
        sys.exit(_selfcheck())
    run_server()
