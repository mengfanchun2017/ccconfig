# option-skill — Claude Code Skills 可选组件

> 可选组件，默认不在 `init-base.sh all` 中安装。Skills 是"内容"而非"基础设施"——ccconfig 核心功能不依赖 skills。

## 安装

```bash
bash ccconfig/option-skill/init.sh --install
```

或通过交互菜单：`bash init-option.sh` → 选择 "option-skill"。

## 命令

```bash
bash ccconfig/option-skill/init.sh --install   # 首次安装（clone 仓库 + symlink + 配置覆盖）
bash ccconfig/option-skill/init.sh --update    # 更新（git pull + CLI deps 更新）
bash ccconfig/option-skill/init.sh --status    # 状态检查
bash ccconfig/option-skill/init.sh             # 交互式菜单
```

## 架构

Skills 由三层仓库组成：

| 仓库 | 角色 | 路径 |
|------|------|------|
| `skill`（公开） | 18 个自建 f-* skill 实体（SKILL.md） | `~/git/skill/plugins/` |
| `ccconfig`（公开） | 安装/同步脚本（`lib/init-skill.sh`） | `~/git/ccconfig/lib/init-skill.sh` |
| `ccprivate`（私有） | API key/token 配置覆盖（YAML） | `~/git/ccprivate/skill-config/` |

安装后，`~/.claude/skills/` 下每个目录是一个 symlink 指向 `~/git/skill/plugins/<name>/`，私有 YAML 配置以 `config.yaml` symlink 叠加。

## 升级

```bash
bash maintain.sh self skill              # git pull + relink（推荐）
bash option-skill/init.sh --update       # git pull + CLI deps 更新
```

## 与 init-base.sh 的关系

`init-base.sh all` 不再自动安装 skills。新机器初始化后，按需运行：
```bash
bash init-base.sh all        # 基础环境（Ubuntu + LLM + MCP + 收尾）
bash init-option.sh          # 可选组件 → 选 option-skill
```

也可以通过维护命令单独更新：`bash maintain.sh self skill`。
