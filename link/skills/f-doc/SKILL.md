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

> 完整格式约束+安全规则参考 → `references/write-checklist.md`

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

> 完整检查清单（含执行步骤+验证）→ `references/write-checklist.md`。此处为摘要，写操作前 MUST 通读清单。

### 标题
- 纯 `# ## ###` 层级，**不加手动编号**（飞书自动生成目录）
- H1/H2/H3 三级，**禁止 H4+**
- 非正文内容用 `>` 引用包裹，不出现在目录；禁止 `<hr/>` 分割线

### 表格 → `<lark-table>` XML
- **禁止 Markdown 表格**，全部用 `<lark-table>` XML
- **colgroup 列宽之和 = 822**（`round(822/N)` 均分），写后 fetch `--detail full` 验证
- 必设属性：`rows="N" cols="N" header-row="true" header-column="true" column-widths="W,W,W"`
- 单元格内纯文本，不用 `#` 标题符号

### 图表 → Mermaid 代码块
- **禁止 ASCII 字符画**，白板只能 `block_insert_after` 插入
- 图表在对应内容位置嵌入，不在末尾

### 缩写
- 首次出现用 DFN 格式：`中文全称（English Full Name, ABBR）`

### 父目录
- **子文档**（用户指定父文档URL）：提取 token 作为 `--parent-token`。**禁止**套用默认值
- **独立文档**（用户未指定位置）：默认 `--wiki-node <your-feishu-wiki-token>`（Claude 工作 wiki）

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

### Step 0: 内容构造
1. 标题：`# ## ###` 三级，检查无 `数字[.、]` 前缀
2. 表格：`<lark-table>` XML，`column-widths` 之和 = 822
3. 图表：mermaid 代码块，禁止 ASCII 字符画

### Step 1: 创建

```bash
cat << 'EOF' | lark-cli docs +create --api-version v2 --wiki-node <your-feishu-wiki-token> --as user --markdown - --title "标题"
内容
EOF
```

常见错误: ❌ `--folder-token` | ❌ `--markdown "内容"` | ✅ `--markdown -` + heredoc

### Step 2: 验证（必做）

```bash
lark-cli docs +fetch --api-version v2 --doc "{token}" --detail full
```
检查：
- `grep '<colgroup'` → 列宽之和 = 822
- `grep '^#'` → 无 `一、` `1.1` `(1)` 等手动编号前缀
- 白板/嵌入资源数量与预期一致

创建后追加到「线上文档索引」表格。

---

## 工作流 A: 增量更新

### Step 1: fetch（必带 `--detail with-ids`）

```bash
lark-cli docs +fetch --api-version v2 --doc "{token或URL}" --detail with-ids
```

### Step 2: 策略判断（fetch 后立即执行）

```bash
# 检查嵌入资源
grep -c '<whiteboard\|<sheet\|<bitable\|<img\|<file'
```
- **含嵌入资源 → 禁止 overwrite**。只能用 `str_replace` / `block_insert_after` / `block_delete`
- 不含 → 全量重写可用 overwrite

### Step 3: 展示结构
标注 H1/H2 层级 + 嵌入资源位置，用户确认变更范围。

### Step 4: 编辑

命令选择：
```
替换文本（单行内）     → str_replace --pattern "..." --content "..."
替换整个 block          → block_replace --block-id "xxx" --content "..."（注意：block_id 会变）
插入到 block 后         → block_insert_after --block-id "xxx" --content "..."
删除 block              → block_delete --block-id "xxx"
追加到末尾              → append
```

安全规则：
- 多步 block 操作**必须串行**（并行触发版本冲突，静默失败）
- 同一 block 的 `block_replace` 只能执行一次
- `str_replace` 不能跨 block；pattern 须文档内唯一
- 白板只能 `block_insert_after` 插入，不能 `str_replace` 插 `<whiteboard>` 标签

### Step 5: 验证（必做，ok:true 不代表生效）

```bash
lark-cli docs +fetch --api-version v2 --doc "{token}" --detail full
```
逐项检查：
1. `grep '<colgroup'` → 列宽之和 = 822
2. `grep '^#'` → 无手动编号
3. `grep '<whiteboard token=' | wc -l` → 数量与编辑前一致
4. 内容变更已生效

