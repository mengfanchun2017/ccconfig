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
