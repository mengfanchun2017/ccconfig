# desktop-app — 桌面 App 项目

> 场景:桌面应用(macOS / Windows / Linux)
> 复杂度:★★★★

## 适用

- 内部工具 / 团队工具
- 跨平台 GUI
- 离线优先应用
- IDE / 编辑器类工具

## 默认技术栈

| 框架 | 选型 | 理由 |
|------|------|------|
| 首选 | Tauri (Rust + WebView) | 体积小(< 10MB)+ 性能好 + 现代 |
| 备选 | Electron (Node + Chromium) | 生态最厚 + 调试容易 |
| 备选 | Flutter Desktop | UI 一致 + 性能好 |
| 备选 | .NET MAUI | 微软生态集成 |
| 备选 | SwiftUI / WinUI 3 | 纯原生(单平台) |

## Tauri vs Electron 决策

| 维度 | Tauri | Electron |
|------|-------|----------|
| 包大小 | ~5-10 MB | ~100-200 MB |
| 内存占用 | 低 | 高 |
| 性能 | 接近原生 | 接近 Chromium |
| 前端栈 | 任意 Web | 任意 Web |
| 后端 | Rust | Node.js |
| 移动端扩展 | 是 | 否 |
| 学习曲线 | 陡(Rust) | 缓(JS) |
| 生态 | 较新 | 成熟 |

## 脚手架结构(Tauri + React + TypeScript)

```
<代号>/
├── src/                   # 前端
│   ├── App.tsx
│   ├── main.tsx
│   └── components/
├── src-tauri/             # Rust 后端
│   ├── src/
│   │   ├── main.rs
│   │   └── lib.rs
│   ├── Cargo.toml
│   ├── tauri.conf.json
│   └── icons/
├── package.json
├── tsconfig.json
├── vite.config.ts
├── CLAUDE.md
├── README.md
├── LICENSE
└── .gitignore
```

## 关键决策

- **自动更新**:Tauri Updater / Squirrel / Sparkle
- **打包格式**:macOS DMG / Windows MSI+NSIS / Linux AppImage+deb+rpm
- **签名**:macOS Developer ID / Windows Authenticode / Linux GPG
- **数据存储**:SQLite (Turso / libsql) / sled / JSON
- **系统集成**:系统托盘 / 全局快捷键 / 文件关联 / 通知

## 风险点

1. **跨平台差异** — macOS / Windows / Linux 行为不一致(文件路径、权限、UI 规范)。缓解:Cargo features 隔离 + 三平台 CI 测试。
2. **代码签名** — 未签名应用会被 OS 警告。缓解:购买签名证书(Apple Developer $99/年 / Windows Authenticode ~$200/年)。
3. **WebView 版本差异** — Tauri 依赖系统 WebView(Safari / Edge WebView2 / WebKitGTK)。缓解:测试覆盖三平台最低版本。
4. **更新机制复杂** — 用户可能关闭自动更新。缓解:手动检查 + UI 提示 + 强制更新选项。
5. **首次安装体验** — 安全警告 / 防火墙弹窗 / SmartScreen 拦截。缓解:文档说明 + 域前置(企业内分发)。

## 学习路径(3-5 周)

| 周 | 任务 |
|----|------|
| 1 | Tauri 初始化 + 前端栈选型 + 简单窗口 |
| 2 | Rust ↔ TS 桥接(commands / events)+ 文件系统访问 |
| 3 | 状态管理 + 本地存储(SQLite) |
| 4 | 系统集成(托盘 / 快捷键 / 通知)+ 打包(tauri build) |
| 5 | 自动更新 + 代码签名 + 分发(网站 / Mac App Store / Microsoft Store) |

## 关联资源

- Tauri 文档:https://tauri.app/
- Tauri 模板:https://github.com/tauri-apps/awesome-tauri
- Electron 文档(备选):https://www.electronjs.org/
