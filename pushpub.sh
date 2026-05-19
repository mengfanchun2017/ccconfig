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
# ccconfig - Claude Code Configuration (Public)

> Public version with templates and scripts only. No personal data or credentials.

This is a public mirror of ccconfig, extracting reusable scripts, config templates, and conventions.

## Directory Structure

- init.sh - Main entry point
- init-ubuntu.sh - Ubuntu/WSL init
- init-llm.sh - LLM backend switch
- init-mcp.sh - MCP server management
- init-skill.sh - Skills sync
- init-autostart.sh - auto-sync autostart
- update.sh - Monthly update
- status.sh - Status check
- monitor.sh - File monitor + Git sync
- setup-links.sh - Rebuild symlinks
- conf/ - Config templates
- lib/ - Shared library
- link/ - Symlink source (~/.claude/)
  - CLAUDE.md - AI behavior guide
  - settings.json - Permissions + MCP + hooks (template)
  - rules/ - Conditional rules
  - commands/ - Command definitions
  - agents/ - Custom agents
  - skills/ - All skills

## Usage

1. Clone repo
2. Fill in credentials in conf/*.json and link/settings.json
3. Run bash setup-links.sh
4. Run bash init.sh all

## Last Sync

Source: Private ccconfig auto-export
EOF

sed -i "s/Source: Private ccconfig auto-export/Source: Private ccconfig auto-export\nTime: $last_sync/" "$PUBLIC_README"

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
