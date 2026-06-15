# conf/ — 配置模板 + symlink

> 所有初始化/升级脚本读取此目录。真实值在 ccprivate/conf/，通过 symlink 穿透访问。

## 文件

| 文件 | 用途 | 状态 |
|------|------|------|
| `versions.json` | 组件版本、Node.js pin | ✅ 公开，git 跟踪 |
| `*.json.example` | 配置模板（占位符） | ✅ 公开，git 跟踪 |
| `*.json` | symlink → ccprivate/conf/ | 🚫 不跟踪（`.gitignore`） |
| `python-requirements.txt` | Python pip 包清单 | ✅ 公开 |
| `third-party-skills.txt` | npx skills 清单 | ✅ 公开 |

## 新用户

1. 如有 ccprivate 仓库：`ccprivate/setup.sh` 自动建立 symlink
2. 无 ccprivate：`share/setup.sh` 交互式引导，从 `.example` 复制并填入真实值
