#!/bin/bash
# pushpub.sh - Export ccconfig to public cccshare version
# Usage: pushpub.sh [local|git]
#   local (default) - export to cccshare/, no git push
#   git             - export to cccshare/, commit and push

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRIVATE_REPO="$SCRIPT_DIR"
SHARE_DIR="$SCRIPT_DIR/cccshare"
MODE="${1:-local}"
PUBLIC_README="$SHARE_DIR/README.md"

echo "-> Export to: $SHARE_DIR (mode: $MODE)"

mkdir -p "$SHARE_DIR"

# Init git if needed
if [ ! -d "$SHARE_DIR/.git" ]; then
    git -C "$SHARE_DIR" init -b main
fi

# Clean share dir (preserve .git)
find "$SHARE_DIR" -mindepth 1 -not -path "$SHARE_DIR/.git" -not -path "$SHARE_DIR/.git/*" -delete 2>/dev/null || true

# Copy shell scripts
for f in init.sh init-ubuntu.sh init-llm.sh init-mcp.sh init-skill.sh init-autostart.sh update.sh status.sh monitor.sh setup-links.sh; do
    [ -f "$PRIVATE_REPO/$f" ] && cp "$PRIVATE_REPO/$f" "$SHARE_DIR/"
done

# Copy lib/
if [ -d "$PRIVATE_REPO/lib" ]; then
    cp -r "$PRIVATE_REPO/lib" "$SHARE_DIR/"
fi

# Copy link/
mkdir -p "$SHARE_DIR/link"
cp "$PRIVATE_REPO/link/CLAUDE.md" "$SHARE_DIR/link/"

if [ -d "$PRIVATE_REPO/link/rules" ]; then
    cp -r "$PRIVATE_REPO/link/rules" "$SHARE_DIR/link/"
fi

if [ -d "$PRIVATE_REPO/link/commands" ]; then
    cp -r "$PRIVATE_REPO/link/commands" "$SHARE_DIR/link/"
fi

if [ -d "$PRIVATE_REPO/link/agents" ]; then
    cp -r "$PRIVATE_REPO/link/agents" "$SHARE_DIR/link/"
fi

if [ -d "$PRIVATE_REPO/link/skills" ]; then
    cp -r "$PRIVATE_REPO/link/skills" "$SHARE_DIR/link/"
fi

# Copy settings.example -> settings.json
if [ -f "$PRIVATE_REPO/link/settings.json.example" ]; then
    cp "$PRIVATE_REPO/link/settings.json.example" "$SHARE_DIR/link/settings.json"
fi

# Copy conf/ (example files only, rename to production names)
mkdir -p "$SHARE_DIR/conf"
for f in claude llm ubuntu feishu; do
    if [ -f "$PRIVATE_REPO/conf/${f}.json.example" ]; then
        cp "$PRIVATE_REPO/conf/${f}.json.example" "$SHARE_DIR/conf/${f}.json"
    fi
done
if [ -f "$PRIVATE_REPO/conf/versions.json" ]; then
    cp "$PRIVATE_REPO/conf/versions.json" "$SHARE_DIR/conf/"
fi

# .gitignore (only for the public share repo)
cat > "$SHARE_DIR/.gitignore" <<'EOF'
settings.json
.config.json
conf/claude.json
conf/feishu.json
conf/llm.json
conf/ubuntu.json
EOF

# Generate README
last_sync=$(date +"%Y-%m-%d %H:%M:%S")

cat > "$PUBLIC_README" <<'EOF'
# ccconfig — Claude Code 配置中枢（公开版）

> **公开版仅包含配置模板和脚本，不含个人数据和凭证。**
>
> 这是 ccconfig 的公开镜像版本，提取了可复用的脚本、配置模板和规范。

## 使用场景

- **环境初始化**：一键初始化 Claude Code、Skills、MCP、飞书工具
- **权限管理**：细粒度权限控制，避免频繁弹窗确认
- **LLM 切换**：多后端支持（DeepSeek、MiniMax、Claude 官方），成本优化
- **自动同步**：文件监控 + 120s 防抖，自动提交推送
- **飞书集成**：lark-cli 终端操作文档/日历/任务

## 目录结构

