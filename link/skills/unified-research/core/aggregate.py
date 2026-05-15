#!/usr/bin/env python3
"""结果聚合去重"""
def deduplicate_by_url(results):
    seen = set()
    unique = []
    for r in results:
        url = r.get('url', '')
        if url and url not in seen:
            seen.add(url)
            unique.append(r)
    return unique

def mark_confidence(results):
    item_groups = {}
    for r in results:
        key = r.get('url', '') or r.get('title', '')
        if key not in item_groups:
            item_groups[key] = []
        item_groups[key].append(r)
    for key, group in item_groups.items():
        sources = set(r.get('_source', '') for r in group)
        has_content = any(len(r.get('content', '')) > 100 for r in group)
        confidence = 'high' if len(sources) >= 2 else ('medium' if has_content else 'low')
        for r in group:
            r['_confidence'] = confidence
    return results

def extract_name(title):
    return title.split('|')[0].split('-')[0].split(':')[0].strip() or 'Unknown'

def generate_summary(results):
    if not results:
        return "No results"
    sources = {}
    for r in results:
        src = r.get('_source', 'unknown')
        sources[src] = sources.get(src, 0) + 1
    high = sum(1 for r in results if r.get('_confidence') == 'high')
    return f"Total: {len(results)} | Sources: {sources} | High: {high}"
