---
name: f-doc
description: |
  统一文档入口 — 创建飞书wiki/表格/白板/PPT、更新报告、整合/拆分文档、飞书↔Office双向转换、文档对比。
  Use when 用户说"创建文档"/"写文档"、"更新文档"/"更新报告"、"整合文档"/"合并文档"、
  "拆分文档"、"导出Word/PPT"、"飞书转Office"、"导入到飞书"、"对比文档"、"生成PPT"、
  "画架构图"/"画流程图"、或给出飞书文档URL要求操作。
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebSearch, mcp__minimax__understand_image
---

# f-doc — 统一文档编排

编排层，不重新实现底层工具。委托飞书操作给 lark-doc/lark-drive/lark-wiki/lark-whiteboard，Office 给 OfficeCLI，PPT 给 f-ppt。

## 首次安装检查（每次调用必须执行）

调用本 skill 时，先检查 rules.d/ 全局约束是否已链接：

```bash
SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"  # 需替换为实际 skill 路径
RULE_FILE="$HOME/.claude/rules/f-doc.md"
SRC_FILE="$SKILL_DIR/rules.d/f-doc.md"

if [[ ! -L "$RULE_FILE" ]] || [[ "$(readlink -f "$RULE_FILE" 2>/dev/null)" != "$(readlink -f "$SRC_FILE")" ]]; then
  mkdir -p "$HOME/.claude/rules"
  ln -sf "$(readlink -f "$SRC_FILE")" "$RULE_FILE"
  echo "✓ f-doc 全局约束已安装到 ~/.claude/rules/"
fi
```

执行后输出结果。符号链接存在且正确则跳过。这条确保格式硬约束始终全局加载，不依赖用户手动运行 init.sh。

## 前置条件

操作前 MUST 读取：
1. `../lark-shared/SKILL.md` — 认证、权限
2. `../lark-doc/SKILL.md` — 文档读写（fetch/create/update 参数）
3. `references/feishu-office-bridge.md` — 跨格式转换（涉及 Office 时）

## 快速决策

```
用户意图
  ├─ "创建文档"/"写文档"/"生成报告"        → 工作流 0: 创建新文档
  ├─ "创建表格"/"画表格"                   → 工作流 0 + lark-table
  ├─ "画架构图"/"流程图"/"时序图"          → 工作流 0 + mermaid/SVG 白板
  ├─ "生成PPT"/"做slides"                 → 委托 f-ppt skill
  ├─ "更新文档"/"update report"           → 工作流 A: 增量更新
  ├─ "整合"/"合并"/"consolidate"          → 工作流 B: 多文档整合
  ├─ "拆分"/"split"                       → 工作流 C: 大文档拆分
  ├─ "导出Word/PPT"/"转Office"            → 工作流 D: 飞书→Office
  ├─ "导入飞书"                           → 工作流 D: Office→飞书
  ├─ "对比"/"diff"                        → 工作流 E: 文档对比
  ├─ "翻译PDF"                            → 工作流 F: PDF 翻译文档
  └─ "找文档"/"有哪些关于X的文档"         → Step S: 文档发现
```

---

## 文档格式规范（所有创建/编辑遵循）

### 标题
- 纯 `# ## ###` 层级，**不加手动编号**（飞书自动生成目录）
- H1/H2/H3 三级，**禁止 H4+**
- 非正文内容（使用说明、参考数据、搜索清单）用 `>` 引用包裹，不出现在目录
- 章节间**不加 `---` 横线**

### 表格 → `<lark-table>` XML
- **禁止 Markdown 表格**，全部用 `<lark-table>` XML
- 必设属性：`rows="N" cols="N" header-row="true" header-column="true" column-widths="W,W,W"`
- 列宽：`round(822 / N)` 均分。2列→411,411 | 3列→274×3 | 4列→205×4 | 5列→164×5
- 单元格内用纯文本，不用 `#` 标题符号

### 图表 → Mermaid 代码块
- **禁止 ASCII 字符画**
- 支持：`graph TD/LR` `flowchart` `sequenceDiagram` `classDiagram` `stateDiagram-v2` `erDiagram` `gantt` `pie`
- 图表在对应内容位置嵌入，不在末尾

