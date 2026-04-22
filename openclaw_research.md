# OpenClaw × 飞书 × 通义千问接入全面研究

> 调研时间：2026-04-23 | 数据来源：官方文档 + 多方实测

---

## 一、OpenClaw 是什么

**一句话**：开源的本地 AI 代理网关，把各种聊天平台统一接入一个本地控制平面，让大模型能在你电脑上 7×24 小时运行。

### 核心特性
- **本地优先**：数据完全自主可控，不上传云端
- **多平台支持**：飞书、Telegram、Discord、WhatsApp、Slack 等 20+ 渠道
- **Agent 能力**：读写文件、执行 Shell、浏览网页、写代码
- **持久记忆**：SOUL.md、AGENTS.md、MEMORY.md 注入 System Prompt
- **MCP 扩展**：Model Context Protocol 作为"AI 的 USB-C"标准接口

### 版本历史
- Clawdbot → Moltbot → **OpenClaw**（2026年正式更名）
- 飞书官方接入工具：`@larksuite/cli`（lark-cli，2026-03-28 开源）

---

## 二、架构解析

### 2.1 核心组件

| 组件 | 职责 |
|------|------|
| **Gateway** | 通信中枢 + 任务调度，单例守护进程，监听 127.0.0.1:18789 |
| **Agent** | AI 逻辑执行者，独立 Workspace，有 SOUL.md/AGENTS.md/MEMORY.md |
| **Channel** | 聊天平台适配器（飞书/Telegram/WhatsApp 等），标准化消息格式 |
| **Skills/Plugins** | 可复用工具库，通过 MCP 或内置方式注册 |
| **Workspace** | Agent 的工作目录，git 初始化，存放记忆和配置文件 |

### 2.2 Gateway 工作原理

```
任意消息渠道（飞书/Telegram/WhatsApp）
        ↓
   Gateway 验证 + 路由
        ↓
   加载 Workspace（SOUL.md/AGENTS.md/Skills）
        ↓
   语义搜索 MEMORY.md + memory/*.md
        ↓
   模型推理（Qwen/Claude/OpenAI）+ 工具调用
        ↓
   响应写回 memory/ 持久化
        ↓
   路由回原始渠道
```

**启动时的 System Prompt 注入**（8 个文件）：
- AGENTS.md、SOUL.md、USER.md、TOOLS.md
- IDENTITY.md、HEARTBEAT.md、MEMORY.md、BOOTSTRAP.md

### 2.3 消息流转

```
Channel 接收消息 → Gateway 验证 JSON Schema
→ 路由到对应 Agent → 加载 Workspace 文件
→ 组装模型请求上下文（系统提示 + 历史 + 工具结果）
→ 调用模型或 MCP 工具
→ 结果写回 session JSONL
→ 通过 Channel 返回用户
```

---

## 三、飞书接入详解

### 3.1 飞书接入的两种方式

| 方式 | 说明 | 适用场景 |
|------|------|----------|
| **OpenClaw 内置飞书 Channel** | 通过飞书开放平台创建机器人，配置 WebSocket 长连接 | 需要 Agent 执行复杂任务（文件/命令/代码） |
| **lark-cli 工具调用** | 通过命令行操作飞书 2500+ API | 轻量级飞书操作（发消息/查日历/写文档） |

**两者可以同时使用**，并不冲突。

### 3.2 OpenClaw 接入飞书（详细步骤）

#### 第一步：创建飞书应用

1. 打开飞书开放平台，点击「创建企业自建应用」
2. 填写应用名称（如"OpenClaw Assistant"）和描述
3. 进入「凭证与基础信息」，记录 App ID 和 App Secret
4. 开启「机器人」能力：在应用详情页点击「添加」机器人
5. 配置权限（一键导入）：
   - im:message（消息收发）
   - im:message:send_as_bot（以机器人身份发消息）
   - docx:document（读写文档）
   - drive:drive（云空间操作）
   - wiki:wiki（知识库读写）
   - bitable:app（多维表格读写）

#### 第二步：命令行配置 OpenClaw

```bash
# 安装（推荐 WSL/Linux）
curl -fsSL https://openclaw.ai/install.sh | bash

# 国内镜像（如遇网络问题）
npm install -g openclaw@latest --registry=https://registry.npmmirror.com

# 启用飞书插件
openclaw plugins enable feishu

# 添加飞书渠道
openclaw channels add
# 选择 Feishu/Lark，输入 App Secret 和 App ID

# 安全策略：建议选择「配对码」模式
```

#### 第三步：配置事件订阅

在飞书开放平台：
1. 进入「事件与回调」→「长连接方式」→「保存」
2. 点击「添加事件」，搜索「接收消息」，勾选
3. 创建版本并发布

#### 第四步：配对连接

```bash
# 飞书搜索你的应用名称，对话获取配对码
# 终端执行配对
openclaw pairing approve feishu <配对码>
```

### 3.3 lark-cli 工具调用（轻量级）

适合在 Claude Code 中通过 agent 直接调用飞书 API：

```bash
# 安装
npm install -g @larksuite/cli

# 初始化（手机扫码授权，一次开通常用权限）
lark-cli config init

# 使用示例
lark-cli docs +create --title "测试" --as user --markdown "# 标题"
lark-cli calendar list
lark-cli message send --content "你好"
```

**覆盖能力**：消息、日历、文档、多维表格、邮箱、任务、会议等 11 个业务域，200+ 命令。

### 3.4 多 Agent 协作（进阶）

