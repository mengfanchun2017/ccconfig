#!/usr/bin/env python3
"""Extract all PPT data and generate batch-create JSON for Base population."""
import json
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

BASE_TOKEN = "JnXYbjiR9aZOFrsuOGUc09mXnZd"
PRES_TABLE = "tblgJhdGJlTxf5S7"
SLIDES_TABLE = "tblORDssdq53f3Mz"

# Field IDs for Presentations table
PRES_FIELDS = ["fldi7gcjEL", "fldsz67jw4", "fldrz0qop2", "fld13OW6Yb", "fld9goMg18", "fldyT5Httg"]
# Fields: 名称, Wiki URL, Presentation ID, 页数, 图片数, 分类

# Field IDs for Slides table
SLIDES_FIELDS = ["fldfqbGtJd", "fldekQXlvT", "fldCeSY0uy", "fldN8uV84x", "fldLTJeyaH", "fldPVJTfNH", "fldlCpyWVz"]
# Fields: Slide ID, 页码, 标题文本, 完整文本, 图片Tokens, 图片数, 所属PPT

ALL_SLIDES = [
    ("交流 > 20260327 运维交流", "YKuLsfuu8ltq6fddzYgccMBFnyd", "交流"),
    ("交流 > 20260210_规划交流目录", "RGFKsRALnlH3YKdtAudcrtMYnHE", "交流"),
    ("交流 > 20260106_综保交流目录", "BjuvsZmRAlLoJ2dC0PucD0Ftnu0", "交流"),
    ("交流 > 20260205_运维AI团队选拔目录", "RKXssW2I7lxzYNdTtOxcFcBinBh", "交流"),
    ("交流 > 选拔 > 运维部AI智能体开发人员选拔方案", "DiTus19xjlDB0YdxEMRcZ3HBnkb", "交流"),
    ("成本 > AI平台云成本管控-20260513", "UI83syinWlmLP1dV42Gc3MeQncw", "成本"),
    ("成本 > AI平台云成本管控-20260513 副本", "FrENs3EBclJcQPdnOeTcsic5npe", "成本"),
    ("成本 > AI平台云成本管控-20260508", "L9YYsm49SlJO2GdYqBocQHs7nhe", "成本"),
    ("成本 > AI平台云成本管控-20260415", "VBFxsEIZElVjxgdGA1Hcf0GGnbd", "成本"),
    ("成本 > 中航云成本管控-20260127", "HIFbstfWClgE0CdpLvJcYVMVnjg", "成本"),
    ("成本 > 中航云成本管控-20260120", "Q2WHs32uElOrTzdEAxmcBZvSnvg", "成本"),
    ("AI platform > AI module", "CHXbsT0MqldbOXdf4NLcrgRrnBh", "AI platform"),
    ("AI everyone > res", "XoIvsLZcBltLUBdUzM6cwumtnvb", "AI everyone"),
    ("AI everyone > q&a", "MiV0spPjTlCBJbduF2CcEnxPnOf", "AI everyone"),
    ("AI everyone > application", "ZS4CsNfbElWF3ldZgwPcXP9Cnxd", "AI everyone"),
    ("AI everyone > nl2sql", "HsHzs05uRliNzKdJZCOcaLBIn1g", "AI everyone"),
    ("AI everyone > dataflow", "G1fNsj2aqlTmp2di7NXca5oUn9c", "AI everyone"),
    ("AI everyone > rag&ft", "WlZlsSGxElVIwGdQlUacRlQjncS", "AI everyone"),
    ("AI everyone > mece", "GJYasJJvzl7JDZddQAqcyv1WnYd", "AI everyone"),
    ("AI everyone > use case > customer service", "SU1Zso0F3lA4iEdZ034cBr38nLg", "AI everyone"),
    ("AI everyone > use case > procurement", "G8OFsjTdAlDaw9dK4I7cuzQ5nVe", "AI everyone"),
    ("AI everyone > key tech > llm basic", "XTTosRyYzlUbaod37RJcvh7dnTf", "AI everyone"),
    ("AI everyone > key tech > llm advanced", "B88NsSvAKlRD9gdEeWzcOOHQn4d", "AI everyone"),
    ("AI everyone > pptnemo > 由知到智_202512", "Nr5hszC5llvwHXdS9PCcY8dmnvh", "AI everyone"),
    ("AI digging > extention", "IjZfsfmbxlrhQodC9H1cX2vpnhb", "AI digging"),
    ("AI digging > prompt", "WM2XsIrvblsmiAdnZd0cCPXKn0f", "AI digging"),
    ("AI digging > agent > cozespace", "LJKish2tylk2BXdjBAfcD1ZBn7T", "AI digging"),
    ("AI digging > agent > ally", "QmbpsL8V8lZBoDdwvlKcbdr2nvh", "AI digging"),
    ("AI digging > agent > OpenClaw 使用指南", "Ej6ksi5OclNvlKdjvRrcC9xOnhe", "AI digging"),
    ("AI digging > agent > ClaudeCode", "CUdwsq2jklQPZddv8hIcshUlnxd", "AI digging"),
    ("AI digging > AI agent Try", "PwMisw2JglqDlWdt9xucikUYnge", "AI digging"),
    ("AI solution > PPTs", "AEFJsNSKClH6RndGNfyceVw5nqd", "AI solution"),
    ("IMDOMC AI Roadmap 2026", "Xl30svAB7l8PuHd7OoWcFKosnXb", "规划"),
    ("template > tp白底通用模板_202508", "CWUosfLGflnU03da3TVc0Q7tnVf", "模板"),
    ("template > tpFrancis_Course_20260110", "BpYasGvq1lxK6qd9a4CcpV2Hn1b", "模板"),
    ("template > tpFrancis_AC_20260112", "E8l0sbFVAlCBXodD8s5cFN9XnKc", "模板"),
]


