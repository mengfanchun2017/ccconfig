#!/bin/bash
# 疑似凭据的统一正则 —— 唯一真相源。
#
# 消费方：hooks/pre-commit（提交前扫描）、lib/example-sync.sh（反向同步写公开库前扫描）。
# 从前两处各写一份，改了前缀必然漂移（实测漏过 tavily/cloudflare/supabase/Exa 四类）。
# 新增服务 key 前缀只改这里。
#
# 用法：source 本文件后使用 $SECRET_RE
#   source "$CCCONFIG_ROOT/lib/secret-patterns.sh"

# 飞书 Base 导出类（第 2 组）是 2026-10-25 事故的补漏：lark-cli 导出的 *.manifest.json
# 含真实 base_token/table_id 与 record_id/file_token，旧规则一个都不认，于是被 auto-sync
# 直接推上公开库。这组按 JSON 字段名匹配（不是裸 token 形状），保持零误报 ——
# 实测对当时全部 221 个被跟踪文件命中 0。
#
# shellcheck disable=SC2034  # 由 source 方使用
SECRET_RE='sk-[a-zA-Z0-9]{20,}|sk-ant-[a-zA-Z0-9_-]{20,}|gho_[a-zA-Z0-9]{36}|ghp_[a-zA-Z0-9]{36}|github_pat_[a-zA-Z0-9_]{20,}|eyJ[a-zA-Z0-9_-]{20,}\.[a-zA-Z0-9_-]{20,}|tvly-[A-Za-z0-9-]{16,}|cfut_[A-Za-z0-9]{16,}|sbp_[A-Fa-f0-9]{16,}|sb_secret_[A-Za-z0-9_-]{20,}|sb_publishable_[A-Za-z0-9_-]{20,}|"x-api-key"[[:space:]]*:[[:space:]]*"[a-f0-9-]{36}"|"base_token"[[:space:]]*:[[:space:]]*"[A-Za-z0-9]{16,}"|"table_id"[[:space:]]*:[[:space:]]*"tbl[A-Za-z0-9]{10,}"|"file_token"[[:space:]]*:[[:space:]]*"[A-Za-z0-9]{20,}"|"record_id"[[:space:]]*:[[:space:]]*"rec[A-Za-z0-9]{12,}"'