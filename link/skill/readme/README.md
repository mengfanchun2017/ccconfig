# Skill 产品化决策记录

> **目的**：把 f-* skill 整理后开源到 GitHub + 配套门户网站。本文档记录：审计、调研、决策、计划，便于后续开发追溯。

**最后更新**：2026-06-04（第二轮决策）
**状态**：Phase 0（审计+决策）完成，Phase 1+ 待执行

---

## 1. 背景与目标

- **现况**：ccconfig/link/skills/ 下有 10 个 f-* skill（飞书文档、PDF、PPT、研究、订餐、浏览器、个人管理等）
- **目标**：
  1. 通用 skill 开源到 GitHub，建立 Claude Code skill 集合
  2. 用 `.claude-plugin/marketplace.json` manifest 走官方 `/plugin` 安装机制
  3. 配套静态站做发现入口，国内可快速访问
  4. 长期运营，建立社区

---

## 2. f-* skill 审计（10 → 9）

2026-06-04 已删除 `f-worklog`（已废弃，被 f-logme 替代）。

| skill | 描述 | 隐私/绑定审计 | 适合开源 | 决策 |
|------|------|---------------|----------|------|
| f-doc | 飞书文档统一入口 | 依赖 lark-cli + 飞书账户 | ⚠️ 剥离飞书特定部分 | 候选 |
| f-pdf | PDF 内容提取（PyMuPDF） | 纯工具，无外部依赖 | ✅ | 候选 |
| f-ppt | PPT 生成（双引擎） | 纯工具，可能含模板 | ✅ | 候选 |
| f-research | 快速研究（三源搜索） | 需 Tavily/minimax/websearch key | ✅ | 候选 |
| f-research-deep | 深度研究（批量 JSON） | 同上 | ✅ | 候选 |
| f-research-report | 报告生成（JSON→MD） | 纯本地处理 | ✅ | 候选 |
| f-feedme | 麦当劳订餐 | 绑死 MCD API/账户/收货地址 | ❌ | 内部 |
| f-vessel | AI 浏览器操控 | 涉及账户/cookie/隐私 | ❌ | 内部 |
| f-logme | 个人管理（OKR/Worklog） | 绑死飞书 Base + 用户数据 | ❌ | 内部 |

**结论**：6 个通用 skill 候选开源，3 个留内部。

---

## 3. 调研结论（2026-06-04 深度调研）

### 3.1 Claude Code skill 开放生态

**官方机制**：
- Anthropic 提供 `/plugin marketplace add <url>` + `/plugin install <name>` 安装流程
- 官方仓库要求 `.claude-plugin/plugin.json` manifest 规范
- 官方 marketplace 为 curated（Anthropic 审核收录）

