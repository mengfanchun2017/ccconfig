---
name: f-pdf
description: |
  PDF 内容提取原语 — 文字/图片/表格/元数据提取。
  被 f-doc 的 PDF 翻译工作流委托调用，也可独立使用（PDF→Markdown、图片提取）。
allowed-tools: Read, Write, Bash, mcp__minimax__understand_image
---

# f-pdf — PDF 内容提取原语

2 级原语，处理 PDF 二进制格式细节。不处理翻译（Claude LLM）和文档创建（f-doc）。

## 前置条件

PyMuPDF（fitz）已安装。未安装时：`PIP_BREAK_SYSTEM_PACKAGES=1 pip3 install PyMuPDF`

## 快速决策

```
用户意图
  ├─ "提取PDF文字"/"PDF转Markdown"       → 工作流 A: 文字提取
  ├─ "提取PDF图片"                        → 工作流 B: 图片提取
  ├─ "翻译PDF"                            → 委托给 f-doc 工作流 F
  ├─ "分析PDF结构"                        → 工作流 C: 结构分析
  └─ "提取PDF元数据"                      → 工作流 D: 元数据
```

---

## 工作流 A: 文字提取（PDF → Markdown）

### CLI 快速

```bash
python3 /home/francis/git/_ext/ppt-master/skills/ppt-master/scripts/source_to_md/pdf_to_md.py input.pdf -o output.md
```

### 编程调用

```python
import fitz
doc = fitz.open("input.pdf")
for page in doc:
    text = page.get_text("text")
    # text 可直接传给 Claude 翻译
```

---

## 工作流 B: 图片提取

提取后 MUST 用 `minimax understand_image` 验证每张图，排除 logo/装饰图。

```bash
python3 /home/francis/git/ccconfig/link/skills/f-pdf/references/extract-images.py input.pdf ./output_dir/
```

---

## 工作流 C: 结构分析

分析字体大小分布、标题层级、页眉页脚统计。

```python
import fitz
doc = fitz.open("input.pdf")
# 字体分布
sizes = {}
for page in doc:
    blocks = page.get_text("dict")["blocks"]
    for b in blocks:
        if b["type"] == 0:
            for line in b["lines"]:
                for span in line["spans"]:
                    sz = round(span["size"], 1)
                    sizes[sz] = sizes.get(sz, 0) + len(span["text"].strip())
print(sorted(sizes.items(), key=lambda x: x[1], reverse=True))
```

---

## 工作流 D: 元数据提取

```python
import fitz
doc = fitz.open("input.pdf")
meta = doc.metadata
print(f"标题: {meta.get('title', 'N/A')}")
print(f"作者: {meta.get('author', 'N/A')}")
print(f"页数: {doc.page_count}")
```

---

## 图片验证规范

```bash
# 逐张验证，排除 logo/装饰图/图标
minimax understand_image --prompt "这张图是学术内容（图表/示意图/照片）还是装饰元素（logo/图标/分隔符）？只回答'学术内容'或'装饰元素'" --image_source ./img.jpg
```

装饰元素直接删除，不嵌入文档。

---

## 工具委托

| 操作 | 工具 |
|------|------|
| 文字提取 | PyMuPDF (fitz) |
| 图片提取+过滤 | PyMuPDF + minimax understand_image |
| Markdown 转换 | pdf_to_md.py (ppt-master) |
| 翻译 | Claude LLM（由 f-doc 编排） |
| 文档创建 | lark-doc（由 f-doc 编排） |

## 参考

- `references/extract-images.py` — 纯 Python 图片提取脚本
- `/home/francis/git/_ext/ppt-master/skills/ppt-master/scripts/source_to_md/pdf_to_md.py` — 完整 PDF→MD 转换
