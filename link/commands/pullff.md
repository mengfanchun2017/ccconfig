运行 `bash ccconfig/gitforce.sh [repo]` 强制单向同步。

- 默认（`--pull`）：云强制覆盖本地，丢弃本地所有改动
- `--push [repo]`：本地强制覆盖远程（高危）
- `--pull [repo]`：显式指定云 → 本地

已知仓库: ccconfig, projectu

高危操作，执行时需输入仓库名二次确认。同步后自动重建符号链接。
