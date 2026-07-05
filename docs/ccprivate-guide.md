# ccprivate 个人仓库搭建指南

> ccconfig 是公开仓库，不含任何 API key / Token / 个人配置。
> 你需要一个**私有仓库 ccprivate** 存放个人敏感数据，通过 symlink 让 ccconfig 读取。

## 概述

```
你的 GitHub
├── ccconfig (public)          ← fork 或 clone 公开仓库
└── ccprivate (private)        ← 你新建的私有仓库，存放个人敏感数据
```

ccprivate 通过 symlink 向 ccconfig 注入真实配置：

```
ccprivate/                         ccconfig/
├── conf/                          conf/
│   ├── llm.json        ──symlink──→ llm.json       (API Key)
│   ├── claude.json     ──symlink──→ claude.json    (MCP env)
│   ├── feishu.json     ──symlink──→ feishu.json    (飞书 App ID/Secret)
│   ├── ubuntu.json     ──symlink──→ ubuntu.json    (Git 用户信息)
│   ├── f-logme.json    ──symlink──→ f-logme.json   (飞书 Base token)
│   ├── f-doc.json      ──symlink──→ f-doc.json     (飞书 wiki node)
│   └── ...
│
├── link/                          ~/
│   ├── CLAUDE.md       ──symlink──→ ~/CLAUDE.md
│   ├── settings.json   ──symlink──→ ~/.claude/settings.json
│   ├── .config.json    ──symlink──→ ~/.claude/.config.json
│   └── projects/       ──symlink──→ ~/.claude/projects/ (memory)
│
└── setup.sh            调用  →    ccconfig/setup-links.sh
```

**原则**：ccprivate 存真实值，ccconfig 存模板（`.example`）和脚本。你 fork ccconfig，自己建 ccprivate。

---

## 第一步：创建 ccprivate 私有仓库

### 1.1 在 GitHub 创建私有仓库

1. 打开 https://github.com/new
2. Repository name: `ccprivate`
3. 选择 **Private**（必须私有！含 API Key）
4. 不要勾选 "Initialize this repository with a README"（空仓即可）
5. 点 "Create repository"

### 1.2 克隆到本地

```bash
mkdir -p ~/git
cd ~/git

# 用 gh 克隆（需要先 gh auth login）
gh repo clone <your-github-username>/ccprivate

# 或直接用 git
git clone https://github.com/<your-github-username>/ccprivate.git
```

---

## 第二步：建立目录结构

```bash
cd ~/git/ccprivate

# 创建子目录
mkdir -p conf
mkdir -p link/projects
```

最终结构：

```
ccprivate/
├── conf/                 # 真实配置文件（含 API Key）
├── link/                 # 个人 Claude Code 配置
│   ├── CLAUDE.md         # 你的全局 AI 行为指南
│   ├── settings.json     # Claude Code 权限设置
│   ├── .config.json      # Claude Code 扩展配置
│   └── projects/         # 项目级 memory
└── setup.sh              # 一键建立所有 symlink
```

---

## 第三步：填写配置文件

### 3.1 conf/llm.json — LLM API Key（必填）

从 `ccconfig/conf/llm.json.example` 复制模板，填入你的 API Key：

```bash
cp ~/git/ccconfig/conf/llm.json.example ~/git/ccprivate/conf/llm.json
```

编辑 `~/git/ccprivate/conf/llm.json`：

```json
{
    "llms": {
        "deepseek": {
            "name": "DeepSeek",
            "base_url": "https://api.deepseek.com/anthropic",
            "model": "deepseek-v4-pro",
            "key": "sk-你的DeepSeek API Key",
            "small_model": "deepseek-v4-pro"
        },
        "minimax": {
            "name": "MiniMax",
            "base_url": "https://api.minimaxi.com/anthropic",
            "model": "MiniMax-M3",
            "key": "sk-你的MiniMax API Key",
            "small_model": "MiniMax-M3"
        }
    },
    "current": "deepseek"
}
```

至少填一个 LLM 后端。`current` 设为你日常用的默认后端。

