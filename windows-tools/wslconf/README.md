# wslconf — WSL 启动配置（Win + WSL 双侧）

WSL 配置分布在两个文件，**两个文件都在 WSL 启动时被读**：

| 脚本 | 目标文件 | 位置 | 谁读 | 管什么 |
|------|---------|------|------|--------|
| `wslconfig.ps1` | `%USERPROFILE%\.wslconfig` | Win 侧 | WSL 服务 `wslservice.exe` | WSL 实例怎么跑（VM 级：网络模式、内存、CPU、代理） |
| `wslconf.ps1` | `/etc/wsl.conf` | WSL 内 | WSL init 进程 | WSL 内部 init 怎么起（init 级：systemd、Win PATH 注入、默认用户） |

**为什么两个文件**：.wslconfig 必须在 WSL VM 启动**之前**就存在（Win 端守护进程读），wsl.conf 必须等 VM 起来后写到 Linux 文件系统里。两者生命周期不重叠，WSL 设计上就是 split。

## 使用

```bash
# WSL 端调 Win 端 ps1 的标准模式
powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w ccconfig/windows-tools/wslconf/wslconfig.ps1)"
wsl.exe --shutdown   # 必须！改 .wslconfig 不热更新

powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w ccconfig/windows-tools/wslconf/wslconf.ps1)"
wsl.exe --shutdown   # 必须！改 wsl.conf 不热更新
```

跑完关掉所有 WSL 终端再开新的，配置生效。

## `.wslconfig` 配置

```ini
[wsl2]
networkingMode=mirrored   # 网络镜像模式（推荐）
dnsTunneling=true         # DNS 隧道
autoProxy=true            # Win 切代理时自动注入 WSL env
firewall=true             # 防火墙集成
```

mirrored 模式下 WSL 和 Windows 共享 localhost，远程连接不再需要端口转发。`autoProxy=true` 把 Win 端代理 IP 注入 WSL 进程 env，让 WSL 端 git/curl 能直接用 Win 端 clash。

## `/etc/wsl.conf` 配置

```ini
[boot]
systemd=true

[interop]
appendWindowsPath=false   # 关键：关掉 Win PATH 注入，避免 WSL 误调 Windows 程序

[user]
default=<当前 WSL 用户>
```

`appendWindowsPath=false` 让 Claude Code / Bun 在 WSL 中不再尝试执行 Windows 程序。

## 验证同步状态

```bash
bash ccconfig/status.sh   # 看 [13] .wslconfig 同步 是否绿勾
```

status.sh 从 wslconfig.ps1 提取 here-string 期望内容，和 `%USERPROFILE%\.wslconfig` 实际内容 diff。无输出 = 同步，有 `<`/`>` 行 = 需要重跑 ps1 + `wsl --shutdown`。

## 编码注意

PowerShell 5.x 的 `Set-Content -Encoding UTF8` 会写 BOM，破坏 status.sh 字节比对。脚本用 `UTF8Encoding($false)` 写无 BOM。详见 [[wslconfig-powershell5-bom]]。
