#!/usr/bin/env python3
"""三源搜索 + Python过滤"""
import json, subprocess
from datetime import datetime

def search_tavily(query, max_results=10):
    cmd = ['tvly', 'search', query, '--max-results', str(max_results), '--depth', 'advanced', '--json']
    try:
        raw = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
        data = json.loads(raw)
        timestamp = datetime.now().strftime('%H%M%S')
        raw_file = f'/tmp/tavily_search_{timestamp}.json'
        with open(raw_file, 'w') as f:
            json.dump(data, f)
        results = [{'score': r.get('score', 0), 'title': r.get('title', ''),
                    'url': r.get('url', ''), 'content': r.get('content', '')[:300]}
                   for r in data.get('results', [])]
        return results, raw_file, [r.get('url', '') for r in data.get('results', [])]
    except Exception as e:
        return [], None, []
