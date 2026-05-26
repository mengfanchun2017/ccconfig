# lark-cli 速查 + 试错自更新

> **规则**: 任何 lark-cli 命令的 flag 试错成功后，立即将正确用法追加到本文。禁止同一错误犯两次。

## 运行前缀
```bash
export LARKSUITE_CLI_CONFIG_DIR="$HOME/.lark-cli-<account>" && export PATH="$HOME/.local/bin:$PATH"
```

## 命令 → flag 对照

| 命令 | token参数 | 内容参数 | 其他易错 |
|------|----------|---------|---------|
| `docs +update/ +fetch` | `--doc` | v1: `--markdown` v2: `--content` | v2 `--command` 必须配 `--content` |
| `docs +search` | - | `--query` | 无 `--api-version` |
| `wiki +node-get` | `--token` | - | 支持URL |
| `wiki +node-create` | - | `--title` `--obj-type` | 不支持 board 类型 |
| `whiteboard +update` | `--whiteboard-token` | `--source` + `--input_format` | mermaid/plantuml/raw |
| `base +*` | `--base-token` | `--json`(单对象) | 不是 `--app-token`/`--fields` |
| `base +record-batch-create` | `--base-token` | `--json '{"fields":[],"rows":[[]]}'` | 数组格式 |
| `sheets +*` | `--spreadsheet-token` | `--values '[[...]]'` | 写数据需 `--range` |
| `drive +create-folder` | `--folder-token` | `--name` | 不是 `--title` |
| `drive +upload` | `--folder-token` | `--file "./rel"` | 必须相对路径，先 cd |

| `slides +create` | - | `--title` `--slides '<json-array>'` | JSON 数组每元素是 XML `<slide>` 字符串 |
| `slides 导出` | - | `api POST export_tasks` | `drive +export` 不支持 slides，用 `lark-cli api` 调原始API |
| `drive +export-download` | `--file-token` | `--file-name` | 必须相对路径，先 cd |

## 新增踩坑（追加在此）

<!-- 2026-05-26 | slides export | drive +export --doc-type slides → 不支持 → lark-cli api POST export_tasks | 用通用API替代 -->
