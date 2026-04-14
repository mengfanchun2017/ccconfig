# Project Memory

This file persists across Claude Code conversations. Keep it concise (&lt;200 lines).

## Quick Links
- Project root: C:\git
- CLAUDE.md: C:\git\CLAUDE.md

---

## ccconfig 仓库结构（2026-04-02）

```
ccconfig/                    # GitHub: <your-github-username>/ccconfig
├── ubuntuinit.sh               # Ubuntu 合一初始化脚本（Git + Claude + 环境）
├── claudeinit.sh               # MCP 服务器安装与配置
├── init-auto-sync.sh           # 文件变化自动同步到 GitHub
├── init-enable-autostart.sh    # auto-sync 自启动配置
├── hook-status.sh              # 状态检查（被 MCP 和 SessionStart hook 调用）
├── mcp-status/                 # 状态 MCP 服务器
│   └── status-mcp.js          # 提供 status 工具
├── conf-ubuntu.json             # ubuntuinit.sh 配置（Git/API）
├── conf-claude.json            # claudeinit.sh 配置（MCP）
└── link/                       # 符号链接文件目录
    ├── CLAUDE.md              # 全局 AI 指令
    ├── .config.json           # MCP 配置（用户状态）
    ├── settings.json           # Claude Code 设置（权限/环境变量/hooks）
    └── -home-francis-git/     # 项目记忆
        └── MEMORY.md
```

**新环境初始化流程**：
```bash
# 阶段一：终端执行（不需要 Claude 运行）
# 一次性完成所有环境初始化
bash ccconfig/ubuntuinit.sh

# 阶段二：进入 Claude 后手动执行
bash ccconfig/claudeinit.sh  # MCP 安装 + 链接检查
```

---

## Claude Code 配置文件体系

| 文件 | 作用 | 同步 |
|------|------|------|
| `~/.claude/settings.json` | 权限、环境变量、hooks、插件配置等 | ✅ 符号链接到 ccconfig |
| `~/.claude/.config.json` | MCP 配置、用户状态、项目信息等 | ✅ 符号链接到 ccconfig |
| `~/CLAUDE.md` | 全局 AI 指令 | ✅ 符号链接到 ccconfig |
| `~/.claude.json` | Claude Code 自动维护的状态 | ❌ 不同步 |

### 符号链接（本地 ↔ GitHub 同步）

| 本地路径 | 指向 | GitHub 路径 | 作用 |
|---------|------|-------------|------|
| `~/.claude/settings.json` | → `ccconfig/link/settings.json` | `link/settings.json` | 权限/环境变量/hooks |
| `~/.claude/.config.json` | → `ccconfig/link/.config.json` | `link/.config.json` | MCP 配置/用户状态 |
| `~/CLAUDE.md` | → `ccconfig/link/CLAUDE.md` | `link/CLAUDE.md` | 全局 AI 指令 |
| `~/.claude/projects/-home-francis-git/memory/MEMORY.md` | → `ccconfig/link/-home-francis-git/MEMORY.md` | `link/-home-francis-git/MEMORY.md` | 记忆同步 |

---

## User Preferences (用户偏好)

- Memory mode: Manual recording at checkpoints / end of session
- Preferred language: Chinese (中文)
- **Session Sync Requirement (会话同步要求)**
  - 每次工作收尾时必须同步记忆
  - 更新 MEMORY.md 后要同步到 ccconfig 仓库
- **MCP 操作规则**:
  - 运行 `bash ccconfig/claudeinit.sh` 管理 MCP
  - Key/Token 存储在 `conf-claude.json` 中
- **提交后通知要求**:
  - 每次提交后，必须用 ✅ 标记 commit hash + message
- **进入 Claude 后的行为**:
  - 当用户说"hookstatus"或在 Claude 对话开头时，主动运行 `bash ccconfig/hook-status.sh` 检查并显示当前环境状态（文件链接、auto-sync、git push 记录、MCP 服务器状态）
- **Queue 指令**:
  - 当用户以 `queue xxx` 开头留言时，先完成当前工作，再处理 `queue` 后面的内容
- **搜索策略**:
  - 中文搜索：用 `minimax web_search` MCP
  - 英文搜索：用 `tavily search` MCP
  - 两种语言都搜可以结合结果，信息更全面
  - tavily 需要 `TAVILY_API_KEY`，在 `conf-claude.json` 中配置
