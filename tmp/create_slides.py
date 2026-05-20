#!/usr/bin/env python3
"""Create slides in Base with proper links to presentations. One-shot script."""
import json, re, subprocess, os, sys
from concurrent.futures import ThreadPoolExecutor, as_completed

BASE_TOKEN = "JnXYbjiR9aZOFrsuOGUc09mXnZd"
PRES_TABLE = "tblgJhdGJlTxf5S7"
SLIDES_TABLE = "tblORDssdq53f3Mz"
SLIDES_FIELDS = ["fldfqbGtJd", "fldekQXlvT", "fldCeSY0uy", "fldN8uV84x", "fldLTJeyaH", "fldPVJTfNH", "fldlCpyWVz"]

ALL_SLIDES = [
    ("交流 > 20260327 运维交流", "YKuLsfuu8ltq6fddzYgccMBFnyd"),
    ("交流 > 20260210_规划交流目录", "RGFKsRALnlH3YKdtAudcrtMYnHE"),
    ("交流 > 20260106_综保交流目录", "BjuvsZmRAlLoJ2dC0PucD0Ftnu0"),
    ("交流 > 20260205_运维AI团队选拔目录", "RKXssW2I7lxzYNdTtOxcFcBinBh"),
    ("交流 > 选拔 > 运维部AI智能体开发人员选拔方案", "DiTus19xjlDB0YdxEMRcZ3HBnkb"),
    ("成本 > AI平台云成本管控-20260513", "UI83syinWlmLP1dV42Gc3MeQncw"),
    ("成本 > AI平台云成本管控-20260513 副本", "FrENs3EBclJcQPdnOeTcsic5npe"),
    ("成本 > AI平台云成本管控-20260508", "L9YYsm49SlJO2GdYqBocQHs7nhe"),
    ("成本 > AI平台云成本管控-20260415", "VBFxsEIZElVjxgdGA1Hcf0GGnbd"),
    ("成本 > 中航云成本管控-20260127", "HIFbstfWClgE0CdpLvJcYVMVnjg"),
    ("成本 > 中航云成本管控-20260120", "Q2WHs32uElOrTzdEAxmcBZvSnvg"),
    ("AI platform > AI module", "CHXbsT0MqldbOXdf4NLcrgRrnBh"),
    ("AI everyone > res", "XoIvsLZcBltLUBdUzM6cwumtnvb"),
    ("AI everyone > q&a", "MiV0spPjTlCBJbduF2CcEnxPnOf"),
    ("AI everyone > application", "ZS4CsNfbElWF3ldZgwPcXP9Cnxd"),
    ("AI everyone > nl2sql", "HsHzs05uRliNzKdJZCOcaLBIn1g"),
    ("AI everyone > dataflow", "G1fNsj2aqlTmp2di7NXca5oUn9c"),
    ("AI everyone > rag&ft", "WlZlsSGxElVIwGdQlUacRlQjncS"),
    ("AI everyone > mece", "GJYasJJvzl7JDZddQAqcyv1WnYd"),
    ("AI everyone > use case > customer service", "SU1Zso0F3lA4iEdZ034cBr38nLg"),
    ("AI everyone > use case > procurement", "G8OFsjTdAlDaw9dK4I7cuzQ5nVe"),
    ("AI everyone > key tech > llm basic", "XTTosRyYzlUbaod37RJcvh7dnTf"),
    ("AI everyone > key tech > llm advanced", "B88NsSvAKlRD9gdEeWzcOOHQn4d"),
    ("AI everyone > pptnemo > 由知到智_202512", "Nr5hszC5llvwHXdS9PCcY8dmnvh"),
    ("AI digging > extention", "IjZfsfmbxlrhQodC9H1cX2vpnhb"),
    ("AI digging > prompt", "WM2XsIrvblsmiAdnZd0cCPXKn0f"),
    ("AI digging > agent > cozespace", "LJKish2tylk2BXdjBAfcD1ZBn7T"),
    ("AI digging > agent > ally", "QmbpsL8V8lZBoDdwvlKcbdr2nvh"),
    ("AI digging > agent > OpenClaw 使用指南", "Ej6ksi5OclNvlKdjvRrcC9xOnhe"),
    ("AI digging > agent > ClaudeCode", "CUdwsq2jklQPZddv8hIcshUlnxd"),
    ("AI digging > AI agent Try", "PwMisw2JglqDlWdt9xucikUYnge"),
    ("AI solution > PPTs", "AEFJsNSKClH6RndGNfyceVw5nqd"),
    ("IMDOMC AI Roadmap 2026", "Xl30svAB7l8PuHd7OoWcFKosnXb"),
    ("template > tp白底通用模板_202508", "CWUosfLGflnU03da3TVc0Q7tnVf"),
    ("template > tpFrancis_Course_20260110", "BpYasGvq1lxK6qd9a4CcpV2Hn1b"),
    ("template > tpFrancis_AC_20260112", "E8l0sbFVAlCBXodD8s5cFN9XnKc"),
]

WORK_DIR = "/home/francis/git/ccconfig/tmp"

def cmd(args, timeout=120):
    r = subprocess.run(args, capture_output=True, text=True, timeout=timeout, cwd=WORK_DIR)
    lines = [l for l in r.stdout.split('\n') if not l.startswith('[lark-cli]')]
    stdout = '\n'.join(lines).strip()
    if not stdout:
        return None, f"Empty stdout: {r.stderr[:200]}"
    try:
        return json.loads(stdout), None
    except json.JSONDecodeError as e:
        return None, f"JSON error: {e}"

