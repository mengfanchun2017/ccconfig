# 飞书集成规范

## 工具选择
- **lark-cli --as user**：所有飞书操作（文档、Base、日历、白板、表格）
- feishu MCP 已删除，不需要任何 MCP 调用

## 文档操作 → f-feishu skill

**硬前置条件（不可跳过）**：任何 `lark-cli docs +create` / `+update` / `+fetch` 命令执行前，**必须先调用 `f-feishu` Skill 工具**。即使你自认为知道 lark-cli 命令怎么写，也必须调——f-feishu 的格式约束（禁止 hr 分割线、表格必须 XML + colgroup=822、图表必须 mermaid、禁止 ASCII 伪图、禁止手动编号、禁止 H4+）只有通过 Skill 调用才会加载到上下文。**跳过 Skill 直接裸调 lark-cli 必然导致格式违规**（2026-06-22 已复现：报告文档满篇 `---` 分割线 + Markdown 表格 + ASCII 伪图，3 类违规）。

**检查方法**：准备执行 lark-cli docs 命令前，自问"这次会话我调过 f-feishu Skill 了吗？"→ 没调就先调。

所有飞书文档的创建/更新/合并/拆分/转换/对比，统一由 `f-feishu` skill 编排。写操作检查清单 → `skills/f-feishu/references/write-checklist.md`（含命令选择+格式自检+写后验证）。

## 写操作后必输出完整链接（强约束）

任何飞书 doc 创建/更新/上传操作（`docs +create` / `+update` / `drive +upload` / `whiteboard +create` 等）完成后，**必须**在回复中输出完整 markdown 链接：

```markdown
[标题](完整 URL)
```

- 链接独占一行，多个链接用表格列出（标题 + 链接 + 日期 + 说明）
- 完整 URL = `https://<tenant>.feishu.cn/wiki/<token>` 或 `/docx/<token>` 或 `/file/<token>`
- 不允许只给 `doc_id` / `file_token`（用户拿到还要自己拼 URL）
- 不允许省略（"已创建文档"等无链接表述视为遗漏）
- 删除操作也要写明（"已删 doc [标题](url)"）

**Why**：飞书 doc 是最终交付物，链接是访问入口。漏给链接 = 用户无法访问，等于没做。
**How to apply**：
- 每次 `+create` / `+update` / `+upload` / `+delete` / `whiteboard +create/update` 返回 token 后 → 立即在回复中输出链接
- 多 doc 操作 → 末尾用表格汇总
- 子文档、附件、嵌入图块 都算交付物，都给链接

## lark-cli 输出解析
lark-cli 在 stdout 输出日志行（非 JSON），pipe 给 `python3 -c "json.load(sys.stdin)"` 会解析失败。
**规则：先 `tail -n +2` 或 `sed '/^\[lark-cli\]/d'` 跳过日志行。**

```bash
# ❌ tail -n +2 不稳定，日志行数不固定时出错
# ✅ sed 过滤日志行，始终有效
lark-cli ... 2>&1 | sed '/^\[lark-cli\]/d' | python3 -c "import json,sys; ..."
```

## 最近编辑文档追踪

每次飞书 doc 写操作（create/update/delete/upload）完成后，**必须**更新 `~/.claude/projects/-home-francis-git/memory/recent_feishu_docs.md`：

- 在表格顶部插入新行：`| 日期 | 标题 | 链接 | 操作 |`
- 保持最近 15 条，超出删旧
- 格式：`| YYYY-MM-DD | 文档标题 | [wiki](完整URL) | 操作简述 |`

**Why**：跨 session 记忆最近操作的文档，下次对话直接定位，不需用户重复提供 URL。
**How to apply**：每次飞书写操作完成后，Read → Edit recent_feishu_docs.md 在表头下一行插入新记录。
