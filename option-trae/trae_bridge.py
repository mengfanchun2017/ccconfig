#!/usr/bin/env python3
"""trae_bridge.py — Anthropic Messages API → Trae (SOLO/CN) 私有 SSE 网关。

让 Claude Code 直接吃 Trae 订阅（kimi-k2.6 / glm-5.2 / DeepSeek-V4 等），
不需要 DSH、不需要 dsh-connect-trae 插件常驻。

链路：
  Claude Code ──/v1/messages──▶ 本网关 ──llm_utils_chat──▶ trae-api-cn.mchost.guru
                              ◀──Trae 命名 SSE────────────┘

设计要点（都是真机踩出来的）：
  * Anthropic → OpenAI 请求体：直接复用 openai_bridge.anthropic_to_openai_req
  * OpenAI → Trae 请求体：assistant 的 tool_calls[].function 必须改名 function_call；
    tools[].function.parameters 必须是 **JSON 字符串**；role=tool 的 content 必须是数组
  * Trae SSE → OpenAI chunk → Anthropic SSE：复用 openai_bridge.openai_chunk_to_anthropic_sse
  * Trae 在有 tool_calls 时 finish_reason 仍是 "stop"，必须自己改写为 "tool_calls"
  * x-app-version-code 必须是纯数字，传 iCubeLastVersion（含点）会被上游 400 拒绝
  * Trae 看不见图片：image 块一律降级成 [image omitted] 文本

用法：
    python3 trae_bridge.py --port 8899
    # Claude Code:
    ANTHROPIC_BASE_URL=http://127.0.0.1:8899 ANTHROPIC_MODEL=kimi-k2.6 claude
"""
from __future__ import annotations

import argparse
import asyncio
import base64
import hashlib
import json
import os
import re
import sys
import time
import uuid
from pathlib import Path

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse

# 复用已验证的 Anthropic ↔ OpenAI 转换层。
# 优先用 option-llmswitch 里的原件（用户维护的唯一真相源），只有在它缺失时才退回
# 本目录的副本 —— 否则两份 openai_bridge.py 会各自漂移，改了一处另一处不生效。
_HERE = Path(__file__).resolve().parent
for _p in (_HERE.parent / "option-llmswitch", _HERE):
    if (_p / "openai_bridge.py").is_file():
        sys.path.insert(0, str(_p))
        break
import openai_bridge as ob  # noqa: E402

# ───────────────────────── 常量 ─────────────────────────

CHAT_BASE = os.environ.get("TRAE_CHAT_BASE", "https://trae-api-cn.mchost.guru").rstrip("/")
CHAT_PATH = "/api/agent/v3/llm_utils_chat"
MODELS_PATH = "/api/ide/v1/get_detail_param"
DEFAULT_FUNCTION = "solo_work_lite"
# 模型 → 频道：glm-5.3 系列只挂在 solo_work_remote；deepseek-v4.1-flash 虽在目录
# 的多个频道里出现，但用 solo_work_lite 实调会被流内 4001 "the param is invalid"
# 拒绝（2026-11-07 实测两个模型都是），统一走 solo_work_remote。前缀匹配。
MODEL_FUNCTION_RULES: list[tuple[str, str]] = [
    ("glm-5.3", "solo_work_remote"),
    ("deepseek-v4.1-flash", "solo_work_remote"),
]
# 模型 → 默认思考档（DSH 档位名，发送前经 WIRE_EFFORT_MAP 转 Trae wire 名）。
# 只在客户端没显式给 effort 时生效：CC 的 /effort、output_config.effort 优先。
MODEL_EFFORT_DEFAULTS: dict[str, str] = {
    "glm-5.3": "high",
    "glm-5.3-flash": "high",
    "glm-5.3-flashx": "high",
}
# DSH/OpenAI 档位名 → Trae wire 档位名（插件 WIRE_EFFORT_MAP 的 Python 等价物；
# Trae 词汇是 light/high/extra_high/max，没有 low/xhigh）
WIRE_EFFORT_MAP = {"low": "light", "medium": "medium", "high": "high",
                   "xhigh": "extra_high", "max": "max"}
# 纯数字构建号；上游对 app_version_code 做整型绑定，传 "2.3.99396" 会 4001
VERSION_CODE = "20260716"
APP_ID = "6eefa01c-1036-4c7e-9ca5-d891f63bfcd8"

DESKTOP_CLIENT_ID = "ono9krqynydwx5"
SOLO_CLIENT_ID = "en1oxy7wnw8j9n"

AUTH_PATH = Path(os.environ.get(
    "TRAE_AUTH_PATH", "/mnt/c/Users/franc/.dsh/.trae-auth.cn.json"))
STORAGE_PATH = Path(os.environ.get(
    "TRAE_STORAGE_PATH", "/mnt/c/Users/franc/AppData/Roaming/Trae CN/User/globalStorage/storage.json"))
PRODUCT_PATH = Path(os.environ.get(
    "TRAE_PRODUCT_PATH",
    "/mnt/c/Users/franc/AppData/Local/Programs/Trae CN/resources/app/product.json"))

REFRESH_LEGACY_PATH = "/cloudide/api/v3/trae/oauth/ExchangeToken"
REFRESH_CURRENT_PATH = "/trae/api/v3/oauth/ExchangeToken"

