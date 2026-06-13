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

## 防卡死规则（硬约束 — 最高优先级）

Vessel 的 40+ 工具平铺注册 + 截图驱动容易导致 agent 陷入死循环。以下规则不可违反：

### 截图限制
- 同一页面截图不超过 **3 次**
- 第 4 次截图前 → 必须改用 `extract_content` mode="text_only" 或 `read_page` mode="text_only"
- 违反此规则 = 陷入截图循环，必须立即停止

### 点击重试限制
- 同一目标元素点击失败不超过 **2 次**
- 第 2 次失败后 → 换 CSS selector（不用 index），或用 `vessel_devtools_query_dom` 重新获取元素
- 还是失败 → 报告失败，停止重试

### 超时熔断
- 单次 `wait_for` 不超过 **10 秒**
- `wait_for_navigation` 不超过 **15 秒**
- 超时后不重试，报告页面不可达
- 单次 Vessel 会话不超过 **15 个工具调用**，超过说明陷入循环

### 提取优先级链
```
1st: extract_content mode="text_only" （≤800 tokens）
2nd: read_page mode="text_only"
3rd: extract_content mode="visible_only"
last: screenshot （5000-10000+ tokens，仅视觉验证时用）
```

### 卡住自检（每 5 个 Vessel 调用后必执行）
- 我在重复同样的操作吗？→ 停止，换方法
- 我截图超过 3 次了吗？→ 停止，用 text 提取
- 目标能用更简单的工具替代吗？→ 停止，切工具
- index-based click 连续失败了吗？→ 停止，换 CSS selector

### 恢复流程（检测到卡住时）
1. 立即停止当前 Vessel 操作
2. 用 `extract_content` mode="text_only" 获取页面状态
3. 根据页面状态决定：继续（换方法）还是放弃（报告失败）
4. 不要重试同样的操作期望不同结果

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
- **Prefer `extract_content` mode="text_only" over `screenshot`** — 10x token savings
- Screenshot only for visual layout verification, max 3 per page
- Save session after login to avoid re-authentication
- Close unused tabs to conserve memory
- Use `vessel_devtools_execute_js` for complex DOM queries, not repeated extract calls
- **If stuck (same action repeated, index clicks failing) → stop, switch to text extraction, report status**
- Keep Vessel sessions short: under 15 tool calls total
