# web-api-backend — Web 后端 API 项目

> 场景:Web 后端 CRUD/REST API,业务后端,长期演进
> 复杂度:★★★ | 真实案例:[[project-name]]

## 适用

- CRUD / REST API 服务
- 内部业务后端
- 移动 App / SPA 的 API 层
- BFF(Backend for Frontend)
- 长期演进(> 6 个月)

## 默认技术栈(2026 主流)

| 组件 | 选型 | 理由 |
|------|------|------|
| 运行时 | Node.js 22 LTS | 稳定 + 生态最厚 |
| 语言 | TypeScript (strict) | 类型安全 |
| Web 框架 | Hono | 性能 + 跨 runtime + 现代 DX |
| ORM | Drizzle | 零 codegen + 小 bundle + edge-ready |
| 数据库(开发) | SQLite (WAL) | 零配置 |
| 数据库(生产) | PostgreSQL | 并发写 + 扩展性 |
| 数据验证 | Zod | TS 生态 + Drizzle/Hono 集成 |
| 测试 | Vitest | TS 生态 + watch 极快 |
| 鉴权 | better-auth | TS-first + 2FA/Passkey/Org 插件 |
| 部署(MVP) | Render (free) | 真 free tier |
| 部署(运营) | Railway ($5/mo) | DX 最佳 |

## 备选技术栈(按项目偏好)

| 偏好 | 替换 |
|------|------|
| 偏好 Python/AI | Python + FastAPI + SQLAlchemy + Pydantic + pytest |
| 偏好性能/工程 | Go + Gin/Axum + sqlx + validator + go test |
| 偏好 Java/Kotlin | Java + Spring Boot + JPA + Bean Validation + JUnit |
| 偏好 Rust | Rust + Axum + SQLx + serde + cargo test |

## 脚手架结构

```
<代号>/
├── src/
│   ├── index.ts           # 入口
│   ├── app.ts             # Hono app 配置
│   ├── routes/            # 路由模块
│   │   ├── users.ts
│   │   ├── posts.ts
│   │   └── auth.ts
│   ├── db/                # Drizzle
│   │   ├── schema.ts
│   │   ├── client.ts
│   │   └── migrations/
│   ├── lib/               # 工具
│   │   ├── auth.ts        # better-auth 集成
│   │   ├── validate.ts    # Zod 工具
│   │   └── errors.ts
│   └── types/             # 全局类型
├── tests/                 # Vitest
│   ├── unit/
│   └── integration/
├── docs/
│   ├── plan.md
│   ├── stack.md
│   └── api.md
├── .env.example
├── package.json
├── tsconfig.json
├── drizzle.config.ts
├── vitest.config.ts
├── CLAUDE.md
├── README.md
├── LICENSE
├── .gitignore
└── .editorconfig
```

## OKR 模板

```yaml
O: 完整 CRUD/REST API 上线且稳定运行
KR1: 核心实体(users/posts/tags)CRUD 全部端到端测试通过
KR2: 鉴权流程(email+password + JWT + RBAC)覆盖 90%+ 用例
KR3: 部署到 Render/Railway,持续可访问 + 错误率 < 1%
```

## 风险点(5 项)

1. **Drizzle 生态相对小,长尾插件少** — 复杂查询得自己写 SQL。缓解:SQL 能力是关键门槛;多数 CRUD Drizzle 已覆盖;边缘场景参考 Kysely 切换。
2. **better-auth v1.6 仅发布 1 个月,生产案例少** — 大流量场景稳定性未充分验证 [待确认]。缓解:关注 v1.x changelog,准备 NextAuth v5 迁移方案作为 fallback。
3. **Hono 跨 runtime 优势对 MVP 阶段无感** — Node 单 runtime 性能可能略低于 Fastify [未验证]。缓解:实测压测对比,差距 < 10% 即可接受。
4. **SQLite → PostgreSQL 迁移存在行为差异** — unique、FTS、事务隔离级别可能不同 [数据有限]。缓解:第 6 周专门做迁移 + 集成测试覆盖关键路径。
5. **better-auth + Drizzle 集成文档细节** — 部分边缘场景文档覆盖不足 [未验证]。缓解:第 3 周实测搭建最小 demo,记录踩坑到项目 README。

## 真实案例

- 飞书技术选型报告:[Web 后端 CRUD/REST API 技术栈选型报告](<飞书文档 URL>)
- 平衡组合:Node + Hono + Drizzle + PostgreSQL + Zod + Vitest + better-auth + Render → Railway

## 学习路径(8 周)

| 周 | 任务 |
|----|------|
| 1 | Node 22 + TypeScript strict + Hono hello world + Drizzle + SQLite 本地 |
| 2 | CRUD: users / posts / tags,DTO 用 Zod,迁移用 drizzle-kit |
| 3 | better-auth: email+password + JWT session,加 RBAC 中间件 |
| 4 | 测试: Vitest 单测 + 集成测试(testcontainers 跑 Postgres) |
| 5 | 部署 Render: web service + Postgres + 自动迁移 |
| 6 | 加 Drizzle Postgres 适配器,SQLite 改 Postgres,对比行为差异 |
| 7 | OpenAPI 文档(hono-openapi)+ rate limit + helmet |
| 8 | 复盘:性能压测、监控(Sentry/Pino)、备份、CI |

## 关联资源

- Hono 文档:https://hono.dev/
- Drizzle 文档:https://orm.drizzle.team/
- better-auth 文档:https://www.better-auth.com/
- Vitest 文档:https://vitest.dev/
- f-research-domain 调研:technical 领域