# Trae 客户端 storage.json 的 AES 派生盐（与官方 JS 一致）
SALT_A = bytes([82, 9, 106, 213, 48, 54, 165, 56, 191, 64, 163, 158, 129, 243, 215, 251,
                124, 227, 57, 130, 155, 47, 255, 135, 52, 142, 67, 68, 196, 222, 233, 203,
                84, 123, 148, 50, 166, 194, 35, 61, 238, 76, 149, 11, 66, 250, 195, 78,
                8, 46, 161, 102, 40, 217, 36, 178, 118, 91, 162, 73, 109, 139, 209, 37])
SALT_B = bytes([31, 221, 168, 51, 136, 7, 199, 49, 177, 18, 16, 89, 39, 128, 236, 95,
                96, 81, 127, 169, 25, 181, 74, 13, 45, 229, 122, 159, 147, 201, 156, 239,
                160, 224, 59, 77, 174, 42, 245, 176, 200, 235, 187, 60, 131, 83, 153, 97,
                23, 43, 4, 126, 186, 119, 214, 38, 225, 105, 20, 99, 85, 33, 12, 125])
SALT_C = bytes([191, 192, 216, 250, 122, 246, 220, 97, 31, 254, 98, 27, 8, 72, 71, 176,
                135, 99, 96, 18, 127, 101, 203, 104, 211, 102, 191, 125, 37, 72, 150, 156,
                51, 229, 121, 35, 17, 153, 141, 177, 110, 131, 150, 128, 172, 255, 254, 6,
                18, 140, 55, 62, 236, 249, 135, 64, 135, 12, 117, 4, 89, 149, 168, 209])
SALT_D = bytes([246, 204, 26, 232, 232, 70, 129, 109, 223, 146, 169, 242, 23, 241, 105, 145,
                50, 196, 165, 42, 254, 120, 3, 54, 244, 207, 209, 85, 53, 6, 138, 106,
                175, 148, 31, 204, 186, 186, 165, 182, 87, 142, 49, 10, 39, 110, 26, 154,
                86, 56, 173, 125, 18, 64, 198, 225, 99, 99, 83, 82, 191, 134, 76, 170])

_REQ_SEQ = [0]

# Claude Code 的 gateway model discovery 只认 /(claude|anthropic)/i 的模型 id，
# 所以对外暴露一律加 claude- 前缀，进来再剥掉还原成 Trae config_name。
CLAUDE_PREFIX = "claude-trae-"
CLAUDE_ALIASES = {
    "claude-sonnet-4-5": "kimi-k2.6",
    "claude-sonnet-4-20250514": "kimi-k2.6",
    "claude-opus-4-1": "glm-5.2",
    "claude-haiku-4-5": "kimi-k2.6",
}
_DIR_CACHE: dict = {"at": 0.0, "names": []}
# get_detail_param 里混着的工具行，不是可对话模型
_NON_MODEL_NAMES = {"summary", "file_search_agent", "computer_use_subagent", "explore_sub_agent_v2"}
_TOOL_ROW = re.compile(r"(subagent|_agent|summary|browser_use|computer_use)", re.I)


def _log(msg: str):
    print(f"[trae-bridge] {msg}", flush=True)


# ───────────────────── Trae 本地状态读取 ─────────────────────

def _xorb(a: bytes, b: bytes) -> bytes:
    return bytes(x ^ y for x, y in zip(a, b))


def decrypt_trae_value(encoded: str) -> str:
    """解 Trae storage.json 里 iCubeAuthInfo://* 的值（AES-128-CBC）。

    注意：官方 JS 在明文前 64 字节放了 sha512(body) 校验，但真机 storage.json
    里那 64 字节并不是正文的 sha512 —— 校验会失败。这里跳过校验，只取 body。
    """
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

    buf = base64.b64decode(encoded)
    hdr = buf[:6]
    if hdr == bytes([116, 99, 5, 16, 0, 0]):
        salt = _xorb(SALT_A, SALT_B)
    elif hdr == bytes([18, 57, 32, 32, 2, 3]):
        salt = _xorb(SALT_C, SALT_D)
    else:
        raise ValueError(f"unsupported Trae auth header {hdr!r}")
    random, enc = buf[6:38], buf[38:]
    derived = hashlib.sha512(hashlib.sha512(random).digest() + salt).digest()
    dec = Cipher(algorithms.AES(derived[:16]), modes.CBC(derived[16:32])).decryptor()
    pt = (dec.update(enc) + dec.finalize())[64:]
    text = pt.decode(errors="replace")
    end = text.rfind("}")
    return text[: end + 1] if end >= 0 else text