def get_slides(pid):
    cmd = [
        "lark-cli", "slides", "xml_presentations", "get",
        "--params", json.dumps({"xml_presentation_id": pid}),
        "--format", "json"
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=45)
        lines = [l for l in result.stdout.split('\n') if not l.startswith('[lark-cli]')]
        stdout = '\n'.join(lines).strip()
        if not stdout:
            return None, "Empty output"
        data = json.loads(stdout)
        if data.get('code') == 0:
            xml = data['data']['xml_presentation']['content']
            rev = data['data']['xml_presentation'].get('revision_id', '?')
            return xml, rev
        return None, data.get('msg', 'Unknown')
    except Exception as e:
        return None, str(e)


def extract_slides_data(xml):
    """Extract slide ID, text, and image tokens from XML."""
    slides = []
    for m in re.finditer(r'<slide\s+id="([^"]*)"[^>]*>(.*?)</slide>', xml, re.DOTALL):
        sid = m.group(1)
        content = m.group(2)
        texts = []
        for pm in re.finditer(r'<p[^>]*>(.*?)</p>', content, re.DOTALL):
            ptext = pm.group(1)
            clean = re.sub(r'<[^>]+>', '', ptext)
            clean = clean.strip()
            if clean:
                texts.append(clean)
        # Extract image tokens
        img_tokens = []
        for im in re.finditer(r'<img[^>]*src="([^"]*)"', content):
            img_tokens.append(im.group(1))
        slides.append({
            'id': sid,
            'texts': texts,
            'img_tokens': img_tokens,
            'img_count': len(img_tokens)
        })
    return slides


def process_one(item):
    label, pid, cat = item
    xml, info = get_slides(pid)
    if xml is None:
        return None, label, pid, cat, info
    slides = extract_slides_data(xml)
    wiki_url = f"https://www.feishu.cn/wiki/{pid}"
    total_imgs = sum(s['img_count'] for s in slides)
    return {
        'label': label.split(' > ')[-1],
        'pid': pid,
        'cat': cat,
        'wiki_url': wiki_url,
        'slide_count': len(slides),
        'img_count': total_imgs,
        'slides': slides
    }, None, None, None, None


def cmd(cmd_args):
    """Run lark-cli command."""
    result = subprocess.run(cmd_args, capture_output=True, text=True, timeout=30)
    lines = [l for l in result.stdout.split('\n') if not l.startswith('[lark-cli]')]
    return '\n'.join(lines).strip()


