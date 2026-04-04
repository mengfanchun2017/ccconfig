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

// MCP 协议处理 - 使用更简单的同步输出方式
process.stdin.setEncoding('utf8');

let buffer = '';
let requestId = 0;

process.stdin.on('data', async (chunk) => {
    buffer += chunk;

    // 按行处理 JSON-RPC 消息
    const lines = buffer.split('\n');
    buffer = lines.pop() || ''; // 保留不完整的行

    for (const line of lines) {
        if (!line.trim()) continue;

        try {
            const msg = JSON.parse(line);
            const resp = handleMessage(msg);
            if (resp) {
                console.log(JSON.stringify(resp));
            }
        } catch (e) {
            // 忽略解析错误
        }
    }
});

function handleMessage(msg) {
    const id = msg.id;

    if (msg.method === 'initialize') {
        return {
            jsonrpc: '2.0',
            id: id,
            result: {
                protocolVersion: '2025-03-26',
                capabilities: { tools: {} },
                serverInfo: { name: 'status-mcp', version: '1.0.0' }
            }
        };
    }

    if (msg.method === 'tools/list') {
        return {
            jsonrpc: '2.0',
            id: id,
            result: {
                tools: [{
                    name: 'status',
                    description: '显示 Claude Code 环境状态（文件链接、auto-sync、MCP 服务器状态）',
                    inputSchema: { type: 'object', properties: {}, required: [] }
                }]
            }
        };
    }

    if (msg.method === 'tools/call') {
        const toolName = msg.params?.name;

        if (toolName === 'status') {
            // 同步执行 hook-status.sh
            const { execSync } = require('child_process');
            try {
                const output = execSync('bash /home/francis/git/ccconfig/hook-status.sh', {
                    encoding: 'utf8',
                    timeout: 30000
                });

                return {
                    jsonrpc: '2.0',
                    id: id,
                    result: {
                        content: [{ type: 'text', text: output }]
                    }
                };
            } catch (err) {
                return {
                    jsonrpc: '2.0',
                    id: id,
                    error: {
                        code: -32603,
                        message: err.message
                    }
                };
            }
        }
    }

    if (msg.method === 'notifications/initialized') {
        return null; // 不需要响应
    }

    return null;
}

// 处理 stdin 关闭
process.stdin.on('end', () => {
    process.exit(0);
});