### 3.2 conf/claude.json — MCP 服务器配置

```bash
cp ~/git/ccconfig/conf/claude.json.example ~/git/ccprivate/conf/claude.json
```

编辑填入：
- `ANTHROPIC_AUTH_TOKEN` — 你的 API Key
- `TAVILY_API_KEY` — Tavily 搜索 API Key（https://tavily.com）
- `MINIMAX_API_KEY` — MiniMax API Key（和 llm.json 用的是同一个）
- Supabase 相关（可选）

### 3.3 conf/ubuntu.json — Git 用户信息

```bash
cp ~/git/ccconfig/conf/ubuntu.json.example ~/git/ccprivate/conf/ubuntu.json
```

编辑填入：

```json
{
    "git": {
        "repo": "你的GitHub用户名/ccconfig",
        "target_dir": "$HOME/git/ccconfig",
        "email": "you@example.com",
        "username": "你的GitHub用户名"
    }
}
```

### 3.4 其他 conf（按需）

| 文件 | 用途 | 必须？ |
|------|------|--------|
| `conf/feishu.json` | 飞书应用 App ID/Secret | 用飞书功能才需要 |
| `conf/f-logme.json` | 飞书 OKR Base token | 用工作日志才需要 |
| `conf/f-doc.json` | 飞书 wiki 节点 token | 用文档功能才需要 |
| `conf/f-ppt.json` | PPT 生成工具路径 | 用 PPT 功能才需要 |
| `conf/cloudflare.json` | Cloudflare API token | 用 Cloudflare 才需要 |
| `conf/supabase.json` | Supabase 数据库 token | 用 Supabase 才需要 |
| `conf/f-moocrec.json` | 慕课推荐配置 | 用课程推荐才需要 |

每个都有对应的 `.example` 模板在 `ccconfig/conf/` 下，复制后编辑即可。

---

## 第四步：填写个人 Claude Code 配置

### 4.1 ~/CLAUDE.md

```bash
# 如果还没有，从 ccconfig 的模板获取灵感
cat > ~/git/ccprivate/link/CLAUDE.md << 'EOF'
# Claude Code 用户配置

## 核心约定
- 中文回复
- 你的其他偏好...
EOF
```

这是全局 AI 行为指南，所有项目通用。详见 `~/CLAUDE.md` 现有内容。

### 4.2 ~/.claude/settings.json

Claude Code 权限设置。至少包含：

```json
{
  "permissions": {
    "allow": [
      "Bash(*)",
      "Read(*)",
      "Write(*)",
      "Edit(*)",
      "Glob(*)",
      "Grep(*)",
      "WebSearch",
      "WebFetch",
      "Skill(*)"
    ]
  }
}
```

> 更多权限选项参考 `ccconfig/link/settings.json.example`。

### 4.3 ~/.claude/.config.json

Claude Code 扩展配置（可选）。如果你有自定义配置，放这里。

---

## 第五步：创建 setup.sh

这是关键脚本 — 一键建立所有 symlink。

