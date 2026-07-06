# ccconfig 架构评估报告（ATAM）

> 版本: v1.0 | 日期: 2026-07-07
> 评估方法: SEI ATAM (Architecture Tradeoff Analysis Method)
> 对应软考考点: 系统架构设计师 — 软件架构评估（ATAM/SAAM）

## 1. 评估概述

### 1.1 评估目标
对 ccconfig 三仓库架构进行系统化的质量属性评估，识别架构风险、敏感点和权衡点，为后续架构演进提供决策依据。

### 1.2 评估范围
- ccconfig: init/update/status/monitor/sync 脚本体系 + 配置模板 + symlink 管理
- claude-skills: marketplace + 12 个 skill 插件 + config overlay
- ccprivate: 私有配置层 + symlink 穿透机制
- 三仓库间的接口和交互

### 1.3 质量属性优先级
经涉众分析，质量属性优先级排序为：
1. **可修改性（Modifiability）** — 用户需频繁跟随上游更新
2. **可用性（Usability）** — 新用户 10 分钟内完成初始化
3. **安全性（Security）** — API key 零泄露
4. **可移植性（Portability）** — WSL2 / Ubuntu / Debian / macOS
5. **可靠性（Reliability）** — monitor 自动同步不丢数据

## 2. 架构方法描述

### 2.1 核心架构决策

| ID | 决策 | 理由 |
|----|------|------|
| AD-1 | 三仓库公私分离 | 公开部分可 fork/审查，私有部分用户自控 |
| AD-2 | symlink 穿透而非配置文件复制 | 单源管理，修改 ccprivate 所有消费方自动生效 |
| AD-3 | init-skill.sh 3 阶段 pipeline | 自建/覆盖/第三方解耦，每阶段独立可重试 |
| AD-4 | monitor.sh inotify + 60s debounce | 平衡实时性与 push 频率 |
| AD-5 | update.sh 中国镜像优先 + 回退 | 解决国内网络问题，不牺牲通用性 |
| AD-6 | Skill YAML 覆盖优于 conf JSON | 面向人可读（注释），skill 内相对路径读取 |

### 2.2 架构视图

**部署视图**:
```
WSL2 Ubuntu 24.04
├── ~/git/ccconfig/        ← git clone（公开）
├── ~/git/claude-skills/   ← git clone（公开）
├── ~/git/ccprivate/       ← git clone（私有）
├── ~/.claude/
│   ├── skills/            ← symlink → claude-skills/plugins/
│   ├── rules/             ← symlink → ccconfig/link/rules/
│   ├── agents/            ← symlink → ccconfig/link/agents/
│   ├── settings.json      ← symlink → ccprivate/link/settings.json
│   └── .config.json       ← symlink → ccprivate/link/.config.json
└── systemd user services
    ├── ccconfig-monitor.service  ← monitor.sh daemon
    └── cc-connect.service        ← option-bridge
```

## 3. 质量属性场景

### 3.1 可修改性场景

| ID | 场景 | 刺激 | 响应 |
|----|------|------|------|
| M-1 | 上游发布新版本 | 用户运行 `update.sh all` | 5 分钟内所有组件升级完成 |
| M-2 | 添加新 skill | 在 claude-skills 创建 SKILL.md → `init-skill.sh sync` | 新 skill 在 `/skills` 可见 |
| M-3 | 修改配置 | 编辑 ccprivate/conf/llm.json | 立即生效（symlink），无需重跑脚本 |
| M-4 | 添加新 option 组件 | 创建 option-*/init.sh | status.sh 自动发现 |

### 3.2 可用性场景

| ID | 场景 | 刺激 | 响应 |
|----|------|------|------|
| U-1 | 新机器首次安装 | 按 BOOTSTRAP 7 阶段执行 | 10 分钟内 status.sh 全绿 |
| U-2 | 恢复已有环境 | `ccprivate/setup.sh` + `init-skill.sh sync` | 3 分钟内恢复 |
| U-3 | 诊断问题 | 运行 `status.sh` | 11 项检查结果，失败项给出修复命令 |

### 3.3 安全性场景

| ID | 场景 | 刺激 | 响应 |
|----|------|------|------|
| S-1 | 误提交私密文件 | `git commit` 包含 `conf/*.json` | pre-commit hook 拦截 |
| S-2 | API key 泄漏 | push 到公开仓库 | 已通过 filter-repo 清理历史 |
| S-3 | 新用户 clone | clone ccconfig 公开仓库 | 零密钥残留 |

### 3.4 可靠性场景

| ID | 场景 | 刺激 | 响应 |
|----|------|------|------|
| R-1 | monitor 进程崩溃 | systemd 检测到进程退出 | 自动重启 |
| R-2 | push 网络失败 | GitHub 不可达 | 3 次重试，间隔 10s |
| R-3 | init 脚本中断 | 子步骤失败 | 容错继续，打印错误 |

## 4. 敏感点与权衡点分析

### 4.1 敏感点（Sensitivity Points）

