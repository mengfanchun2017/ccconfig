# conf/ — 公开配置模板 + 版本文件

> 本目录只含公开文件。个人配置（API key/token）在 `~/git/ccprivate/conf/`，
> 脚本通过 `resolve_conf()` 自动查找，无需 symlink。

## 文件

| 文件 | 用途 | 状态 |
|------|------|------|
| `versions.json` | 组件版本、Node.js pin | ✅ 公开，git 跟踪 |
| `*.json.example` | 配置模板（占位符） | ✅ 公开，git 跟踪 |
| `python-requirements.txt` | Python pip 包清单 | ✅ 公开 |

## 新用户

1. 如有 ccprivate 仓库：`cd ~/git/ccprivate && bash setup.sh` 建立用户级链接
2. 无 ccprivate：`bash ccconfig/init-ccprivate-repo.sh` 交互式引导创建
3. 配置在 `~/git/ccprivate/conf/` 目录，脚本自动通过 `resolve_conf()` 读取
