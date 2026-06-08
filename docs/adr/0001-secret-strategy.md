# 0001. 真实配置文件不入 git 仓

> 日期: 2026-06-08
> 状态: ✅ Accepted
> 关联: [Phase 0 安全 + 公开化](../plans/phase-0-security.md)

## 背景

ccconfig 仓库需要公开同步（GitHub 公开 dotfiles 风格），但当前 5 个 JSON conf 文件含真实 API key / token：

| 文件 | 含敏感字段 |
|---|---|
| `conf/llm.json` | MiniMax `sk-cp-...`、DeepSeek `sk-...` |
| `conf/claude.json` | Claude API key（如有） |
| `conf/feishu.json` | 飞书 app_secret / verification token |
| `conf/ubuntu.json` | （通常无） |
| `link/.config.json` | `ANTHROPIC_AUTH_TOKEN`（明文） |

这些 key 在 2026-05-21 仓库初始化时已 commit 到 main，公开后被 GitHub bot 实时爬取的概率 ≈ 100%。

## 决策

1. **`.gitignore` 5 个真实文件**：
   - `conf/llm.json`
   - `conf/claude.json`
   - `conf/feishu.json`
   - `link/.config.json`
   - `conf/ubuntu.json`（防御性，防未来加敏感字段）

2. **公开仓库仅含 `.example` 模板**，结构与真实文件一致，但 key 字段为占位符。

3. **`init.sh` bootstrap 阶段加检测分支**：
   - 检测到真实 conf 缺失 → `cp .example 真实文件` + 提示用户编辑
   - 不在 CI 中报错（CI 跑 `init.sh --check` 时 fallback）
   - 给现有 1 周迁移期：旧机器跑一次 `init.sh` 自动补齐

4. **每台机器一份真实 key**，跨机器不传播（避免「一把 key 走天下」增加泄露面）。

## 替代方案

### ❌ 方案 A：git-crypt / SOPS 加密文件

- **优点**：仓库仍含真实文件，无需 bootstrap 引导
- **缺点**：
  - 单人项目过度工程
  - 私钥分发问题（首次仍要 bootstrap 把私钥传到新机器）
  - 增加了系统层依赖（git-crypt 装包 / SOPS + age / KMS）
  - 加密文件 diff 不可读，code review 困难

### ❌ 方案 B：环境变量 + 运行时注入

- **优点**：完全不写文件，泄露面最小
- **缺点**：
  - Claude Code settings.json / hooks 引用环境变量语法不一致
  - 跨工具（claude / lark-cli / cc-connect）各自管 env，配置碎片化
  - 用户新增 tool 需重新配 env，体验差
  - `init.sh` 检测不到 env 是否已设，错误提示不友好

### ❌ 方案 C：1Password CLI / Keychain 拉取

- **优点**：单点管理，跨机器自动同步
- **缺点**：
  - 强依赖 1Password 账号 / 客户端
  - macOS 专属（Linux 需 pass / bitwarden）→ 跨平台不一致
  - init.sh 调用 `op read` 增加外部依赖
  - 用户未装 1Password 时引导路径复杂
- **未来可考虑**：当个人 tool 增多、key 轮换频繁时升级到此方案

### ✅ 方案 D：`.gitignore` + `.example` + 引导输入（**本决策**）

- **优点**：
  - 简单：标准 Git 工作流，零新依赖
  - 通用：跨平台、跨工具一致
  - 透明：conf 文件 diff 可读，code review 正常
  - 与 f-logme 飞书存储兼容（key 不进 git 也不进飞书）
- **缺点**：
  - 每台新机器首次要手动填 key（5 秒操作）
  - 未来 rotate 流程需手写文档（已写在 CHANGELOG）
  - 没有自动 key 轮换提醒

## 后果

### 正面

- ✅ 仓库完全干净，可公开
- ✅ 配置结构（schema）跨机器同步
- ✅ 真实 key 一台机器一份，独立 revoke
- ✅ 任何 dev 看 `.example` 即可理解配置结构
- ✅ `git diff` 不会泄露任何敏感信息

### 负面

- ❌ 首次新机器需手动填 key（5 秒）
- ❌ 多机器时 key 漂移（每台独立 update，不自动同步）
- ❌ key 轮换靠人记 / CHANGELOG 记录
- ❌ link/.config.json 移走会断一些 hook 引用（需在 Phase 0 任务 #8 验证）

## 缓解

- **R1**（hook 挂）：Phase 0 任务 #8 全量验证
- **R2**（key 漂移）：建立年审机制（每年 12 月提醒 rotate）
- **R3**（轮换遗忘）：f-logme 加「ccconfig 维护」周期性 Reflect 模板

## 实施步骤（详见 Phase 0 计划）

1. 加 `.gitignore`（任务 #1）
2. 改 `init.sh` 加检测（任务 #2）
3. Rotate 3 把 key（任务 #3-5）
4. 建 secret-scan workflow（任务 #6）
5. 改写历史做 defense in depth（任务 #7）
6. 全量验证（任务 #8）
7. CHANGELOG 更新（任务 #9）

## 后续 ADR 候选

未来可能需要写：

- **0002** 脚本组织：根 12 个 .sh 是否拆 `bin/`
- **0003** Skill 3 层架构：自建 / 私有 / 第三方分层
- **0004** LLM 切换：deepseek-v4-pro API 兼容层选择
- **0005** auto-sync：为什么用文件监听不用 systemd timer
