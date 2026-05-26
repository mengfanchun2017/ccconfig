# 飞书 lark-cli 命令速查

> CLI flag 模式易错点 — 避免 `--token`/`--doc`/`--fields`/`--json` 等重复试错

## 通用规则
- **运行前必加**: `export LARKSUITE_CLI_CONFIG_DIR="$HOME/.lark-cli-<account>" && export PATH="$HOME/.local/bin:$PATH"`
- **token 参数名不统一**: docs 用 `--doc`，wiki 用 `--token`，whiteboard 用 `--whiteboard-token`，sheets 用 `--spreadsheet-token`，base 用 `--base-token`
- **help 优先**: 不确定 flag 名时先 `lark-cli <cmd> <subcmd> --help`

## 按命令分类

### wiki
- `wiki +node-get --token "<URL或token>"` — 获取节点详情
- `wiki +node-list --space-id "<id>"` — 列出空间节点
- `wiki +node-create --space-id "<id>" --title "..." --obj-type docx|sheet|bitable|mindnote|slides` — 创建节点（不支持 board）
- `wiki +node-create --parent-node-token "<token>" --title "..." --obj-type ...` — 在父节点下创建

### docs
- `docs +update --doc "<token>" --mode overwrite|append --markdown "..."` — v1 API 更新（支持 markdown）
- `docs +update --api-version v2 --doc "<token>" --command overwrite|append|... --content "<xml>"` — v2 API 更新（仅 XML）
- `docs +fetch --doc "<token>"` — 读取文档
- `docs +search --query "..."` — 搜索（无需 --api-version）
- `<whiteboard type="blank"></whiteboard>` — markdown 中嵌入空白白板

### whiteboard
- `whiteboard +update --whiteboard-token "<token>" --input_format mermaid --overwrite --source "..."` — 更新白板

### base
- `base +table-create --base-token "<token>" --name "..."` — 创建表
- `base +field-create --base-token "<token>" --table-id "<id>" --json '{...}'` — 创建字段（单个JSON对象）
- `base +record-batch-create --base-token "<token>" --table-id "<id>" --json '{"fields":["名1","名2"],"rows":[["v1","v2"]]}'` — 批量创建记录

### sheets
- `sheets +info --spreadsheet-token "<token>"` — 获取表信息
- `sheets +write --spreadsheet-token "<token>" --range "<sheetId>!A1:D10" --values '[[...]]'` — 写入数据
- `sheets +update-sheet --spreadsheet-token "<token>" --sheet-id "<id>" --title "..."` — 重命名 sheet

### drive
- `drive +create-folder --name "..." --folder-token "<parent>"` — 创建文件夹（--name 不是 --title）
- `drive +upload --file "./relative-path" --folder-token "<token>"` — 上传文件（必须相对路径，先 cd 到文件目录）

### auth
- `auth login --recommend` — 默认授权
- `auth login --scope "search:docs:read"` — 追加 scope

## v2 API 要点
- `docs +create --api-version v2 --content "<xml>"` — v2 创建仅支持 XML
- `docs +update --api-version v2 --command ... --content "<xml>"` — v2 更新仅 `--content`（XML），不接受 `--markdown`
- `docs +fetch --api-version v2 --doc "..."` — v2 读取
- markdown 内容用 v1 API（`--mode overwrite --markdown "..."`）更方便

## 常见错误对照
| 错误写法 | 正确写法 | 命令 |
|----------|----------|------|
| `--token` | `--doc` | docs +update |
| `--token` | `--whiteboard-token` | whiteboard +update |
| `--fields` | `--json` | base +field-create |
| `--app-token` | `--base-token` | base 所有操作 |
| `--title` | `--name` | drive +create-folder |
| `--file "/abs/path"` | `cd /dir && --file "./rel"` | drive +upload |
| `--command overwrite --markdown` | `--mode overwrite --markdown` (v1) | docs +update |
