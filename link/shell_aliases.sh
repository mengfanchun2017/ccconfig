# shell_aliases.sh — 跨终端同步的 shell 别名/函数
# 由 ccconfig/setup-links.sh 链接到 ~/.claude/shell_aliases.sh
# ~/.bashrc 自动 source 此文件

# claude-mini: 切换到 MiniMax LLM 后启动 Claude
claude-mini() {
    bash ~/git/ccconfig/init-llm.sh minimax && claude "$@"
}

# claude-ds: 切换到 DeepSeek LLM 后启动 Claude
claude-ds() {
    bash ~/git/ccconfig/init-llm.sh deepseek && claude "$@"
}
