# ppt-master — PPT 生成引擎

> 可选组件，默认不在 `init.sh all` 中安装

## 是什么

hugohe3/ppt-master（⭐12.9k）将 SVG 模板转为原生 DrawingML PPTX（非 PNG 光栅），输出可编辑形状。支持 22 种模板、演讲者备注、转场动画、元素入场动画。

- 仓库: [hugohe3/ppt-master](https://github.com/hugohe3/ppt-master)
- 平台: Python 3（跨平台）
- 许可: MIT

## 快速开始

```bash
# 一键安装
bash ccconfig/option-ppt-master/init.sh

# 或分步
bash ccconfig/option-ppt-master/init.sh --install   # 安装依赖 + 克隆
bash ccconfig/option-ppt-master/init.sh --status    # 状态检查
```

## 安装内容

- `python-pptx` + `cairosvg` + `lxml` (Python 依赖)
- `~/git/_ext/ppt-master/` (ppt-master 仓库，含 22 种模板)

## 配合使用

- `unified-ppt` skill：从 md/wiki 生成飞书 PPTX
- 4 步流水线：结构化 → 模板匹配 → SVG 生成 → 导出上传

## 新终端初始化

```bash
bash ccconfig/option-ppt-master/init.sh --install
```
