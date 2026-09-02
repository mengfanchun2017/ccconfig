#!/bin/bash
git add init-bootstrap.sh init-base.sh BOOTSTRAP.md bootstrap-gh-auth.sh init-ccprivate-repo.sh
git commit -m 'init-bootstrap.sh: merge gh auth + ccprivate into one script

init-bootstrap.sh 合并 bootstrap-gh-auth.sh 和 init-ccprivate-repo.sh
的逻辑，PAT 认证一次，ccprivate 操作复用同一认证。
不作为编排器串接，而是真正合并两个脚本的代码。

init-base.sh new 调用 init-bootstrap.sh（gh auth + ccprivate）
成功后自动续跑 init-base.sh all（全量初始化）。

Co-Authored-By: Claude <noreply@anthropic.com>'
rm -f /home/francis/git/ccconfig/.bootstrap-commit.sh