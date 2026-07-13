# ccconfig 产品需求文档（PRD）

> 文档版本: v1.0 | 日期: 2026-07-07 | 作者: mengfanchun2017
> 对应软考考点: 系统分析师 — 需求工程（需求获取→分析→规格说明→验证）

## 1. 产品愿景

**一句话**: ccconfig 让任何开发者在 10 分钟内从零搭建全功能 Claude Code 终端，多设备配置自动同步，持续跟随上游更新。

**要解决的问题**: Claude Code 配置分散在 `~/.claude/`、环境变量、MCP 服务器、skills 等多处。换机器或重装系统后需要数小时重新配置。每次上游更新（新 Claude Code 版本、新 skill、新 MCP 服务器）都需要手动跟进。

**产品定位**: Claude Code 配置管理的"基础设施即代码"（Configuration as Code）——所有配置版本化、脚本化、可复现。

## 2. 用户画像

### 2.1 主要用户: Claude Code 重度用户

| 属性 | 描述 |
|------|------|
| 身份 | 全栈开发者 / 技术 TL / 独立开发者 |
| 使用频率 | 每天 4-8 小时使用 Claude Code |
| 设备 | 台式机（主力）+ 笔记本（移动），WSL2 / Ubuntu |
| 痛点 | 配置分散、换机痛苦、多机不一致、不知道有什么新功能可用 |
| 目标 | 一键拉起、自动同步、安心升级 |
| 技能水平 | 熟练 git / bash / CLI，不惧终端操作 |

### 2.2 次要用户: Claude Code 新手

| 属性 | 描述 |
|------|------|
| 身份 | 刚接触 Claude Code 的开发者 |
| 设备 | 单台机器，WSL2 / Ubuntu / macOS |
| 痛点 | 不知道该怎么配置、不知道有哪些 skill 可用 |
| 目标 | 用最短时间获得最佳配置 |
| 技能水平 | 会用 git clone 和 bash |

### 2.3 扩展用户: 团队 TL

| 属性 | 描述 |
|------|------|
| 身份 | 想统一团队 Claude Code 配置的技术负责人 |
| 设备 | 管理 3-10 人的团队 |
| 痛点 | 团队配置不一致、新人上手慢、无法共享 rules/skills |
| 目标 | fork ccconfig → 定制团队配置 → 团队成员一键安装 |

## 3. 核心场景（Use Cases）

### UC-1: 新机器初始化
```
角色: 开发者
前置: 新装 WSL2 Ubuntu 24.04，无任何开发环境
流程:
  1. 安装 gh CLI → 登录 GitHub
  2. 生成 SSH key → 添加到 GitHub
  3. git clone ccconfig + skill
  4. 运行 init-ccprivate.sh → 填写 GitHub 账号 + API Key
  5. 运行 init.sh all → 自动安装所有依赖
  6. 运行 status.sh → 验证 11 项检查通过
后置: Claude Code 可用，所有 skill 已装，auto-sync 在跑
耗时: ≤10 分钟
```

### UC-2: 月度升级
```
角色: 开发者
前置: ccconfig 已安装，monitor 在跑
流程:
  1. 运行 update.sh all
  2. 自动 git pull ccconfig → Node.js → Claude Code → pip → gh → skills
  3. 查看升级总结（版本对比表）
后置: 所有组件升级到最新，快照已保存
耗时: ≤5 分钟
```

### UC-3: 多机同步
```
角色: 开发者在笔记本上恢复环境
前置: 台式机已配置好 ccconfig，monitor 自动 push 到 GitHub
流程:
  1. git clone ccconfig + ccprivate + skill
  2. 运行 ccprivate/setup.sh → 一键建立所有 symlink
  3. 运行 init-skill.sh sync → 同步 skills
  4. 运行 status.sh → 验证
后置: 笔记本配置与台式机一致
耗时: ≤3 分钟
```

