# Releasing ccconfig

> 发布流程。ccconfig 双仓库（公开 + 私有），发布仅涉及公开部分。

## 版本策略

语义版本 `MAJOR.MINOR.PATCH`：

| 变更 | 版本 | 例子 |
|------|------|------|
| 破坏性变更（不兼容旧配置） | MAJOR | 2.0→3.0 |
| 新功能/新 option/新 script | MINOR | 2.0→2.1 |
| Bug fix / 文档 / CI | PATCH | 2.0→2.0.1 |

`conf/versions.json` 是外部组件版本源，**与 ccconfig 自身版本无关**。

## 发布检查清单

每次发布前跑：

```bash
# 1. 语法
find . -name "*.sh" -not -path "./.git/*" -print0 | xargs -0 -I{} bash -n {} 2>&1 | grep -v "\.py" || echo "OK"

# 2. 依赖
bash deps-check.sh

# 3. 敏感信息
grep -rn "sk-\|app_secret\|ANTHROPIC_AUTH_TOKEN" --include="*.json" --include="*.sh" --include="*.yaml" . 2>/dev/null | grep -v ".example" | grep -v ".git/" || echo "OK"

# 4. 私密文件未入 git
git ls-files conf/ | grep -v ".example" | grep -v "versions.json" | grep -v "python-requirements.txt" | grep -v "README.md" | grep -v "third-party-skills.txt" && echo "❌ 私密文件在跟踪中" || echo "OK"

# 5. broken symlink
find . -type l ! -path "./.git/*" -exec sh -c 'test ! -e "{}" && echo "BROKEN: {}"' \; | grep BROKEN && echo "❌ 有断链" || echo "OK"
```

## 发布步骤

### 1. 更新 CHANGELOG

`[Unreleased]` → `[X.Y.Z] — YYYY-MM-DD`

### 2. 更新 ROADMAP

标记当前 Phase 状态、更新日期。

### 3. 提交

```bash
git add -A
git commit -m "release: vX.Y.Z

<一句话总结本次发布>

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### 4. 打 tag

```bash
git tag -a vX.Y.Z -m "vX.Y.Z: <一句话总结>"
```

tag 必须 annotated（`-a`），含描述。

### 5. 推送 tag

```bash
git push origin main
git push origin vX.Y.Z
```

### 6. 创建 GitHub Release

在 GitHub Releases 页面从 tag 创建：
- Title: `vX.Y.Z`
- Description: 贴 CHANGELOG 对应段落
- 不附加二进制资产

## 版本编号来源

`ROADMAP.md` 定 MAJOR.MINOR 目标，CHANGELOG 记录实际内容。当前：

| 版本 | 目标 | 状态 |
|------|------|------|
| v1.0 | 初始版本 | ✅ 2026-05-21 |
| v2.0.0 | 公私分离 + 安全加固 + 公开化 | 🚧 即将发布 |

## 发布后

1. [ ] 验证 `git checkout vX.Y.Z` 后 `bash -n *.sh` 全通过
2. [ ] 验证 `git clone` 干净 clone 后 `README.md` 步骤可走通
3. [ ] 更新 `docs/progress.md` 状态变迁日志