- **飞书文档创建规则**:
  - feishu-mcp 创建文档：用 `feishu_create_doc`，内容是纯文本 markdown（不渲染）
  - lark-cli 创建文档：用 `lark-cli docs +create --markdown "$(cat file)" --as user`，支持飞书原生 markdown 渲染
  - 用户身份文档：用 `lark-cli docs +create --as user --folder-token xxx`，文档在用户个人空间
  - 应用身份文档：feishu-mCP 创建，文档在应用"cc编程大虾"空间
- **lark-cli 配置**:
  - 安装：`npm install -g @larksuite/cli`
  - PATH 修复：`ln -s ~/.local/node-v20.11.0-linux-x64/bin/lark-cli ~/.local/bin/lark-cli`
  - 初始化：`echo "secret" | lark-cli config init --app-id cli_xxx --app-secret-stdin --brand feishu`
  - 用户授权：`lark-cli auth login --recommend`
  - 用户身份创建文档：`lark-cli docs +create --as user --folder-token xxx --title "标题" --markdown "$(cat file)"`

---

## 设备列表

| 主机名 | 操作系统 | 备注 |
|--------|---------|------|
| Francis_MiPro | Windows 11 家庭中文版 | 主工作电脑 |
| (待添加) | | |

---

## 目录规则

- **Git 仓库根目录**: `/home/francis/git`
- 所有代码仓库都存放在 `/home/francis/git` 下
- 项目结构按仓库名组织

---

## Key Learnings (关键知识点)

### 2026-04-14 [Francis_MiPro] - 添加仓库目录规则

**规则**：git 仓库统一存放在 `/home/francis/git` 目录

---

### 2026-04-02 [Francis_MiPro] - ccconfig 重构完成

**目录结构变更**：
- `auto-sync.sh` → `init-auto-sync.sh`
- `enable-autostart.sh` → `init-enable-autostart.sh`
- `status.sh` → `hook-status.sh`
- `claudemcp.sh` → `claudeinit.sh`
- `confinit.json` → `conf-init.json`
- `mcpconf.json` → `conf-claude.json`
- `memory/` → `link/`
- `config/` 目录已删除

**重构要点**：
- init01-03 在 Ubuntu 直接执行，配置读取 conf-init.json
- claudeinit 在进入 Claude 后执行，完成 MCP 和链接检查
- 链接文件统一放在 link/ 目录

---

---

## 待办任务

### 初始化触发指令
**触发关键词**: "新环境初始化"

当用户在新 Ubuntu 环境说完这句话后，执行以下操作：
1. 运行 `bash ccconfig/claudeinit.sh` 配置所有 MCP
2. 运行 `bash ccconfig/hook-status.sh` 检查状态
3. 确认结果：文件链接 ✅、sync 自动同步进程 ✅、MCP 配置 ✅、记忆最新 ✅

---

## Session Logs (会话记录)

### 2026-04-02 [Francis_MiPro] - ccconfig 重构

**完成内容**：
1. 重命名所有脚本文件（添加 init-/hook- 前缀）
2. 移动配置文件到根目录
3. memory 目录改名为 link
4. 更新所有文档和引用
5. 中文字体安装优化（免密失败才让我输入密码）

### 2026-04-04 [Francis_MiPro] - 添加初始化触发指令

**完成内容**：
1. 记录"初始化claudeinit检查status"触发指令到待办任务
2. 等待用户在新的 Ubuntu 环境配置完成后说出该指令
3. 届时将执行：claudeinit.sh → hook-status.sh → 确认四项状态

### 2026-04-04 [Francis_MiPro] - 修复 init02claude + 新增 ubuntuinit.sh

**问题**：官方 `curl https://claude.ai/install.sh | bash` 在某些地区返回 HTML 错误页
**修复**：Claude Code 改用 npm 安装（`npm install -g @anthropic-ai/claude-code`）
**新增**：`ubuntuinit.sh` 合一初始化脚本，合并 init01+02+03

### 2026-04-04 [Francis_MiPro] - 修复 SessionStart hook 输出不可见问题

**问题**：SessionStart hook 执行了但不显示输出给用户（Claude Code 设计如此）
**原因**：Claude Code 的 command hook 设计为静默运行
**解决**：创建 `mcp-status/status-mcp.js` 提供 status 工具
**用法**：在 Claude 中说"运行 status 工具"即可查看环境状态
**注意**：SessionStart hook 仍然会在后台运行（执行 git pull 等），但不显示输出

