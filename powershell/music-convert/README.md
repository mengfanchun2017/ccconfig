# music-convert — 网易云 NCM 音乐格式转换

## 依赖

- Windows + PowerShell 5+
- [ffmpeg](https://ffmpeg.org/download.html) 已安装并加入 PATH
- `ncmdump.exe`（已包含在本目录）

## 使用

```powershell
# 交互菜单模式（默认）
.\convert.ps1

# 参数模式（跳过菜单，适合自动化）
.\convert.ps1 -Mode both          # NCM → FLAC + MP3
.\convert.ps1 -Mode flac          # NCM → FLAC only
.\convert.ps1 -Mode mp3           # NCM → MP3 only
.\convert.ps1 -Mode flac2mp3      # 已有 FLAC → 转 MP3

# 自定义路径
.\convert.ps1 -Mode both -SourceDir D:\Music -FlacDir D:\Out\flac -Mp3Dir D:\Out\mp3
```

## 目录结构

```
C:\CloudMusic\
  convert.ps1        ← 入口脚本
  ncmdump.exe        ← 解密工具
  VipSongsDownload\  ← 放 .ncm 源文件（默认）
  flac\              ← FLAC 输出
  mp3\               ← MP3 输出
```

## 工作流

1. 把 `.ncm` 文件放入 `VipSongsDownload\`
2. 运行 `.\convert.ps1`，选菜单
3. 输出到 `flac\` / `mp3\`

## 旧脚本（已合并）

- `_ncm2flac.ps1` — NCM 解密 → FLAC（已合并入 convert.ps1 选项 1）
- `_flac2mp3.ps1` — FLAC → MP3（已合并入 convert.ps1 选项 4）
