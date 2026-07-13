---
paths:
  - "**/*.py"
  - "**/requirements*.txt"
  - "**/pyproject.toml"
---

# Python 管理规范

## 版本
- Python 3.12.3，来自 Ubuntu 24 apt，不在终端用 deadsnakes/conda
- `python3` = `/usr/bin/python3`，不要自己编译安装

## 包管理
- **原则**: 能用 apt 安装的优先 apt，apt 没有的用 pip3
- **PIP_BREAK_SYSTEM_PACKAGES=1** 已在 ~/.bashrc 全局设置（WSL 开发机，非生产环境）
- pip3 安装到 user site: `~/.local/lib/python3.12/site-packages/`
- apt 安装到系统目录: `/usr/lib/python3/dist-packages/`
- 如果 apt 和 pip 都有同一个包，pip 版本会优先（user site 路径优先）

## 依赖清单
- 用户安装: `ccconfig/conftemp/python-requirements.txt`
- 恢复: `pip3 install -r ccconfig/conftemp/python-requirements.txt`

## 常用包
| 包 | 来源 | 用途 |
|----|------|------|
| python-pptx | pip3 | PPT 后处理 (autofit fontScale) |
| python-docx | pip3 | Word 文档读取 |
| cairosvg | pip3 | SVG → PNG/PDF 转换 |
| lxml | pip3 | XML 解析 |
| pillow | pip3 | 图片处理 |
| matplotlib | pip3 | 数据可视化（报告绘图主力） |
| seaborn | pip3 | 统计可视化（基于 matplotlib） |
| plotly | pip3 | 交互可视化（HTML 输出） |

## 报告绘图约定
- **选型**：常规图（折线/柱状/散点）→ matplotlib + seaborn；交互/网页嵌入 → plotly
- **保存位置**：图先存 `/tmp/figs/<图名>.png`，由子文档读取后嵌入飞书
- **嵌入方式**：子文档 = 详细档案（图 + 解读 + 代码）；父文档 = `block_insert_after` 嵌入图块
- **字体**：中文字体需 matplotlib 显式设置（`plt.rcParams['font.sans-serif']=['Noto Sans CJK SC']`），否则中文乱码
- **尺寸**：默认 `figsize=(10, 6)`，`dpi=150` 适合飞书全宽展示

## 安装/更新权限
- Claude 可以在任务需要时自主 `pip3 install` 新包，不询问用户
- 安装后自动更新 `ccconfig/conftemp/python-requirements.txt` 并标注新增
- 用户执行 `pip3 install` 同理，Claude 应该同步更新清单

## 升级
- 月度升级（`bash ccconfig/update.sh all`）自动执行 `pip3 install --upgrade -r ccconfig/conftemp/python-requirements.txt`
- 手动升级: `pip3 install --upgrade -r ccconfig/conftemp/python-requirements.txt`
- 生成最新清单: `pip3 freeze --user > ccconfig/conftemp/python-requirements.txt`

## 禁止
- 禁止用 `sudo pip3 install`（sudo 会装到系统 site-packages，与 apt 冲突）
- 禁止创建 venv 来做临时任务（太复杂，直接 pip3 install）
