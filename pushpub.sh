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
for f in init.sh init-ubuntu.sh init-llm.sh init-mcp.sh init-skill.sh init-autostart.sh update.sh status.sh monitor.sh setup-links.sh deps-check.sh; do
    [ -f "$PRIVATE_REPO/$f" ] && cp "$PRIVATE_REPO/$f" "$SHARE_DIR/"
done

# Copy share/ (setup wizard)
if [ -d "$PRIVATE_REPO/share" ]; then
    cp -r "$PRIVATE_REPO/share" "$SHARE_DIR/"
fi

# Copy standard project files
for f in LICENSE CHANGELOG.md CONTRIBUTING.md .editorconfig; do
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
.monitor-sync.log
.monitor-sync.pid
.monitor-sync.debounce
.snapshots/
EOF

# Generate README
last_sync=$(date +"%Y-%m-%d %H:%M:%S")

cat > "$PUBLIC_README" <<'PUBEOF'
# ccconfig — Claude Code Configuration Hub

> **Public edition**: scripts, templates, and rules. No personal data or credentials.
>
> Auto-generated from private ccconfig repo.

## Quick Start

```bash
git clone https://github.com/<your-github-username>/cccshare.git ~/git/cccshare
cd ~/git/cccshare

# Guided setup wizard (recommended for new users)
bash share/setup.sh

# Or one-shot full init
bash init.sh all

# Check status
bash status.sh
```

## Directory

```
cccshare/
├── init.sh                   # Entry point (interactive menu)
├── init-ubuntu.sh            # Ubuntu/WSL full env init
├── init-llm.sh               # LLM backend switcher
├── init-mcp.sh               # MCP server manager
├── init-skill.sh             # Skills sync
├── init-autostart.sh         # auto-sync systemd service
├── update.sh                 # Monthly upgrade (9 components)
│
├── status.sh                 # Status check (12 checks)
├── monitor.sh                # File watcher + auto git sync
├── setup-links.sh            # Rebuild ~/.claude/ symlinks
├── deps-check.sh             # Dependency integrity check
│
├── share/                    # Share module
│   └── setup.sh              # Guided onboarding wizard
│
├── conf/                     # Config templates
│   ├── claude.json           # MCP servers, API keys
│   ├── llm.json              # LLM backends
│   ├── ubuntu.json           # Git user info
│   ├── feishu.json           # Feishu integration
│   └── versions.json         # Version single source of truth
│
├── lib/                      # Shared library
│   └── path-helper.sh        # Dynamic path resolution (4-tier fallback)
│
├── link/                     # → ~/.claude/ symlink sources
│   ├── CLAUDE.md             # AI behavior guide
│   ├── settings.json         # Permissions + MCP + hooks (template)
│   ├── rules/                # Conditional rules (code, git, python, search, feishu, godot)
│   ├── agents/               # Custom agents (assistant, feishucreate, learnchinese)
│   └── skills/               # All skills (26)
│
├── LICENSE                   # MIT
├── CHANGELOG.md              # Change log
├── CONTRIBUTING.md           # Contribution guide
└── .editorconfig             # Editor config
```

## Private vs Public

| Content | Private | Public |
|---------|---------|--------|
| Scripts | ✅ | ✅ |
| rules/skills/agents | ✅ | ✅ |
| share/setup.sh | ✅ | ✅ |
| conf/*.json | ✅ (with credentials) | ✅ (templates only) |
| settings.json | ✅ (personal permissions) | ✅ (template) |
| MEMORY.md | ✅ | ❌ |
| option-bridge/ | ✅ | ❌ |
| option-officecli/ | ✅ (for reference) | ❌ |
| option-ppt-master/ | ✅ (for reference) | ❌ |
| remote/ | ✅ | ❌ |

## Guided Setup

The `share/setup.sh` wizard walks new users through:

1. Dependency check (git, node, python3, curl, gh, claude)
2. Git user info (name, email)
3. LLM API key configuration
4. Private config repo setup (optional)
5. Symlink creation

```bash
bash share/setup.sh                        # Full interactive
bash share/setup.sh --quick                # Quick mode (essentials only)
bash share/setup.sh --config-repo <url>    # Import from private repo
```

## Using a Private Config Repo

Keep your API keys and tokens in a separate private repo:

```bash
# Create private config repo
mkdir ~/git/ccconfig-private
cd ~/git/ccconfig-private && git init -b main

# Add your config files
mkdir conf
cp ~/git/cccshare/conf/*.json.example conf/
# Edit conf/*.json with your credentials
# ...

git add -A && git commit -m "Initial config"
git remote add origin git@github.com:you/ccconfig-private.git
git push -u origin main

# Then import during setup
bash share/setup.sh --config-repo git@github.com:you/ccconfig-private.git
```

## Updates

```bash
bash update.sh all     # Upgrade all core components
bash update.sh         # Interactive menu

# Update cccshare itself
git pull origin main
bash setup-links.sh    # Rebuild symlinks if configs changed
```

## License

MIT — see [LICENSE](LICENSE)

---

Last sync from private ccconfig repo
PUBEOF

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