class TraeIdentity:
    """storage.json 里那套设备指纹 —— 上游按机器校验，不能编。"""

    def __init__(self, storage: dict, app_version: str):
        self.storage = storage
        self.app_version = app_version
        self.machine_id = storage["telemetry.machineId"]
        self.device_id = storage["telemetry.devDeviceId"]
        self.device_key_pair = None
        for k, v in storage.items():
            if k.startswith("iCubeAuthInfo://icube-dc:"):
                try:
                    self.device_key_pair = json.loads(decrypt_trae_value(v))
                except Exception as e:  # noqa: BLE001
                    _log(f"device keypair decrypt failed: {e}")

    @classmethod
    def load(cls) -> "TraeIdentity":
        storage = json.loads(STORAGE_PATH.read_text())
        app_version = "3.4.15"
        try:
            app_version = json.loads(PRODUCT_PATH.read_text()).get("appVersion") or app_version
        except Exception:  # noqa: BLE001
            pass
        return cls(storage, app_version)

    def headers(self, access_token: str, user_id: str) -> dict:
        trace = uuid.uuid4().hex
        return {
            "Authorization": f"Cloud-IDE-JWT {access_token}",
            "X-Ide-Token": access_token,
            "X-Cloudide-Token": access_token,
            "x-uid": user_id,
            "x-plugin-channel": "icube-ai",
            "User-Agent": f"Trae/{self.app_version}",
            "x-app-id": APP_ID,
            "x-machine-id": self.machine_id,
            "x-device-id": self.device_id,
            "x-device-type": "windows",
            "x-device-cpu": "AMD Ryzen 7 7840HS w/ Radeon 780M Graphics",
            "x-os-version": "Windows 10.0.26300.0",
            "x-app-version": self.app_version,
            "x-ide-version": self.app_version,
            "x-app-version-code": VERSION_CODE,
            "x-ide-version-code": VERSION_CODE,
            "x-ide-version-type": "stable",
            "x-custom-trace-id": trace,
            "x-flow-traceparent": f"04-{trace}-{trace[:16]}-01",
            "request-traffic-type": "prod",
            "x-request-id": trace,
            "x-trae-request-id": trace,
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
        }


class CredentialStore:
    """access token 的读取 + 刷新 + 回写。

    刷新用 **legacy 契约**（/cloudide/api/v3/trae/oauth/ExchangeToken，ClientSecret="-"，无
    DeviceProof）。当前契约 /trae/api/v3/... 需要设备私钥对 "POST\\npath\\nclientId\\n
    refreshToken\\nts\\nnonce" 做 ECDSA 签名，本机实测被拒 20403 "Token device not match"
    （设备绑定在服务端，签名格式另有一层约束），legacy 契约实测 200 且能换到新 token。
    """

    def __init__(self, path: Path = AUTH_PATH, margin_ms: int = 300_000):
        self.path = path
        self.margin_ms = margin_ms
        self._cred: dict | None = None
        self._lock = asyncio.Lock()
        self._last_failure = 0.0

    def load(self) -> dict:
        doc = json.loads(self.path.read_text())
        self._cred = doc["credentials"][0]
        self._doc = doc
        return self._cred

    def reload_if_changed(self) -> dict:
        """DSH 插件与本网关共用同一个 auth 文件，而 refresh token 是**轮换**的：
        插件刷新后旧 refresh token 立即失效。所以每次用前重新读盘，谁最后刷新谁赢，
        不会出现「两边各自持有一份过期副本、互相把对方刷死」。
        """
        try:
            doc = json.loads(self.path.read_text())
        except Exception:  # noqa: BLE001
            return self.credential
        cred = (doc.get("credentials") or [None])[0]
        if not cred or not cred.get("accessToken"):
            return self.credential
        if self._cred is not None and cred.get("accessToken") == self._cred.get("accessToken"):
            return self._cred
        if self._cred is not None and cred.get("expiresAtMs", 0) < self._cred.get("expiresAtMs", 0):
            return self._cred  # 盘上是更旧的一份，保留内存里的
        self._doc, self._cred = doc, cred
        _log("auth file changed on disk; reloaded credential")
        return self._cred

    @property
    def credential(self) -> dict:
        if self._cred is None:
            self.load()
        return self._cred

    def _needs_refresh(self) -> bool:
        return self.credential["expiresAtMs"] - int(time.time() * 1000) < self.margin_ms

    async def ensure(self, client: httpx.AsyncClient, force: bool = False) -> dict:
        async with self._lock:
            self.reload_if_changed()
            if not force and not self._needs_refresh():
                return self.credential
            # 失败后 5 分钟内不反复打上游
            if time.monotonic() - self._last_failure < 300 and not force:
                return self.credential
            try:
                await self._refresh(client)
                self._last_failure = 0.0
            except Exception as e:  # noqa: BLE001
                self._last_failure = time.monotonic()
                remain = self.credential["expiresAtMs"] - int(time.time() * 1000)
                if remain <= 0:
                    raise RuntimeError(
                        f"trae: token refresh failed and access token is expired ({e}); "
                        "sign in again in Trae") from e
                _log(f"refresh failed, still using current token for {remain//1000}s: {e}")
            return self.credential

    async def _refresh(self, client: httpx.AsyncClient):
        cred = self.credential
        host = (cred.get("host") or "https://api.trae.cn").rstrip("/")
        body = {
            "ClientID": DESKTOP_CLIENT_ID,
            "ClientSecret": "-",
            "RefreshToken": cred["refreshToken"],
            "UserID": cred.get("userId"),
        }
        last = None
        for path in (REFRESH_LEGACY_PATH, REFRESH_CURRENT_PATH):
            r = await client.post(host + path, json=body, timeout=30)
            if r.status_code == 200:
                res = r.json().get("Result") or {}
                if not res.get("Token"):
                    last = f"{path}: no token in response"
                    continue
                cred["accessToken"] = res["Token"]
                if isinstance(res.get("TokenExpireAt"), (int, float)):
                    cred["expiresAtMs"] = int(res["TokenExpireAt"])
                if res.get("RefreshToken"):
                    cred["refreshToken"] = res["RefreshToken"]
                if isinstance(res.get("RefreshExpireAt"), (int, float)):
                    cred["refreshExpiresAtMs"] = int(res["RefreshExpireAt"])
                self._write_back()
                _log(f"token refreshed via {path}; expires "
                     f"{time.strftime('%Y-%m-%d %H:%M', time.localtime(cred['expiresAtMs']/1000))}")
                return
            last = f"{path}: http {r.status_code} {r.text[:160]}"
        raise RuntimeError(last or "no refresh endpoint responded")

    def _write_back(self):
        """原子回写，DSH 插件下次读盘就能拿到新 token。"""
        tmp = self.path.with_suffix(self.path.suffix + ".tmp")
        tmp.write_text(json.dumps(self._doc, ensure_ascii=False))
        os.replace(tmp, self.path)


