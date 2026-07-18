# OfficeCLI — AI-native Office 工具

> 可选组件，默认不在 `init-base.sh all` 中安装

## 是什么

OfficeCLI（⭐5k）是首个专为 AI Agent 设计的 Office 命令行工具。单二进制零依赖，支持创建/编辑/读取 .pptx .docx .xlsx。JSON 输出，批量模式，MCP 协议。

- 仓库: [iOfficeAI/OfficeCLI](https://github.com/iOfficeAI/OfficeCLI)
- 平台: Linux x64 / macOS / Windows
- 许可: Apache 2.0
- 最新: v1.0.96 (2026-05-21)

## 快速开始

```bash
# 一键安装
bash ccconfig/option-officecli/init.sh

# 或分步
bash ccconfig/option-officecli/init.sh --install   # 安装
bash ccconfig/option-officecli/init.sh --status    # 状态检查
```

## 核心能力

- `.pptx` `.docx` `.xlsx` 全格式支持
- JSON 输出（`--json`）— AI Agent 友好
- 批量模式：一个 JSON 数组创建整个文档
- 模板合并：`{{key}}` 占位符替换
- 实时预览：`officecli watch file.pptx` + 浏览器热重载
- MCP 集成：`officecli mcp claude` 注册为 Claude Code MCP server

## 配合使用

- `unified-ppt` skill：双引擎之一，用于自定义设计/精确布局
- `officecli-pptx` skill：OfficeCLI 自带的设计规范 skill（可选安装）

## 新终端初始化

```bash
bash ccconfig/option-officecli/init.sh --install
```