```
cccshare/
├── init.sh                   # 总入口（交互式两级菜单）
├── init-ubuntu.sh            # Ubuntu/WSL 全环境初始化
├── init-llm.sh               # LLM 后端切换
├── init-mcp.sh               # MCP 服务器管理
├── init-skill.sh             # Skills 同步管理
├── init-autostart.sh         # auto-sync systemd 自启动配置
├── update.sh                 # 月度升级
│
├── status.sh                 # 状态检查
├── monitor.sh                # 文件监控 + 自动 Git 同步（120s 防抖）
├── setup-links.sh            # 重建 ~/.claude/ 符号链接
│
├── conf/                     # 配置文件（单一来源）
│   ├── claude.json           # MCP 服务器配置、API Key（模板）
│   ├── llm.json              # LLM 多后端配置（模板）
│   ├── ubuntu.json           # Git 用户信息（模板）
│   ├── feishu.json           # 飞书统一配置（模板）
│   └── versions.json         # 版本单一真相源
│
├── lib/                      # 共享库
│   └── path-helper.sh        # 动态路径解析（4级回退）
│
└── link/                     # 符号链接源 → ~/.claude/
    ├── CLAUDE.md             # AI 行为指南
    ├── settings.json         # 权限 + MCP + hooks（模板）
    ├── rules/                # 条件规则（编码、Git、Python、搜索、飞书、Godot）
    ├── commands/             # 命令定义
    ├── agents/               # 自定义 agents
    └── skills/               # 全部 skills
```

## 与私有版的区别

| 内容 | 私有库 | 公开库 |
|------|--------|--------|
| 脚本 | ✅ | ✅ |
| rules/skills/agents | ✅ | ✅ |
| conf/*.json | ✅（含凭证） | ✅（模板） |
| settings.json | ✅（个人权限） | ✅（模板） |
| MEMORY.md | ✅ | ❌ |
| option-bridge/ | ✅ | ❌ |
| remote/ | ✅ | ❌ |

## 使用方式

### 1. 克隆公开库

```bash
git clone https://github.com/<your-github-username>/cccshare.git ~/git/cccshare
cd ~/git/cccshare
```

### 2. 配置凭证

```bash
# Claude MCP / API Key
vim conf/claude.json

# LLM 后端
vim conf/llm.json

# 飞书（可选）
vim conf/feishu.json

# Git 用户信息
vim conf/ubuntu.json

# settings.json 权限和 MCP
vim link/settings.json
```

### 3. 建立符号链接

```bash
bash setup-links.sh
```

### 4. 初始化

```bash
bash init.sh all          # 一键初始化
bash status.sh            # 检查状态
```

## 权限双层机制

| 层级 | 文件 | 作用 |
|------|------|------|
| AI 行为指南 | link/CLAUDE.md | 告诉 Claude 哪些命令可用 |
| 权限系统 | link/settings.json | 控制是否弹窗询问 |

## LLM 切换

```bash
bash init-llm.sh              # 交互式选择
bash init-llm.sh deepseek     # 切换到 DeepSeek
bash init-llm.sh minimax      # 切换到 MiniMax
```

## auto-sync 同步

```bash
./monitor.sh start     # 后台启动（120s 防抖）
./monitor.sh stop      # 停止
./monitor.sh status    # 查看状态
./monitor.sh log       # 最近日志
```

## 月度升级

```bash
bash update.sh all     # 一键升级全部
```

## 导出公开库

```bash
bash pushpub.sh        # 导出到 cccshare/（不推送）
bash pushpub.sh git    # 导出并推送到 GitHub
```

## 最后同步

来源：私有库 ccconfig 自动导出
EOF

sed -i "s/来源：私有库 ccconfig 自动导出/来源：私有库 ccconfig 自动导出\n时间：$last_sync/" "$PUBLIC_README"

# Copy pushpub.sh itself
cp "$PRIVATE_REPO/pushpub.sh" "$SHARE_DIR/"

# Update VERSION.md
if [ ! -f "$SHARE_DIR/VERSION.md" ]; then
    cat > "$SHARE_DIR/VERSION.md" <<'EOF'
# 版本记录

> 更新频率：每月一次，或有大变更时

## 首次发布

- 从 ccconfig 私有库导出
- 清理个人隐私信息

## 版本说明

- 每次更新记录变更内容
EOF
fi

# Git operations (only in git mode)
if [ "$MODE" = "git" ]; then
    cd "$SHARE_DIR"
    git add -A

    if git diff --cached --quiet; then
        echo "No changes, skipping commit"
        exit 0
    fi

    git commit -m "Export: $last_sync"

    if git remote get-url origin &>/dev/null 2>&1; then
        git push origin main
    else
        echo "Remote not set, push manually:"
        echo "  cd $SHARE_DIR && git remote add origin <url> && git push -u origin main"
    fi

    echo "Exported to $SHARE_DIR and pushed"
else
    echo "Exported to $SHARE_DIR (local mode)"
    echo "Review changes: cd $SHARE_DIR && git diff"
    echo "To push: bash pushpub.sh git"
fi