# ─────────────────── 请求体：OpenAI → Trae ───────────────────

def _flatten_content(content, *, allow_image_note: bool = True, keep_images: bool = False):
    """Trae 消息 content 归一化。

    keep_images=False（默认，纯文本模型）：图片降级成占位符。
    keep_images=True（视觉路由到 Trae 视觉模型）：image_url 原样保留 ——
    实测 Doubao-Seed-2.1-Turbo / kimi-k2.6 能看图，deepseek/glm 系报参数错误。
    """
    if isinstance(content, str):
        return [{"type": "text", "text": content}]
    if not isinstance(content, list):
        return [{"type": "text", "text": ""}]
    parts = []
    for p in content:
        if not isinstance(p, dict):
            continue
        if p.get("type") == "text":
            parts.append({"type": "text", "text": p.get("text") or ""})
        elif p.get("type") in ("image_url", "image"):
            if keep_images:
                # anthropic_to_openai_req 已把 Anthropic image 转成 OpenAI image_url 格式
                if p.get("type") == "image_url" and p.get("image_url"):
                    parts.append(p)
            elif allow_image_note:
                parts.append({"type": "text", "text": "[image omitted: this endpoint is text-only]"})
        elif p.get("type") == "input_text":
            parts.append({"type": "text", "text": p.get("text") or ""})
    return parts or [{"type": "text", "text": ""}]


def openai_to_trae_body(oa: dict, model: str, function: str = DEFAULT_FUNCTION,
                        keep_images: bool = False) -> dict:
    """OpenAI chat-completions 请求体 → Trae llm_utils_chat 请求体。"""
    msgs = []
    for m in oa.get("messages") or []:
        role = m.get("role") or "user"
        if role == "developer":
            role = "system"
        out = {"role": role, "content": _flatten_content(m.get("content"), keep_images=keep_images)}
        if role == "assistant" and m.get("tool_calls"):
            calls = []
            for i, tc in enumerate(m["tool_calls"]):
                fn = tc.get("function") or {}
                calls.append({
                    "index": i,
                    "id": tc.get("id") or f"call_{uuid.uuid4().hex[:24]}",
                    "type": "function",
                    # 键名必须是 function_call：写 function 会被上游
                    # "ToolCall read field 4 'FunctionCall' ... Name is not set" 拒绝
                    "function_call": {
                        "name": fn.get("name") or "",
                        "arguments": fn.get("arguments") or "{}",
                    },
                })
            out["tool_calls"] = calls
        if role == "tool":
            if not m.get("tool_call_id"):
                raise ValueError("Trae SOLO tool message requires tool_call_id")
            out["tool_call_id"] = m["tool_call_id"]
        msgs.append(out)

    body: dict = {
        "messages": msgs,
        "model": model,
        "config_name": model,
        "function": function,
        "stream": True,
    }
    # 思考档：apply_model_effort 已把档位名换成 Trae wire 词汇（light/high/...）
    if oa.get("reasoning_effort"):
        body["reasoning_effort"] = oa["reasoning_effort"]
    tools = oa.get("tools") or []
    if tools:
        conv = []
        for t in tools:
            fn = t.get("function") or {}
            if not fn.get("name"):
                continue
            conv.append({
                "type": "function",
                "function": {
                    "name": fn["name"],
                    "description": fn.get("description") or "",
                    # 必须是 JSON **字符串**，传对象上游解析失败
                    "parameters": json.dumps(fn.get("parameters") or
                                             {"type": "object", "properties": {}}),
                },
            })
        if conv:
            body["tools"] = conv
    return body


# ─────────────────── 响应：Trae SSE → OpenAI chunk ───────────────────

def _oa_chunk(model: str, delta: dict, finish: str | None = None, usage: dict | None = None) -> str:
    obj: dict = {
        "id": "chatcmpl-trae",
        "object": "chat.completion.chunk",
        "created": int(time.time()),
        "model": model,
        "choices": [{"index": 0, "delta": delta, "finish_reason": finish}],
    }
    if usage:
        obj["usage"] = usage
    return "data: " + json.dumps(obj, ensure_ascii=False, separators=(",", ":")) + "\n\n"


def _trae_tool_calls(raw) -> list:
    """Trae 的 tool_calls → OpenAI 形（function_call 改回 function）。"""
    out = []
    for tc in raw or []:
        if not isinstance(tc, dict):
            continue
        fn = tc.get("function_call") or tc.get("function") or {}
        item: dict = {"index": tc.get("index", 0), "type": "function", "function": {
            "name": fn.get("name") or "",
            "arguments": fn.get("arguments") or "",
        }}
        if tc.get("id"):
            item["id"] = tc["id"]
        out.append(item)
    return out


# ───────────────────────── 网关本体 ─────────────────────────

app = FastAPI(title="trae-bridge")


