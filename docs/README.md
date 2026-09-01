# docs/ — 设计文档

> ccconfig 架构设计、决策记录、操作指南。**组件专属文档已下放到各自目录**（`option-cloudflare/README.md`、`option-skill/README.md`、`templates/CATALOG.md`），本目录只放跨组件架构/流程类文档。

## 目录

| 文件 | 说明 |
|------|------|
| `architecture.md` | 产品架构设计（三仓库模型、数据流、初始化流程） |
| `SH-MENU-CONVENTIONS.md` | SH 菜单统一规范（渲染格式、颜色变量、data-driven 模式） |
| `upgrade-guide.md` | 升级策略与指南 |
| `ccprivate-guide.md` | ccprivate 私有配置仓库详细指南（ccprivate 仓库阅读） |
| `docs/adr/` | 架构决策记录（MADR 4.0 格式）+ 决策时间线（worklog 提取） |

## 组件专属文档（已下放）

| 主题 | 位置 |
|------|------|
| 规则目录（rules/ 索引） | [`templates/CATALOG.md`](../templates/CATALOG.md) |
| Skill 生命周期 | [`option-skill/README.md`](../option-skill/README.md) |
| Cloudflare 插件参考 | [`option-cloudflare/README.md`](../option-cloudflare/README.md) |
| 远程连接（SSH + Tailscale） | [`option-remote/README.md`](../option-remote/README.md) |
