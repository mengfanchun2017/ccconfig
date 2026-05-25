---
name: doc-master
description: |
  文档生命周期管理 — 更新飞书报告、整合散落文档、拆分大文档、飞书↔本地Office双向转换。
  Use when 用户说"更新文档"/"更新报告"、"整合文档"/"合并文档"/"consolidate"、
  "拆分文档"/"split document"、"导出Word/PPT"、"飞书转Office"、"导入到飞书"、
  "对比文档"/"文档有什么变化"。
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebSearch
---

# doc-master — 文档生命周期管理

编排层，不重新实现底层工具。委托飞书操作给 lark-doc/lark-drive/lark-wiki，Office 文件操作给 OfficeCLI，PPT 生成给 unified-ppt。

## 前置条件

操作前 MUST 读取：
1. `../lark-shared/SKILL.md` — 认证、权限（所有飞书操作通用）
2. `../lark-doc/SKILL.md` — 文档读写（fetch/create/update 参数）
3. `references/feishu-office-bridge.md` — 跨格式转换（涉及 Office 时）

## 快速决策

```
用户意图
  ├─ "更新文档"/"update report"        → 工作流 A: 增量更新
  ├─ "整合"/"合并"/"consolidate"       → 工作流 B: 多文档整合
  ├─ "拆分"/"split"                    → 工作流 C: 大文档拆分
  ├─ "导出Word/PPT"/"转Office"         → 工作流 D: 飞书→Office
  ├─ "导入飞书"                         → 工作流 D: Office→飞书
  ├─ "对比"/"diff"                     → 工作流 E: 文档对比
  └─ "找文档"/"有哪些关于X的文档"      → Step 0: 文档发现
```

## Step 0: 文档发现

```bash
# 跨知识库+云盘搜索（已验证：wiki/doc/docx 全覆盖）
lark-cli drive +search --query "关键词" --doc-types "wiki,doc,docx" --page-size 20

# 仅搜标题
lark-cli drive +search --query "关键词" --doc-types "wiki,doc,docx" --only-title

# 限定知识空间
lark-cli drive +search --query "关键词" --space-ids "space_id_1,space_id_2"
```

搜索结果返回 token/URL/edit_time/owner，token 可直接用于 `docs +fetch`。

列出知识空间：`lark-cli wiki +space-list`

## 工作流 A: 增量更新

```
fetch 文档结构 → 用户确认变更 → 计算最小编辑 → apply → 验证
```

1. `lark-cli docs +fetch --api-version v2 --doc "{token或URL}"` 读取
2. 展示结构概览（H1/H2 标题层级，非全文）
3. 用户描述变更（"把第三章的XX改成YY，增加ZZ段落"）
4. 用 `str_replace` 或 `block_replace` 做最小化编辑
5. 重新 fetch 验证变更生效

详见 `references/update-workflow.md`

## 工作流 B: 多文档整合

```
搜索相关文档 → 全部fetch → 去重+结构分析 → 合并方案 → 用户审批 → 创建
```

1. Step 0 发现所有候选文档
2. 逐个 fetch 获取结构和内容
3. 分析：重复内容/互补内容/冲突内容
4. 输出合并方案（章节编排、去重决策、冲突解决建议）
5. 用户确认后创建新文档或覆写

详见 `references/merge-workflow.md`

## 工作流 C: 大文档拆分

```
fetch 源文档 → 分析H1/H2边界 → 拆分方案 → 用户审批 → 创建子文档
```

1. fetch 文档，提取标题层级
2. 按 H1 或 H2 边界识别逻辑断点
3. 输出拆分方案（每部分的标题、行数、独立主题）
4. 用户确认后创建多个子文档

详见 `references/split-workflow.md`

## 工作流 D: 飞书↔Office 双向转换

**飞书→Office（导出）：**
1. `docs +fetch` 获取内容 → 转为 OfficeCLI JSON 结构
2. `officecli add` / `officecli set` 写入 .docx
3. 也可委托 unified-ppt skill 生成 .pptx

**Office→飞书（导入）：**
1. `officecli get` 读取 .docx 结构
2. 转为飞书 DocxXML
3. `docs +create --api-version v2` 上传

详见 `references/feishu-office-bridge.md`

## 工作流 E: 文档对比

1. 获取两个文档的内容
2. 按章节对齐，标注差异
3. 输出对比报告（新增/删除/修改）

## 工具委托速查

| 操作 | 工具 | 命令前缀 |
|------|------|---------|
| 搜索文档 | lark-drive | `lark-cli drive +search` |
| 读取文档 | lark-doc | `lark-cli docs +fetch --api-version v2` |
| 编辑文档 | lark-doc | `lark-cli docs +update --api-version v2` |
| 创建文档 | lark-doc | `lark-cli docs +create --api-version v2` |
| 知识库操作 | lark-wiki | `lark-cli wiki +node-*` |
| 搜索知识库 | lark-drive | `lark-cli drive +search` (含 wiki 类型) |
| 创建/编辑 .docx | OfficeCLI | `officecli add/set/get` |
| 生成 PPT | unified-ppt | 委托 unified-ppt skill |
| 画图表 | lark-whiteboard | 委托 lark-whiteboard skill |
| 文件上传 | lark-drive | `lark-cli drive +upload` |

## 关键陷阱

- `drive +search` 返回 obj_token（如 `VofDwC...`），可用于 `docs +fetch`，但不能直接用于 `wiki +node-get`（需加 `--obj-type`）
- 飞书编辑后 MUST 重新 fetch 验证（参考 feedback_fetch_verify 记忆）
- 搜索参数是 `--query` 不是 `--keyword`
- OfficeCLI 写 .docx 前先 `officecli open` 驻留进程以加速
- 更新已有文档优先用 `str_replace`/`block_replace`，不用 `append`（避免重复）
