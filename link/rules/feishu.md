# 飞书集成规范

> **可选模块**：仅在使用飞书/Lark 文档功能时需要。不使用可安全忽略此文件。

## lark-cli auth 预检（写操作前置）

**任何 `docs +create` / `+update` / `drive +upload` 前**，先验证 auth 存活：

```bash
lark-cli drive +search --query test --page-size 1 --as user 2>&1 | sed '/^\[lark-cli\]/d'
```

若返回 `"ok":true` → 继续。若返回 `token_missing` / `need_user_authorization` → auth 过期，走 QR 码授权流程（一次性，1 分钟）：

```bash
# 1. 请求设备授权（含完整读写 scopes）
lark-cli auth login --scope "docx:document:create,docx:document:readonly,drive:drive:readonly" --no-wait --json
# 2. 生成 QR 码
lark-cli auth qrcode "<verification_url>" --output ./feishu-auth-qr.png
# 3. 用户扫码后确认
lark-cli auth login --device-code "<device_code>"
```

**Why**：session token 有 TTL（~30天），过期后需重新授权。config.json 存在 ≠ auth 有效。
**How to apply**：写操作前先 drive +search 验证，失败走 auth 流程。

## 账号配置
- **当前使用**: 企业飞书账号，通过 `LARKSUITE_CLI_CONFIG_DIR` 环境变量指定 lark-cli 配置目录
- 切换账号: `lark-cli` 前缀必须带 `LARKSUITE_CLI_CONFIG_DIR`，不可省略

## 工具选择
- **lark-cli --as user**：所有飞书操作（文档、Base、日历、白板、表格）
- feishu MCP 已删除，不需要任何 MCP 调用

## 文档操作 → f-feishu skill

**硬前置条件**：任何 `lark-cli docs` 命令前必须先调 `f-feishu` Skill。格式约束（禁止分割线、表格必须 XML+colgroup=822、禁止手动编号、禁止 ASCII 伪图）只在 skill 调用时加载到上下文。跳过直接裸调 lark-cli 必然格式违规。

## 写操作后必输出完整链接

飞书 doc 创建/更新/上传/删除后，**必须**输出 `[标题](完整 URL)` 格式链接。不允只给 doc_id/file_token，不允省略。多链接用表格汇总。子文档、附件、嵌入图块都算交付物。

## lark-cli 输出解析

stdout 含日志行（`[lark-cli] ...`）和进度行（`Uploading media for import: ...`），pipe 前 `sed '/^\[lark-cli\]/d'` 不敷过滤。**禁止 pipe 到 `json.load` 全量解析**，用 `grep` 提取目标字段：

```bash
# ❌ 错误：进度行导致 json.load 失败
lark-cli ... 2>&1 | sed '/^\[lark-cli\]/d' | python3 -c "import json,sys; d=json.load(sys.stdin); ..."
# ✅ 正确：grep 提取单字段
lark-cli ... 2>&1 | grep '"token"' | head -1
```

`api` 子命令不输出 JSON。详情 → f-feishu `references/lark-cli-cheatsheet.md`。

## 最近编辑文档追踪

每次飞书 doc 写操作（create/update/delete/upload）完成后，**必须**更新当前项目的 `recent_feishu_docs.md` 记忆文件（路径：`~/.claude/projects/<project-id>/memory/recent_feishu_docs.md`）：

- 在表格顶部插入新行：`| 日期 | 标题 | 链接 | 操作 |`
- 保持最近 15 条，超出删旧
- 格式：`| YYYY-MM-DD | 文档标题 | [wiki](完整URL) | 操作简述 |`

**Why**：跨 session 记忆最近操作的文档，下次对话直接定位，不需用户重复提供 URL。
**How to apply**：每次飞书写操作完成后，Read → Edit recent_feishu_docs.md 在表头下一行插入新记录。
