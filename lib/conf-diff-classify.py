#!/usr/bin/env python3
"""conf/*.json 模板 vs ccprivate 差异分类器。

模板用占位符（请填入*/<xxx>/$HOME 变量），本地是真实值 —— 这类差异是
**预期且良性**的，不该当"需要同步"警告。本脚本把差异分为两类：

  命令: python3 conf-diff-classify.py <example> <local>
  输出: 0 = 完全一致 / 仅占位符差异 → 可忽略
        1 = 存在真实差异 → 需人工确认
  附带 stderr 输出差异明细。
"""
import json, re, sys

PH_PATTERNS = [
    r'^请填入', r'^请到.*获取', r'^你的', r'^your[- ]',
    r'^<[^/].*>$', r'^\$HOME', r'^~', r'^\.\.\.$',
]
PH_KEY_RE = r'<[^/]+>|your[- ]|placeholder|\.\.\.'


def is_ph_str(v):
    if not isinstance(v, str):
        return False
    s = v.strip()
    core = re.sub(r'[:/].*$', '', s) if s.startswith('<') else s
    return any(re.search(p, s) or re.search(p, core) for p in PH_PATTERNS)


def is_ph_key(k):
    return isinstance(k, str) and bool(re.search(PH_KEY_RE, k))


def is_meta_key(k):
    return isinstance(k, str) and k.startswith('_')


def normalize(node):
    if isinstance(node, dict):
        out = {}
        ph_vals = []
        for k, v in node.items():
            if is_meta_key(k):
                continue
            nv, v_ph = normalize(v)
            if is_ph_key(k):
                ph_vals.append(nv)
            elif v_ph:
                out[k] = "__PH__"
            else:
                out[k] = nv
        if ph_vals:
            # 占位符键（如 supabase tokens.<project-name>）值归一化后与真实键
            # 不要求完全对齐 —— 只要占位符键存在，视为该槽已被本地真实键替代
            out["__PH_KEYS__"] = "__PH__"
        return out, False
    if isinstance(node, list):
        out = []
        for x in node:
            nx, x_ph = normalize(x)
            out.append("__PH__" if x_ph else nx)
        return out, False
    if isinstance(node, str):
        if re.search(r'<[^/]{2,}>', node) or re.search(r':<\w+>', node):
            return "__PH__", True
        s = re.sub(r'^/home/[^/]+', '$HOME', node)
        if is_ph_str(s) or s != node:
            return "__PH__", True
        return node, False
    return node, False


def collect_real_diff(a, b, path="", notes=None):
    """返回真实差异明细列表（占位符差异已豁免）。"""
    if notes is None:
        notes = []
    if a == "__PH__" or b == "__PH__":
        return notes
    if isinstance(a, dict) and isinstance(b, dict):
        # 占位符键 <project-name> 槽 vs 真实键 bwater：视为同槽，跳过该 dict
        if ("__PH_KEYS__" in a and "__PH_KEYS__" not in b and not any(k.startswith("__") for k in b)) or \
           ("__PH_KEYS__" in b and "__PH_KEYS__" not in a and not any(k.startswith("__") for k in a)):
            return notes
        for k in sorted(set(a) | set(b)):
            if k == "__PH_KEYS__":
                continue  # 占位符键槽位标记，不参与真实 diff
            kp = f"{path}.{k}" if path else k
            if k not in a:
                notes.append(f"{kp}: 仅模板有")
            elif k not in b:
                notes.append(f"{kp}: 仅本地有")
            else:
                collect_real_diff(a[k], b[k], kp, notes)
    elif isinstance(a, list) and isinstance(b, list):
        if a != b:
            if len(a) == len(b):
                for i, (x, y) in enumerate(zip(a, b)):
                    collect_real_diff(x, y, f"{path}[{i}]", notes)
            else:
                notes.append(f"{path}: 列表长度 {len(a)}→{len(b)}")
    else:
        if a != b:
            notes.append(f"{path}: {str(a)[:40]!r} → {str(b)[:40]!r}")
    return notes


def main():
    if len(sys.argv) != 3:
        print("用法: conf-diff-classify.py <example> <local>", file=sys.stderr)
        sys.exit(2)
    try:
        a = json.load(open(sys.argv[1]))
        b = json.load(open(sys.argv[2]))
    except Exception as e:
        print(f"解析失败: {e}", file=sys.stderr)
        sys.exit(0)  # 解析失败不算差异告警（另有 JSON 校验兜底）

    if a == b:
        print("一致")
        sys.exit(0)
    na, _ = normalize(a)
    nb, _ = normalize(b)
    notes = collect_real_diff(na, nb)
    if notes:
        for n in notes:
            print(f"  {n}", file=sys.stderr)
        print(f"{len(notes)} 处真实差异")
        sys.exit(1)
    print("仅占位符差异（正常）")
    sys.exit(0)


if __name__ == "__main__":
    main()