# Contributing to ccconfig

## 项目定位

ccconfig 是 Claude Code 的配置中枢，统一管理配置、脚本、Skills、Agents、Rules。
通过 GitHub 跨设备同步，支持新终端一键恢复。

## 目录约定

```
ccconfig/
├── init*.sh          # 初始化脚本（init-* 前缀）
├── status.sh         # 状态检查
├── monitor.sh        # 文件监控 + 自动同步
├── update.sh         # 月度升级
├── deps-check.sh     # 依赖完整性检查
├── conf/             # 配置文件（含 .example 模板）
├── lib/              # 共享库
├── link/             # → ~/.claude/ 符号链接源
├── option-*/         # 可选组件（option- 前缀）
├── remote/           # 远程连接
├── windows/          # Windows/WSL 互操作
└── cccshare/         # 公开分享版输出（由 pushpub.sh 生成）
```

## 提交规范

- 提交信息用中文描述 WHY
- Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
- 不跳过 hooks，不 force push 到 main

## 脚本规范

- `set -e` 开头
- `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` 获取脚本目录
- 颜色变量统一：`RED/GREEN/YELLOW/CYAN/GRAY/NC`
- 避免 `cd` 导致 cwd 漂移，用 `git -C` 或绝对路径
- 所有脚本通过 `bash -n` 语法检查
- 新脚本添加后可被 `deps-check.sh` 检测到依赖

## 添加可选组件

1. 创建 `option-<name>/` 目录
2. 包含 `init.sh`（入口）和 `README.md`（说明）
3. 在 `deps-check.sh` 的 `OPTIONAL_DEPS` 数组添加依赖检测
4. 在 `status.sh` 添加状态检查
5. 更新 `README.md` 目录结构

## 配置模板

- `conf/*.json` 包含敏感信息，不公开提交
- `conf/*.json.example` 是公开模板
- 新用户首次运行脚本时自动从 `.example` 复制

## Pull Request 流程

1. Fork 仓库
2. 创建 feature 分支
3. 确保 `bash -n` 通过所有 .sh 文件
4. 确保 `deps-check.sh` 通过
5. 提交 PR 并描述变更原因
