# music-convert — 网易云 NCM 音乐格式转换

## 依赖

- Windows + PowerShell 5+
- [ffmpeg](https://ffmpeg.org/download.html) 已安装并加入 PATH
- `ncmdump.exe`（已包含在本目录）

## 使用

**推荐：双击 / 调 `convert.cmd`**（自动处理 ExecutionPolicy，免去手工配置）

```cmd
REM 交互菜单模式
convert.cmd

REM 参数模式
convert.cmd -Mode both               :: NCM → FLAC + MP3
convert.cmd -Mode flac               :: NCM → FLAC only
convert.cmd -Mode mp3                :: NCM → MP3 only
convert.cmd -Mode flac2mp3           :: 已有 FLAC → MP3

REM 自定义路径
convert.cmd -Mode both -SourceDir D:\Music -FlacDir D:\Out\flac -Mp3Dir D:\Out\mp3
```

**直接调 .ps1**（需 ExecutionPolicy 配置）

```powershell
# 一次性绕过 policy
powershell -NoProfile -ExecutionPolicy Bypass -File .\convert.ps1 -Mode flac

# 或永久配置（推荐当前用户粒度）
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\convert.ps1 -Mode flac
```

## 目录结构

```
music-convert\
  convert.cmd        ← 推荐入口（双击/PATH 友好）
  convert.ps1        ← PowerShell 脚本本体
  ncmdump.exe        ← 解密工具
  VipSongsDownload\  ← 放 .ncm 源文件（默认）
  flac\              ← FLAC 输出
  mp3\               ← MP3 输出
```

## 工作流

1. 把 `.ncm` 文件放入 `VipSongsDownload\`（或 `-SourceDir` 指定目录）
2. 运行 `convert.cmd`，选菜单或加参数
3. 输出到 `flac\` / `mp3\`

## 常见问题

| 错 | 原因 / 修 |
|----|----------|
| `convert.ps1 cannot be loaded because running scripts is disabled` | 默认 ExecutionPolicy=Restricted。改用 `convert.cmd`，或执行 `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| `未检测到 ffmpeg` | ffmpeg 不在 PATH。`winget install Gyan.FFmpeg` 或从 https://ffmpeg.org 下载 |
| `未找到 ncmdump.exe` | 脚本找不到 `ncmdump.exe`。从 ccconfig 同步整个 `music-convert/` 目录（含 ncmdump.exe）|
| `Workflow-NcmToFlac is not recognized` | 用的是参数模式但脚本版本老。git pull 同步最新 convert.ps1 |
| `未找到 NCM 文件` | 默认源是 `.\VipSongsDownload`。把 ncm 放进去或加 `-SourceDir` 参数 |
| `convert.cmd` 双击没反应 / `UNC paths are not supported` | cmd.exe 不支持 `\\wsl$\...` UNC 路径。把整个 `music-convert/` 目录放在真实 Windows 盘（C:\、D:\）上再双击 |

## 旧脚本（已合并）

- `_ncm2flac.ps1` — NCM 解密 → FLAC（已合并入 convert.ps1 选项 1）
- `_flac2mp3.ps1` — FLAC → MP3（已合并入 convert.ps1 选项 4）
