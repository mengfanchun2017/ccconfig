#!/usr/bin/env python3
"""feedme preferences & history manager — single-file JSON store."""
import json, sys, os
from datetime import datetime

CONF_DIR = os.path.expanduser("~/.claude/projects/-home-francis-git/conf/feedme")
CONF_FILE = os.path.join(CONF_DIR, "feedme.json")

DEFAULT = {
    "mcd": {
        "token": "",
        "mcp_configured": False
    },
    "preferences": {
        "taste": [],        # ["spicy", "sweet", "savory"]
        "favorites": [],    # ["巨无霸", "麦辣鸡腿堡"]
        "dislikes": [],     # []
        "budget": 50,       # max per order CNY
        "meal_time": {      # preferred meal windows
            "breakfast": "06:00-10:30",
            "lunch": "11:00-14:00",
            "dinner": "17:00-21:00"
        }
    },
    "addresses": [
        # {"id": "addr_1", "city": "北京", "contactName": "张三", "phone": "13800138000",
        #  "address": "朝阳区", "addressDetail": "xxx路xxx号x层", "beType": 2}
    ],
    "history": [
        # {"action": "order", "items": [...], "store": "...", "total": 32.0, "time": "2026-05-20T12:00:00"}
    ]
}

def load():
    os.makedirs(CONF_DIR, exist_ok=True)
    if not os.path.exists(CONF_FILE):
        save(DEFAULT)
        return DEFAULT
    with open(CONF_FILE) as f:
        return json.load(f)

def save(data):
    os.makedirs(CONF_DIR, exist_ok=True)
    with open(CONF_FILE, 'w') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

def get_path(data, path):
    """dot-separated path getter: 'preferences.taste'"""
    parts = path.split('.')
    for p in parts:
        if isinstance(data, dict) and p in data:
            data = data[p]
        else:
            return None
    return data

def set_path(data, path, value):
    parts = path.split('.')
    target = data
    for p in parts[:-1]:
        if p not in target:
            target[p] = {}
        target = target[p]
    target[parts[-1]] = value
    return data

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("usage: prefs.py <get|set|add-history|list-keys> [path] [value]", file=sys.stderr)
        sys.exit(1)

    cmd = sys.argv[1]
    data = load()

    if cmd == 'get':
        path = sys.argv[2] if len(sys.argv) > 2 else None
        if path:
            val = get_path(data, path)
            print(json.dumps(val, ensure_ascii=False, indent=2))
        else:
            print(json.dumps(data, ensure_ascii=False, indent=2))

    elif cmd == 'set':
        path = sys.argv[2]
        val = json.loads(sys.argv[3]) if len(sys.argv) > 3 else None
        data = set_path(data, path, val)
        save(data)
        print("OK")

    elif cmd == 'add-history':
        entry = json.loads(sys.argv[2])
        entry['time'] = entry.get('time', datetime.now().isoformat())
        data['history'].insert(0, entry)
        if len(data['history']) > 1000:
            data['history'] = data['history'][:1000]
        save(data)
        print("OK")

    elif cmd == 'list-keys':
        def flatten(d, prefix=''):
            keys = []
            for k, v in d.items():
                full = f"{prefix}.{k}" if prefix else k
                if isinstance(v, dict) and not isinstance(v, list):
                    keys.extend(flatten(v, full))
                else:
                    keys.append(full)
            return keys
        for k in flatten(data):
            print(k)

    elif cmd == 'init':
        save(DEFAULT)
        print(f"Initialized {CONF_FILE}")

    elif cmd == 'show':
        print(json.dumps(data, ensure_ascii=False, indent=2))

    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)