| ID | 敏感点 | 影响的质量属性 | 说明 |
|----|--------|--------------|------|
| SP-1 | symlink 路径硬编码 | 可移植性 | `~/git/ccconfig` 假设可通过环境变量覆盖，但多层脚本间传递可能断裂 |
| SP-2 | init-skill.sh debounce 时间 | 可用性 vs 可靠性 | 60s 太短 → 频繁 push；太长 → 数据丢失窗口大 |
| SP-3 | conf/ 中 JSON vs config/ 中 YAML 并存 | 可修改性 | 两种格式、两种消费路径，增加理解成本 |
| SP-4 | Python 脚本依赖 pip 包 | 可移植性 | 新机器必须先 `pip3 install` 才能跑 Python 脚本 |
| SP-5 | lark-cli npm 全局安装 | 可靠性 | Node 升级后 symlink 可能指向旧版本，需重建 |

### 4.2 权衡点（Tradeoff Points）

| ID | 权衡点 | 方案 A | 方案 B | 当前选择 |
|----|--------|--------|--------|---------|
| TP-1 | 配置格式 | JSON（机器友好，无注释） | YAML（人类友好，有注释） | 系统配置 JSON + Skill 配置 YAML（混合） |
| TP-2 | Skill 安装方式 | symlink（实时更新，本地开发方便） | marketplace install（标准方式，版本锁定） | symlink（ccconfig 用户） + marketplace（独立用户）双模式 |
| TP-3 | 自动同步策略 | push 全量仓库（简单可靠） | 仅 push 改动仓库（节省时间） | 仅 push 改动仓库（60s debounce） |
| TP-4 | 升级保守度 | 全自动升级到最新（省心） | 版本锁定手动升级（稳定） | update.sh 自动 + versions.json pin 可选（兼顾） |
| TP-5 | 私有数据隔离 | 独立仓库 ccprivate（复杂度高） | .gitignore + .env（简单） | 独立仓库（安全性优先） |

## 5. 风险识别

### 5.1 架构风险

| ID | 风险 | 严重度 | 影响 |
|----|------|--------|------|
| AR-1 | symlink 链路过长 | 中 | `ccprivate/conf/llm.json → ccconfig/conf/llm.json → 脚本读取`，任何一环断裂用户难以排查 |
| AR-2 | JSON/YAML 双轨并存 | 中 | 新贡献者困惑：什么时候用 JSON 什么时候用 YAML？ |
| AR-3 | init-skill.sh 对 network 的隐式依赖 | 中 | 阶段 2 marketplace 检 + 阶段 3 npx skills 安装依赖网络，离线环境失败 |
| AR-4 | monitor.sh inotify 在 WSL2 上的限制 | 低 | WSL2 跨文件系统 inotify 不支持（Windows 侧 `/mnt/c/` 文件变化不触发） |

### 5.2 非风险

| ID | 非风险 | 说明 |
|----|--------|------|
| NR-1 | 三仓库模型复杂度 | 通过 init-ccprivate.sh 向导 + BOOTSTRAP 7 阶段降级，用户无需理解全部 |
| NR-2 | bash 脚本可维护性 | 每个脚本职责单一（init/update/status/monitor），长度可控（100-700 行） |
| NR-3 | 12 个 skill 的管理成本 | SKILL.md 平均 200 行，config 化后私有部分隔离，维护负担低 |

## 6. 改进建议

| ID | 建议 | 优先级 | 预期收益 |
|----|------|--------|---------|
| IMP-1 | 统一配置格式为 YAML | P2 | 消除 JSON/YAML 双轨困惑，减少解析代码路径 |
| IMP-2 | 增加 `init-skill.sh --offline` 模式 | P2 | 离线环境可跳过网络依赖阶段 |
| IMP-3 | 增加 `ccconfig doctor` 命令 | P2 | 诊断 symlink 链路完整性，给出修复建议 |
| IMP-4 | monitor.sh 增加文件系统检测 | P3 | 检测 `/mnt/c/` 路径并警告 inotify 限制 |
| IMP-5 | 增加 smoke test 套件 | P2 | 每个 init 脚本至少一个幂等测试 |

## 7. 评估结论

ccconfig 三仓库架构在**安全性**和**可修改性**上表现优秀：公私分离彻底（filter-repo + pre-commit + .gitignore 三重防御），symlink 机制使配置修改即时生效。

主要改进方向在**可移植性**（WSL2 inotify 限制、macOS 部分支持）和**一致性**（JSON/YAML 双轨）。当前架构对目标用户群体（Claude Code 重度用户，WSL2/Ubuntu）满足度良好。

## 8. 与软考系统架构设计师考点的映射

| ATAM 章节 | 对应考试知识点 | 大纲章节 |
|----------|-------------|---------|
| 1. 评估概述 | 软件架构评估方法 | 系统架构设计基本技术 |
| 2. 架构方法描述 | 软件架构文档化 | 系统设计文档编写 |
| 3. 质量属性场景 | 质量属性（性能/安全/可用性/可修改性/可测试性） | ISO/IEC 25010 |
| 4. 敏感点/权衡点 | 架构评估核心概念 | ATAM 方法 |
| 5. 风险识别 | 风险管理 | 架构风险/非风险 |
| 6. 改进建议 | 架构演进 | 架构重构 |