@app.middleware("http")
async def _strip_anthropic_prefix(request: Request, call_next):
    """同时接受 / 与 /anthropic 两种前缀。

    为什么需要：ccconfig 的 init-llm.sh 用 base_url 里有没有 /anthropic 来判断
    该端点是原生 Anthropic 还是 OpenAI-only（preset_bridge_mode / test_llm 都靠它）。
    本网关就是原生 Anthropic 协议，把 base_url 写成 http://127.0.0.1:8899/anthropic
    就能让它走「直连 + 探 /v1/messages 等 message_stop」这条路，不误判成需要
    openai_bridge 中转。Claude Code 则把 base 当作前缀拼 /v1/messages，同样成立。
    """
    path = request.scope.get("path") or ""
    if path.startswith("/anthropic"):
        rest = path[len("/anthropic"):]
        request.scope["path"] = rest or "/"
    return await call_next(request)


STATE = {
    "model": os.environ.get("TRAE_MODEL", "kimi-k2.6"),
    "function": os.environ.get("TRAE_FUNCTION", DEFAULT_FUNCTION),
    "debug": bool(os.environ.get("TRAE_BRIDGE_DEBUG")),
}


def _load_vision() -> dict:
    """读全局视觉路由配置（7B 设定，跟主 LLM 预设无关）。

    配置落在 ccprivate/conf/vision.json（全局唯一，不分预设）：
      {"provider": "zhipu" | "trae", "model": ..., "upstream": ..., "key_preset": ...}
      zhipu = 外部智谱（OpenAI 协议改发，key 查 mlayer.json/llm.json）
      trae  = Trae 订阅内视觉模型（keep_images 直发，复用订阅额度）

    why 独立文件而不是塞进每个 LLM 预设：7B 只管视觉、3A 只管 LLM，两个正交
    维度不该捆绑 —— 主模型切什么都不影响视觉后端选择。

    环境变量仍可覆盖（测试/临时切换用）：TRAE_VISION_MODEL/UPSTREAM/KEY。
    """
    # 先看全局 vision.json
    vcfg = {}
    try:
        vcfg = json.loads((Path.home() / "git/ccprivate/conf/vision.json").read_text())
    except Exception:  # noqa: BLE001
        pass
    # 兼容旧模式：vision.json 不存在时回落 merged 缓存里当前预设的 vision_* 字段
    llm = {}
    if not vcfg:
        cfg_path = Path(os.environ.get("TRAE_VISION_CFG",
                                       str(Path.home() / ".cache/llm-merged.json")))
        cur_path = Path(os.environ.get("TRAE_VISION_CURRENT",
                                       str(Path.home() / ".claude/llm-current")))
        cur = ""
        try:
            cur = cur_path.read_text().strip()
        except Exception:  # noqa: BLE001
            pass
        try:
            llm = json.loads(cfg_path.read_text()).get("llms", {}).get(cur, {})
        except Exception:  # noqa: BLE001
            llm = {}
    provider = os.environ.get("TRAE_VISION_PROVIDER") or vcfg.get("provider") or (
        "trae" if (llm.get("vision_model") or "").lower().startswith(("doubao", "kimi")) else "zhipu")
    model = os.environ.get("TRAE_VISION_MODEL") or vcfg.get("model") or llm.get("vision_model") or ""
    upstream = (os.environ.get("TRAE_VISION_UPSTREAM") or vcfg.get("upstream")
                or llm.get("vision_upstream") or "")
    key = os.environ.get("TRAE_VISION_KEY") or ""
    if not key and provider == "zhipu":
        ref = vcfg.get("key_preset") or llm.get("vision_key_preset") or ""
        if ref:
            for kf in ("mlayer.json", "llm.json"):
                try:
                    k = json.loads((Path.home() / f"git/ccprivate/conf/{kf}").read_text()
                                   ).get("llms", {}).get(ref, {}).get("key", "")
                    if k:
                        key = k
                        break
                except Exception:  # noqa: BLE001
                    pass
    return {"provider": provider, "model": model, "upstream": upstream, "key": key}


VISION = _load_vision()

creds = CredentialStore()
_identity: TraeIdentity | None = None
_client: httpx.AsyncClient | None = None


def identity() -> TraeIdentity:
    global _identity
    if _identity is None:
        _identity = TraeIdentity.load()
    return _identity


@app.on_event("startup")
async def _startup():
    global _client
    _client = httpx.AsyncClient(
        timeout=httpx.Timeout(300.0, connect=30.0, read=180.0, write=120.0, pool=30.0),
        trust_env=False,
    )
    creds.load()
    _log(f"upstream={CHAT_BASE} default_model={STATE['model']}")


@app.on_event("shutdown")
async def _shutdown():
    if _client is not None:
        await _client.aclose()


@app.get("/health")
async def health():
    c = creds.credential
    return {
        "ok": True,
        "upstream": CHAT_BASE,
        "model": STATE["model"],
        "function": STATE["function"],
        "account": c.get("accountName"),
        "token_expires_in_s": max(0, int((c["expiresAtMs"] - time.time() * 1000) / 1000)),
    }