### UC-4: 添加新 Skill
```
角色: 开发者/TL
前置: ccconfig 已安装
流程:
  1. 在 skill/plugins/<name>/ 创建 SKILL.md
  2. 可选: 创建 config.yaml.example
  3. 在 marketplace.json 注册
  4. 运行 init-skill.sh sync
  5. 新开 Claude Code session 验证
后置: 新 skill 在 /skills 菜单可见
```

### UC-5: 定制团队配置
```
角色: TL
前置: fork 了 ccconfig
流程:
  1. 修改 link/rules/ 添加团队编码规范
  2. 修改 link/agents/ 添加团队专用 agent
  3. 修改 conftemp/third-party-skills.txt 添加团队需要的 skill
  4. git push → 团队成员 git pull
后置: 团队成员拿到统一配置
```

## 4. 功能需求

### FR-1: 环境初始化
| ID | 需求 | 优先级 |
|----|------|--------|
| FR-1.1 | 一键安装 Ubuntu/WSL 全环境（git, Node.js, uv, Claude Code, 字体） | P0 |
| FR-1.2 | 交互式创建私有配置仓库（init-ccprivate.sh） | P0 |
| FR-1.3 | LLM 后端切换（DeepSeek / MiniMax / Claude / Gateway） | P0 |
| FR-1.4 | MCP 服务器安装与配置 | P1 |
| FR-1.5 | 符号链接自动建立（私有 + 公开一步到位） | P0 |

### FR-2: Skills 管理
| ID | 需求 | 优先级 |
|----|------|--------|
| FR-2.1 | 自建 skill 从 skill symlink 到 ~/.claude/skills/ | P0 |
| FR-2.2 | 私有配置 YAML 覆盖（ccprivate config → skill config.yaml） | P0 |
| FR-2.3 | 第三方 skill 通过 npx skills 安装（idempotent） | P1 |
| FR-2.4 | marketplace 自动注册 | P1 |

### FR-3: 自动同步
| ID | 需求 | 优先级 |
|----|------|--------|
| FR-3.1 | 监听 ~/git/ 下所有仓库文件变化（inotify） | P0 |
| FR-3.2 | 60s debounce 后自动 git commit + push | P0 |
| FR-3.3 | 仅 push 真正改动的仓库 | P0 |
| FR-3.4 | systemd user service 守护 | P0 |

### FR-4: 组件升级
| ID | 需求 | 优先级 |
|----|------|--------|
| FR-4.1 | Node.js 升级（中国镜像优先，支持版本锁定） | P0 |
| FR-4.2 | Claude Code 升级（CDN + npm 回退） | P0 |
| FR-4.3 | Python pip 包批量升级 | P1 |
| FR-4.4 | gh CLI / uv / lark-cli 升级 | P1 |
| FR-4.5 | 升级前版本快照 | P1 |

### FR-5: 状态检查
| ID | 需求 | 优先级 |
|----|------|--------|
| FR-5.1 | 11 项状态检查（symlink/依赖/sync/推送/记忆/项目/飞书/Playwright/MCP/远程/组件） | P0 |
| FR-5.2 | 破坏的 symlink 自动修复 | P0 |
| FR-5.3 | MCP 服务器并行健康检查（24h 缓存） | P1 |

### FR-6: 远程访问
| ID | 需求 | 优先级 |
|----|------|--------|
| FR-6.1 | SSH + tmux 一键配置 | P2 |
| FR-6.2 | Tailscale 组网支持 | P2 |

### FR-7: 安全
| ID | 需求 | 优先级 |
|----|------|--------|
| FR-7.1 | pre-commit hook 拦截私密文件提交 | P0 |
| FR-7.2 | 公开仓库零密钥残留 | P0 |
| FR-7.3 | .example 模板与真实值分离 | P0 |

## 5. 非功能需求

### NFR-1: 可用性
| ID | 需求 | 指标 |
|----|------|------|
| NFR-1.1 | 新机初始化时间 | ≤10 分钟 |
| NFR-1.2 | 月度升级时间 | ≤5 分钟 |
| NFR-1.3 | 符号链接恢复时间 | ≤30 秒 |
| NFR-1.4 | 新用户理解成本 | BOOTSTRAP 7 阶段自解释 |

