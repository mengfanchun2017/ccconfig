---
name: f-vessel
description: Vessel AI Agent 浏览器 — MCP 操控真实浏览器，人类监督审批。Use when you need to browse the web, log into sites, fill forms, extract page content, take screenshots, or perform multi-step web tasks on behalf of the user.
---

# Vessel — AI Agent Browser Control

Vessel is an open-source browser (Linux) that Claude Code controls via MCP (port 3100). All actions are visible in the Supervisor sidebar for human approval.

## Core Capabilities

| Action | Tool | Notes |
|--------|------|-------|
| Navigate to URL | `navigate` | Full URL including protocol |
| Click element | `click` | By selector, text, or coordinates |
| Type text | `type` | Into input fields |
| Extract page content | `extract` | Text, HTML, or structured data |
| Screenshot | `screenshot` | Visible viewport or full page |
| Execute JavaScript | `evaluate` | Run arbitrary JS in page context |
| Tab management | `new_tab`, `switch_tab`, `close_tab` | Multi-tab workflows |
| Wait for element | `wait` | Wait for selector or timeout |
| Scroll | `scroll` | Scroll by pixels or to element |
| Form fill | `fill_form` | Batch fill multiple fields |
| Bookmark | `bookmark` | Save/read bookmarks |
| Session | `save_session`, `restore_session` | Persist cookies + localStorage |

## 在研究流程中的定位

Vessel 不是搜索工具，是**浏览器操控工具**。在研究框架中的角色：

```
Tavily extract → 拿到内容 → 直接用
               → 失败（空壳/登录墙/SPA/反爬） → Vessel 打开页面提取
```

- **搜索始终用 Tavily**（速度快、成本低、可并行）
- **Vessel 只用于 Tavily 提取失败的页面**，或需要交互/登录的场景
- 日常调研中 Vessel 是最后 fallback，不是主力

## Workflow Pattern

When asked to perform a web task:

1. **Navigate** to the target URL
2. **Wait** for page to load (wait for key element)
3. **Extract** or **Screenshot** to understand the page
4. **Interact** (click, type, scroll)
5. **Verify** with another extract/screenshot
6. **Report** results back to user

## Login & Authentication

- Vessel persists cookies and localStorage across sessions
- Log in once, session survives restarts
- Use `save_session` to checkpoint after login

## Privacy & Safety

- All agent actions are visible in the Supervisor sidebar
- Sensitive actions (payments, form submissions) require explicit approval
- User can pause/deny any action
- Sessions are stored locally in `~/.config/@quanta-intellect/vessel-browser/`

## Best Practices

- Use `wait` after navigation, don't assume instant load
- Prefer `extract` over `screenshot` for text data (lower token cost)
- Use `screenshot` when visual layout matters
- Save session after login to avoid re-authentication
- Close unused tabs to conserve memory
- Use `evaluate` for complex DOM queries, not repeated extract calls