@app.get("/v1/models")
async def models():
    """Claude Code 的 gateway model discovery 会 GET {base}/v1/models?limit=1000，
    并且**只保留 id 匹配 /(claude|anthropic)/i 的条目**（二进制里写死的过滤）。
    所以这里把 Trae 的 config_name 全部包成 claude-trae-<name>，既过过滤又能反解。"""
    data = [{"id": CLAUDE_PREFIX + STATE["model"], "object": "model", "created": 0,
             "owned_by": "trae", "display_name": f"Trae {STATE['model']}"}]
    for name in await _trae_directory():
        data.append({"id": CLAUDE_PREFIX + name, "object": "model", "created": 0,
                     "owned_by": "trae", "display_name": f"Trae {name}"})
    for alias, target in CLAUDE_ALIASES.items():
        data.append({"id": alias, "object": "model", "created": 0, "owned_by": "trae",
                     "display_name": f"Trae {target} (alias)"})
    seen, uniq = set(), []
    for d in data:
        if d["id"] in seen:
            continue
        seen.add(d["id"])
        uniq.append(d)
    return {"object": "list", "data": uniq, "has_more": False,
            "first_id": uniq[0]["id"], "last_id": uniq[-1]["id"]}


def resolve_model(requested: str | None) -> str:
    """把 Claude Code 送上来的 model 名翻回 Trae 的 config_name。"""
    m = (requested or "").strip()
    if not m:
        return STATE["model"]
    if m.startswith(CLAUDE_PREFIX):
        return m[len(CLAUDE_PREFIX):]
    if m in CLAUDE_ALIASES:
        return CLAUDE_ALIASES[m]
    if m.startswith("claude-") or m.startswith("anthropic-"):
        return STATE["model"]
    return m


def function_for_model(model: str) -> str:
    """按模型选频道：命中前缀规则用规则值，否则全局 STATE['function']。"""
    for prefix, fn in MODEL_FUNCTION_RULES:
        if model.startswith(prefix):
            return fn
    return STATE["function"]


def apply_model_effort(oa: dict, model: str):
    """模型级默认思考档：客户端没给 effort 时补上，并把档位名换成 Trae wire 名。

    openai_bridge.anthropic_to_openai_req 已经把 CC 的 thinking/output_config 翻成
    OpenAI 的 reasoning_effort（low/medium/high）；Trae wire 只认 light/medium/high/
    extra_high/max —— 这里统一改名，未知名的档位删除（与插件行为一致）。
    """
    e = oa.get("reasoning_effort")
    if not e:
        e = MODEL_EFFORT_DEFAULTS.get(model)
        if e:
            oa["reasoning_effort"] = e
            oa.setdefault("enable_thinking", True)
    if e in WIRE_EFFORT_MAP:
        oa["reasoning_effort"] = WIRE_EFFORT_MAP[e]
    else:
        oa.pop("reasoning_effort", None)


@app.post("/v1/messages/count_tokens")
async def count_tokens(request: Request):
    """Claude Code 会调 /v1/messages/count_tokens?beta=true 估上下文占用。
    Trae 没有对应接口，这里按 ~3.2 字符/token 粗估——只影响客户端显示的上下文百分比，
    不参与任何路由决策，误差可接受（比 404 让它走兜底路径更稳）。"""
    body = await request.json()
    chars = 0
    for m in body.get("messages") or []:
        c = m.get("content")
        if isinstance(c, str):
            chars += len(c)
        elif isinstance(c, list):
            for blk in c:
                if isinstance(blk, dict):
                    chars += len(json.dumps(blk, ensure_ascii=False))
    sys_prompt = body.get("system")
    if isinstance(sys_prompt, str):
        chars += len(sys_prompt)
    elif isinstance(sys_prompt, list):
        chars += len(json.dumps(sys_prompt, ensure_ascii=False))
    return {"input_tokens": max(1, int(chars / 3.2))}


async def _trae_directory() -> list[str]:
    """拉 Trae 真实可调模型目录（get_detail_param），10 分钟缓存，失败静默。

    只拉 STATE['function'] 一个频道会漏模型（glm-5.3 只在 solo_work_remote），
    所以把全局频道 + 各模型规则频道全部拉一遍合并去重。"""
    now = time.monotonic()
    if _DIR_CACHE["at"] and now - _DIR_CACHE["at"] < 600:
        return _DIR_CACHE["names"]
    fns = [STATE["function"]] + [fn for _, fn in MODEL_FUNCTION_RULES]
    names: list[str] = []
    try:
        cred = await creds.ensure(_client)
        idn = identity()
        for fn in dict.fromkeys(fns):  # 去重保序
            hdrs = idn.headers(cred["accessToken"], cred.get("userId") or "")
            hdrs["Accept"] = "application/json"
            r = await _client.post(
                CHAT_BASE + MODELS_PATH,
                headers=hdrs,
                json={"function": fn, "config_names": None, "need_prompt": False,
                      "current_config_info": None, "poly_prompt": True, "mode_type": None,
                      "agent_type": None},
                timeout=30,
            )
            if r.status_code == 200:
                for item in (r.json().get("config_info_list") or []):
                    name = item.get("config_name")
                    if name and name not in _NON_MODEL_NAMES and not _TOOL_ROW.match(name) \
                            and name not in names:
                        names.append(name)
    except Exception as e:  # noqa: BLE001
        _log(f"directory fetch failed: {e}")
    if names:
        _DIR_CACHE["at"], _DIR_CACHE["names"] = time.monotonic(), names
    return names or _DIR_CACHE["names"]