可配置多个 Agent 协同处理飞书消息：
- **main**：项目总负责人，接收任务并协调
- **writer**：写作角色，负责内容创作
- **read**：资料搜集角色，负责信息检索和总结

配置示例：
```bash
npx -y @larksuite/openclaw-lark-tools install
```

---

## 四、通义千问模型接入

### 4.1 支持的 Qwen 模型

| 模型 | 上下文 | 适用场景 | 推荐用途 |
|------|--------|----------|----------|
| **Qwen3.6-Plus** | 1M token | Agent 编程旗舰 | OpenClaw 主力模型 |
| **Qwen3.6-35B-A3B** | 262K | 本地部署 | 单卡可跑，性价比最高 |
| **Qwen3 Coder** | 262K | 编程任务 | OpenClaw 默认编程模型 |
| **Qwen3 Coder Plus** | 1M | 复杂编程 + 长上下文 | 困难问题 + 长代码库 |

### 4.2 配置接入（DashScope API）

```bash
# 交互式引导（推荐新手）
openclaw onboard

# 手动配置 openclaw.json
{
  "models": {
    "mode": "merge",
    "providers": {
      "dashscope": {
        "baseUrl": "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
        "apiKey": "YOUR_DASHSCOPE_API_KEY",
        "api": "openai-completions",
        "models": [
          {
            "id": "qwen3.6-plus",
            "name": "Qwen3.6 Plus",
            "reasoning": true,
            "input": ["text", "image"],
            "contextWindow": 1000000,
            "maxTokens": 65536
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "dashscope/qwen3.6-plus"
      }
    }
  }
}
```

### 4.3 本地部署（Ollama）

如需完全本地运行：
```bash
# 安装 Ollama
curl -fsSL https://ollama.ai/install.sh | bash

# 拉取模型
ollama pull qwen3.6-35b-a3b

# OpenClaw 连接到本地
openclaw configure
# 选择 Ollama provider
```

---

## 五、MCP 集成

### 5.1 什么是 MCP

Model Context Protocol，AI 工具的"USB-C 接口"。OpenClaw 通过 MCP 注册 Skills，使模型能调用外部工具。

### 5.2 OpenClaw MCP 架构

```
Agent Runtime
    ↓ 调用工具
MCP Server（openclaw-mcp）
    ↓
Gateway（本地执行）
    ↓ 或远程 HTTP
外部 MCP Server（飞书/日历/文档）
```

### 5.3 配置示例

```bash
# 启动 MCP 服务器
openclaw mcp serve --url http://localhost:18789 --token-file ./token.txt

# 环境变量
export OPENCLAW_URL=http://localhost:18789
export OPENCLAW_GATEWAY_TOKEN=your-token

# 查看可用工具
openclaw mcp list
```

---

## 六、最佳实践

### 6.1 部署环境要求

| 配置项 | 最低 | 推荐 |
|--------|------|------|
| 系统 | Node.js >= 22.x | Linux/macOS/WSL2 |
| 内存 | 2GB | 4GB+ |
| 网络 | 能访问 GitHub/npm | 科学上网环境 |

### 6.2 安全配置

建议的安全配置：
- gateway.bind: loopback（只允许本地访问）
- gateway.auth.mode: token（强制 Token 认证）
- channels.feishu.dmPolicy: pairing（配对码模式）

### 6.3 Token 费用优化

重要：OpenClaw 每次会话注入完整的 System Prompt + 历史消息 + 工具结果，容易超支。

优化策略：
- 启用 compaction 模式（默认 safeguard）
- 定期清理 session JSONL
- 配置合理的 heartbeat 间隔
- 使用 Qwen3.6-35B-A3B 本地部署降低 API 成本

---

## 七、与飞书集成的应用场景

| 场景 | 说明 |
|------|------|
| **飞书消息触发 Agent** | 在群聊 @机器人，驱动 OpenClaw 执行任务 |
| **文档读写** | AI 帮你读飞书文档、写报告、自动整理 |
| **日历管理** | "明天 3 点开会" → Agent 自动创建日历 |
| **多维表格同步** | 数据自动写入飞书表格 |
| **审批流自动化** | 结合飞书审批插件实现自动处理 |
| **代码审查** | Qwen3.6-Plus 分析代码，通过飞书反馈结果 |

---

## 八、参考资源

| 资源 | 链接 |
|------|------|
| OpenClaw 官方文档 | https://docs.openclaw.ai |
| OpenClaw GitHub | https://github.com/openclaw/openclaw |
| lark-cli GitHub | https://github.com/larksuite/cli |
| Qwen 官方博客 | https://qwen.ai/blog |
| 飞书开放平台 | https://open.feishu.cn |
| DashScope API | https://www.alibabacloud.com/product/model-studio |

---

## 九、总结

OpenClaw + 飞书 + Qwen3.6 是一个强大的组合：

1. **OpenClaw** 作为本地 AI 网关，连接所有聊天渠道
2. **飞书** 提供企业级协作和消息基础设施
3. **Qwen3.6-Plus** 提供旗舰级 Agent 能力（编程+推理+百万上下文）

对于已有 Claude Code + lark-cli 配置的用户，接入路径：
1. 直接用 `lark-cli` 操作飞书（轻量级，已在用）
2. 额外安装 OpenClaw + 配置飞书 Channel（重量级，需要完整 Agent 能力）
3. Qwen3.6-Plus 作为 OpenClaw 的主力模型（需 DashScope API Key）

**推荐路径**：先试 lark-cli（已熟悉），再按需引入 OpenClaw 获得 Agent 级能力。