#!/usr/bin/env python3
"""Create slides in Base with proper links to presentations."""
import json
import re
import subprocess
import os
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

BASE_TOKEN = "JnXYbjiR9aZOFrsuOGUc09mXnZd"
PRES_TABLE = "tblgJhdGJlTxf5S7"
SLIDES_TABLE = "tblORDssdq53f3Mz"

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


def run_cmd(cmd_args, timeout=120):
    result = subprocess.run(cmd_args, capture_output=True, text=True, timeout=timeout, cwd=WORK_DIR)
    lines = [l for l in result.stdout.split('\n') if not l.startswith('[lark-cli]')]
    stdout = '\n'.join(lines).strip()
    if not stdout:
        return None, f"Empty stdout, stderr: {result.stderr[:200]}"
    try:
        return json.loads(stdout), None
    except json.JSONDecodeError as e:
        return None, f"JSON error: {e}"


def api_get(path, timeout=60):
    """Call lark-cli API and return parsed JSON."""
    result = subprocess.run(
        ["lark-cli", "api", "GET", path, "--format", "json"],
        capture_output=True, text=True, timeout=timeout
    )
    stdout = result.stdout
    start = stdout.find('{')
    end = stdout.rfind('}') + 1
    if start >= 0 and end > start:
        return json.loads(stdout[start:end])
    return None


def get_all_presentation_records():
    """Fetch all presentation records using pagination."""
    all_data = []
    all_rids = []
    page_token = ""
    while True:
        path = f"/open-apis/base/v3/bases/{BASE_TOKEN}/tables/{PRES_TABLE}/records?page_size=50"
        if page_token:
            path += f"&page_token={page_token}"
        resp = api_get(path)
        if not resp or resp.get('code') != 0:
            print(f"  API error: {resp}")
            break
        inner = resp['data']
        rids = inner.get('record_id_list', [])
        rows = inner.get('data', [])
        fid_list = inner.get('field_id_list', [])
        all_rids.extend(rids)
        all_data.extend(zip(rids, rows, [fid_list] * len(rows)))
        has_more = inner.get('has_more', False)
        page_token = inner.get('page_token', '')
        print(f"  Fetched {len(rids)} records (total: {len(all_rids)}, has_more={has_more})")
        if not has_more:
            break

    # Build PID -> record_id map
    pid_to_record = {}
    for rid, row, fid_list in all_data:
        try:
            pid_idx = fid_list.index('fldrz0qop2')  # Presentation ID field
            pid = row[pid_idx]
            if pid:
                pid_to_record[pid] = rid
        except (ValueError, IndexError):
            pass
    return pid_to_record


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
            return xml, None
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


def extract_all_ppts():
    """Extract all PPT data in parallel."""
    results = {}
    failed = []
    with ThreadPoolExecutor(max_workers=6) as pool:
        futures = {pool.submit(get_slides, item[1]): item for item in ALL_SLIDES}
        for i, future in enumerate(as_completed(futures), 1):
            item = futures[future]
            label, pid, cat = item
            xml, err = future.result()
            if err:
                failed.append((label, pid, err))
                print(f"  [{i}/{len(ALL_SLIDES)}] FAIL {label}: {err}")
            else:
                slides = extract_slides_data(xml)
                total_imgs = sum(s['img_count'] for s in slides)
                results[pid] = {
                    'label': label.split(' > ')[-1],
                    'pid': pid,
                    'cat': cat,
                    'slide_count': len(slides),
                    'img_count': total_imgs,
                    'slides': slides
                }
                print(f"  [{i}/{len(ALL_SLIDES)}] OK {results[pid]['label']} ({len(slides)} s, {total_imgs} imgs)")
    return results, failed


def main():
    os.chdir(WORK_DIR)

    # Step 1: Get presentation record IDs
    print("=== Step 1: Fetching presentation records ===")
    pid_to_record = get_all_presentation_records()
    print(f"Found {len(pid_to_record)} presentation records")

    if not pid_to_record:
        print("ERROR: No presentation records found!")
        sys.exit(1)

    # Step 2: Extract all PPT data
    print("\n=== Step 2: Extracting PPT data ===")
    cache_file = "./ppt_extract_cache.json"
    if os.path.exists(cache_file):
        with open(cache_file) as f:
            cache = json.load(f)
        results = cache['results']
        failed = cache.get('failed', [])
        print(f"Loaded {len(results)} PPTs from cache")
    else:
        results, failed = extract_all_ppts()
        with open(cache_file, "w") as f:
            json.dump({'results': results, 'failed': failed}, f, ensure_ascii=False)
        print(f"\nFetched: {len(results)}/{len(ALL_SLIDES)}, Failed: {len(failed)}")

    # Step 3: Build slide rows with links
    print("\n=== Step 3: Building slide rows ===")
    all_slide_rows = []
    skipped = 0
    for pid, d in results.items():
        pres_record_id = pid_to_record.get(pid)
        if not pres_record_id:
            print(f"  SKIP: no record for PID {pid} ({d.get('label', '?')})")
            skipped += 1
            continue
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
                pres_record_id,
            ]
            all_slide_rows.append(row)

    total_slides = len(all_slide_rows)
    print(f"Total slides to create: {total_slides} (skipped {skipped} PPTs without records)")

    # Step 4: Create slides in batches of 200
    print("\n=== Step 4: Creating slides ===")
    batch_size = 200
    for batch_start in range(0, total_slides, batch_size):
        batch_num = batch_start // batch_size
        batch_rows = all_slide_rows[batch_start:batch_start + batch_size]

        slides_json = {"fields": SLIDES_FIELDS, "rows": batch_rows}
        fname = f"./slides_batch_{batch_num}.json"
        with open(fname, "w") as f:
            json.dump(slides_json, f, ensure_ascii=False)
        print(f"  Batch {batch_num}: {len(batch_rows)} rows, {os.path.getsize(fname)} bytes")

        data, err = run_cmd(["lark-cli", "base", "+record-batch-create",
                             "--base-token", BASE_TOKEN,
                             "--table-id", SLIDES_TABLE,
                             "--json", f"@{fname}"], timeout=120)
        if err:
            print(f"  ERROR: {err}")
        else:
            ok = data.get('ok')
            n = len(data.get('data', {}).get('record_id_list', []))
            print(f"  Batch {batch_num}: {n} created, ok={ok}")

    print(f"\nDone! {total_slides} slides created.")
    if failed:
        print(f"Failed PPTs ({len(failed)}):")
        for label, pid, err in failed:
            print(f"  - {label}: {err}")


if __name__ == "__main__":
    main()
