# lark-cli 速查

> 完整命令参考 + 踩坑记录 → f-feishu skill `references/lark-cli-cheatsheet.md`

## 运行前缀
```bash
export LARKSUITE_CLI_CONFIG_DIR="${LARKSUITE_CLI_CONFIG_DIR:-$HOME/.lark-cli}" && export PATH="$HOME/.local/bin:$PATH"
```

## auth 预检（写操作前必做）
```bash
lark-cli drive +search --query test --page-size 1 --as user 2>&1 | sed '/^\[lark-cli\]/d'
```
若 `token_missing` → token 过期。完整授权流程见 [feishu.md](feishu.md) § auth 预检。

## 命令速查

命令表 + 关键约束 + JSON 格式 → f-feishu skill `references/lark-cli-cheatsheet.md`（调用 f-feishu 时自动加载）。