### NFR-2: 可靠性
| ID | 需求 | 指标 |
|----|------|------|
| NFR-2.1 | init 脚本幂等 | 重复运行不破坏已有配置 |
| NFR-2.2 | monitor 守护进程存活 | systemd 自动重启 |
| NFR-2.3 | push 网络失败重试 | 3 次，间隔 10s，超时 30s |
| NFR-2.4 | 升级前快照 | 所有组件升级前版本可查 |

### NFR-3: 可移植性
| ID | 需求 | 指标 |
|----|------|------|
| NFR-3.1 | 操作系统 | Ubuntu 24.04+ / Debian 12+（WSL2 全支持） |
| NFR-3.2 | macOS 兼容 | 部分支持（BOOTSTRAP 有备注） |
| NFR-3.3 | 架构 | x86_64, aarch64 |

### NFR-4: 安全性
| ID | 需求 | 指标 |
|----|------|------|
| NFR-4.1 | API key 存放 | 仅私有仓库 ccprivate |
| NFR-4.2 | 历史泄漏 | git filter-repo 已清理 |
| NFR-4.3 | 公开仓库 | 零密钥残留（自动化检查） |

### NFR-5: 可维护性
| ID | 需求 | 指标 |
|----|------|------|
| NFR-5.1 | 脚本语法 | 全部通过 `bash -n` |
| NFR-5.2 | option-* 自动发现 | 无需修改 status.sh |
| NFR-5.3 | 环境变量可配 | CCCONFIG_HOME / CCPRIVATE_HOME / SKILL_SRC |

## 6. 约束与假设

### 6.1 技术约束
- 运行环境: WSL2 Ubuntu 24.04 LTS（主力），Debian 12+（兼容）
- 依赖: git, bash, curl, python3, gh CLI, Node.js
- 需要 GitHub 账号（SSH key 认证）
- 需要至少一个 LLM API Key（DeepSeek / MiniMax / Anthropic）

### 6.2 业务约束
- ccconfig + skill 为 MIT 开源
- ccprivate 为个人私有仓库（每人自建）
- 发布分支: main（开发）/ release（稳定）

### 6.3 假设
- 用户有基本的命令行操作能力
- 用户有 GitHub 账号且会生成 SSH key
- 网络可访问 GitHub（中国用户可能需要代理）
- WSL2 已正确安装（阶段 0 已在 BOOTSTRAP 覆盖）

## 7. 验收标准

### 7.1 新机初始化验收
- [ ] `git clone` 后按 BOOTSTRAP 步骤执行，10 分钟内 `status.sh` 显示全绿
- [ ] `claude` 命令可用，`/skills` 显示 12 个 f-* skill
- [ ] 修改任意文件，60s 内 monitor 自动 commit + push

### 7.2 升级验收
- [ ] `update.sh all` 无报错完成
- [ ] 升级后 `claude --version` 为最新版本
- [ ] 升级后所有 symlink 不中断

### 7.3 安全验收
- [ ] `grep -rn "sk-" conftemp/` 在公开仓库无结果（除 .example）
- [ ] `git ls-files conftemp/` 仅含 .example + versions.json + 公开文件
- [ ] pre-commit hook 拒绝提交私密文件

## 8. 与软考系统分析师考点的映射

| PRD 章节 | 对应考试知识点 | 考试大纲章节 |
|---------|-------------|------------|
| 1. 产品愿景 | 项目提出与选择、问题分析 | 8.2-8.4 |
| 2. 用户画像 | 涉众分析 | 9.1 软件需求工程 |
| 3. 核心场景 | 用例建模、业务流程分析 | 8.5, 9.3 |
| 4. 功能需求 | 功能需求规格说明 | 9.4 |
| 5. 非功能需求 | 质量属性、约束条件 | 9.5 |
| 6. 约束与假设 | 可行性分析 | 8.7 |
| 7. 验收标准 | 需求验证 | 9.8 |
