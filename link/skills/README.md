# skills/

运行时 skill 安装目录。**不直接编辑**。

Skill 来源（由 `init-skill.sh sync` 管理）：
- 自建 f-* → symlink 自 `claude-skills/plugins/`
- 第三方 → `npx skills add` 自动 symlink
- 私有配置覆盖 → `ccprivate/skill-config/*.yaml` → `config.yaml`

添加新 skill → `claude-skills/plugins/<name>/`，然后 `bash ccconfig/init-skill.sh sync`。
