# 编码规范

## 禁止的操作
- rm -rf, git reset --hard, git clean -f, mkfs, dd, chmod -R 777
- sudo（除 apt-get 外）
- 重定向覆盖 (:/>)

## 代码风格
- 默认不写注释，只在 WHY 非显然时加一行
- 不添加错误处理/fallback/验证给不可能发生的场景
- 不设计假想的未来需求，三个相似行优于过早抽象
- 不写多行 docstring 或注释块
- 优先编辑现有文件，不新建除非必须
- 不引入安全漏洞（SQL 注入、XSS、命令注入等）
