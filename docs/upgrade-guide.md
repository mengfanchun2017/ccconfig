# ccconfig 升级指南

> 面向已安装用户。如何跟上 ccconfig 上游更新，保持终端最佳状态。

## 发布通道

| 分支 | 用户 | 更新频率 | 稳定性 |
|------|------|---------|--------|
| `release` | 普通用户 | 大版本发布时 merge | 稳定，推荐 |
| `main` | 开发者 | 每天 push | 最新，可能有未完成功能 |

**推荐**：clone 时用 `--branch release`，拿稳定版本。想尝鲜用 `main`。

```bash
# 查看当前分支
git -C ~/git/ccconfig branch --show-current
```

## 日常：自动同步

`monitor.sh` 自动 commit + push 你的本地改动到 GitHub。不自动 pull——需要手动拉取上游更新。

```bash
# 查看同步状态
bash ~/git/ccconfig/monitor.sh status

# 没在跑？启动
bash ~/git/ccconfig/init-autostart.sh
```

## 月度：组件升级

```bash
bash ~/git/ccconfig/update.sh all
```

这一步会自动：
1. **git pull ccconfig** — 拉最新脚本
2. **Node.js** — 升级到 conf/versions.json 锁定的版本
3. **lark-cli** — npm 全局升级
4. **Python pip 包** — 升级到 conf/python-requirements.txt 最新
5. **GitHub CLI** — 升级到最新 release
6. **Claude Code** — `claude install --force` 升级
7. **uv** — 升级（30 天内已检查则跳过）
8. **MCP 缓存** — 刷新（24h 内已刷新则跳过）

升级前自动创建版本快照（`.snapshots/`），保留 90 天。升级后显示版本对比表。

```bash
# 只看不升（兼容性预检查）
bash ~/git/ccconfig/update.sh  # 菜单模式，选 0 退出

# 单项升级
bash ~/git/ccconfig/update.sh node     # Node.js
bash ~/git/ccconfig/update.sh claude   # Claude Code
bash ~/git/ccconfig/update.sh python   # Python pip 包
bash ~/git/ccconfig/update.sh skills   # Skills 同步
```

## Skills 更新

```bash
# 更新自建 skill + 第三方 skill + ccprivate 配置覆盖
bash ~/git/ccconfig/init-skill.sh sync

# 查看 skill 状态
bash ~/git/ccconfig/init-skill.sh status

# 更新第三方 skill（npx skills）
bash ~/git/ccconfig/scripts/update-third-party-skills.sh
```

skill 同步流程（3 阶段）：
1. symlink 自建 f-* skill（claude-skills/plugins → ~/.claude/skills/）
2. ccprivate 配置覆盖（config/*.yaml → ~/.claude/skills/<skill>/config.yaml）
3. npx skills 装第三方 skill（conf/third-party-skills.txt）

## claude-skills 更新

```bash
cd ~/git/claude-skills && git pull
bash ~/git/ccconfig/init-skill.sh sync
```

独立用户（不用 ccconfig）：

```
/plugin marketplace update <your-username>-skills
```

## ccconfig 自身更新

```bash
# 拉取最新 ccconfig + 重建 symlink
cd ~/git/ccconfig && git pull
bash ~/git/ccprivate/setup.sh
```

`update.sh all` 开头自动 `git pull` ccconfig，通常不需要手动拉。如果本地有未提交改动，`update.sh` 会显示冲突处理菜单。

## 大版本升级

当 ccconfig 发布新 MAJOR.MINOR 版本时：

1. 看 [CHANGELOG.md](../CHANGELOG.md) 了解破坏性变更
2. 看 [RELEASING.md](../RELEASING.md) 了解发布内容

```bash
# release 分支用户：直接 git pull
cd ~/git/ccconfig && git pull origin release

# main 分支用户：可能有冲突
cd ~/git/ccconfig && git pull origin main
```

大版本升级后建议：

```bash
# 重建所有 symlink
bash ~/git/ccprivate/setup.sh

# 重新初始化（幂等，只装缺失的）
bash ~/git/ccconfig/init.sh all

# 验证
bash ~/git/ccconfig/status.sh
```

## 升级前检查清单

- [ ] 没有正在运行的 Claude Code session（`claude --version` 可以跑，但升级后需新开会话）
- [ ] monitor 在跑（`monitor.sh status`），本地改动已 push
- [ ] 网络正常（`update.sh` 需要下载 Node.js / GitHub Release 等）
- [ ] `conf/versions.json node.pin` 如果没有特殊需求保持默认（latest LTS）

## 升级后验证

```bash
# 完整状态检查
bash ~/git/ccconfig/status.sh

# 确认 skill 正常
bash ~/git/ccconfig/init-skill.sh status

# 确认 symlink 无断链
find ~/.claude -type l ! -exec test -e {} \; -print
# （应无输出）

# Claude Code 版本
claude --version
```

## 回滚

### ccconfig 回滚到指定 tag

```bash
cd ~/git/ccconfig
git checkout v1.0.1  # 或其他 tag
bash ~/git/ccprivate/setup.sh
```

### Node.js 版本锁定

编辑 `conf/versions.json`，设置 `node.pin`：

```json
{
  "components": {
    "node": {
      "pin": "22",
      "version": "22.11.0"
    }
  }
}
```

`pin: "22"` = 锁定在 v22.x 最新 LTS。`pin: ""` = 跟随最新 LTS。`pin: "latest"` = 跟随最新版本（含非 LTS）。

### 快照恢复

`update.sh` 每次升级前创建版本快照（`.snapshots/versions.json.pre.*`），记录升级前各组件版本。手动恢复到快照中的版本：

```bash
# 查看快照
ls ~/git/ccconfig/.snapshots/

# 读快照内容
python3 -c "import json; print(json.load(open('~/git/ccconfig/.snapshots/versions.json.pre.20260705-143022')))"
```

## 多机同步

```
机器 A（台式机）
  ├── 改代码 → monitor 自动 push 到 GitHub
  └── 跑 update.sh all（月度）

机器 B（笔记本）
  ├── 开机 → git pull ccconfig + ccprivate + claude-skills
  ├── bash ~/git/ccprivate/setup.sh  # 重建 symlink
  └── bash ~/git/cconfig/init-skill.sh sync
```

ccprivate 的 conf/*.json 通过 setup.sh symlink 到 ccconfig/conf/，改 ccprivate 后 push → 另一台机器 pull ccprivate + 重跑 setup.sh 即可同步。

## 常见问题

| 问题 | 原因 | 解决 |
|------|------|------|
| `update.sh` 卡在 git pull | 本地有未提交改动 | 选 a) 远程覆盖 或 c) 手动处理 |
| `/skills` 看不到新 skill | Claude Code 缓存 skill 列表 | 新开一个 session |
| `init-skill.sh sync` 跳过已有 skill | `~/.claude/skills/<name>` 是真目录不是 symlink | `rm -rf ~/.claude/skills/<name>` 再跑 sync |
| LLM 切了但 Claude 还是用旧的 | settings.json 没更新 | `bash init-llm.sh <backend>` 重写配置 |
| Node 升级后 lark-cli 失效 | symlink 指向旧 Node 路径 | `bash update.sh npm` 重建 symlink |
