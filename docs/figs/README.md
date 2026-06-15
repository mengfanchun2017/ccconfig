# docs/figs/ — 文档配图规范

> ccconfig 4 层追踪系统的**可视化资产库**。每张图都跟飞书 doc / 博客 / README 配对。

## 命名约定

`<topic-slug>.<format>`

例：
- `rule-of-three-cover.png` — Rule of Three 封面 PNG（fallback / README / 博客用）
- `cover.mmd` — 同主题的 mermaid 源（飞书白板可编辑版）
- `4layer-framework.png` — 4 层追踪系统架构图

## 配图三件套模式

每张配图同时存**两种格式** + **源**：

| 格式 | 用途 | 工具 |
|---|---|---|
| `.png` | README / 博客 / Notion / 微信 / 邮件 | `matplotlib` + `seaborn` |
| `.mmd` (mermaid) | 飞书白板（**可编辑**）| `lark-cli whiteboard +update` |
| `.py` | 重跑脚本（traceability）| `python3` |

## 中文字体

matplotlib 必显式设置，否则中文乱码：
```python
plt.rcParams['font.sans-serif'] = ['WenQuanYi Micro Hei']
```

或系统已有 Noto Sans CJK SC：
```python
plt.rcParams['font.sans-serif'] = ['Noto Sans CJK SC']
```

## 当前配图

| 文件 | 配对的飞书 doc |
|---|---|
| `rule-of-three-cover.png` + `cover.mmd` | 固定任务写脚本的工程实践 — Rule of Three 与决策矩阵 |

## 用法

```bash
# 重跑 PNG（编辑 .py 后）
python3 /tmp/figs/gen_cover.py

# 重跑飞书白板（编辑 .mmd 后）
lark-cli whiteboard +update --whiteboard-token <token> \
  --input_format mermaid --source docs/figs/cover.mmd --overwrite
```
