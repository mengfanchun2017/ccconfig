# ccconfig 沙盒测试 — 模拟全新 Ubuntu，预注测试 Key，跑完整安装流程
#
# 用法（本地）:
#   docker build --no-cache -t ccconfig-sandbox -f tests/sandbox/Dockerfile .
#   docker run --rm -it ccconfig-sandbox
#
# 做什么:
#   1. 模拟 init-ubuntu.sh (装 Node/Claude Code/symlink)
#   2. 模拟 init-llm.sh (LLM 配置)
#   3. 跑 status.sh 验证
#   4. 验证 17+ 检查点（symlink、文件、退出码）
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl wget ca-certificates python3 sudo bash \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash tester && echo "tester ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

ENV HOME=/home/tester
# 沙盒 Key — 假值，仅验证配置写入，不会被实际 API 调用
ENV ANTHROPIC_AUTH_TOKEN=sk-sandbox-test
ENV TAVILY_API_KEY=tvly-sandbox-test
ENV MINIMAX_API_KEY=eyJhbGciOiJIUzI1NiJ9.sandbox
ENV BOOTSTRAP_NOSUDO=1

USER tester
WORKDIR /home/tester

COPY --chown=tester:tester . /home/tester/git/ccconfig

CMD ["bash", "/home/tester/git/ccconfig/tests/sandbox/run.sh"]
