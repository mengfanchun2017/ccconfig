# 0051. tailscale accept-routes 让单位内网 LLM 变黑洞（0050 的反向）

> **Status**: ✅ Accepted
> **日期**: 2026-10-16
> **关联**: `lib/tailscale-guard.sh`（新增）、`lib/init-llm.sh`、`maintain.sh`、`lib/status.sh`、`option-remote/init.sh`、ADR [0047](0047-tailscale-subnet-vs-office-intranet.md)
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

2026-10-16，在单位主机 A（WSL/Ubuntu，跑 `officeds41flash` 连单位 LLM 网关）上启动 tailscale 后，Claude 立即报 `API error`；关掉 tailscale 即恢复。现象与 ADR 0047 高度相似，但 0047 的结论（A 自己开了 subnet router）**不成立** —— A 的 `AdvertiseRoutes` 一直是 `null`。

实测证伪 0047 的单因假设，得到新证据链：

| 观测点 | 结果 |
|---|---|
| A 的 `AdvertiseRoutes` | `null`（A 没开 subnet） |
| A 的 **`RouteAll`**（=accept-routes） | **`true`** |
| tailnet 上某节点广告 | `[lU8TI]/<tailnet-node> (<tailnet-node-ip>)` 广告 `<office-subnet>` —— **正是单位网段** |
| tailscaled 日志 | `open-conn-track: timeout opening (TCP <tailnet-node-ip-2> => <internal-llm-ip>:18080) to node [lU8TI]` |
| tailscale 关闭时 | 单位网关 `http=401 connect=0.016s`，路由 `via <internal-ip-5> dev eth1` |

关键点：**黑洞不是"我广告了别人的网段"，而是"我接受了别人的广告、于是去单位网关的流量被拐进隧道"**。0047 只查了 `AdvertiseRoutes`（往外广告），漏了 `RouteAll`（往里接受）—— 同一个黑洞的两个方向。

修复后 tailscale 的 health check 直接印证：
```
- Some peers are advertising routes but --accept-routes is false
```

## Decision Drivers

- **D1 只改自己**：`<tailnet-node>` 的 subnet router 是**另一个场景在用**（有意配置），不能动它
- **D2 症状可自辨**：同类"tailscale 一开就挂"必须能一步定位到本机 accept-routes，不再经历"怀疑 bridge → 怀疑网关 → 怀疑 DNS"的反复考古
- **D3 默认不误伤**：`home*` 系列**本就该走 tailnet**（经跳板 + Host 透传），关 accept-routes 对它无益；公网端点更不相干。防护必须精准命中 `office*` 型
- **D4 用户无感**：修复要随正常流程（切 preset / 一键修复 / 初始化）自动落实，不能要求用户记命令

## Considered Options

1. **要求 `<tailnet-node>` 停掉 subnet 广告** — 治本是断掉广告源，但该机 subnet 是别的用途，动它属于本末倒置；且无法约束他人/他机
2. **A 每次用 office\* 前手动 `tailscale set --accept-routes=false`** — 有效但靠人记，忘一次就复现
3. **A 侧自动防护：按当前 preset 判定，命中"外部私有内网 upstream"就关 accept-routes** — 只改自己、精准命中、可固化进 init/maintain

## Decision

**选方案 3。** 新增 `lib/tailscale-guard.sh`，核心判定：

```
upstream 是私有内网地址（10/8、172.16/12、192.168/16、或解析到这些段的域名）
  且 host_header 为空（host_header 非空 = home* 的 tailnet 跳板透传形态，跳过）
  且 本机 accept-routes = true
→ 自动执行 tailscale set --accept-routes=false
```

接入四处：

| 位置 | 触发时机 | 作用 |
|---|---|---|
| `lib/init-llm.sh` `switch_llm` | 切 preset 时 | 切到 office\* 当场防护 |
| `maintain.sh` `do_setup` 第 7 节 | 一键修复 | 老用户 git pull 后迁移 |
| `lib/status.sh` `_bridge_cold_start` | 每次会话启动 | 只报不修，提示修法 |
| `option-remote/init.sh` `do_server` | 装远程访问时 | 装 tailscale 的场景最容易踩 |

## Consequences

- ✅ **A 侧自足**：不依赖修改 `<tailnet-node>`，他人 subnet 配置变化不影响本机
- ✅ **精准不误伤**：`home*`（tailnet 跳板，host_header 非空）与公网端点自动跳过；判定用例已覆盖
- ✅ **零用户操作**：切 preset / 一键修复 / 初始化任一动作都会自动落实
- ✅ **两条路复用**：`switch_llm`（交互）与 `maintain fix`（批量）调同一个 guard，规则不漂移
- ⚠️ **仅覆盖"本机可改"的部分**：若某台机器**必须**同时（a）走 tailnet 访问 `<tailnet-node>` subnet 后面的资源，（b）直连单位 LLM —— 则 accept-routes 的取舍需要按需在两者间切换，guard 只保证 office\* 场景正确
- ⚠️ **判定依赖 DNS**：域名型 upstream 靠 `getent hosts` 解析落段判定；内网 DNS 不可达时会漏判（此时 tailscale 通常也连不上，影响有限）

## Implementation

### 手动执行

```bash
bash lib/tailscale-guard.sh report    # 看风险状态
bash lib/tailscale-guard.sh fix       # 按当前 preset 按需关闭
```

### 直接命令（Windows PowerShell）

```powershell
& "$env:ProgramFiles\Tailscale\tailscale.exe" set --accept-routes=false
```

### 诊断顺序（下次遇"tailscale 一开 office\* 就挂"）

```powershell
# 两个方向都要查：往外广告 + 往里接受
& "$env:ProgramFiles\Tailscale\tailscale.exe" debug prefs | Select-String 'AdvertiseRoutes|RouteAll'
```

`AdvertiseRoutes` 非 null = 本机在当 subnet router（0047）；
`RouteAll=true` 且 tailnet 有人广告内网段 = 本机在**接受**广告（本文）。
两者都会造成同一个黑洞。