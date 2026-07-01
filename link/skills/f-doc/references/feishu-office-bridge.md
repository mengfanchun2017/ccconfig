# 飞书 ↔ 本地 Office 双向转换

## 飞书 → Office (.docx)

### Step 1: 获取飞书内容

```bash
lark-cli docs +fetch --api-version v2 --doc "{token}" --format json > /tmp/doc.json
```

### Step 2: 转为 OfficeCLI 结构

用 Python 解析飞书 blocks → OfficeCLI JSON 操作序列：

```python
import json

with open('/tmp/doc.json') as f:
    doc = json.load(f)

blocks = doc['data']['document']['blocks']
commands = []

for b in blocks:
    t = b.get('type', '')
    content = b.get('content', '')
    
    if t.startswith('heading'):
        lvl = int(t[-1])
        commands.append({
            "add": "/body", "element": "paragraph",
            "props": {"style": f"Heading{lvl}", "text": content}
        })
    elif t == 'paragraph':
        commands.append({
            "add": "/body", "element": "paragraph",
            "props": {"text": content}
        })
    # ... 处理 list/table/image/callout

with open('/tmp/commands.json', 'w') as f:
    json.dump(commands, f)
```

### Step 3: 应用 OfficeCLI

```bash
officecli create /tmp/output.docx
officecli batch /tmp/output.docx --input /tmp/commands.json
```

### 转 PPTX

委托 unified-ppt skill：
- 飞书文档 → `docs +fetch` 获取 Markdown
- → unified-ppt 双引擎生成 PPTX

---

## Office (.docx) → 飞书

### Step 1: 读取 .docx

```bash
# 获取完整文档结构
officecli get /path/to/file.docx /body --json > /tmp/docx_structure.json

# 或查询段落
officecli query /path/to/file.docx "paragraph" --json
```

### Step 2: 转为飞书 DocxXML

OfficeCLI 元素 → 飞书 XML 映射：

| OfficeCLI 元素 | 飞书 XML |
|---------------|----------|
| `paragraph` (HeadingN style) | `<h1>` / `<h2>` ... |
| `paragraph` (Normal) | `<p>` |
| `paragraph` (ListBullet) | `<ul><li>` |
| `table` | `<table>` |
| `picture` → `officecli get picture --extract /tmp/img.png` | `<a>` with `+media-upload` |

### Step 3: 上传到飞书

```bash
lark-cli docs +create --api-version v2 --content "{飞书XML}" --title "标题"
```

---

## 格式映射参考

### 文本样式

| 飞书 | OfficeCLI docx (.docx) |
|------|----------------------|
| `<h1>` / `<h2>` ... | `paragraph` style=`Heading1`/`Heading2` |
| `<p>` | `paragraph` style=`Normal` |
| `<strong>` | `run` bold=true |
| `<em>` | `run` italic=true |
| `<code>` | `run` font=`Consolas` |
| `<u>` | `run` underline=true |
| `<s>` / `<del>` | `run` strikethrough=true |

### 块元素

| 飞书 | OfficeCLI docx |
|------|---------------|
| `<ul><li>` | `paragraph` style=`ListBullet` |
| `<ol><li>` | `paragraph` style=`ListNumber` |
| `<table>` | `table` element |
| `<callout>` | `paragraph` + border/shading props |
| `<grid>` | `table` (1-row, n-columns) |
| `<a href="URL">` | `hyperlink` within run |
| `<img>` | `picture` element (先下载) |

### 不支持/降级

| 飞书元素 | 降级方案 |
|---------|---------|
| `<bitable>` / `<sheet>` | 截图为图片嵌入 |
| `<synced_reference>` | 展开为静态引用 |
| `<whiteboard>` | 导出为图片 |
| `<task>` | 转为 checklist |

---

## 坑点

- OfficeCLI 操作 .docx 前必须先 `officecli open file.docx` 驻留进程
- docx 的 heading 样式名是 `Heading1` 不是 `Heading 1`（无空格）
- 飞书图片需先 `+media-download` 下载到本地，再嵌入 OfficeCLI
- 批量操作用 `officecli batch --input cmds.json` 不要逐条执行
- .docx 中文字体默认用 `SimSun`（宋体），英文用 `Calibri`
- 飞书文档中的内嵌 sheet/bitable 无法在 .docx 中原样保留

## 中文字体（关键，不加 = 乱码）

officecli 创建 .docx 时**默认不设中文字体**，中文全部 fallback 到 Calibri → 无字形 → 乱码。

**每个 paragraph add 必须带中文字体参数**：

```bash
officecli add file.docx /body --type paragraph \
  --prop text="中文内容" \
  --prop font.ea="Microsoft YaHei" \
  --prop font.latin=Calibri \
  --prop lang.ea=zh-CN \
  --prop size=11pt
```

| 属性 | 值 | 说明 |
|------|-----|------|
| `font.ea` | `Microsoft YaHei` / `SimSun` | 东亚字体槽（中文），不加=乱码 |
| `font.latin` | `Calibri` | 拉丁字体槽（英文/数字） |
| `lang.ea` | `zh-CN` | 东亚语言标记 |
| `font` (简写) | `Microsoft YaHei` | 同时设 ascii+hAnsi+eastAsia，可用但中英同字体不推荐 |

**2026-07-02 实测**：不加 `font.ea` → Word 打开全是乱码（`effective.font.ascii: Calibri`，无 `effective.font.eastAsia`）。加后正常渲染。

### Python 调用：禁止 json.dumps 传中文（关键坑）

**`json.dumps(text)` 会把中文转成 `\uXXXX` 转义序列**，officecli 原样写入 XML → Word 看到的是 ASCII 转义字符串，不是汉字 → 乱码。

```python
# ❌ 错误：json.dumps 把中文转 \uXXXX → officecli 原样写入 → 乱码
text = "强基计划"
cmd = f"officecli add ... --prop text={json.dumps(text)}"
# XML 结果: <w:t>强基计划</w:t>  ← 不是中文！

# ✅ 正确：shlex.quote 保留原始 UTF-8 中文
import shlex
cmd = f"officecli add ... --prop text={shlex.quote(text)}"
# XML 结果: <w:t>强基计划</w:t>  ← 真正的中文
```

| 方法 | XML 输出 | Word 渲染 |
|------|---------|-----------|
| `json.dumps(text)` | `强基...` | 乱码 |
| `shlex.quote(text)` | `强基计划...` | 正常 |
| shell heredoc 直接写 | `强基计划...` | 正常 |

**Why**：`json.dumps` 默认 `ensure_ascii=True`，非 ASCII 字符全部转义。officecli 不做反向解析，直接写入 OOXML。

### 页面边距（压缩到 1 页）

```bash
# A4 默认边距太宽（上下 2.54cm，左右 3.18cm），缩到 1.5cm 可多挤 ~30% 内容
officecli set file.docx /section[1] \
  --prop marginTop=1.5cm --prop marginBottom=1.5cm \
  --prop marginLeft=1.8cm --prop marginRight=1.8cm
```