### 缩写
- 首次出现用 DFN 格式：`中文全称（English Full Name, ABBR）`

### 父目录
- **子文档**（用户指定父文档URL）：提取 token 作为 `--parent-token`。**禁止**套用默认值
- **独立文档**（用户未指定位置）：默认 `--wiki-node <your-feishu-wiki-token>`（Claude 工作 wiki）
- 提取方法：`https://my.feishu.cn/wiki/{token}` → token = parent-token

---

## Step S: 文档发现

```bash
lark-cli drive +search --query "关键词" --doc-types "wiki,doc,docx" --page-size 20
lark-cli drive +search --query "关键词" --doc-types "wiki,doc,docx" --only-title
lark-cli drive +search --query "关键词" --space-ids "space_id_1,space_id_2"
```

列出知识空间：`lark-cli wiki +space-list`

---

## 工作流 0: 创建新文档

### 基本命令

```bash
cat << 'EOF' | lark-cli docs +create --api-version v2 --wiki-node <your-feishu-wiki-token> --as user --markdown - --title "标题"
内容
EOF
```

常见错误: ❌ `--folder-token` | ❌ `--markdown "内容"` | ✅ `--markdown -` + heredoc

### 含表格/白板的创建

表格用 `<lark-table>`，图表用 mermaid 代码块，PPT 路由到 f-ppt skill。

### 验证

创建后 MUST fetch 验证：`lark-cli docs +fetch --api-version v2 --doc "{token}"`

---

## 工作流 A: 增量更新

```
fetch 文档结构 → 用户确认变更 → 最小编辑 → apply → 验证
```

1. `lark-cli docs +fetch --api-version v2 --doc "{token或URL}"` 读取
2. 展示结构概览（H1/H2 标题层级）
3. 用户描述变更
4. 用 `str_replace` 或 `block_replace` 做最小化编辑
5. 重新 fetch 验证（**必做**，ok:true 不代表生效）

```bash
# 追加
cat << 'EOF' | lark-cli docs +update --api-version v2 --doc <doc_id> --as user --mode append --markdown -

# 替换章节
cat << 'EOF' | lark-cli docs +update --api-version v2 --doc <doc_id> --as user --mode replace_range --selection-by-title "章节标题" --markdown -
```

详见 `references/update-workflow.md`

---

## 工作流 B: 多文档整合

```
搜索相关文档 → 全部fetch → 去重+结构分析 → 合并方案 → 用户审批 → 创建
```

详见 `references/merge-workflow.md`

---

## 工作流 C: 大文档拆分

```
fetch 源文档 → 分析H1/H2边界 → 拆分方案 → 用户审批 → 创建子文档
```

子文档 MUST 使用源文档 URL 的 token 作为 `--parent-token`。

详见 `references/split-workflow.md`

---

## 工作流 D: 飞书↔Office 双向转换

**飞书→Office（导出）：**
1. `docs +fetch` 获取内容 → OfficeCLI JSON
2. `officecli add` / `officecli set` 写入 .docx
3. PPT 委托 f-ppt skill

**Office→飞书（导入）：**
1. `officecli get` 读取 .docx
2. 转为飞书 DocxXML
3. `docs +create --api-version v2` 上传

详见 `references/feishu-office-bridge.md`

---

## 工作流 E: 文档对比

1. 获取两个文档内容
2. 按章节对齐
3. 输出对比报告

---

## 工作流 F: PDF 翻译文档

### 结构（2层父子）
```
翻译文档 (父)
  ├── PDF源文件与扩展资料 (子)
  └── PPT演示文稿 (子)
```

### 格式
- 标题：中文翻译
- 正文第一行：`**English Original Title**`
- 每段：中文译文 + `> English Original` 引用原文
- 图片嵌入对应段落之后
- PDF 附件：`lark-cli docs +media-insert --type file --file ./xxx.pdf`