def get_pres_records():
    """Get all presentation record IDs via shortcut."""
    data, err = cmd(["lark-cli", "base", "+record-list",
                     "--base-token", BASE_TOKEN,
                     "--table-id", PRES_TABLE,
                     "--limit", "500",
                     "--format", "json"])
    if err:
        print(f"ERROR: {err}")
        return {}
    inner = data['data']
    fid_list = inner.get('field_id_list', [])
    pid_idx = fid_list.index('fldrz0qop2')
    pid_to_record = {}
    for rid, row in zip(inner.get('record_id_list', []), inner.get('data', [])):
        pid = row[pid_idx] if pid_idx < len(row) else ''
        if pid:
            pid_to_record[pid] = rid
    return pid_to_record

def get_slides_xml(pid):
    result = subprocess.run(
        ["lark-cli", "slides", "xml_presentations", "get",
         "--params", json.dumps({"xml_presentation_id": pid}),
         "--format", "json"],
        capture_output=True, text=True, timeout=45)
    lines = [l for l in result.stdout.split('\n') if not l.startswith('[lark-cli]')]
    stdout = '\n'.join(lines).strip()
    if not stdout:
        return None
    data = json.loads(stdout)
    if data.get('code') == 0:
        return data['data']['xml_presentation']['content']
    return None

def extract_slides(xml):
    slides = []
    for m in re.finditer(r'<slide\s+id="([^"]*)"[^>]*>(.*?)</slide>', xml, re.DOTALL):
        sid = m.group(1)
        content = m.group(2)
        texts = []
        for pm in re.finditer(r'<p[^>]*>(.*?)</p>', content, re.DOTALL):
            clean = re.sub(r'<[^>]+>', '', pm.group(1)).strip()
            if clean:
                texts.append(clean)
        img_tokens = re.findall(r'<img[^>]*src="([^"]*)"', content)
        slides.append({'id': sid, 'texts': texts, 'img_tokens': img_tokens})
    return slides

def main():
    os.chdir(WORK_DIR)

    # Step 1: Get presentation records
    print("=== Step 1: Get presentation records ===")
    pid_to_record = get_pres_records()
    print(f"Found {len(pid_to_record)} presentation records")

    # Step 2: Extract PPTs (cached)
    print("\n=== Step 2: Extract PPT data ===")
    cache_file = "./ppt_extract_cache.json"
    if os.path.exists(cache_file):
        with open(cache_file) as f:
            results = json.load(f)['results']
        print(f"Loaded {len(results)} PPTs from cache")
    else:
        results = {}
        failed = []
        with ThreadPoolExecutor(max_workers=6) as pool:
            futures = {}
            for label, pid in ALL_SLIDES:
                futures[pool.submit(get_slides_xml, pid)] = (label, pid)
            for i, future in enumerate(as_completed(futures), 1):
                label, pid = futures[future]
                xml = future.result()
                if xml is None:
                    failed.append((label, pid))
                    print(f"  [{i}/{len(ALL_SLIDES)}] FAIL {label}")
                else:
                    slides = extract_slides(xml)
                    total_imgs = sum(len(s['img_tokens']) for s in slides)
                    results[pid] = {
                        'label': label.split(' > ')[-1],
                        'slides': slides,
                        'img_count': total_imgs,
                        'slide_count': len(slides)
                    }
                    print(f"  [{i}/{len(ALL_SLIDES)}] OK {results[pid]['label']} ({len(slides)}s, {total_imgs}imgs)")
        with open(cache_file, "w") as f:
            json.dump({'results': results, 'failed': failed}, f, ensure_ascii=False)
        print(f"Extracted: {len(results)}/{len(ALL_SLIDES)}")

    # Step 3: Build slide rows
    print("\n=== Step 3: Build slide rows ===")
    all_rows = []
    skipped = []
    for pid, d in results.items():
        pres_rid = pid_to_record.get(pid)
        if not pres_rid:
            skipped.append(pid)
            continue
        for pn, slide in enumerate(d['slides'], 1):
            title = slide['texts'][0] if slide['texts'] else ""
            full = "\n".join(slide['texts'])
            imgs = ",".join(slide['img_tokens']) if slide['img_tokens'] else ""
            all_rows.append([slide['id'], pn, title, full, imgs, len(slide['img_tokens']), pres_rid])

    print(f"Total slides: {len(all_rows)}, skipped PPTs without records: {len(skipped)}")

    # Step 4: Create slides in batches
    print("\n=== Step 4: Create slides ===")
    for start in range(0, len(all_rows), 200):
        batch = all_rows[start:start+200]
        n = start // 200
        fname = f"./slides_batch_{n}.json"
        with open(fname, "w") as f:
            json.dump({"fields": SLIDES_FIELDS, "rows": batch}, f, ensure_ascii=False)
        sz = os.path.getsize(fname)

        data, err = cmd(["lark-cli", "base", "+record-batch-create",
                         "--base-token", BASE_TOKEN,
                         "--table-id", SLIDES_TABLE,
                         "--json", f"@{fname}"], timeout=120)
        if err:
            print(f"  Batch {n} ERROR: {err}")
        else:
            c = len(data.get('data', {}).get('record_id_list', []))
            print(f"  Batch {n}: {c} slides ({sz}B)")

    print(f"\nDone! {len(all_rows)} slides created.")

if __name__ == "__main__":
    main()
