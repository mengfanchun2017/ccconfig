#!/usr/bin/env node
// Status MCP Server - 提供状态检查功能
// 运行 hook-status.sh 并返回结果

const { spawn } = require('child_process');

function runHookStatus() {
    return new Promise((resolve, reject) => {
        const hookScript = '/home/francis/git/ccconfig/hook-status.sh';
        const proc = spawn('bash', [hookScript], {
            cwd: '/home/francis/git/ccconfig'
        });

        let stdout = '';
        let stderr = '';

        proc.stdout.on('data', (data) => {
            stdout += data.toString();
        });

        proc.stderr.on('data', (data) => {
            stderr += data.toString();
        });

        proc.on('close', (code) => {
            if (code === 0) {
                resolve(stdout);
            } else {
                reject(new Error(stderr || `Exit code: ${code}`));
            }
        });

        proc.on('error', (err) => {
            reject(err);
        });
    });
}

// MCP 协议处理
let requestId = 0;

process.stdin.on('data', async (chunk) => {
    const lines = chunk.toString().split('\n').filter(l => l.trim());

    for (const line of lines) {
        try {
            const msg = JSON.parse(line);

            if (msg.method === 'initialize') {
                const response = {
                    jsonrpc: '2.0',
                    id: msg.id,
                    result: {
                        protocolVersion: '2025-03-26',
                        capabilities: { tools: {} },
                        serverInfo: { name: 'status-mcp', version: '1.0.0' }
                    }
                };
                console.log(JSON.stringify(response));
            }

            else if (msg.method === 'tools/list') {
                const response = {
                    jsonrpc: '2.0',
                    id: msg.id,
                    result: {
                        tools: [
                            {
                                name: 'status',
                                description: '显示 Claude Code 环境状态（文件链接、auto-sync、 MCP 服务器状态）',
                                inputSchema: {
                                    type: 'object',
                                    properties: {},
                                    required: []
                                }
                            }
                        ]
                    }
                };
                console.log(JSON.stringify(response));
            }

            else if (msg.method === 'tools/call') {
                const toolName = msg.params?.name;

                if (toolName === 'status') {
                    try {
                        const output = await runHookStatus();
                        const response = {
                            jsonrpc: '2.0',
                            id: msg.id,
                            result: {
                                content: [
                                    {
                                        type: 'text',
                                        text: output
                                    }
                                ]
                            }
                        };
                        console.log(JSON.stringify(response));
                    } catch (err) {
                        const response = {
                            jsonrpc: '2.0',
                            id: msg.id,
                            error: {
                                code: -32603,
                                message: err.message
                            }
                        };
                        console.log(JSON.stringify(response));
                    }
                }
            }

            else if (msg.method === 'notifications/initialized') {
                // 初始化完成，无需响应
            }
        } catch (e) {
            // 忽略解析错误
        }
    }
});

// 处理 stdin 关闭
process.stdin.on('end', () => {
    process.exit(0);
});
