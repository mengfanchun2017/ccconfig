#!/bin/bash
# 疑似凭据的统一正则 —— 唯一真相源。
#
# 消费方：hooks/pre-commit（提交前扫描）、lib/example-sync.sh（反向同步写公开库前扫描）。
# 从前两处各写一份，改了前缀必然漂移（实测漏过 tavily/cloudflare/supabase/Exa 四类）。
# 新增服务 key 前缀只改这里。
#
# 用法：source 本文件后使用 $SECRET_RE
#   source "$CCCONFIG_ROOT/lib/secret-patterns.sh"

# shellcheck disable=SC2034  # 由 source 方使用
SECRET_RE='sk-[a-zA-Z0-9]{20,}|sk-ant-[a-zA-Z0-9_-]{20,}|gho_[a-zA-Z0-9]{36}|ghp_[a-zA-Z0-9]{36}|github_pat_[a-zA-Z0-9_]{20,}|eyJ[a-zA-Z0-9_-]{20,}\.[a-zA-Z0-9_-]{20,}|tvly-[A-Za-z0-9-]{16,}|cfut_[A-Za-z0-9]{16,}|sbp_[A-Fa-f0-9]{16,}|"x-api-key"[[:space:]]*:[[:space:]]*"[a-f0-9-]{36}"'