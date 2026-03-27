#!/bin/bash
# Claude MCP 管理脚本
# 直接调用 initMCP.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/initMCP.sh"