@app.post("/v1/messages")
async def messages(request: Request):
    anth = await request.json()
    stream = bool(anth.get("stream"))
    model = resolve_model(anth.get("model"))

    _REQ_SEQ[0] += 1
    req_no = _REQ_SEQ[0]

    # 视觉路由：带图请求改发视觉模型，纯文本照常走 Trae。
    # 两种 provider（7B 全局二选一）：
    #   zhipu  = 外部智谱 glm-4.6v-flash（OpenAI 协议改发，key 在 mlayer.json）
    #   trae   = Trae 订阅内视觉模型（Doubao-Seed-2.1-Turbo / kimi-k2.6 等，
    #            复用订阅额度，无限流 key；实测见 option-trae/README.md）
    # why 放在网关内：_bridge_supported() 拒绝 loopback/anthropic 端点，外部桥接
    # 协议层接不上；trae provider 还能直接复用 _stream/_collect 的 SSE 状态机。
    if VISION["model"] and ob._body_has_image(anth):
        if VISION.get("provider") == "trae":
            oa = ob.anthropic_to_openai_req(anth, VISION["model"], allow_thinking=False)
            oa.pop("reasoning_effort", None)
            try:
                vbody = openai_to_trae_body(oa, VISION["model"],
                                            function_for_model(VISION["model"]), keep_images=True)
            except ValueError as e:
                return JSONResponse(status_code=400, content={
                    "type": "error", "error": {"type": "invalid_request_error", "message": str(e)}})
            if stream:
                return StreamingResponse(
                    _stream(anth, vbody, VISION["model"], req_no),
                    media_type="text/event-stream",
                    headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})
            return await _collect(anth, vbody, VISION["model"], req_no)
        return await _vision_messages(anth, stream, req_no)

    oa = ob.anthropic_to_openai_req(anth, model, allow_thinking=True)
    apply_model_effort(oa, model)
    try:
        trae_body = openai_to_trae_body(oa, model, function_for_model(model))
    except ValueError as e:
        return JSONResponse(status_code=400, content={
            "type": "error", "error": {"type": "invalid_request_error", "message": str(e)}})

    if stream:
        return StreamingResponse(
            _stream(anth, trae_body, model, req_no),
            media_type="text/event-stream",
            headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
        )
    return await _collect(anth, trae_body, model, req_no)


async def _vision_messages(anth: dict, stream: bool, req_no: int):
    """带图请求 → 外部视觉模型（OpenAI 协议直发，不经 Trae）。

    非流式直接拿完整响应再转 SSE 下发：视觉模型只处理单轮看图，逐字流式没有价值，
    而多一条流式路径就多一处要维护的 SSE 状态机。
    """
    vmodel = VISION["model"]
    base = (VISION["upstream"] or "").rstrip("/")
    target = base + ("/chat/completions" if re.search(r"/v\d+(/|$)", base) else "/v1/chat/completions")
    oa = ob.anthropic_to_openai_req(anth, vmodel, allow_thinking=False)
    oa.pop("reasoning_effort", None)
    headers = {"Authorization": f"Bearer {VISION['key']}", "Content-Type": "application/json"}
    try:
        r = await _client.post(target, headers=headers, json=oa)
    except Exception as e:  # noqa: BLE001
        return _vision_error(f"vision upstream: {e}")
    if r.status_code != 200:
        return _vision_error(f"vision upstream http {r.status_code}: {r.text[:300]}")
    try:
        payload = r.json()
    except Exception:  # noqa: BLE001
        return _vision_error("vision upstream returned non-JSON")
    resp = ob.openai_to_anthropic_resp(payload, f"msg_vision_{req_no}")
    if stream:
        return StreamingResponse(
            iter([ob.anthropic_resp_to_sse(resp)]),
            media_type="text/event-stream",
            headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
        )
    return resp


def _vision_error(msg: str):
    return JSONResponse(status_code=502, content={
        "type": "error", "error": {"type": "api_error", "message": msg}})


async def _collect(anth, trae_body, model, req_no):
    """非流式：把 Trae 流读完拼成一条 Anthropic message。"""
    text_parts, tool_calls, usage, finish = [], [], {}, None
    async for ev, payload in _trae_events(trae_body):
        if ev == "output":
            d = payload
            if d.get("response"):
                text_parts.append(d["response"])
            if d.get("tool_calls"):
                for tc in _trae_tool_calls(d["tool_calls"]):
                    slot = tc["index"]
                    while len(tool_calls) <= slot:
                        tool_calls.append({"id": "", "name": "", "args": ""})
                    cur = tool_calls[slot]
                    if tc.get("id"):
                        cur["id"] = tc["id"]
                    fn = tc["function"]
                    if fn.get("name"):
                        cur["name"] = fn["name"]
                    if fn.get("arguments"):
                        cur["args"] += fn["arguments"]
        elif ev == "usage":
            usage = payload
        elif ev == "done":
            finish = payload.get("finish_reason")
        elif ev == "error":
            return JSONResponse(status_code=502, content={
                "type": "error",
                "error": {"type": "api_error", "message": payload.get("message", "trae error")}})

    content = []
    text = "".join(text_parts)
    if text:
        content.append({"type": "text", "text": text})
    for tc in tool_calls:
        try:
            args = json.loads(tc["args"] or "{}")
        except Exception:  # noqa: BLE001
            args = {"_raw": tc["args"]}
        content.append({"type": "tool_use", "id": tc["id"] or f"toolu_{uuid.uuid4().hex[:24]}",
                        "name": tc["name"], "input": args})
    stop = "tool_use" if tool_calls else "end_turn"
    return {
        "id": f"msg_trae_{req_no}", "type": "message", "role": "assistant", "model": model,
        "content": content, "stop_reason": stop, "stop_sequence": None,
        "usage": {"input_tokens": usage.get("prompt_tokens", 0),
                  "output_tokens": usage.get("completion_tokens", 0)},
    }


