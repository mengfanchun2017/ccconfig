# 2026-03-28 会话变更总结

## 睡前后续工作完成

### 1. MiniMax-MCP 多模态接入 ✅

**两个 MiniMax MCP 的区别**：

| MCP | 包名 | 功能 |
|-----|------|------|
| minimax | minimax-coding-plan-mcp | 网络搜索、图片理解（M2.7 编程模型工具） |
| minimax-mcp | minimax-mcp | 语音生成、视频生成、图像生成、音乐生成 |

**Token Plan 支持**：
- Hailuo 2.3 (视频)
- Speech 2.8 (语音)
- Music 1.5/2.5 (音乐)
- Image-01 (图像)

---

### 2. auto-sync.sh 自动同步脚本 ✅

**功能**：监控仓库文件变化，自动提交并推送到 GitHub

**特性**：
- 使用 `inotifywait` 监控所有文件变化
- 3秒防抖（避免频繁提交）
- 后台运行 (PID: 20108)
- 用法：`bash scripts/bash/auto-sync.sh start|stop|status`

**集成到 start.sh**：
- `start.sh` 现在在初始化最后自动启动 auto-sync
- 用户无需手动调用 start/end，变化会自动同步

---

### 3. MiniMax M2.7 思考级别问题 ✅

**结论**：MiniMax M2.7 **没有** thinking level 配置参数

- M2.7 使用 Interleaved Thinking（内置能力）
- 模型在任意位置进行思考，不像 Gemini 那样有 LOW/MEDIUM/HARD 三档
- **Gemini** 才有思考级别配置

---

### 4. init03env.sh 更新 ✅

新增 inotify-tools 安装：
```bash
# 已在 init03env.sh 中添加 install_inotify() 函数
# 在 install_playwright_deps 之后调用
```

---

### 5. 白名单更新 ✅

已添加到 `config/CLAUDE.md`：
- `inotifywait` - 文件变化监控（auto-sync 依赖）

---

## Git 提交记录

```
532e485 feat: add auto-sync support to start.sh and init03env.sh
```

---

## 当前运行状态

| 服务 | 状态 | PID |
|------|------|-----|
| auto-sync | 运行中 | 20108 |

---

## start/end 脚本还需要吗？

**答案**：有了 auto-sync 后：
- ✅ start.sh 仍需要（拉取远程更新、同步符号链接、启动 auto-sync）
- ✅ end.sh 仍需要（手动同步时、停止 auto-sync）
- ✅ auto-sync 处理日常的文件变化自动推送
- ✅ start/end 提供显式的拉取/推送控制

**工作流保持不变**：
1. `gitinit` 或 `bash claude-config/scripts/bash/start.sh` 开始工作
2. 正常工作，auto-sync 自动推送变化
3. `gitarc` 或 `bash claude-config/scripts/bash/end.sh` 结束工作

---

## 待测试功能

- [ ] MiniMax 多模态 MCP 测试（语音/视频/图像/音乐生成）
  - 需要配置 `MINIMAX_API_KEY` 和 `MINIMAX_API_HOST` 在 `config/mcpidentity.json`

---

## 文件变更清单

| 文件 | 变更 |
|------|------|
| scripts/bash/auto-sync.sh | 新增 |
| scripts/bash/start.sh | 修改 - 末尾添加 auto-sync 启动 |
| scripts/bash/init03env.sh | 修改 - 添加 inotify-tools 安装 |
| config/mcplist.json | 修改 - 更新 minimax 描述，添加 minimax-mcp |
| config/CLAUDE.md | 修改 - 添加 inotifywait 到白名单 |
| memory/-home-francis-git/MEMORY.md | 修改 - 添加会话记录 |
| .gitignore | 修改 - 添加 .auto-sync.log, .auto-sync.pid |
