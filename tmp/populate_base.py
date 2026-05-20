#!/usr/bin/env python3
"""Extract all PPT data and populate Base using file-based JSON."""
import json
import re
import subprocess
import sys
import time
import os
from concurrent.futures import ThreadPoolExecutor, as_completed

BASE_TOKEN = "JnXYbjiR9aZOFrsuOGUc09mXnZd"
PRES_TABLE = "tblgJhdGJlTxf5S7"
SLIDES_TABLE = "tblORDssdq53f3Mz"

PRES_FIELDS = ["fldi7gcjEL", "fldsz67jw4", "fldrz0qop2", "fld13OW6Yb", "fld9goMg18", "fldyT5Httg"]
SLIDES_FIELDS = ["fldfqbGtJd", "fldekQXlvT", "fldCeSY0uy", "fldN8uV84x", "fldLTJeyaH", "fldPVJTfNH", "fldlCpyWVz"]

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

WORK_DIR = "/home/francis/git/ccconfig/tmp"


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


def run_cmd(cmd_args, timeout=120):
    """Run command from WORK_DIR and return parsed JSON."""
    result = subprocess.run(cmd_args, capture_output=True, text=True, timeout=timeout, cwd=WORK_DIR)
    lines = [l for l in result.stdout.split('\n') if not l.startswith('[lark-cli]')]
    stdout = '\n'.join(lines).strip()
    if not stdout:
        return None, f"Empty stdout, stderr: {result.stderr[:200]}"
    try:
        return json.loads(stdout), None
    except json.JSONDecodeError as e:
        return None, f"JSON error: {e}, stdout: {stdout[:300]}"


def main():
    os.chdir(WORK_DIR)

    # Check for cached extraction
    cache_file = "./ppt_extract_cache.json"
    if os.path.exists(cache_file):
        print(f"Loading cached extraction from {cache_file}")
        with open(cache_file) as f:
            cache = json.load(f)
        results = cache.get('results', {})
        failed = cache.get('failed', [])
    else:
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
                    print(f"[{i}/{len(ALL_SLIDES)}] OK {data['label']} ({data['slide_count']} s, {data['img_count']} imgs)")
        # Cache results
        with open(cache_file, "w") as f:
            json.dump({'results': results, 'failed': failed}, f, ensure_ascii=False)

    print(f"\nFetched: {len(results)}/{len(ALL_SLIDES)}, Failed: {len(failed)}")

    # Step 1: Create Presentations
    print("\n=== Step 1: Creating Presentations ===")
    pres_rows = []
    for label, pid, cat in ALL_SLIDES:
        if pid not in results:
            continue
        d = results[pid]
        pres_rows.append([
            d['label'],
            d['wiki_url'],
            d['pid'],
            d['slide_count'],
            d['img_count'],
            d['cat'],
        ])

    pres_json = {"fields": PRES_FIELDS, "rows": pres_rows}
    with open("./pres_batch.json", "w") as f:
        json.dump(pres_json, f, ensure_ascii=False)

    data, err = run_cmd(["lark-cli", "base", "+record-batch-create",
                         "--base-token", BASE_TOKEN,
                         "--table-id", PRES_TABLE,
                         "--json", "@pres_batch.json"])
    if err:
        print(f"ERROR creating presentations: {err}")
        return
    print(f"Presentations: {data}")

    pres_record_ids = data.get('data', {}).get('record_id_list', [])
    print(f"Created {len(pres_record_ids)} presentation records")

    # Build pid -> record_id map
    pid_to_record = {}
    idx = 0
    for label, pid, cat in ALL_SLIDES:
        if pid in results and idx < len(pres_record_ids):
            pid_to_record[pid] = pres_record_ids[idx]
            idx += 1

    # Step 2: Create Slides in batches
    print("\n=== Step 2: Creating Slides ===")
    all_slide_rows = []
    for label, pid, cat in ALL_SLIDES:
        if pid not in results:
            continue
        d = results[pid]
        for page_num, slide in enumerate(d['slides'], 1):
            title = slide['texts'][0] if slide['texts'] else ""
            full = "\n".join(slide['texts'])
            img_tokens_str = ",".join(slide['img_tokens']) if slide['img_tokens'] else ""
            row = [
                slide['id'],
                page_num,
                title,
                full,
                img_tokens_str,
                slide['img_count'],
                None,  # 所属PPT - will link later
            ]
            all_slide_rows.append((pid, row))

    total_slides = len(all_slide_rows)
    print(f"Total slides: {total_slides}")

    batch_size = 200
    for batch_start in range(0, total_slides, batch_size):
        batch = all_slide_rows[batch_start:batch_start + batch_size]
        batch_rows = [row for _, row in batch]
        slides_json = {"fields": SLIDES_FIELDS, "rows": batch_rows}

        fname = f"./slides_batch_{batch_start//batch_size}.json"
        with open(fname, "w") as f:
            json.dump(slides_json, f, ensure_ascii=False)

        data, err = run_cmd(["lark-cli", "base", "+record-batch-create",
                             "--base-token", BASE_TOKEN,
                             "--table-id", SLIDES_TABLE,
                             "--json", f"@{fname}"], timeout=120)
        if err:
            print(f"ERROR batch {batch_start//batch_size}: {err}")
        else:
            n = len(data.get('data', {}).get('record_id_list', []))
            print(f"Batch {batch_start//batch_size + 1}: {n} slides created")

    # Step 3: Link slides to presentations
    print("\n=== Step 3: Linking slides to presentations ===")
    # We need to read back all slide record_ids and link them
    # This requires listing slides and updating links
    # For now, skip linking - can be done later via UI or script

    total_imgs = sum(results[pid]['img_count'] for pid in results)
    print(f"\nSummary: {len(results)} PPTs, {total_slides} slides, {total_imgs} images")
    if failed:
        print(f"Failed ({len(failed)}):")
        for label, pid, err in failed:
            print(f"  - {label}: {err}")


if __name__ == "__main__":
    main()
