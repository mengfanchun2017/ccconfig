# mobile-app — 移动 App 项目

> 场景:移动应用(iOS / Android / 跨平台)
> 复杂度:★★★★

## 适用

- 消费类 App(社交 / 工具 / 内容)
- 企业内部 App
- 跨平台需求(iOS + Android 一套代码)
- 简单游戏(参考 game 类型)

## 默认技术栈

| 框架 | 选型 | 理由 |
|------|------|------|
| 首选 | React Native + Expo | JS/TS 复用 + Expo 工具链完善 |
| 备选 | Flutter (Dart) | 性能好 + 跨平台一致 |
| 备选 | Kotlin Multiplatform | 原生体验 + 跨平台逻辑 |
| 不推荐 | 纯原生(iOS Swift / Android Kotlin) | 双倍开发成本,除非深度平台特性 |

## 关键决策

| 决策 | 选项 |
|------|------|
| 状态管理 | Zustand / Redux / Riverpod (Flutter) |
| 导航 | React Navigation / Expo Router |
| 网络 | TanStack Query / SWR |
| 本地存储 | MMKV / SQLite / AsyncStorage |
| 推送 | Expo Push / FCM / APNs |
| 认证 | Expo AuthSession / Clerk / Supabase Auth |
| 支付 | RevenueCat (跨平台) |

## 脚手架结构(React Native + Expo)

```
<代号>/
├── app/                   # Expo Router 路由
│   ├── (tabs)/
│   ├── _layout.tsx
│   └── index.tsx
├── src/
│   ├── components/
│   ├── hooks/
│   ├── lib/
│   └── types/
├── assets/                # 图标/启动屏
├── app.json               # Expo 配置
├── eas.json               # EAS Build 配置
├── package.json
├── tsconfig.json
├── CLAUDE.md
├── README.md
├── LICENSE
└── .gitignore
```

## 风险点

1. **App Store 审核被拒** — 政策合规、内购、隐私。缓解:首次提交前研究 App Store Guidelines;用 EAS Submit 自动构建。
2. **原生模块兼容性** — RN/Flutter 桥接原生库可能版本不兼容。缓解:锁版本 + 测试覆盖 + 备选方案。
3. **包大小膨胀** — 资源/字体未优化。缓解:expo-image + 字体子集化 + 按需加载。
4. **离线策略** — 网络不稳定地区体验差。缓解:TanStack Query 持久化 + 乐观更新 + 冲突合并。
5. **推送通知到达率** — 厂商(Firebase/APNs)过滤。缓解:多通道(Push + SMS / 邮件 fallback)+ 退订机制。

## 学习路径(4-8 周)

| 周 | 任务 |
|----|------|
| 1 | Expo 项目初始化 + 路由 + 基础 UI |
| 2 | 状态管理(Zustand)+ 网络(TanStack Query) |
| 3 | 列表 / 详情 / 表单 完整 CRUD |
| 4 | 认证 + 路由保护 + 持久登录 |
| 5 | 推送通知 + 深链 + 分享 |
| 6 | 离线策略 + 数据同步 + 冲突处理 |
| 7 | EAS Build + TestFlight / Internal Testing |
| 8 | App Store / Play Store 提交 + 审核响应 |

## 关联资源

- Expo 文档:https://docs.expo.dev/
- React Navigation:https://reactnavigation.org/
- EAS Build:https://docs.expo.dev/build/introduction/
- App Store Guidelines:https://developer.apple.com/app-store/review/guidelines/