def main():
    print("Fetching all PPTs in parallel...")
    results = {}
    failed = []

    with ThreadPoolExecutor(max_workers=6) as pool:
        futures = {pool.submit(process_one, item): item for item in ALL_SLIDES}
        for i, future in enumerate(as_completed(futures), 1):
            data, label, pid, cat, err = future.result()
            if err:
                failed.append((label, pid, err))
                print(f"[{i}/{len(ALL_SLIDES)}] FAIL {label}: {err}")
            else:
                results[data['pid']] = data
                print(f"[{i}/{len(ALL_SLIDES)}] OK {data['label']} ({data['slide_count']} slides, {data['img_count']} imgs)")

    print(f"\nFetched: {len(results)}/{len(ALL_SLIDES)}, Failed: {len(failed)}")

    # Step 1: Create Presentations records
    print("\n--- Creating Presentations records ---")
    pres_rows = []
    for label, pid, cat in ALL_SLIDES:
        if pid not in results:
            continue
        d = results[pid]
        pres_rows.append([
            d['label'],           # 名称
            d['wiki_url'],        # Wiki URL
            d['pid'],             # Presentation ID
            d['slide_count'],     # 页数
            d['img_count'],       # 图片数
            d['cat'],             # 分类
        ])

    # Write Presentations batch JSON
    pres_json = {"fields": PRES_FIELDS, "rows": pres_rows}
    with open("./pres_batch.json", "w") as f:
        json.dump(pres_json, f, ensure_ascii=False)
    print(f"Wrote {len(pres_rows)} presentation rows to pres_batch.json")

    # Step 2: Upload Presentations
    print("Uploading Presentations...")
    out = cmd(["lark-cli", "base", "+record-batch-create",
               "--base-token", BASE_TOKEN,
               "--table-id", PRES_TABLE,
               "--json", json.dumps(pres_json)])
    print(out[:500])

    # Parse presentation record_ids (need for linking slides)
    try:
        pres_result = json.loads(out)
        pres_record_ids = pres_result.get('data', {}).get('record_id_list', [])
        print(f"Created {len(pres_record_ids)} presentation records")
    except:
        print("Failed to parse presentation result, will need to query record IDs")
        pres_record_ids = []

    # Build pid -> record_id map
    pid_to_record = {}
    if pres_record_ids:
        for i, (label, pid, cat) in enumerate(ALL_SLIDES):
            if pid in results and i < len(pres_record_ids):
                pid_to_record[pid] = pres_record_ids[i]

    # Step 3: Create Slides records (in batches of 200)
    print("\n--- Creating Slides records ---")
    all_slide_rows = []
    for label, pid, cat in ALL_SLIDES:
        if pid not in results:
            continue
        d = results[pid]
        for page_num, slide in enumerate(d['slides'], 1):
            # Title text = first text block (or empty)
            title = slide['texts'][0] if slide['texts'] else ""
            # Full text = all texts joined
            full = "\n".join(slide['texts'])
            # Image tokens
            img_tokens_str = ",".join(slide['img_tokens']) if slide['img_tokens'] else ""

            row = [
                slide['id'],            # Slide ID
                page_num,               # 页码
                title,                  # 标题文本
                full,                   # 完整文本
                img_tokens_str,         # 图片Tokens
                slide['img_count'],     # 图片数
                None,                   # 所属PPT (will fill after)
            ]
            all_slide_rows.append((pid, row))

    # Batch create slides (200 per batch)
    for batch_start in range(0, len(all_slide_rows), 200):
        batch = all_slide_rows[batch_start:batch_start+200]
        batch_rows = [row for _, row in batch]
        slides_json = {"fields": SLIDES_FIELDS, "rows": batch_rows}

        out = cmd(["lark-cli", "base", "+record-batch-create",
                   "--base-token", BASE_TOKEN,
                   "--table-id", SLIDES_TABLE,
                   "--json", json.dumps(slides_json)])
        print(f"Slides batch {batch_start//200 + 1}: {len(batch_rows)} rows -> {out[:200]}")

    print(f"\nTotal slides to create: {len(all_slide_rows)}")
    print("Done! Slides created without links (links need record IDs).")

    # Save mapping for later link updates
    with open("./pid_record_map.json", "w") as f:
        json.dump(pid_to_record, f, ensure_ascii=False)

    total_slides = sum(len(results[pid]['slides']) for pid in results)
    total_imgs = sum(results[pid]['img_count'] for pid in results)
    print(f"\nSummary: {len(results)} PPTs, {total_slides} slides, {total_imgs} images")
    if failed:
        print(f"Failed: {len(failed)}")
        for label, pid, err in failed:
            print(f"  - {label}: {err}")


if __name__ == "__main__":
    main()