### 2026-04-04 [Francis_MiPro] - status MCP 改为自动显示状态

**改进**：status-mcp.js 在 MCP 初始化完成后（notifications/initialized），自动发送 `notifications/message` 通知来在对话中显示状态
**目的**：让用户每次进入 Claude 时自动看到环境状态输出
**注意**：需要重启 Claude Code 加载更新后的 MCP

### 2026-04-05 [Francis_MiPro] - 飞书集成完整配置

**完成内容**：
1. **feishu-claude-code (Bridge) 配置完成**
   - WebSocket 长连接飞书机器人
   - App ID: <your-feishu-app-id>
   - 可在飞书里和我对话

2. **lark-cli + Skills 配置完成**
   - lark-cli 用户 OAuth 授权成功（Francis 账号）
   - 20 个 lark-* Skills 安装完成
   - Skills 存放位置：~/.agents/skills/

3. **飞书文档架构详解文档创建**
   - 文档已创建：https://www.feishu.cn/docx/EeFPdQtGkoUNhNx4YQccomj9nkd
   - 存放在指定目录：IFngftQdzlUhW7db6AOcZvYxnrg

4. **技术架构说明**
   - MCP：标准协议，Claude 直接调用（Tavily/Supabase/MiniMax等）
   - Skill：封装 lark-cli 的说明书，让我读取后执行
   - Bridge：Python WebSocket 程序，实现飞书双向对话

5. **文档目录已配置**
   - folder-token: IFngftQdzlUhW7db6AOcZvYxnrg
   - 所有新建文档都会放在这个目录

### 2026-04-10 [Francis_MiPro] - 修复 claudeinit.sh 同步逻辑

**问题**：
- `is_registered()` 只检查 `~/.claude.json`，而配置源是 `conf-claude.json`
- 导致 conf-claude.json 中定义的 MCP 被错误判定为"未注册"
- `sync_to_settings()` 只同步 `~/.claude.json` 中的 mcpServers，不完整

**修复**：
1. 修改 `is_registered()` 同时检查 `~/.claude.json` 和 `conf-claude.json`
2. 修改 `sync_to_settings()` 从 `conf-claude.json` 获取完整 mcpServers 配置
3. 更新 `link/settings.json` 添加所有 MCP 的完整配置
4. 添加 feishu、tavily、supabase 等的 mcpTools 配置

**验证**：重启 Claude Code 后所有 MCP 连接正常

### 2026-04-13 [Francis_MiPro] - 配置文件体系修正

**问题**：之前混淆了 settings.json 和 .config.json 的作用

**发现**：
- `~/.claude/settings.json` → 权限/环境变量/hooks（官方推荐手动配置）
- `~/.claude/.config.json` → MCP 配置/用户状态（Claude Code 实际读取）
- `~/.claude.json` → Claude Code 自动维护的状态（不同步）

**修复**：
1. 添加 `.config.json` 到 ccconfig/link/ 并创建符号链接
2. 确认三个核心文件都正确同步：
   - `~/.claude/settings.json` → link/settings.json
   - `~/.claude/.config.json` → link/.config.json
   - `~/CLAUDE.md` → link/CLAUDE.md
3. 更新 README.md 和 MEMORY.md 反映新架构

### 2026-04-13 [Francis_MiPro] - lark-cli 用户身份配置完成

**问题**：feishu-mcp 创建的文档归属"cc编程大虾"应用，不是用户个人

**解决方案**：lark-cli 支持 `--as user` 以用户身份创建文档

**完成内容**：
1. 修复 lark-cli PATH 问题：创建符号链接
2. 使用已有应用凭证初始化 lark-cli
3. 完成用户 OAuth 授权（Francis 账号）
4. 创建"ClaudeCode"文件夹（token: VB6nflC8JlFYhcdXNric6vORndg）
5. 创建配置指南文档：https://www.feishu.cn/docx/TpzedSvLhortLbx4EXYc5JfUnQx

**飞书文档创建最佳实践**：
- feishu-mCP：适合聊天、消息收发，内容创建用 lark-cli
- lark-cli + `--as user`：用户身份创建，文档在个人空间，markdown 会被飞书渲染
- 飞书 OAuth 授权管理：https://account.feishu.cn/ → 账号与安全 → 应用授权管理

