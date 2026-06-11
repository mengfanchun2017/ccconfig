# cli-tool — CLI 工具项目

> 场景:命令行工具(个人/团队/公开发布)
> 复杂度:★★

## 适用

- 个人/团队效率工具
- 代码脚手架工具(如本 skill 的 init.sh)
- 系统管理 / 运维工具
- 一次性数据处理脚本(规模上升后考虑)

## 默认技术栈

| 语言 | 选型 | 理由 |
|------|------|------|
| 首选 | Node.js (TypeScript) | 跨平台(npm/pnpm) + 类型安全 + 异步易写 |
| 备选 | Go | 单二进制 + 性能 + 易分发 |
| 备选 | Rust | 性能 + 零成本抽象 + 跨平台 |
| 备选 | Python | 快速原型(用户已熟悉) |

按发布渠道选:

| 渠道 | 推荐 |
|------|------|
| npm/pnpm | Node.js |
| Homebrew | Go(Formula 易写) |
| cargo | Rust |
| pip/PyPI | Python |

## 脚手架结构(Node.js TypeScript)

```
<代号>/
├── src/
│   ├── index.ts           # 入口
│   ├── cli.ts             # CLI 框架(commander/yargs)
│   └── commands/          # 子命令
├── tests/
├── bin/
│   └── <代号>             # 软链到 src/index.ts
├── package.json
├── tsconfig.json
├── README.md
├── LICENSE
└── .gitignore
```

## 脚手架结构(Go)

```
<代号>/
├── cmd/<代号>/
│   └── main.go
├── internal/
│   └── ...
├── pkg/
├── go.mod
├── README.md
└── LICENSE
```

## 关键决策

- **CLI 框架**:Node 用 `commander` / `yargs` / `citty`;Go 用 `cobra` / `urfave/cli`;Rust 用 `clap`
- **配置加载**:Node `cosmiconfig`;Go `viper`;Rust `config-rs`
- **更新机制**:`self-update` (Node) / `go-update` (Go)
- **跨平台打包**:`pkg` (Node) / `goreleaser` (Go) / `cargo-dist` (Rust)
- **测试**:`vitest` (Node) / `go test` / `cargo test`

## 风险点

1. **跨平台路径/编码差异** — Windows / macOS / Linux 行为不一致。缓解:CI 三平台跑测。
2. **依赖膨胀** — Node 工具易带巨型 node_modules。缓解:用 `bun` / `deno` / Deno compile / Go 单二进制。
3. **向后兼容** — 公开工具改了 CLI 行为会破坏用户脚本。缓解:版本化 + 弃用警告 + `--legacy` flag。
4. **错误信息** — 默认错误栈用户看不懂。缓解:用 `error-cause` (Node) / `errors.Join` (Go 1.20+) 提供友好错误。
5. **首次发布** — npm publish / Homebrew tap / crates.io 流程多。缓解:写发布 checklist + 自动化 GitHub Actions。

## 学习路径(1-2 周)

| 天 | 任务 |
|----|------|
| 1-2 | 选 CLI 框架 + 实现 1 个命令 + 参数解析 |
| 3-4 | 加配置加载 + 日志 + 错误处理 |
| 5-6 | 写测试 + CI(GitHub Actions) |
| 7-8 | 文档(README + examples) + 发布到 npm/Homebrew/cargo |
