# 文档操作规范

> 飞书文档创建/更新的一站式规则。始终全局加载。操作流程细节在 `skills/f-doc/SKILL.md`。

## f-doc 统一入口

所有文档操作（创建/更新/整合/拆分/转换/对比）统一由 `f-doc` skill 编排。
f-doc 委托底层：
- 飞书文档读写 → lark-doc
- 知识库管理 → lark-wiki
- 文件搜索/上传 → lark-drive
- 白板图表 → lark-whiteboard
- PPT 生成 → f-ppt
- PDF 内容提取 → f-pdf
- Office 文件 → OfficeCLI

## 文档创建

### 父目录
- **子文档**（用户给父文档URL）：提取 wiki token → `--parent-token {token}`。禁止套用默认
- **独立文档**（无父文档）：`--parent-token <your-feishu-wiki-token>`（Claude 工作 wiki）
- 提取：`https://<your-tenant>.feishu.cn/wiki/{token}` → token

### 格式
- 标题：`# ## ###` 三级，不加手动编号，禁止 H4+
- 表格：`<lark-table>` XML，禁止 Markdown 表格。colgroup 列宽之和 = 820px
- 禁止 `<hr/>` 分割线，主题间用标题层级和留白自然过渡
- 图表：需要图表时优先插入画板（whiteboard）而非图片
- 缩写：首次 DFN 格式 `中文全称（English Full Name, ABBR）`
- 链接：用 `www.feishu.cn` 域名，非 `open.feishu.cn`
- 禁止表格裸 URL：表格内链接必须用 Markdown 链接格式
- 非正文（说明/清单）用 `>` 引用包裹，不污染目录

### 交互约定
- **用户展示的格式要对等回写**：用户展示表格 → 用 `<table>` 回写；用户展示列表 → 用 `<ul>/<ol>` 回写
- **用户给的完整内容默认全部插入**，不截断。不确定范围时确认
- **插入或替换表格后必须验证** colgroup 总和 = 820，`block_replace` 返回 ok 不代表宽度正确

### 命令
```bash
cat << 'EOF' | lark-cli docs +create --api-version v2 --parent-token <your-feishu-wiki-token> --as user --doc-format markdown --content -
内容
EOF
```
常见错误：❌ `--folder-token` | ❌ `--wiki-node`（已废弃） | ✅ `--parent-token` + `--doc-format markdown --content -`

## 文档更新

### 验证
编辑后 MUST 重新 fetch 验证（`--scope range`）。`ok: true` 不代表生效。

### 更新命令
```bash
# 追加
lark-cli docs +update --api-version v2 --doc <id> --as user --mode append --markdown -

# 替换章节
lark-cli docs +update --api-version v2 --doc <id> --as user --mode replace_range --selection-by-title "标题" --markdown -
```

## 学习输出
- 无文档 URL → 创建新飞书文档，分享链接
- 有文档 URL + 要求扩展 → 直接更新文档，不输出终端长文

## 搜索发现
```bash
lark-cli drive +search --query "关键词" --doc-types "wiki,doc,docx" --page-size 20
```
注意：参数是 `--query` 不是 `--keyword`

## 研究管道
- 快速研究 → f-research → 飞书 wiki 文档
- 深度研究 → f-research-deep → JSON → f-research-report → Markdown

## Base 约定
- 字段设计优先考虑公式字段、查找引用
- 涉及跨表计算时优先用关联字段而非硬编码 ID

## 关键陷阱
- 飞书编辑后 fetch 验证，用 `--scope range`，不用 `keyword`
- `drive +search` 返回 obj_token，用于 `docs +fetch` 但不能直接用于 `wiki +node-get`（需 `--obj-type`）
- lark-cli pipe 给 JSON 解析器前，先 `tail -n +2` 跳过日志行
- `str_replace` 用 `--pattern`+`--content`，不用 `--json`
- `block_replace` 后 block_id 会变化
- json 文件路径必须相对
- `<lark-table>` colgroup 总和必须 = 820
- `replace_range` 不支持含空行内容，用 `delete_range` + `insert_after`
