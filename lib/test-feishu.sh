#!/bin/bash
# lib/test-feishu.sh — 飞书集成 E2E 测试
#
# 执行 7 项检测：安装 / 授权 / 创建文档 / Base 写入 / 权限 / larkbridge / API 兼容
#
# 用法：
#   bash lib/test-feishu.sh                 # 全量测试
#   bash lib/test-feishu.sh --skip-cleanup  # 测试后不清理

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/colors.sh"
source "$SCRIPT_DIR/path-helper.sh"

FEISHU_CONF="$(resolve_conf feishu.json 2>/dev/null)" || true
MARKER_FILE="$HOME/.lark-cli-account"

TESTS_PASSED=0; TESTS_FAILED=0; TESTS_SKIPPED=0
CLEANUP_DOCS=(); CLEANUP_RECORDS=()
TEST_DOC_URL=""

_ok()   { echo -e "  ${GREEN}✅${NC} $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
_fail() { echo -e "  ${RED}❌${NC} $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }
_skip() { echo -e "  ${YELLOW}○${NC} $1"; TESTS_SKIPPED=$((TESTS_SKIPPED + 1)); }

_lark() {
  local d="$1"; shift
  LARKSUITE_CLI_CONFIG_DIR="$d" PATH="$HOME/.local/bin:$PATH" lark-cli "$@" 2>&1 | grep -v '^\[lark-cli\]' || true
}

_get_active_config() {
  local name="" cfg=""
  if [ -f "$MARKER_FILE" ]; then
    name=$(grep '^name=' "$MARKER_FILE" 2>/dev/null | cut -d'=' -f2)
    cfg=$(grep '^configDir=' "$MARKER_FILE" 2>/dev/null | cut -d'=' -f2)
  fi
  cfg="${cfg:-${LARKSUITE_CLI_CONFIG_DIR:-$HOME/.lark-cli}}"
  cfg="${cfg/#\~/$HOME}"
  echo "${name:-?}|$cfg"
}

cleanup_resources() {
  echo -e "${CYAN}── 清理测试资源 ──${NC}"
  echo -e "  ${YELLOW}⚠ 上方测试资源请在飞书中手动删除${NC}"
  echo ""
}

main() {
  local ACTIVE_INFO; ACTIVE_INFO=$(_get_active_config)
  local ACTIVE_NAME="${ACTIVE_INFO%%|*}"
  local ACTIVE_DIR="${ACTIVE_INFO#*|}"
  if [ -z "$ACTIVE_DIR" ]; then
    _fail "无法获取 lark-cli 活跃 configDir"
    echo -e "  ${YELLOW}请先: bash ccconfig/option-larkcli/lark-switch.sh <name>${NC}"
    return 1
  fi
  echo -e "  账号: ${GREEN}${ACTIVE_NAME}${NC} (${ACTIVE_DIR})"
  echo ""

  # 1) lark-cli 安装
  echo -e "${CYAN}── 1/7 lark-cli 安装 ──${NC}"
  if command -v lark-cli &>/dev/null; then
    local v; v=$(lark-cli --version 2>/dev/null | head -1 | sed 's/^[^0-9]*//')
    _ok "lark-cli v${v}"
  else _fail "未安装 (npm install -g @larksuite/cli)"
  fi
  echo ""

  # 2) OAuth 授权
  echo -e "${CYAN}── 2/7 OAuth 授权 ──${NC}"
  local ao; ao=$(_lark "$ACTIVE_DIR" auth status 2>/dev/null) || true
  if echo "$ao" | grep -q '"tokenStatus".*"valid"'; then
    local uid; uid=$(echo "$ao" | python3 -c "
import json,sys
d=json.load(sys.stdin)
u=d.get('identities',{}).get('user',{})
print(u.get('userName','?')+' ('+u.get('openId','?')+')')" 2>/dev/null)
    _ok "OAuth 有效 — $uid"
  else _fail "OAuth 未授权"
  fi
  echo ""

  # 3) 创建文档
  echo -e "${CYAN}── 3/7 创建文档 ──${NC}"
  local ts; ts=$(date +%s)
  local doc_out
  doc_out=$(echo '# 飞书 E2E 测试文档' | _lark "$ACTIVE_DIR" docs +create --api-version v2 --doc-format markdown --as user --title "ccconfig-e2e-${ts}" --content - 2>/dev/null) || true
  local doc_ok; doc_ok=$(echo "$doc_out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('ok','false'))" 2>/dev/null || echo "false")
  if [ "$doc_ok" = "True" ]; then
    local did; did=$(echo "$doc_out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',{}).get('document',{}).get('document_id',''))" 2>/dev/null)
    doc_url=$(echo "$doc_out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',{}).get('document',{}).get('url',''))" 2>/dev/null)
    _ok "文档已创建"
    TEST_DOC_URL="$doc_url"
    CLEANUP_DOCS+=("$did")
    echo "    $doc_url"
  else
    local em; em=$(echo "$doc_out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('error',{}).get('message','?'))" 2>/dev/null)
    _fail "创建失败: $em"
  fi
  echo ""

  # 4) Base Worklog 写入
  echo -e "${CYAN}── 4/7 Base Worklog 写入 ──${NC}"
  local fc="${HOME}/git/skill/plugins/flogme/config.yaml"
  if [ ! -f "$fc" ]; then _skip "flogme config.yaml 不存在"; else
    local bc; bc=$(python3 -c "
import yaml, json
c = yaml.safe_load(open('${fc}'))
b = c['bases']['okr_v2']
print(json.dumps({'token': b['token'], 'table': b['tables']['Worklog']}))
" 2>/dev/null) || true
    if [ -z "$bc" ]; then _fail "解析 config.yaml 失败"; else
      local bt; bt=$(echo "$bc" | python3 -c "import json,sys; print(json.load(sys.stdin)['token'])")
      local tb; tb=$(echo "$bc" | python3 -c "import json,sys; print(json.load(sys.stdin)['table'])")
      local payload; payload=$(python3 -c "import json; print(json.dumps({'fields':['标题','成果类型','关联KR','日期','说明'], 'rows':[['ccconfig-e2e-${ts}','工具开发',[{'id':'recvmWXG8X7gZA'}],'2026-08-10','e2e']]}))")
      local bf; bf=$(mktemp /tmp/ccconfig-e2e-XXXXXX.json)
      echo "$payload" > "$bf"
      local bfn; bfn=$(basename "$bf")
      local bo
      bo=$(cd /tmp && LARKSUITE_CLI_CONFIG_DIR="$ACTIVE_DIR" PATH="$HOME/.local/bin:$PATH" lark-cli base +record-batch-create --base-token "$bt" --table-id "$tb" --as user --json "@${bfn}" 2>&1 | grep -v '^\[lark-cli\]') || true
      rm -f "$bf"
      local bok; bok=$(echo "$bo" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('ok','false'))" 2>/dev/null || echo "false")
      if [ "$bok" = "True" ]; then
        local rid; rid=$(echo "$bo" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',{}).get('record_id_list',['?'])[0])" 2>/dev/null)
        local tenant_domain; tenant_domain="rcnejwuhyp41.feishu.cn"  # 从 flogme config 取
        if [ -f "$fc" ]; then
          tenant_domain=$(python3 -c "import yaml; print(yaml.safe_load(open('${fc}')).get('tenant_domain','rcnejwuhyp41.feishu.cn'))" 2>/dev/null || echo "rcnejwuhyp41.feishu.cn")
        fi
        _ok "Worklog 已写入"
        echo "    https://${tenant_domain}/base/${bt}/table/${tb}/record/${rid}"
        CLEANUP_RECORDS+=("$rid|$bt|$tb|$tenant_domain")
      else
        local em; em=$(echo "$bo" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('error',{}).get('message','?'))" 2>/dev/null)
        _fail "Base 写入失败: $em"
      fi
    fi
  fi
  echo ""

  # 5) 权限完整性
  echo -e "${CYAN}── 5/7 权限完整性 ──${NC}"
  if [ -z "$FEISHU_CONF" ] || [ ! -f "$FEISHU_CONF" ]; then _skip "feishu.json 不存在"; else
    source "$SCRIPT_DIR/feishu-perms.sh" 2>/dev/null || { _skip "feishu-perms.sh 不可用"; }
    local aid; aid=$(python3 - "$FEISHU_CONF" "${ACTIVE_NAME}" << 'PYEOF' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
for a in d.get('apps',[]):
  if a.get('name') == sys.argv[2]: print(a.get('appId','')); break
PYEOF
)
    local asec; asec=$(python3 - "$FEISHU_CONF" "${ACTIVE_NAME}" << 'PYEOF' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
for a in d.get('apps',[]):
  if a.get('name') == sys.argv[2]: print(a.get('appSecret','')); break
PYEOF
)
    if [ -n "$aid" ] && [ -n "$asec" ]; then
      local rc=0; local result; result=$(_feishu_check_perms "$aid" "$asec" 2>&1) || rc=$?
      if [ "$rc" -eq 0 ]; then _ok "权限组全部通过"
      elif [ "$rc" -eq 1 ]; then _fail "权限缺失"; echo "$result" | grep 'MISSING' | sed 's/^/    /'
      else _skip "权限检测失败: $(echo "$result" | head -1)"
      fi
    else _skip "找不到 ${ACTIVE_NAME} 的 appId/appSecret"
    fi
  fi
  echo ""

  # 6) larkbridge
  echo -e "${CYAN}── 6/7 larkbridge ──${NC}"
  if command -v lark-channel-bridge &>/dev/null; then
    local lv; lv=$(lark-channel-bridge --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?")
    if systemctl --user is-active lark-channel-bridge.service &>/dev/null 2>&1; then _ok "lark-channel-bridge v${lv} (systemd)"
    elif pgrep -f "lark-channel-bridge" &>/dev/null; then _ok "lark-channel-bridge v${lv} (进程)"
    else _skip "lark-channel-bridge v${lv} 已装未运行"
    fi
  else _skip "lark-channel-bridge 未安装"
  fi
  echo ""

  # 7) API 兼容性
  echo -e "${CYAN}── 7/7 API 兼容性 ──${NC}"
  if _lark "$ACTIVE_DIR" docs +create --help 2>/dev/null | grep -q 'doc-format'; then
    _ok "v2 API 命令兼容"
  else _fail "lark-cli 版本过旧，缺少 --doc-format"
  fi
  echo ""

  # 清理
  if [[ "${1:-}" != "--skip-cleanup" ]]; then
    cleanup_resources "$ACTIVE_DIR"
  fi

  # 汇总
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${GREEN}通过: ${TESTS_PASSED}${NC}  ${RED}失败: ${TESTS_FAILED}${NC}  ${YELLOW}跳过: ${TESTS_SKIPPED}${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  return $([ "$TESTS_FAILED" -gt 0 ] && echo 1 || echo 0)
}

main "$@"
