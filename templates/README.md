# templates/ — .example 模板

> 新用户复制 `.example` 文件到 ccprivate 后自定义。运行时文件在 ccprivate，
> 由 `ccprivate/setup.sh` 管理 symlink。

## 目录

| 路径 | 说明 |
|------|------|
| `rules/*.md.example` | 编码规范模板 → 复制到 ccprivate/rules/ |
| `agents/*.md.example` | Agent 定义模板 → 复制到 ccprivate/agents/ |
| `settings.json.example` | LLM env 模板（`~/.claude/settings.json`，含 API key 占位） |
| `.config.json.example` | 会话配置模板（permissions / hooks / statusLine / mcpServers） |
| `.claudeignore.example` | context 策略模板 |
| `ccprivate-setup.sh` | **setup.sh 唯一真相源**（bootstrap 与 upgrade 都 cp 它） |
| `skills/` | skill 说明占位（skill 开发在独立 skill 仓进行） |

> 规则目录索引（`rules/*.md.example` 每个文件的加载模式、大小、内容）见 [CATALOG.md](CATALOG.md)。

## 运行时部署一览

**共享**（symlink，改一处全机生效）：

```
~/CLAUDE.md              ← ccprivate/link/CLAUDE.md
~/.claude/shell_init.sh  ← ccconfig/lib/shell_init.sh
~/.claude/rules/         ← ccprivate/rules/
~/.claude/agents/        ← ccprivate/agents/
~/.claude/skills/        ← ~/git/skill/plugins/f*（独立仓库）
```

**本机**（首次 cp 一次，之后各机独立，**不跨机同步**）：

```
~/.claude/settings.json  ← 本文件（LLM env，A 机切换不应影响 B 机）
~/.claude/.config.json   ← 本文件（会话配置）
~/.claude/.claudeignore  ← 本文件（context 策略）
```

理由见 [ADR-0032](../docs/adr/0032-config-layering.md)：这三件是每机状态，symlink 到 ccprivate 会随 git push 互相覆盖。

## 新用户初始化

```bash
# 一行命令（clone ccconfig + 生成 ccprivate + 建链接）
curl -fsSL https://raw.githubusercontent.com/mengfanchun2017/ccconfig/main/bootstrap-gh-auth.sh | bash
```

已有 ccprivate 时只需重建链接：

```bash
bash ~/git/ccprivate/setup.sh
```
