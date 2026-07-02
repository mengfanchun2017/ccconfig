# PPT 样式硬规则

> 所有 PPT 生成必须遵守。违反任一条即为 bug。

## 封面

- **不显示副标题**：`SUBTITLE=""`
- **不显示组织标记**：`ORG_SHORT=""`（右下角）、`AUTHOR=""`（如需撰稿人则保留）
- **撰稿人**：如有需要，`AUTHOR="运行维护中心 &amp; AI技术组"` 一行即可
- 封面只保留：主标题 + 撰稿人（可选）+ 日期

## 内容页

- **右上角**：不显示组织名（`ORG_SHORT` 已从 03_content.svg 模板移除）
- **右下角 footer**：不显示组织名（同上）
- **章节日**：不显示组织名（`ORGANIZATION` 已从 02_chapter.svg 模板移除）
- **结束页**：不显示组织名（`ORGANIZATION` 已从 04_ending.svg 模板移除）

## 链接输出

- URL/文件链接不用 Markdown 表格（WSL 终端换行截断无法点击）
- 每个链接独占一行：`[标题](URL)`

## 字体

- 全站统一 Arial / Microsoft YaHei（见 themes/professional_blue.md）
- 正文 ≤ 18px（见 references/build-guide.md）

## 颜色

- 默认 professional_blue 模板：蓝 `#4472C4` + 深灰 `#1F2329`
- 不做多色（不引入橙/绿/金等杂色）

## 输出目录

- **默认**: `C:\ccout`（WSL 路径 `/mnt/c/ccout/`）
- **飞书上传**: 仅用户明确说"飞书"/"上传飞书"/"同步到飞书"时才执行
- 不在每次生成后自动上传飞书

## 默认测试文档

- 飞书 wiki: https://<your-tenant>.feishu.cn/wiki/<your-wiki-token>
- 标题: 算力资源池组网规划
- 内容: 交换机选型 + 服务器部署参数 + 组网方案
- 用途: f-ppt 功能测试的默认输入文档
