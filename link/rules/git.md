# Git 规范

## 提交
- 不跳过 hooks（--no-verify）
- commit 消息用 heredoc 传递，描述 why 不描述 what
- Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>

## 安全
- push 前确认远程分支
- 不 force push 到 main/master
- 不 amend 已发布的 commit
