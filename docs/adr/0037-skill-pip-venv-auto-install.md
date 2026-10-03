# 0037. Skill pip 依赖经自建 venv 自动安装

> **Status**: ✅ Accepted
> **日期**: 2026-10-03
> **关联**: `lib/init-skill.sh`（pip 分支）、`skill/plugins/fmashwork/scripts/setup.sh`、`skill/plugins/fmashwork/deps.txt`
> **模板**: MADR 4.0 极简版
> **取代**: 旧行为「pip 依赖 → 未知管理器 → 跳过」

## Context and Problem Statement

`deps.txt` 声明 pip 依赖（如 fmashwork 的 trimesh/pymeshfix/numpy/pyyaml）时，旧 `init-skill.sh` 不认识 `pip:` 管理器，输出 `⚠ trimesh: 未知管理器 pip — 跳过`，依赖只在 skill 启动时靠自身脚本补装。用户期望安装时序统一：**skill 安装/同步时依赖就绪**，别终端拉到即可直接调用，无需手动逐包装。

但 pip 包不能直接系统级装：新版 Ubuntu/Debian 的 Python 被 apt 管理，`pip install` 系统级与 `--user` 都被 PEP-668（externally-managed-environment）拦截。

## Decision Drivers

- **D1 单命令安装**：别终端 `maintain.sh self all` / `sync` 后一次性就绪
- **D2 不污染系统 Python**：venv 隔离，卸载即删目录，系统包互不干扰
- **D3 幂等**：重复运行只补装缺失，不重复下载/重建
- **D4 后台可跑通**：agent 无法输 sudo 密码，流程内不能依赖交互式提权

## Considered Options

1. **系统级 `pip install`（+ `--user`）** — pros: 最直觉、全系统复用；cons: **PEP-668 硬拦截**，需 `--break-system-packages` 或用户级 venv，前者破坏性，后者已违背初衷
2. **skill 自建隔离 venv（采纳）** — pros: 隔离、权限零依赖（用户路径可写）、ensurepip 缺失是唯一人工边界且有明确提示；cons: 多 skill 同包各自建 venv 重复占盘（受 `required_by` 聚合约束，首个声明者负责）
3. **不归 init 管，全部启动时自装** — pros: init 零改动；cons: 首次调用才有依赖，用户感知为"没装好"，且启动路径复杂（需要 execv 重入）

## Decision

pip 依赖不由 init-skill.sh 直接装，改由**首个声明该包的 skill** 的 `scripts/setup.sh` 建隔离 venv 后安装。`init-skill.sh` 的 `pip)` 分支：

- 取 `required_by` 首个 skill，定位其 `setup.sh`（`$CLAUDE_SKILLS_DIR` / `$SKILLS_SRC` / `$LOCAL_SKILLS_SRC` 三源按序）
- 幂等探测 = **venv 可执行文件存在**（`~/.${first_skill}-venv/bin/python`），而非 import 测试——pip 包名 ≠ import 模块名（如 `pyyaml` 包 import 为 `yaml`），import 测试会误判
- venv 不存在 → `bash setup.sh`（建 venv + 循环逐装缺失包）
- setup.sh 自含 ensurepip 检查：缺时打印唯一一条 sudo 命令并退出，agent 转人工

## Consequences

- ✅ 安装时序统一：skill 同步/安装时依赖就绪，启动时不再承担首次安装职责
- ✅ 别终端 `maintain.sh self all` 拉到即可直接调用，`pip)` 输出从「未知管理器 — 跳过」变「venv 安装中…→ ✓」
- ✅ venv 不污染系统 Python，PEP-668 天然绕过，无 `--break-system-packages`
- ✅ 幂等：venv 在即视为已装，不重复下载
- ❌ 每个 pip 依赖的 skill 必须自带 `scripts/setup.sh`，缺该脚本的声明会被跳过（有 warn）
- ⚠️ 多 skill 同包时首个声明者负责建 venv，后续 skill 复用同一 venv（`required_by` 聚合）
- ⚠️ 全新系统唯一手动边界：`sudo apt-get install python3.<minor>-venv`（ensurepip 缺失），一次即永久
- ⚠️ 运行时 skill（`fmashwork.py`）用 `sys.prefix != sys.base_prefix` 判是否已在 venv，顶部 `execv` 切入——venv 的 bin/python 是系统 python 的 symlink，`realpath` 比较恒真判不出，不能用

## Implementation

- `lib/init-skill.sh` `pip)` 分支（line ~239）
- `skill/plugins/fmashwork/scripts/setup.sh` — venv 建立 + 逐装 trimesh/pymeshfix/numpy/pyyaml
- `skill/plugins/fmashwork/deps.txt` — `pip:latest fmashwork` × 4

## Related Decisions

- `ADR-0032`（配置分层）— skill 安装时序的既有机制
- `skill-public-private-cleanup` — skill 维护 / marketplace 要点

## Notes

本 ADR 的 venv 判断只用**文件存在**，不看 import——`fmashwork.py` 侧的 check-env 才做 import 真校验，两者分工明确，避免误判漏装。