```bash
# 追加（示例）
cat << 'EOF' | lark-cli docs +update --api-version v2 --doc <doc_id> --as user --mode append --markdown -

# 替换章节（示例）
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

## 工作流 G: 图子文档生成（数据/分析图）

> 架构/流程图仍走 Mermaid 白板。本工作流用于**数据/分析图**：每个图建独立子文档。
> 内容规范见 `../f-report-framework/SKILL.md`，触发见 `../f-research-report/SKILL.md` 工作流 G。

### 完整流程

```
父文档（已有）
  ↓ G.1 写 python 脚本 → /tmp/figs/<名>.py
  ↓ G.2 跑脚本 → /tmp/figs/<名>.png
  ↓ G.3 创建子文档（含图/解读/代码 3 段）
  ↓ G.4 父文档 block_insert_after 嵌入图块
父文档（含图嵌入 + 详见子文档链接）
```

### Step G.1: 写 python 脚本

```python
# /tmp/figs/<图名>.py
import matplotlib.pyplot as plt
plt.rcParams['font.sans-serif'] = ['Noto Sans CJK SC']  # 中文
plt.rcParams['axes.unicode_minus'] = False  # 负号

fig, ax = plt.subplots(figsize=(10, 6), dpi=150)
# ... 数据 + 绘图 ...
plt.tight_layout()
plt.savefig('/tmp/figs/<图名>.png', dpi=150, bbox_inches='tight')
print('✅ /tmp/figs/<图名>.png')
```

```bash
python3 /tmp/figs/<图名>.py
```

### Step G.2: 验证图生成

```bash
ls -la /tmp/figs/<图名>.png
file /tmp/figs/<图名>.png  # 确认 PNG
```

### Step G.3: 创建子文档（3 段式）

子文档用 lark-cli docs +create，**父文档 token 作为 --parent-token**：

```bash
PARENT_TOKEN="<父文档 URL 或 token>"
FIG_NAME="<图名，简洁中文>"

cat << EOF | lark-cli docs +create --api-version v2 \
  --parent-token "$PARENT_TOKEN" --as user \
  --title "$FIG_NAME" --markdown -

# $FIG_NAME

## 图

![$FIG_NAME](attachment://<图名>.png)

> 详细解读见下文

## 解读

> 此处填写图的分析：数据来源、对比维度、关键洞察、注意点、不确定项

- 关键发现 1
- 关键发现 2
- 关键发现 3
- 不确定项：[待确认] / [数据有限]

## 代码

\`\`\`python
# 完整可重跑的 python 脚本
$(cat /tmp/figs/<图名>.py)
\`\`\`

EOF
```

**输出**：子文档 URL 和 token（保存到父文档嵌入步骤）。

### Step G.4: 父文档嵌入图块

**先 fetch 父文档拿到 block 结构**：

```bash
lark-cli docs +fetch --api-version v2 --doc "$PARENT_TOKEN" --detail with-ids
```

**找到要插入位置的 block_id**（如 `<target_block_id>`），用 `block_insert_after` 嵌入子文档链接：

```bash
CHILD_TOKEN="<子文档 token>"
CHILD_URL="<子文档 URL>"

# 在目标 block 后插入图块（链接到子文档）
cat << EOF | lark-cli docs +update --api-version v2 \
  --doc "$PARENT_TOKEN" --as user --mode block_insert_after \
  --block-id "<target_block_id>" --markdown -

**$FIG_NAME**：详见 [$FIG_NAME]($CHILD_URL)

EOF
```

**关键原则**：
- **绝不复制图到父文档**（飞书是引用，子文档 = 唯一源）
- 父文档用 `block_insert_after` 不能用 `str_replace`（避免破坏嵌入资源）
- **多步操作必须串行**（并行触发版本冲突）

### Step G.5: 验证

```bash
lark-cli docs +fetch --api-version v2 --doc "$PARENT_TOKEN" --detail full | grep -c "$FIG_NAME"
# 期望：≥ 1
```

### 常见错误

| 错误 | 原因 | 修复 |
|------|------|------|
| `media-insert` 路径错 | 路径必须相对 git 根目录 | `cd <git 根> && lark-cli drive +upload` |
| `block_insert_after` 找不到 block | block_id 错了 | 重 fetch 带 `--detail with-ids` |
| 子文档父目录错 | `--parent-token` 用了 doc token 而非 wiki node | 父文档 URL 提取的 token 即 wiki node |
| 中文乱码 | matplotlib 字体未设 | `plt.rcParams['font.sans-serif']=['Noto Sans CJK SC']` |

### 命名约定

- 子文档名 = 图名（简洁中文，与正文用语一致）
- `/tmp/figs/<图名>.{py,png}` 命名一致（`占比分析.py` → `占比分析.png`）

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
| 数据图（图子文档） | f-doc 本工作流 G | lark-cli + python |
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

## 参考手册

> 完整格式约束、命令速查、所有陷阱 → `references/write-checklist.md`

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
