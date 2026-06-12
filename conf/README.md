# conf/ — 配置文件（单一真相源）

> 所有初始化/升级脚本读取此目录下的配置文件。修改后下次运行自动生效。

## 文件

| 文件 | 用途 | 读取方 | 入 git |
|------|------|--------|--------|
| `versions.json` | 组件版本、Node.js pin | `update.sh`, `path-helper.sh` | ✓ |
| `ubuntu.json` | Git 用户信息、仓库地址 | `init-ubuntu.sh` | ✗ (敏感) |
| `llm.json` | LLM 多后端配置、当前选择 | `init-llm.sh`, `init-ubuntu.sh` | ✗ (敏感) |
| `claude.json` | MCP 服务器列表、env 配置 | `init-mcp.sh`, `update.sh` | ✗ (敏感) |
| `feishu.json` | 飞书 lark-cli + cc-connect 配置 | `option-bridge/` | ✗ (敏感) |
| `cloudflare.json` | Cloudflare API tokens（多项目共用） | 各项目部署脚本（jq 读 → env） | ✗ (敏感) |
| `python-requirements.txt` | Python pip 包清单 | `update.sh` | ✓ |

## 注意

此目录包含敏感信息（API Key、Token、App Secret），**不要公开提交**。