### PDF 内容提取
委托 f-pdf skill（2 级原语）：
1. **文字提取**：`pdf_to_md.py`（PyMuPDF，含标题层级/粗斜体/列表/表格检测）
2. **图片提取**：`extract-images.py`（PyMuPDF + 纯 Python zlib 回退）
3. **图片验证**：`minimax understand_image` 逐张过滤 logo/装饰图

详细 → `../f-pdf/SKILL.md`

---

## 工具委托速查

| 操作 | 工具 | 命令 |
|------|------|------|
| 搜索文档 | lark-drive | `lark-cli drive +search` |
| 读取文档 | lark-doc | `lark-cli docs +fetch --api-version v2` |
| 编辑文档 | lark-doc | `lark-cli docs +update --api-version v2` |
| 创建文档 | lark-doc | `lark-cli docs +create --api-version v2` |
| 知识库操作 | lark-wiki | `lark-cli wiki +node-*` |
| 创建/编辑 .docx | OfficeCLI | `officecli add/set/get` |
| 生成 PPT | f-ppt | 委托 f-ppt skill |
| 画图表 | lark-whiteboard | 委托 lark-whiteboard skill |
| 文件上传 | lark-drive | `lark-cli drive +upload` |
| PDF 提取 | f-pdf | 委托 f-pdf skill |
| SVG 白板 | whiteboard-cli | `npx -y @larksuite/whiteboard-cli@^0.2.10` |

---

## 用户配置

用户说"配置 f-doc"时，读取 `config.yaml` 展示可配置项，用 AskUserQuestion 让用户修改，写回文件。

```bash
cat "$SKILL_DIR/config.yaml"
```

配置项说明见 `config.yaml` 注释。用户直接编辑该文件也可，无需重启。

---

## 关键陷阱

- 飞书编辑后 MUST 重新 fetch 验证（`--scope range`，不用 `keyword`）
- `drive +search` 参数是 `--query` 不是 `--keyword`
- `drive +search` 返回 obj_token，可用于 `docs +fetch`，但不能直接用于 `wiki +node-get`（需加 `--obj-type`）
- `docs +update str_replace` 用 `--pattern`+`--content`，不用 `--json`
- `block_replace` 后 block_id 会变化
- lark-cli 输出 pipe 给 JSON 解析器前，先 `tail -n +2` 跳过日志行
- OfficeCLI 写 .docx 前先 `officecli open` 驻留进程加速
- 更新已有文档优先用 `str_replace`/`block_replace`，不用 `append`
- `replace_range` 不支持含空行的内容，改用 `delete_range` + `insert_after`
- `<lark-table>` colgroup 总和必须 = 822
- json 文件路径必须用相对路径

---

## 线上文档索引

> f-doc 创建/编辑的文档。每次操作后追加。格式：`[标题](url) | 日期 | 说明`

| 标题 | 链接 | 日期 | 说明 |
|------|------|------|------|
| [国航大模型双轨架构深度研究](https://<your-tenant>.feishu.cn/docx/DOwxdvTVMoSMYRx28XGcliH0nte) | 2026-06-01 | 国航AI架构专题研究，对标全球航空业AI最佳实践 |
| [知识图谱与专业能力提升 — 2026年上半年总结及下半年工作思路](https://<your-tenant>.feishu.cn/docx/XMrHd3bNeowq4KxLyNXccsTpnJf) | 2026-05-31 | 知识图谱半年总结报告，父文档 workreview |

### 常用 Wiki 节点

| 用途 | Token | URL |
|------|-------|-----|
| Claude 工作 wiki（默认父目录） | `<your-feishu-wiki-token>` | https://<your-tenant>.feishu.cn/wiki/<your-feishu-wiki-token> |
| OKR/SUM 文档父目录 | `VPsDw42KsixH77kugfcc8FyInCh` | https://<your-tenant>.feishu.cn/wiki/VPsDw42KsixH77kugfcc8FyInCh |

> **注意**: f-logme 管辖的文档（OKR/SUM/Worklog）索引在 `skills/f-logme/SKILL.md` 的「线上文档索引」节。f-doc 索引只记录 f-doc 直接创建的文档（研究/翻译/合并等）。
