# static-web-personal — 个人静态 web 项目

> 场景:个人静态 web(礼物 / 纪念 / 展示 / 主页),无后端或极简后端,纯前端静态资源
> 复杂度:★ | 真实案例:[[<project-name>-project]]

## 适用

- 给特定人/小群体的礼物站(密码门 + 个性化内容)
- 个人作品集 / 主页 / 简历
- 纪念页(婚礼 / 生日 / 旅程)
- 知识沉淀 / 文档站(纯静态)
- 内容规模 5-100 项(超过考虑 web-api-backend + CMS)

## 默认技术栈

| 组件 | 选型 | 理由 |
|------|------|------|
| 标记 | HTML5 | 零构建 |
| 样式 | CSS3(原生变量 + Grid) | 无需 Tailwind 之类 |
| 脚本 | JavaScript ES Modules | 无需打包,浏览器原生支持 |
| 密码门 | Web Crypto API(SHA-256) | 纯前端,无后端 |
| 地图 | Leaflet + OpenStreetMap/CartoDB | 轻量,免费瓦片 |
| 图标 | 内联 SVG / Lucide | 零依赖 |
| 字体 | 系统字体栈 / Google Fonts | 中文 Noto Sans CJK SC |
| 国际化 | 简单 JSON 字典 / 无 | UI 翻译,内容保持原语言 |
| 数据 | 单文件 JSON | 5-100 项规模适用 |

## 不适用

- 需要用户登录、评论、动态加载 → 用 web-api-backend
- 内容频繁更新(> 1 次/天)→ 考虑 CMS(Strapi / Sanity)
- 多语言内容管理 → 用 i18n 工具(astro-i18n / next-intl)

## 脚手架结构

```
<代号>/
├── index.html              # 首页
├── pages/                  # 子页面(可选)
│   └── <id>.html
├── assets/
│   ├── css/
│   │   └── main.css
│   ├── js/
│   │   ├── main.js         # 入口
│   │   ├── lock.js         # 密码门
│   │   └── i18n.js         # 国际化
│   ├── img/                # 图片(WebP 优先)
│   └── data/
│       └── <name>.json     # 数据
├── tools/                  # 工具脚本(可选)
│   └── calc-hash.mjs       # 密码 hash 计算
├── tests/                  # 测试(可选)
│   └── smoke.test.mjs
├── CLAUDE.md
├── README.md
├── DEPLOY.md               # 部署指南
├── LICENSE
├── .gitignore
└── .editorconfig
```

## OKR 模板(O = 一句话目标,KR = 关键结果)

```yaml
O: 个人静态 web 站发布并稳定可访问
KR1: 内容数据完整(主条目 + i18n 完成度 100%)
KR2: 部署成功且自定义域名 HTTPS 可达
KR3: 分享给目标用户,获得 1+ 反馈
```

## 风险点(5 项)

1. **零构建选型局限** — 复杂交互需手写 vanilla JS,规模扩大后维护成本上升。缓解:超过 200 行 JS 考虑迁移到 Vite/Astro。
2. **Web Crypto 密码门是单向验证** — 密码泄露无解。缓解:用强随机密码 + 定期换 + 不存明文。
3. **静态部署平台免费层政策** — webify / Netlify / GitHub Pages 免费层可能调整。缓解:在 DEPLOY.md 写多平台备份方案。
4. **图片体积影响加载** — 大量 WebP 占空间,CDN 缓存失效。缓解:用 Squoosh 压缩 + 多分辨率 srcset。
5. **i18n 字典维护** — 新增内容易漏翻译。缓解:加缺失语言降级到英文,UI 加"missing translation"提示。

## 真实案例:[[<project-name>-project]]

- 位置:~/git/<project-name>
- 部署:腾讯云 webify(GitHub push 触发)
- 密码:Web Crypto SHA-256,占位密码 `deepblue2025`
- 地图:Leaflet + CartoDB Dark
- i18n:zh-CN + en
- 数据:`data/samples.json` 5 条占位水样
- 测试:零依赖方案(node:test + schema validator + e2e smoke)

参考其 README/DEPLOY.md 即可复用整套方案。

## 学习路径(2-3 天)

| 天 | 任务 |
|----|------|
| 1 | 静态 HTML/CSS/JS ESM 跑通首页 + 数据 JSON 加载 |
| 2 | Web Crypto 密码门 + i18n 切换 + Leaflet 地图(如需) |
| 3 | 部署 webify + 真实数据替换 + 反馈迭代 |

## 关联资源

- <project-name> 项目:`~/git/<project-name>/`
- <project-name> 测试方案:`~/.claude/projects/.../memory/<project-name>_test_setup.md`
- Leaflet 入门:https://leafletjs.com/examples.html
- Web Crypto MDN:https://developer.mozilla.org/en-US/docs/Web/API/Web_Crypto_API