**社区生态**：
- 案例参考（star 数验证模式可行）：
  - [anthropics/skills](https://github.com/anthropics/skills) — 官方模板
  - [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official) — manifest 范式
  - [alirezarezvani/claude-skills](https://github.com/alirezarezvani/claude-skills) — 5200+ stars，单仓库模式
  - [jeffallan/claude-skills](https://github.com/jeffallan/claude-skills) — 8705 stars 集合
  - [ComposioHQ/awesome-claude-skills](https://github.com/ComposioHQ/awesome-claude-skills) — 目录收录入口
  - [secondsky/sap-skills](https://github.com/secondsky/sap-skills) — 垂直领域（GPL-3.0）
  - [agentskills.io](https://agentskills.io/specification) — 跨平台规范

**SKILL.md frontmatter 推荐字段**：
```
name, id, version, description, keywords/tags, author/maintainers,
license, entrypoint/commands, runtime/dependencies, install_url/marketplace_url,
examples, repository, changelog, compatibility, security_contact
```

### 3.2 国内静态站托管对比

| 平台 | 免费额度 | 限制 | 国内访问 | 推荐度 |
|------|---------|------|----------|--------|
| **腾讯云 Webify / CloudBase 静态托管** | 1GB 容量 + 5GB 流量/月（按量计费首个环境）| 小流量够个人站 | ⭐⭐⭐⭐⭐ | ⭐ **首选** |
| **火山引擎 Pages** | 未明确公开免费额度（白名单）| 10 项目/月 100 次部署/zip 50MB | ⭐⭐⭐⭐⭐ | ⭐ 备选（需申请） |
| 阿里云 OSS 静态网站 | 个人 20GB/3 个月 + 5GB/月 | 需配合 CDN，配置复杂 | ⭐⭐⭐⭐⭐ | 备选 |
| 腾讯云 COS 静态网站 | 5GB 存储 + 5GB 流量/月 | 需备案域名 | ⭐⭐⭐⭐⭐ | 备选 |
| 火山引擎 TOS 静态网站 | 10GB 存储 + 2GB 流量（首月/新用户）| 需 CDN 配合 | ⭐⭐⭐⭐⭐ | 复杂场景 |
| Gitee Pages | 免费 | 不支持免费自定义域名（早期政策）| ⭐⭐⭐⭐ | 镜像/兜底 |
| Vercel/Netlify/Cloudflare Pages | 国外 CDN | 访问慢/被墙 | ⭐⭐ | ❌ 国内不用 |
| GitHub Pages | 免费 | 国内访问慢/被墙 | ⭐⭐ | ❌ 国内不用 |

**结论**：
- **首选：腾讯云 Webify** — 免费额度够用，国内 CDN 极快，HTTPS + 自定义域名 + 零配置
- **备选：火山引擎 Pages** — 字节 CDN 同样快，但目前白名单功能（需提交工单）
- **绝不用作主站**：Vercel/Netlify/Cloudflare/GitHub Pages（国内访问问题）
- **域名备案**：若要绑定国内域名仍需 ICP 备案（这是国内合规硬要求）

---

## 4. 用户决策

### 2026-06-04 第一轮

| 决策项 | 决定 | 备注 |
|--------|------|------|
| 删除无用 skill | ✅ 删 f-worklog | 已执行（2026-06-04） |
| 记录过程到 readme | ✅ 本文档 | 持续更新 |
| 开源范围 | ✅ 按建议（6 个通用）| 用户先自行完善 |
| 门户站形态 | ✅ 静态站 | — |
| 托管服务 | 🟡 腾讯云 Webify 首选，火山 Pages 备选 | 待确认 |

### 2026-06-04 第二轮

| 决策项 | 决定 | 备注 |
|--------|------|------|
| 托管服务最终选择 | ✅ **腾讯云 Webify** | 火山 Pages 白名单作备选不申请 |
| 发布模式 | ✅ **单聚合仓库（marketplace）** | 详见 §10 |
| 静态站定位 | ✅ **catalog 入口，不分发代码** | 复制安装命令走 marketplace |
| GitHub 组织 | 🟡 倾向建组织 | 待确认组织名 |
| 域名 | 🟡 MVP 阶段用默认域名 | 备案同步进行 |

**未决项**（待用户后续确认）：
- [ ] GitHub 组织名（个人账号 vs 建组织）
- [ ] 品牌名（ailab / francis / 其他）
- [ ] 域名（境内 vs 境外）
- [ ] i18n 优先级（先英文 / 中英并行 / 先中文）
- [ ] 备案情况（个人 / 企业，影响能否绑国内域名）

---

## 5. 实施计划（6 阶段）

### Phase 0：审计 + 决策（✅ 已完成）
- 逐个 skill 隐私/绑定审计
- LICENSE 选 MIT（最低阻力）
- 删 f-worklog
- 调研 + 决策文档

### Phase 1：skill 标准化（1 周）
- [ ] 统一 SKILL.md frontmatter（name/description/version/license/author/keywords/compatibility）
- [ ] 每个 skill 补：README.md + CHANGELOG.md + examples/ + tests/
- [ ] GitHub Actions CI（lint、frontmatter 校验、测试）
- [ ] 写 manifest：`.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json`

### Phase 2：建 GitHub 仓库（1 周）
- [ ] 建 `<org>/claude-skills` 单仓库起步
- [ ] 每个 skill 一个子目录 + 共享 `.claude-plugin/`
- [ ] 根 README（中英）+ LICENSE + CONTRIBUTING.md + CODE_OF_CONDUCT.md
- [ ] 提交到 awesome-claude-skills 等目录

### Phase 3：发布 marketplace（1 天）
- [ ] 验证 `/plugin marketplace add <url>` 安装流程
- [ ] 写安装教程到 README

### Phase 4：门户网站（2-4 周）
- [ ] 选型：VitePress（轻、快、中文友好，优先）或 Docusaurus
- [ ] 数据源：CI 自动扫 SKILL.md frontmatter → JSON index
- [ ] 功能：分类、搜索、复制安装命令、star 数展示
- [ ] 部署：腾讯云 Webify（首选）/ 火山 Pages（备选）

### Phase 5：CI/CD + 自动化（持续）
- [ ] GitHub Actions：PR 检查 / 文档同步 / 版本发布
- [ ] semantic-release 或 skill-semver 自动版本化
- [ ] GitHub Action 自动 rebuild portal 数据

---

## 6. 托管选型详细说明

### 6.1 腾讯云 Webify（首选）

**优势**：
- 1GB 容量 + 5GB 流量/月 完全免费
- 国内 CDN 极快
- HTTPS 免费
- 支持自定义域名
- GitHub/GitLab 仓库自动部署
- 零配置上手

**开通步骤**：
1. 注册腾讯云账号 + 实名认证
2. 开通 CloudBase 环境（首个环境免 1GB+5GB/月）
3. 控制台 → 静态网站托管 → 上传 / 关联 Git 仓库
4. 绑定自定义域名（CNAME 到 webify 提供的地址）

**风险**：
- 自定义域名需 ICP 备案（国内合规）
- 5GB 流量对个人站够用，超出按量计费

### 6.2 火山引擎 Pages（备选）

**优势**：
- 字节跳动 CDN，国内访问快
- 边缘函数支持，理论上比 Webify 更现代

**限制**：
- **目前是白名单功能**（需提交工单申请）
- 限制：10 项目/月 100 次部署/zip 50MB/单文件 25MB
- 免费额度未公开明确

**适用场景**：
- 申请通过后
- 或作为镜像站

### 6.3 域名与备案

- 境内域名（.cn / .com.cn / 国内服务商注册）：必须 ICP 备案，约 7-20 天
- 境外域名（海外注册商）：用 Cloudflare 中转可绕过备案（但访问可能受跨境网络影响）
- 建议：先用腾讯云 Webify 默认域名上线，备案同步进行

---

## 7. TODO / 后续行动

### 立即可做
- [ ] 用户注册腾讯云账号 + 实名认证
- [ ] 选 GitHub 组织名 + 创建仓库
- [ ] 选品牌名 + Logo
- [ ] 决定备案方式（个人 / 企业）

### 用户自己完善 skill 阶段
- [ ] 给每个 f-* skill 补 README/CHANGELOG/examples
- [ ] 剥离 f-doc 中的飞书特定代码（如有）
- [ ] 加 LICENSE（MIT）
- [ ] 加 GitHub Actions CI

### 上线前
- [ ] manifest 文件编写
- [ ] 安装流程测试
- [ ] awesome-claude-skills 提交收录
- [ ] 1-2 篇发布博文（CSDN/掘金/dev.to）

---

## 8. 参考资料

### 官方/规范
- [Anthropic 插件发现文档](https://code.claude.com/docs/en/discover-plugins)
- [Anthropic 官方 skills 仓库](https://github.com/anthropics/skills)
- [Anthropic 官方 plugins 仓库](https://github.com/anthropics/claude-plugins-official)
- [agentskills.io 规范](https://agentskills.io/specification)

### 社区参考
- [ComposioHQ/awesome-claude-skills](https://github.com/ComposioHQ/awesome-claude-skills)
- [alirezarezvani/claude-skills](https://github.com/alirezarezvani/claude-skills) — 5200+ stars
- [jeffallan/claude-skills](https://github.com/jeffallan/claude-skills) — 8705 stars
- [secondsky/sap-skills](https://github.com/secondsky/sap-skills) — GPL-3.0 垂直案例
- [cathy-kim/skill-semver](https://github.com/cathy-kim/skill-semver) — 自动化版本化

### 国内托管服务
- [腾讯云 Webify / CloudBase 静态托管](https://cloud.tencent.com/product/webify)
- [腾讯云静态网站托管产品页](https://cloud.tencent.com/product/wh)
- [火山引擎 Pages 文档](https://www.volcengine.com/docs/6454/2179040)
- [阿里云 OSS 免费额度](https://www.alibabacloud.com/help/zh/oss/free-quota-for-new-users)

---

## 9. 变更日志

| 日期 | 变更 | 决策人 |
|------|------|--------|
| 2026-06-04 | 创建本文档，初始审计 + 决策 | Claude + 用户 |
| 2026-06-04 | 删 f-worklog（已废弃）| Claude 执行 |
| 2026-06-04 | 调研确定首选腾讯云 Webify | Claude |
| 2026-06-04 | 最终选定 Webify（火山 Pages 备选不申请）| 用户 |
| 2026-06-04 | 决定发布模式：单聚合仓库（marketplace）| 用户 + Claude |
| 2026-06-04 | 静态站定位：catalog 入口（不打包分发）| 用户 + Claude |
| TBD | Phase 1-5 推进 | — |

---

## 10. 发布模式详解

### 10.1 模式选择对比

| 模式 | 仓库结构 | 适用阶段 | 代表案例 |
|------|---------|---------|---------|
| **A. 单聚合仓库** ⭐ 推荐 | 1 个 `<org>/claude-skills` 仓库，根 `.claude-plugin/marketplace.json` 指向各 skill 子目录 | 起步期（< 20 skill）| alirezarezvani/claude-skills（5200+ stars）|
| B. 多仓库 + 元仓库 | 每个 skill 独立 repo + 1 个 meta marketplace | 大量 skill，需独立版本 | jeffallan/claude-skills（8705 stars）|
| ❌ C. 静态站打包分发 | 静态站只做下载入口 | — | 违背官方机制，**不推荐** |

### 10.2 为什么不是"打包放到静态里"

- Claude Code 官方安装机制是 `/plugin marketplace add <repo>` + `/plugin install <name>`
- 走 git 仓库 + manifest 才能版本管理、自动更新、声明依赖
- "下载 zip 解压" 跳过更新检查，违背 skill 生态标准
- 静态站做 catalog（发现入口）即可，分发交给 git

### 10.3 完整目录结构（模式 A）

```
<org>/claude-skills/                        # 单仓库
├── .claude-plugin/
│   ├── marketplace.json                    # 市场清单（用户首安装的入口）
│   └── plugin.json                         # （可选）插件自身元数据
├── plugins/
│   ├── f-pdf/
│   │   ├── .claude-plugin/plugin.json      # 单个 skill 的 manifest
│   │   ├── SKILL.md                        # skill 描述（frontmatter）
│   │   ├── README.md
│   │   ├── CHANGELOG.md
│   │   ├── examples/
│   │   └── tests/
│   ├── f-ppt/
│   ├── f-research/
│   ├── f-research-deep/
│   ├── f-research-report/
│   └── f-doc/                              # （剥离飞书部分后）
├── .github/
│   └── workflows/ci.yml                    # frontmatter 校验 + 测试
├── README.md                               # 仓库主页（中英双语）
├── LICENSE                                 # MIT
├── CONTRIBUTING.md
└── CODE_OF_CONDUCT.md
```

### 10.4 安装命令（官方格式）

```bash
# 1. 添加市场（一行命令，用户在 Claude Code 内执行）
/plugin marketplace add <org>/claude-skills

# 2. 安装具体 skill
/plugin install f-pdf@<org>-claude-skills
/plugin install f-ppt@<org>-claude-skills
# ...

# 3. 后续更新
/plugin marketplace update <org>-claude-skills
```

**用户完整流程**：
1. 访问静态门户站 → 看到想用的 skill
2. 复制 `/plugin marketplace add <org>/claude-skills` 命令
3. 粘贴到 Claude Code → 自动安装
4. 之后用 `/plugin install <name>` 选择性启用

### 10.5 静态站与 git 的关系

| 静态站角色 | 不做的事 |
|-----------|---------|
| ✅ 展示 skill 列表（名称、描述、截图）| ❌ 分发代码 |
| ✅ 一键复制 `/plugin marketplace add` 命令 | ❌ 提供 zip 下载 |
| ✅ 搜索、分类、star 数 | ❌ 替代 GitHub |
| ✅ 引导用户到 GitHub 仓库 | — |

**数据流**：
```
GitHub 仓库 (单仓库) ← 真相源
  ↓ GitHub Action 扫描 SKILL.md frontmatter
  ↓ 生成 skills.json
静态站 (Webify 部署) ← 读取 skills.json 渲染
```

### 10.6 marketplace.json 模板（参考 anthropics/claude-plugins-official）

```json
{
  "name": "ailab-claude-skills",
  "owner": {
    "name": "ailab",
    "email": "your@email.com"
  },
  "plugins": [
    {
      "name": "f-pdf",
      "description": "PDF content extraction (PyMuPDF)",
      "source": "./plugins/f-pdf",
      "version": "0.1.0",
      "keywords": ["pdf", "extraction", "document"]
    },
    {
      "name": "f-ppt",
      "description": "PPT generation (dual engine)",
      "source": "./plugins/f-ppt",
      "version": "0.1.0",
      "keywords": ["ppt", "presentation"]
    }
  ]
}
```

