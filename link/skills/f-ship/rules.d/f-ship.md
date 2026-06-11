# f-ship 全局约束

> 项目启动 skill 的硬约束。完整规则 → `~/.claude/skills/f-ship/SKILL.md`

## 命名

- 项目代号 = kebab-case(`<project-name>` / `<project-name>` / `my-tool`)
- 不在代号后加 `-v1` `-mvp` 等版本后缀(版本由 git tag 管)
- `~/git/<代号>/` 是唯一允许的父目录(可在 `config.yaml` 改)

## 脚手架强制项

- 必须生成 `CLAUDE.md`(AI 行为指南,不可空)
- 必须生成 `README.md`(人类可读入口)
- 必须生成 `.gitignore`(按类型定制)
- LICENSE 默认 MIT(可在 config.yaml 改)
- 不生成 .env.example(项目专属,启动后按需加)

## 禁止

- 禁止 `rm -rf` 删除任何已存在的项目目录(脚手架只在空目录生成)
- 禁止覆盖已有 CLAUDE.md(用户有内容则保留)
- 禁止在 `~/git/<代号>/` 嵌套其他 git 项目(用 submodule)

## 触发条件(自然语言)

- "新项目" / "建项目" / "scaffold" / "项目启动" / "项目立项"
- "我想做一个 X" / "帮我起一个 X 项目"
- "init project" / "create project"

## 与其他 skill 协作

- 大型项目(complexity ≥ 3)→ 委派 `f-research-domain` 做技术选型
- 调 `f-doc` 生成飞书 wiki 报告(可选,按 config.yaml)
- 调 `f-logme` 写 OKR(可选,按 config.yaml)
- 完成后必写 memory 到 `~/.claude/projects/.../memory/project_<代号>.md`

## 文档规范

- 飞书 doc 走 f-doc 工作流 0(创建新文档)
- 含嵌入资源(白板/图片)文档禁止 overwrite
- 表格用 lark-table XML,colgroup 列宽之和 = 822
- 标题不加手动编号
