运行 `bash ccconfig/sync-pullff.sh [repo]` 强制同步仓库。

- 不传参数 → 同步 ccconfig
- 传 `projectu` → 同步 projectu
- 传其他项目名 → 同步对应仓库

逻辑：fetch → rebase/ff → push，避免多机冲突。同步后自动重建符号链接（rules/commands/projects）。

完成后确认：
1. 输出当前 HEAD commit 摘要
2. 确认工作树干净（git status）