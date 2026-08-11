#!/bin/bash
# ==============================================
# json-validate.sh — JSON Schema 校验助手
#
# 功能：
#   - assert_json <file> <schema_name>  校验文件符合 schema；失败 exit 1
#   - try_assert_json                    同上，但不退出，返回 0/1
#   - validate_all_conf                  校验所有 conf/*.json
#
# 用法：
#   source "$LIB_DIR/json-validate.sh"
#   assert_json "$MCP_CONF_FILE" mcp
#
# 要求：python3 + python3-jsonschema
#   apt install -y python3-jsonschema
# ==============================================

_SCHEMA_DIR="${JSON_SCHEMA_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/conf/schema}"

# 内部：跑一次校验，输出错误到 stderr
# 返回: 0=通过, 1=失败
_do_validate() {
    local file="$1"
    local schema_name="$2"
    local schema_file="$_SCHEMA_DIR/${schema_name}.schema.json"

    if [ ! -f "$file" ]; then
        echo "[json-validate] file not found: $file" >&2
        return 1
    fi
    if [ ! -f "$schema_file" ]; then
        echo "[json-validate] schema not found: $schema_file" >&2
        return 1
    fi

    if ! python3 -c "import jsonschema" 2>/dev/null; then
        echo "[json-validate] python3-jsonschema not installed (apt install python3-jsonschema)" >&2
        return 1
    fi

    python3 - "$file" "$schema_file" << 'PYEOF'
import json, sys
try:
    from jsonschema import Draft7Validator
    with open(sys.argv[1]) as f:
        data = json.load(f)
    with open(sys.argv[2]) as f:
        schema = json.load(f)
    v = Draft7Validator(schema)
    errors = list(v.iter_errors(data))
    if errors:
        for e in errors[:5]:
            path = "/".join(str(p) for p in e.absolute_path) or "<root>"
            print(f"  ✗ {path}: {e.message}", file=sys.stderr)
        if len(errors) > 5:
            print(f"  ... and {len(errors) - 5} more errors", file=sys.stderr)
        sys.exit(1)
    sys.exit(0)
except json.JSONDecodeError as e:
    print(f"  ✗ JSON parse error: {e}", file=sys.stderr)
    sys.exit(2)
except Exception as e:
    print(f"  ✗ {e}", file=sys.stderr)
    sys.exit(3)
PYEOF
}

# 断言通过：失败则退出
assert_json() {
    local file="$1"
    local schema_name="$2"
    if ! _do_validate "$file" "$schema_name"; then
        echo "[json-validate] $file failed $schema_name schema validation" >&2
        return 1
    fi
    return 0
}

# 尝试校验：不退出，返回 0/1
try_assert_json() {
    _do_validate "$1" "$2"
}

# 批量校验 conf/*.json
# 用法：validate_all_conf
validate_all_conf() {
    local conf_dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/conf}"
    local rc=0
    local mapping=(
        "mcp-servers.json:mcp"
        "llm.json:llm"
        "feishu.json:feishu"
        "versions.json:versions"
    )
    for entry in "${mapping[@]}"; do
        local file="${entry%%:*}"
        local schema="${entry##*:}"
        local path="$conf_dir/$file"
        if [ -f "$path" ]; then
            if _do_validate "$path" "$schema"; then
                echo "[json-validate] ✓ $file ($schema)"
            else
                echo "[json-validate] ✗ $file ($schema) FAILED"
                rc=1
            fi
        fi
    done
    return $rc
}
