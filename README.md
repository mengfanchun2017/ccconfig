# ccconfig — Claude Code Configuration Hub

> Unified Claude Code configuration management. Git-synced across devices. One-command restore on new terminals.

## Overview

ccconfig manages the full lifecycle of Claude Code configuration:

- **Environment**: one-command Ubuntu/WSL initialization
- **Config**: single source of truth for LLM backends, MCP servers, API keys
- **Sync**: file watcher + auto git commit/push across all repos under `~/git/`
- **Skills**: 22 curated skills (Feishu docs, research, PPT generation, diagnostics)
- **Rules**: conditional rules loaded by path (code style, git, python, search, feishu, godot)
- **Agents**: intent-routing agents (assistant, feishucreate, learnchinese)
- **Optional**: Feishu Bridge, OfficeCLI, PPT generation, Vessel browser, remote SSH

## Architecture

```
~/.claude/  (symlinks)  ←──  ccconfig/link/  (source, git-tracked)
    ├── settings.json        ├── settings.json
    ├── .config.json         ├── .config.json
    ├── rules/               ├── rules/         (8 rules)
    ├── skills/              ├── skills/        (22 skills)
    ├── agents/              ├── agents/        (4 agents)
    └── projects/memory/     └── projects/memory/  (cross-session memory)

~/CLAUDE.md  ←──  ccconfig/link/CLAUDE.md
```

```
ccconfig/
├── init.sh                   # Entry point (interactive 2-level menu)
├── init-ubuntu.sh            # Ubuntu/WSL full environment init
├── init-llm.sh               # LLM backend switcher
├── init-mcp.sh               # MCP server manager
├── init-skill.sh             # Skills sync manager
├── init-autostart.sh         # auto-sync systemd service
├── update.sh                 # Monthly component upgrade (9 components)
│
├── status.sh                 # Status check (11 checks)
├── monitor.sh                # Multi-repo file watcher + auto git sync
├── sync.sh                    # Multi-repo smart sync (cloud↔local)
├── setup-links.sh            # Rebuild ~/.claude/ symlinks
├── deps-check.sh             # Dependency integrity check (CLI + JSON)
├── pushpub.sh                # Export to public cccshare
│
├── conf/                     # Configuration (single source of truth)
│   ├── claude.json           # MCP servers, API keys
│   ├── feishu.json           # Feishu unified config (lark-cli + cc-connect)
│   ├── llm.json              # LLM multi-backend config
│   ├── ubuntu.json           # Git user info
│   ├── versions.json         # Component versions + pins
│   └── python-requirements.txt  # Python package manifest
│
├── lib/                      # Shared library
│   └── path-helper.sh        # Dynamic path resolution (4-tier fallback)
│
├── link/                     # → ~/.claude/ symlink sources
│   ├── CLAUDE.md             # AI behavior guide
│   ├── settings.json         # Permissions + MCP + hooks
│   ├── .config.json          # Environment + state
│   ├── rules/                # Conditional rules (loaded by path)
│   ├── agents/               # Intent-routing agents
│   ├── skills/               # All skills (22)
│   └── projects/             # MEMORY.md per project
│
├── share/                    # Public share module
│   └── setup.sh              # Guided onboarding wizard
│
├── option-bridge/            # Optional: Feishu message Bridge
│   ├── init.sh               # lark-cli + cc-connect installer
│   ├── lark-switch.sh        # Multi-account switcher
│   ├── bot-status.sh         # Bot status viewer
│   └── mcp-bridge/           # Optional MCP for bot messages
│
├── option-officecli/         # Optional: OfficeCLI (AI-native Office tools)
│   └── init.sh               # Installer + status + update
│
├── option-ppt-master/        # Optional: PPT generation (python-pptx)
│   └── init.sh               # Clone repo + install deps
│
├── option-vessel/            # Optional: Vessel AI browser
│   └── init.sh               # Installer + MCP registration
│
├── remote/                   # Remote access (Tailscale + SSH + tmux)
│   ├── server/               # SSH Server + tmux setup
│   └── client/               # Windows Tailscale setup
│
├── windows/                  # Windows/WSL interop
│
├── LICENSE                   # MIT
├── CHANGELOG.md              # Change history
├── CONTRIBUTING.md           # Contribution guide
└── .editorconfig             # Editor settings
```

## Quick Start

```bash
# Clone
git clone git@github.com:<your-github-username>/ccconfig.git ~/git/ccconfig
cd ~/git/ccconfig

# Interactive menu
bash init.sh

# Or one-shot full init (Ubuntu + LLM + MCP + Skills)
bash init.sh all

# Check everything
bash status.sh
```

## Core Commands

| Command | Purpose |
|---------|---------|
| `bash init.sh` | Interactive menu (env, remote, MCP, skills, tools) |
| `bash init.sh all` | One-shot full initialization |
| `bash status.sh` | Full status check (11 items) |
| `bash deps-check.sh` | Dependency integrity check |
| `bash update.sh all` | Monthly component upgrade |
| `bash monitor.sh start` | Start auto-sync daemon |
| `bash monitor.sh status` | Sync daemon status |
| `bash monitor.sh log` | Recent sync log |
| `bash setup-links.sh` | Rebuild ~/.claude/ symlinks |

