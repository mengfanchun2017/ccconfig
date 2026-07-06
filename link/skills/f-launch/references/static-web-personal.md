# static-web-personal — 个人静态 web 项目

> 场景:个人静态 web（礼物 / 纪念 / 展示 / 主页），可选轻量后端（Supabase）
> 复杂度:★（纯静态）/ ★★（加 Supabase + R2） | 真实案例:[[project-name]]

## 适用

- 给特定人/小群体的礼物站（URL 直达 + 个性化内容）
- 个人作品集 / 主页 / 简历
- 纪念页（婚礼 / 生日 / 旅程）
- 知识沉淀 / 文档站（纯静态）
- 内容规模 5-100 项（超过考虑 web-api-backend + CMS）

## 默认技术栈

| 组件 | 选型 | 理由 |
|------|------|------|
| 标记 | HTML5 | 零构建 |
| 样式 | CSS3（原生变量 + Grid） | 无需 Tailwind 之类 |
| 脚本 | JavaScript ES Modules | 无需打包，浏览器原生支持 |
| 认证 | URL 即凭据（默认）/ Supabase Auth（可选） | 无密码门；管理功能需登录 |
| 地图 | Leaflet + OpenStreetMap/CartoDB | 轻量，免费瓦片 |
| 图标 | 内联 SVG / Lucide | 零依赖 |
| 字体 | 系统字体栈 / Google Fonts | 中文 Noto Sans CJK SC |
| 国际化 | 简单 JSON 字典 | UI 翻译，内容保持原语言 |
| 数据 | JSON 文件 / Supabase REST API | 5-100 项纯 JSON；需协作/动态写用 Supabase |
| 存储 | Cloudflare R2（可选） | 照片/文件上传，CF Functions 代理 |
| 后端 | Supabase PostgreSQL + Auth（可选） | 管理后台/录入向导需后端时启用 |
| 部署 | Cloudflare Pages | 零成本，全球 CDN，原生 Functions + R2 |
| 测试 | node:test（零依赖） | unit + data schema + e2e smoke 三层 |

## 不适用

- 需要用户登录、评论、动态加载 → 用 web-api-backend
- 内容频繁更新（> 1 次/天）→ 考虑 CMS（Strapi / Sanity）
- 多语言内容管理 → 用 i18n 工具（astro-i18n / next-intl）

## 脚手架结构

### 极简模式（纯静态 JSON）

```
<代号>/
├── index.html              # 入口（?id=xxx 路由）
├── 404.html                # 独立 404 页
├── assets/
│   ├── css/                # reset / theme / components / pages
│   ├── js/                 # ESM 模块（main / data / i18n / map / detail）
│   └── img/                # SVG 装饰 / WebP 图片
├── data/
│   └── samples.json        # 静态数据
├── tests/
│   ├── unit/               # 单元测试
│   ├── data/               # schema 校验
│   └── e2e/                # smoke 测试
├── docs/
│   ├── architecture.md
│   ├── data-model.md
│   └── adr/                # 架构决策记录
├── CLAUDE.md
├── ROADMAP.md
├── README.md
└── .gitignore
```

### 完整模式（+ Supabase + R2 + 管理 SPA）

```
<代号>/
├── ...（同上）...
├── tools/
│   ├── admin/              # 后台管理 SPA（Supabase Auth + CRUD + 照片上传）
│   └── contribute/         # 录入向导 SPA（Supabase Auth + 表单 + 直接入库）
├── functions/              # CF Pages Functions
│   ├── api/upload.js       # POST multipart → R2（Bearer token 认证）
│   └── r2/[key].js         # GET 公开读取（Cache-Control 一年）
└── ...
```

## OKR 模板（O = 一句话目标，KR = 关键结果）

```yaml
O: 个人静态 web 站发布并稳定可访问
KR1: 内容数据完整（主条目 + i18n 完成度 100%）
KR2: 部署成功且自定义域名 HTTPS 可达
KR3: 分享给目标用户，获得 1+ 反馈
```

## 风险点

1. **零构建选型局限** — 复杂交互需手写 vanilla JS，规模扩大后维护成本上升。缓解:超过 200 行 JS 考虑迁移到 Vite/Astro。
2. **URL 即凭据安全模型** — 数据 JSON 公开可遍历，恶意爬取无法阻止。缓解:内容规模小（5-100 项）时风险可接受；物理媒介（水样瓶）等同访问令牌。
3. **静态部署平台免费层政策** — CF Pages / Netlify / GitHub Pages 免费层可能调整。缓解:多平台备份方案写进 DEPLOY.md。
4. **图片体积影响加载** — 大量图片占空间，CDN 缓存失效。缓解:Squoosh 压缩 + 多分辨率 srcset + R2 缓存一年。
5. **i18n 字典维护** — 新增内容易漏翻译。缓解:缺失语言降级到英文，UI 加"missing translation"提示。

### Supabase 模式额外风险

6. **Supabase 免费层限制** — 500MB 数据库，50K 月活用户。缓解:监控用量，超标前升级。
7. **双数据源同步** — Supabase + 本地 JSON（测试 fallback）需保持 schema 一致。缓解:`mapRow()` / `toDbRow()` 映射函数统一维护。

## 测试方案

零依赖 `node:test` 三层:

```bash
npm test                       # 全量
npm run test:unit              # JS 模块逻辑
npm run test:data              # JSON schema 校验
npm run test:e2e               # HTTP smoke
```

- `tests/unit/` — 数据校验函数、ID 格式、映射函数
- `tests/data/` — JSON schema 结构完整性
- `tests/e2e/` — 页面端点 200 响应

## 真实案例:[[project-name]]

- 位置:~/git/<project-name>
- 版本:v0.3.0-alpha
- 部署:Cloudflare Pages（GitHub push 自动部署 + Functions + R2）
- 认证:URL 即凭据（无密码门，ADR 0008）+ Supabase Auth（admin/contribute 登录门）
- 数据:Supabase PostgreSQL（公开读走 REST API），本地 `data/samples.json` 为测试 fallback
- 存储:Cloudflare R2（照片上传，CF Functions 代理，Bearer token 认证）
- 地图:Leaflet + CartoDB Dark
- i18n:zh-CN + en
- 管理:SPA `/tools/admin/`（Supabase Auth + CRUD + 照片上传）
- 录入:SPA `/tools/contribute/`（Supabase Auth + 单页表单 + 直接入库）
- 测试:node:test 零依赖三层（unit/data/e2e），每个 PR 前全量跑
- 文档:13 ADR + ROADMAP + CHANGELOG + 完整 docs/

参考其架构/测试/ADR 即可复用整套方案。

## 学习路径（3-4 天）

| 天 | 任务 |
|----|------|
| 1 | 静态 HTML/CSS/JS ESM 跑通首页 + 数据 JSON 加载 + URL 路由 |
| 2 | i18n 切换 + Leaflet 地图（如需）+ 详情页渲染 |
| 3 | 部署 CF Pages + 真实数据替换 + 反馈迭代 |
| 4 | （可选）Supabase Auth + admin SPA + R2 上传 + CF Functions |

## 关联资源

- 参考项目:`~/git/<project-name>/`
- Leaflet 入门:https://leafletjs.com/examples.html
- Cloudflare Pages:https://pages.cloudflare.com/
- Supabase JS SDK:https://supabase.com/docs/reference/javascript