async def _trae_events(body: dict):
    """POST 到 Trae，逐个吐出 (事件名, data dict)。含 401 重试一次。"""
    assert _client is not None
    cred = await creds.ensure(_client)
    idn = identity()
    url = CHAT_BASE + CHAT_PATH
    hdrs = idn.headers(cred["accessToken"], cred.get("userId") or "")

    for attempt in (0, 1):
        resp = await _client.send(
            _client.build_request("POST", url, headers=hdrs, json=body), stream=True)
        if resp.status_code == 401 and attempt == 0:
            await resp.aread()
            await resp.aclose()
            cred = await creds.ensure(_client, force=True)
            hdrs = idn.headers(cred["accessToken"], cred.get("userId") or "")
            continue
        break

    try:
        if resp.status_code != 200:
            text = (await resp.aread()).decode(errors="replace")
            yield "error", {"message": f"trae upstream http {resp.status_code}: {text[:400]}"}
            return
        ev = ""
        async for line in resp.aiter_lines():
            if not line:
                continue
            if line.startswith("event:"):
                ev = line[6:].strip()
                continue
            if not line.startswith("data:"):
                continue
            raw = line[5:].strip()
            if not raw or raw == "[DONE]":
                continue
            try:
                d = json.loads(raw)
            except Exception:  # noqa: BLE001
                continue
            if ev == "error" or (isinstance(d, dict) and d.get("error")):
                yield "error", d.get("error") or d
            elif ev == "token_usage":
                yield "usage", d
            elif ev == "done":
                yield "done", d
            elif ev in ("output", "extra_info"):
                yield "output", d
            # metadata / timing_cost / 其它：忽略
    finally:
        await resp.aclose()


async def _stream(anth, trae_body, model, req_no):
    """Trae SSE → OpenAI chunk → Anthropic SSE。"""
    msg_id = f"msg_trae_{req_no}"
    sse: dict = {"started": False, "finished": False}
    saw_tool = False
    usage: dict = {}

    def render(chunk: str) -> str:
        out = ob.openai_chunk_to_anthropic_sse(chunk, msg_id, model, sse)
        return out or ""

    async def emit_ping():
        return ": ping\n\n"

    try:
        last_out = time.monotonic()
        async for ev, payload in _trae_events(trae_body):
            if ev == "error":
                msg = payload.get("message") if isinstance(payload, dict) else str(payload)
                err = json.dumps({"type": "error", "error": {"type": "api_error", "message": msg}},
                                 ensure_ascii=False, separators=(",", ":"))
                yield f"event: error\ndata: {err}\n\n"
                yield 'event: message_stop\ndata: {"type":"message_stop"}\n\n'
                return
            if ev == "usage":
                usage = payload
                continue
            if ev == "done":
                if payload.get("finish_reason"):
                    finish = "tool_calls" if saw_tool else payload["finish_reason"]
                    for piece in (render(_oa_chunk(model, {}, finish)),):
                        if piece:
                            yield piece
                            last_out = time.monotonic()
                if usage:
                    u = {"prompt_tokens": usage.get("prompt_tokens", 0),
                         "completion_tokens": usage.get("completion_tokens", 0)}
                    piece = render(_oa_chunk(model, {}, None, u))
                    if piece:
                        yield piece
                piece = render("data: [DONE]\n\n")
                if piece:
                    yield piece
                return

            d = payload
            delta: dict = {}
            if d.get("reasoning_content"):
                # 思考内容不转 thinking 块：Anthropic 的 thinking 块要 signature，
                # 凭空造会污染下游缓存；丢弃即可（长时间静默由 ping 兜住）
                pass
            if d.get("response"):
                delta["content"] = d["response"]
            tcs = _trae_tool_calls(d.get("tool_calls"))
            if tcs:
                saw_tool = True
                delta["tool_calls"] = tcs
            if not delta:
                if time.monotonic() - last_out >= 10.0:
                    last_out = time.monotonic()
                    yield await emit_ping()
                continue
            piece = render(_oa_chunk(model, delta))
            if piece:
                yield piece
                last_out = time.monotonic()

        # 上游没发 done 就断流：补齐收尾，否则 CC 一直等 message_stop
        piece = render("data: [DONE]\n\n")
        if piece:
            yield piece
    except Exception as e:  # noqa: BLE001
        err = json.dumps({"type": "error", "error": {"type": "api_error", "message": f"trae-bridge: {e}"}},
                         ensure_ascii=False, separators=(",", ":"))
        yield f"event: error\ndata: {err}\n\n"
        yield 'event: message_stop\ndata: {"type":"message_stop"}\n\n'


def main():
    global AUTH_PATH
    ap = argparse.ArgumentParser(description="Trae → Anthropic Messages gateway")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8899)
    ap.add_argument("--model", default=STATE["model"])
    ap.add_argument("--function", default=STATE["function"])
    ap.add_argument("--auth-path", default=str(AUTH_PATH))
    ap.add_argument("--debug", action="store_true")
    a = ap.parse_args()

    STATE["model"] = a.model
    STATE["function"] = a.function
    STATE["debug"] = a.debug
    AUTH_PATH = Path(a.auth_path)
    creds.path = AUTH_PATH

    import uvicorn
    uvicorn.run(app, host=a.host, port=a.port, log_level="info")


if __name__ == "__main__":
    main()