```bash
cat > ~/git/ccprivate/setup.sh << 'SETUPEOF'
#!/bin/bash
# ccprivate setup.sh — 私有 + 公开链接一步到位
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="${CCCONFIG_HOME:-$HOME/git/ccconfig}"
GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }

link_file() {
    local src="$1" dst="$2" name="$3"
    mkdir -p "$(dirname "$dst")"
    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
        info "$name: 已链接"
        return 0
    fi
    [ -e "$dst" ] || [ -L "$dst" ] && rm -f "$dst"
    ln -sf "$src" "$dst"
    success "$name: 已链接"
}

echo "=== ccprivate/setup.sh — 私有链接 ==="

# conf/ 配置文件 → ccconfig/conf/（symlink）
for f in "$SCRIPT_DIR"/conf/*.json; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    link_file "$f" "$CCCONFIG_DIR/conf/$name" "conf/$name"
done

# link/ 个人 Claude Code 配置 → ~/
if [ -f "$SCRIPT_DIR/link/CLAUDE.md" ]; then
    link_file "$SCRIPT_DIR/link/CLAUDE.md" "$HOME/CLAUDE.md" "~/CLAUDE.md"
fi
if [ -f "$SCRIPT_DIR/link/settings.json" ]; then
    link_file "$SCRIPT_DIR/link/settings.json" "$HOME/.claude/settings.json" "~/.claude/settings.json"
fi
if [ -f "$SCRIPT_DIR/link/.config.json" ]; then
    link_file "$SCRIPT_DIR/link/.config.json" "$HOME/.claude/.config.json" "~/.claude/.config.json"
fi

# projects/ memory 目录 → ccconfig/link/projects/
if [ -d "$SCRIPT_DIR/link/projects" ]; then
    link_file "$SCRIPT_DIR/link/projects" "$CCCONFIG_DIR/link/projects" "link/projects"
fi

echo ""
echo "=== ccconfig/setup-links.sh — 公开链接 ==="
if [ -f "$CCCONFIG_DIR/setup-links.sh" ]; then
    bash "$CCCONFIG_DIR/setup-links.sh"
fi

echo ""
success "全部链接完成"
echo "下一步: bash $CCCONFIG_DIR/init.sh all"
SETUPEOF

chmod +x ~/git/ccprivate/setup.sh
```

---

## 第六步：推送到 GitHub

```bash
cd ~/git/ccprivate

# 创建 .gitignore（防御：防止意外提交敏感文件到其他仓）
cat > .gitignore << 'EOF'
# 既然是私有仓库，理论上所有文件都可以提交。
# 但以下几类暂时不跟：
*.swp
*~
.DS_Store
EOF

git add -A
git commit -m "init: ccprivate 个人配置仓库

Co-Authored-By: Claude <noreply@anthropic.com>"

git push -u origin main
```

---

## 第七步：运行 setup.sh

```bash
# 一键建立所有 symlink（私有 + 公开）
bash ~/git/ccprivate/setup.sh
```

然后继续 [BOOTSTRAP.md](../BOOTSTRAP.md) 的阶段 4（初始化）。

---

## 日常使用

### 修改配置

1. 直接编辑 `~/git/ccprivate/conf/<file>.json`（因为是 symlink，ccconfig 侧自动生效）
2. `cd ~/git/ccprivate && git add -A && git commit -m "..." && git push`

### 新机器恢复

```bash
gh repo clone <your-username>/ccprivate ~/git/ccprivate
bash ~/git/ccprivate/setup.sh
```

### 添加新配置文件

1. 在 ccconfig 创建 `.example` 模板：`ccconfig/conf/new-service.json.example`
2. 在 ccprivate 创建真实配置：`ccprivate/conf/new-service.json`
3. 更新 `ccprivate/setup.sh` 自动处理（或用已有的 `conf/*.json` glob）
4. 确保 `ccconfig/.gitignore` 包含 `conf/new-service.json`

---

## 常见问题

### Q: 为什么 ccprivate 不直接 fork？
A: ccprivate 和 ccconfig 是完全不同的仓库。ccconfig 是公开的工具集，ccprivate 是你个人的密钥库。没有"官方 ccprivate"可以 fork——每个人的密钥不同。

### Q: 可以不用 ccprivate 吗？
A: 可以。用 `bash ccconfig/share/setup.sh` 交互式配置向导，手动输入 API Key。但 ccprivate 方式更方便——一次配置，多机复用，`git pull` 即可恢复。

### Q: ccprivate/setup.sh 和 ccconfig/setup-links.sh 的关系？
A: `ccprivate/setup.sh` 做私有链接（conf + CLAUDE.md + settings.json），然后调用 `ccconfig/setup-links.sh` 做公开链接（rules/agents/commands/skills）。一步到位。

### Q: conf/ 文件是 symlink，git 会跟踪吗？
A: ccconfig 的 `.gitignore` 已忽略 `conf/*.json`（除 `.example` 和 `versions.json`），symlink 不会被 commit。`hooks/pre-commit` 也会拦截。
