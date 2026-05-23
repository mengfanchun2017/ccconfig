# Vessel — AI Agent 浏览器

> 可选组件，默认不在 `init.sh all` 中安装

## 是什么

Vessel 是开源 AI Agent 浏览器（Linux）。Claude Code 通过 MCP 协议操控它：打开网页、点击按钮、填写表单、提取内容、截图。所有操作在 Supervisor 侧边栏实时可见，人类可审批/拒绝。

- 仓库: [unmodeled-tyler/vessel-browser](https://github.com/unmodeled-tyler/vessel-browser)
- 平台: Linux x86_64（WSL2 可用 WSLg 显示）
- 许可: MIT 开源
- MCP 端口: `3100`

## 快速开始

```bash
# 一键安装
bash ccconfig/option-vessel/init.sh

# 或分步
bash ccconfig/option-vessel/init.sh --install   # 安装
bash ccconfig/option-vessel/init.sh --mcp       # 配置 MCP
```

## 架构

```
Claude Code ──MCP──> Vessel (localhost:3100) ──Chromium──> 网页
   ↑                                                      ↑
   │ 我操作                                                 │ WSLg 渲染到 Windows
   │                                                       │
   你 ─────────── Supervisor 侧边栏审批 ──────────────────→
```

## 关键约定

### Claude Code 作为操作者

Claude Code 通过 Vessel MCP 可直接：
- 导航到 URL、前进/后退/刷新
- 点击元素、填写表单、选择下拉
- 提取页面文本/HTML
- 截图（可见区域或全页）
- 管理标签页（新建、切换、关闭）
- 管理书签
- 保存/恢复命名会话（持久化 cookie + localStorage）

### 人类作为监督者

- Supervisor 侧边栏实时显示 AI 操作
- 敏感操作（支付、提交）默认要求确认
- 随时可暂停/拒绝

## 安装内容

- `libnspr4 libnss3 libasound2t64` (系统依赖)
- `~/.local/bin/vessel` (启动脚本)
- `~/.local/lib/vessel/squashfs-root/` (浏览器文件)
- `~/.config/@quanta-intellect/vessel-browser/` (用户数据)

## MCP Token

Vessel 启动后在 Settings (`Ctrl+,`) 中查看 MCP Bearer Token。用以下命令注册：

```bash
bash ccconfig/option-vessel/init.sh --mcp-token <你的token>
```

## 新终端初始化

```bash
bash ccconfig/option-vessel/init.sh --install   # 安装 Vessel
bash ccconfig/option-vessel/init.sh --start     # 启动
# 在 Vessel Settings 中获取 token
bash ccconfig/option-vessel/init.sh --mcp-token <token>  # 注册 MCP
```
