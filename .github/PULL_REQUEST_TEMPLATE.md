Thank you for contributing to ccconfig.

## PR 标题

`<type>(<scope>): <subject>` — 例 `feat(option-skill): add npx update subcommand` / `fix(init-base): handle missing ccprivate gracefully`

## 关联

- Closes #（issue 编号）
- ADR: 在 `docs/adr/` 新增一条决策记录（如有非可逆架构变更）

## 类型

- [ ] Bug fix（非可逆变更少）
- [ ] New feature
- [ ] Refactor / 性能优化
- [ ] Documentation

## 自检清单

- [ ] 跑 `bash -n` 在所有改动的 .sh 文件
- [ ] 跑 `shellcheck -S error` 通过
- [ ] 跑 `bash lib/deps-check.sh --required` 通过
- [ ] 跑 `bash tests/test-init-base.sh --verbose` 通过
- [ ] 不含任何 API key / Token / 个人标识符（`hooks/pre-commit` 会拦截）
- [ ] 涉及公共约定改动时同步更新 [README.md](README.md) 和 [BOOTSTRAP.md](BOOTSTRAP.md)
- [ ] CHANGELOG.md 加一条到 [Unreleased] 段

## 测试说明

复现此 PR 的命令：

```bash
git clone https://github.com/mengfanchun2017/ccconfig.git /tmp/ccconfig-test
cd /tmp/ccconfig-test
git checkout <your-branch>
bash init-base.sh test-mode
```

## 截图 / 日志

（如适用）