## Status Check Coverage

`status.sh` performs 11 checks on every Claude Code session start:

1. Config symlinks (settings.json, .config.json, CLAUDE.md, MEMORY.md, rules, commands)
2. Core dependencies (git, bash, curl)
3. auto-sync daemon + systemd service
4. GitHub last push date
5. MEMORY.md last update
6. ppt-master environment (repo, python-pptx, cairosvg)
7. Feishu (lark-cli: install, config, auth, bridge, bots)
8. Vessel AI browser (install, process, token, MCP)
9. OfficeCLI (install, MCP registration)
10. MCP servers (parallel health check, 24h cache)
11. Remote access (SSH, port, WSL network mode, Tailscale)
12. Option components auto-discovery

## Dependency Check

`deps-check.sh` verifies all tool and package dependencies:

```bash
bash deps-check.sh              # Full check
bash deps-check.sh --required   # Essential deps only
bash deps-check.sh --json       # JSON output for scripting
```

Checks: git, bash, curl, node, python3, pip3, npm, gh, claude, inotify-tools, systemd, tmux, ssh, uv, lark-cli, cc-connect, officecli, python-pptx, cairosvg, lxml, pillow, plus network connectivity (GitHub, npm, PyPI).

## Auto-Sync

`monitor.sh` watches all git repos under `~/git/` for changes, auto-commits and pushes:

```bash
./monitor.sh start     # Start daemon (120s debounce, 60s min push gap)
./monitor.sh stop      # Stop daemon
./monitor.sh status    # Show status + tracked repos + pending changes
./monitor.sh log 50    # Last 50 log lines
./monitor.sh tail      # Follow push results live
./monitor.sh monitor   # Follow file changes live
```

Flow: `inotifywait` watches `~/git/` → detects changes → 120s debounce → `git add -A` → `git commit` → `git pull --ff-only` → `git push` → rebuild symlinks → sync skills.

## Optional Components

All optional components follow the `option-<name>/` convention:

```bash
# Feishu Bridge (lark-cli + cc-connect)
bash option-bridge/init.sh

# OfficeCLI (AI-native .pptx/.docx/.xlsx)
bash option-officecli/init.sh

# PPT generation (python-pptx + cairosvg + ppt-master)
bash option-ppt-master/init.sh

# Vessel AI browser
bash option-vessel/init.sh
```

Each option component supports at minimum `init.sh --status` for health checks.

## LLM Backends

```bash
bash init-llm.sh              # Interactive selection
bash init-llm.sh list         # List available backends
bash init-llm.sh deepseek     # Switch to DeepSeek
bash init-llm.sh minimax      # Switch to MiniMax
bash init-llm.sh claude       # Switch to Claude (Anthropic)
```

## Remote Access

Connect to desktop Claude Code tmux session from laptop via Tailscale + SSH:

```bash
# Desktop WSL (one-time setup)
bash remote/server/tmux-sshd.sh

# Desktop Windows (admin PowerShell)
powershell -ExecutionPolicy Bypass -File "remote/client/ts-setup.ps1"

# Laptop
ssh francis@<Tailscale IP> -p 2222  # Auto-attaches to tmux 'claude' session
```

## Public Share (cccshare)

Export a public version without private data:

```bash
bash pushpub.sh        # Export to cccshare/ (local)
bash pushpub.sh git    # Export and push to GitHub
```

The public version includes `share/setup.sh` — a guided onboarding wizard for new users. See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## Development

```bash
# Syntax check all scripts
for f in *.sh lib/*.sh option-*/*.sh share/*.sh; do bash -n "$f" && echo "$f OK"; done

# Run dependency check
bash deps-check.sh

# Test status
bash status.sh

# Validate JSON configs
python3 -c "import json; [json.load(open(f'conf/{f}.json')) for f in ['claude','llm','ubuntu','versions','feishu']]"
```

### Adding an Option Component

1. Create `option-<name>/` with `init.sh` and `README.md`
2. Support `--status` flag in init.sh
3. Add deps to `deps-check.sh` OPTIONAL_DEPS array
4. It auto-appears in `status.sh` option components section

### Adding a Skill

1. Create skill in `link/skills/<name>/`
2. Run `bash init-skill.sh sync`

## Files Not Tracked

- `conf/claude.json` — API keys
- `conf/feishu.json` — App secrets
- `conf/llm.json` — LLM API keys
- `conf/ubuntu.json` — Git user info
- `link/settings.json` — Personal permissions
- `link/.config.json` — Environment state
- `.monitor-sync.*` — Runtime state
- `.snapshots/` — Upgrade snapshots
- `tmp/` — One-off task artifacts
- `cccshare/` — Public export (generated)

## License

MIT — see [LICENSE](LICENSE)
