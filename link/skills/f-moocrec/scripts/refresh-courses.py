#!/usr/bin/env python3
"""refresh-courses.py — 刷新 Supabase 课程数据库

定期检查课程链接有效性，更新价格和状态。
Usage: python3 refresh-courses.py [--check-urls] [--update-prices]
"""

import json
import requests
import sys
from datetime import date

API_URL = "https://api.supabase.com/v1/projects/<your-supabase-project-id>/database/query"
ACCESS_TOKEN = "<your-supabase-access-token>"
HEADERS = {
    "Authorization": f"Bearer {ACCESS_TOKEN}",
    "Content-Type": "application/json",
}


def query(sql):
    r = requests.post(API_URL, headers=HEADERS, json={"query": sql}, timeout=30)
    r.raise_for_status()
    return r.json()


def check_urls():
    """检查所有课程 URL 是否仍可访问"""
    courses = query("SELECT id, name, url FROM courses WHERE is_active = true;")
    for c in courses:
        try:
            r = requests.head(c["url"], timeout=10, allow_redirects=True)
            if r.status_code >= 400:
                print(f"⚠️  {c['name']}: HTTP {r.status_code}")
            else:
                print(f"✅ {c['name']}: OK")
        except Exception as e:
            print(f"❌ {c['name']}: {e}")


def update_verified_date():
    """更新最后验证日期"""
    today = date.today().isoformat()
    result = query(
        f"UPDATE courses SET last_verified_date = '{today}' WHERE is_active = true;"
    )
    print(f"Updated last_verified_date to {today}")


if __name__ == "__main__":
    if "--check-urls" in sys.argv:
        check_urls()
    elif "--update-prices" in sys.argv:
        print("Price update not yet implemented")
    else:
        update_verified_date()
        print("Run with --check-urls to verify course links")
