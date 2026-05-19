#!/bin/bash
# pushpub.sh - Export ccconfig to public version

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRIVATE_REPO="$SCRIPT_DIR"
PUBLIC_REPO="$SCRIPT_DIR-public"
PUBLIC_README="$PUBLIC_REPO/README.md"

echo "-> Export to: $PUBLIC_REPO"

mkdir -p "$PUBLIC_REPO"

# Init git
if [ ! -d "$PUBLIC_REPO/.git" ]; then
    git -C "$PUBLIC_REPO" init -b main
fi

# Clean public repo
rm -rf "$PUBLIC_REPO"/* "$PUBLIC_REPO"/.gitignore 2>/dev/null || true

# Copy shell scripts
for f in init.sh init-ubuntu.sh init-llm.sh init-mcp.sh init-skill.sh init-autostart.sh update.sh status.sh monitor.sh setup-links.sh; do
    [ -f "$PRIVATE_REPO/$f" ] && cp "$PRIVATE_REPO/$f" "$PUBLIC_REPO/"
done

# Copy lib/
if [ -d "$PRIVATE_REPO/lib" ]; then
    cp -r "$PRIVATE_REPO/lib" "$PUBLIC_REPO/"
fi

# Copy link/
mkdir -p "$PUBLIC_REPO/link"
cp "$PRIVATE_REPO/link/CLAUDE.md" "$PUBLIC_REPO/link/"

if [ -d "$PRIVATE_REPO/link/rules" ]; then
    cp -r "$PRIVATE_REPO/link/rules" "$PUBLIC_REPO/link/"
fi

if [ -d "$PRIVATE_REPO/link/commands" ]; then
    cp -r "$PRIVATE_REPO/link/commands" "$PUBLIC_REPO/link/"
fi

if [ -d "$PRIVATE_REPO/link/agents" ]; then
    cp -r "$PRIVATE_REPO/link/agents" "$PUBLIC_REPO/link/"
fi

if [ -d "$PRIVATE_REPO/link/skills" ]; then
    cp -r "$PRIVATE_REPO/link/skills" "$PUBLIC_REPO/link/"
fi

# Copy settings.example -> settings.json
if [ -f "$PRIVATE_REPO/link/settings.json.example" ]; then
    cp "$PRIVATE_REPO/link/settings.json.example" "$PUBLIC_REPO/link/settings.json"
fi

# Copy conf/ (example files only)
mkdir -p "$PUBLIC_REPO/conf"
for f in claude llm ubuntu feishu; do
    if [ -f "$PRIVATE_REPO/conf/${f}.json.example" ]; then
        cp "$PRIVATE_REPO/conf/${f}.json.example" "$PUBLIC_REPO/conf/${f}.json"
    fi
done
if [ -f "$PRIVATE_REPO/conf/versions.json" ]; then
    cp "$PRIVATE_REPO/conf/versions.json" "$PUBLIC_REPO/conf/"
fi

# .gitignore
cat > "$PUBLIC_REPO/.gitignore" <<'EOF'
settings.json
.config.json
conf/claude.json
conf/feishu.json
conf/llm.json
conf/ubuntu.json
EOF

# README
last_sync=$(date +"%Y-%m-%d %H:%M:%S")

cat > "$PUBLIC_README" <<'EOF'
# ccconfig — Claude Code 配置中枢（公开版）

> **公开版仅包含配置模板和脚本，不含个人数据和凭证。**
>
> 这是 ccconfig 的公开镜像版本，提取了可复用的脚本、配置模板和规范。

## 目录结构

```
ccconfig-public/
├── init.sh                   # 总入口
├── init-ubuntu.sh            # Ubuntu/WSL 初始化
├── init-llm.sh               # LLM 后端切换
├── init-mcp.sh               # MCP 服务器管理
├── init-skill.sh             # Skills 同步
├── init-autostart.sh         # auto-sync 自启动
├── update.sh                 # 月度升级
├── status.sh                 # 状态检查
├── monitor.sh                # 文件监控 + Git 同步
├── setup-links.sh            # 重建符号链接
│
├── conf/                     # 配置模板
│   ├── claude.json           # MCP + API Key 模板
│   ├── llm.json              # LLM 多后端配置模板
│   ├── ubuntu.json           # Git 用户信息模板
│   ├── feishu.json           # 飞书配置模板
│   └── versions.json         # 版本单一真相源
│
├── lib/                      # 共享库
│   └── path-helper.sh        # 动态路径解析
│
└── link/                     # 符号链接源
    ├── CLAUDE.md             # AI 行为指南
    ├── settings.json         # 权限 + MCP + hooks（模板）
    ├── rules/                # 条件规则
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
git clone https://github.com/yourusername/ccconfig-public.git ~/git/ccconfig-public
cd ~/git/ccconfig-public
```

### 2. 配置凭证

复制模板文件并填入实际值：

```bash
vim conf/claude.json      # Claude MCP / API Key
vim conf/llm.json         # LLM 后端
vim conf/feishu.json      # 飞书（可选）
vim conf/ubuntu.json      # Git 用户信息
vim link/settings.json    # 权限和 MCP
```

### 3. 建立符号链接

```bash
bash setup-links.sh
```

### 4. 初始化

```bash
bash init.sh all          # 一键初始化
bash init.sh status       # 检查状态
```

## 权限双层机制

| 层级 | 文件 | 作用 |
|------|------|------|
| AI 行为指南 | link/CLAUDE.md | 告诉 Claude 哪些命令可用 |
| 权限系统 | link/settings.json | 控制是否弹窗询问 |

运行 bash status.sh 检查状态。

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
bash update.sh all           # 一键升级全部
```

升级组件：Node.js → npm → GitHub CLI → Claude Code → uv → MCP → Skills → systemd

## 最后同步

来源：私有库 ccconfig 自动导出
EOF

sed -i "s/来源：私有库 ccconfig 自动导出/来源：私有库 ccconfig 自动导出\n时间：$last_sync/" "$PUBLIC_README"

# Commit
cd "$PUBLIC_REPO"
git add -A
if git diff --cached --quiet; then
    echo "No changes, skipping commit"
    exit 0
fi

commit_msg="Export: $last_sync"

git commit -m "$commit_msg"

echo "Exported to $PUBLIC_REPO"
echo "  cd $PUBLIC_REPO && git push origin main"
