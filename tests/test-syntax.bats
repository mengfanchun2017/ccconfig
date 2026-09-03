#!/usr/bin/env bats
# test-syntax.bats — 所有 .sh 脚本的 bash -n 语法检查
#
# bats 包装版本，自动发现并检查所有 .sh 文件。
# 继承 CI 原本的 bash -n 逻辑。

@test "all .sh files pass bash -n" {
    result=0
    while IFS= read -r f; do
        if ! bash -n "$f" 2>/dev/null; then
            echo "SYNTAX ERROR: $f"
            result=1
        fi
    done < <(find . -name "*.sh" -not -path "./.git/*" -not -path "./.claude/*" -print0 2>/dev/null | xargs -0 -I{} echo {})
    [ "$result" -eq 0 ]
}
