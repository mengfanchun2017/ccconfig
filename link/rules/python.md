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
- 用户安装: `ccconfig/conf/python-requirements.txt`
- 恢复: `pip3 install -r ccconfig/conf/python-requirements.txt`

## 常用包
| 包 | 来源 | 用途 |
|----|------|------|
| python-pptx | pip3 | PPT 生成 (ppt-master 依赖) |
| python-docx | pip3 | Word 文档读取 |
| cairosvg | pip3 | SVG → PNG/PDF 转换 |
| lxml | pip3 | XML 解析 |
| pillow | pip3 | 图片处理 |

## 禁止
- 禁止用 `sudo pip3 install`（sudo 会装到系统 site-packages，与 apt 冲突）
- 禁止创建 venv 来做临时任务（太复杂，直接 pip3 install --user）
