#!/usr/bin/env python3
"""Generate 10-slide PPT with conservative sizing — no overflow, proper padding."""
import os, re

TP = "/home/francis/git/_ext/ppt-master/skills/ppt-master/templates/layouts/professional_blue"
OUT = "/tmp/pptx_project/svg_fc"
os.makedirs(OUT, exist_ok=True)

# ── Design constants ──
B = "#4472C4"      # blue
D = "#1F2329"      # dark text
G = "#8F959E"      # gray
W = "#FFFFFF"
LG = "#F5F7FA"     # light bg
LB = "#BBE2FF"     # light blue accent
F = "Arial, Microsoft YaHei, sans-serif"
ORG = "运行维护中心 &amp; AI技术组"

# Font scale (px in SVG at 1280×720 canvas):
# Title: 30px, Section header: 20px, Body: 18px, Small: 15px, Note: 13px
FT = "30"   # page title
FH = "20"   # section header bar
FB = "18"   # body text
FS = "15"   # small notes
FN = "13"   # tiny notes/footer

# ── Helpers ──
def load(n):
    with open(os.path.join(TP, n)) as f: return f.read()

def sub(s, **kw):
    for k, v in kw.items(): s = s.replace("{{%s}}" % k, str(v))
    return s

def save(n, s):
    with open(os.path.join(OUT, n), "w") as f: f.write(s)
    print(f"  {n}")

def content_page(num, chap, title, body, org=ORG):
    s = load("03_content.svg")
    s = sub(s, CHAPTER_NUM=chap, PAGE_TITLE=title, PAGE_NUM=num, ORG_SHORT=org)
    return s.replace("{{CONTENT_AREA}}", body)

# ═══════════════════════════════════════
# 1. Cover
# ═══════════════════════════════════════
s = load("01_cover.svg")
s = sub(s, TITLE="AI 算力机部署地点建议",
        SUBTITLE="", AUTHOR="运行维护中心 &amp; AI技术组", DATE="2026 年 6 月", ORG_SHORT="")
save("01_cover.svg", s)

# ═══════════════════════════════════════
# 2. TOC
# ═══════════════════════════════════════
s = load("02_toc.svg")
items = [("决策建议", "核心结论与部署理由"),
         ("背景说明", "算力机规模与负载特征"),
         ("多维度对比", "成本 · 技术 · 运维"),
         ("风险与时间线", "风险对策 + 关键里程碑")]
for i, (t, d) in enumerate(items):
    s = s.replace(f"{{{{TOC_ITEM_{i+1}_TITLE}}}}", t)
    s = s.replace(f"{{{{TOC_ITEM_{i+1}_DESC}}}}", d)
s = sub(s, PAGE_NUM="02")
save("02_toc.svg", s)

# ═══════════════════════════════════════
# 3. Decision (core recommendation + 4 cards)
# ═══════════════════════════════════════
cards = [
    ("1", "电力成本更低",
     "成都 0.78 元/度 vs 北京 0.87 元/度",
     "8 台年省 9.6–19.2 万元（50%–100% 负载）",
     "机柜资源充裕、独立区域制冷效率更优"),
    ("2", "组网与扩展更优",
     "24 台集中部署 → 一对交换机（约 134 万）",
     "北京分两区 → +60% 交换机费（约 214 万）",
     "成都机房空置，改造风险低/无生产影响"),
    ("3", "技术条件相当",
     "成都→北京专线延迟 18–25ms",
     "网络延迟占 LLM 推理总延迟 &lt; 10%",
     "贵州 22–28ms 已稳定支撑 11 台生产推理"),
    ("4", "运维能力全覆盖",
     "系统层以上：AI组负责（带外管理远程）",
     "基础运维：属地运维工程师负责",
     "运维遵循运行维护中心各项管理要求"),
]
body = f"""<!-- KEY MESSAGE -->
    <rect x="96" y="128" width="1094" height="42" rx="6" fill="#F0F4FF" stroke="#BBE2FF" stroke-width="1"/>
    <text x="640" y="155" text-anchor="middle" font-family="{F}" font-size="22" font-weight="bold" fill="{B}">建议：首批 2 台 AI 算力机部署于成都机房</text>"""
for i, (n, ct, l1, l2, l3) in enumerate(cards):
    col, row = i % 2, i // 2
    cx = 96 + col * 551
    cy = 182 + row * 248
    cw = 543
    ch = 230
    body += f"""
    <rect x="{cx}" y="{cy}" width="{cw}" height="{ch}" rx="6" fill="{LG}" stroke="#E5E6EB" stroke-width="1"/>
    <rect x="{cx}" y="{cy}" width="{cw}" height="4" rx="2" fill="{B}"/>
    <circle cx="{cx+28}" cy="{cy+42}" r="15" fill="{B}"/>
    <text x="{cx+28}" y="{cy+48}" text-anchor="middle" font-family="Arial, sans-serif" font-size="{FS}" font-weight="bold" fill="{W}">{n}</text>
    <text x="{cx+52}" y="{cy+48}" font-family="{F}" font-size="{FH}" font-weight="bold" fill="{B}">{ct}</text>
    <text x="{cx+16}" y="{cy+82}" font-family="{F}" font-size="{FB}" fill="{D}">{l1}</text>
    <text x="{cx+16}" y="{cy+110}" font-family="{F}" font-size="{FB}" fill="{D}">{l2}</text>
    <text x="{cx+16}" y="{cy+138}" font-family="{F}" font-size="{FS}" fill="{G}">{l3}</text>"""
s = content_page("03", "01", "核心建议", body)
save("03_decision.svg", s)

# ═══════════════════════════════════════
# 4. Background
# ═══════════════════════════════════════
body = f"""<rect x="96" y="128" width="1094" height="36" rx="4" fill="{B}"/>
    <text x="640" y="152" text-anchor="middle" font-family="{F}" font-size="{FH}" font-weight="bold" fill="{W}">算力机技术概要（真武 M810 算力卡）</text>
    <text x="112" y="198" font-family="{F}" font-size="{FB}" fill="{D}"><tspan font-weight="bold" fill="{B}">设备：</tspan>2台阿里算力机，每台 16 块真武 M810 算力卡，非 CUDA 兼容，独立软件栈</text>
    <text x="112" y="226" font-family="{F}" font-size="{FB}" fill="{D}"><tspan font-weight="bold" fill="{B}">规格：</tspan>96GB HBM2e · 互联带宽 700 GB/s · PCIe 5.0 x16 · 典型 400W</text>
    <text x="112" y="254" font-family="{F}" font-size="{FB}" fill="{D}"><tspan font-weight="bold" fill="{B}">算力：</tspan>FP16/BF16 ≈ 920 TFLOPS（对标 H20）· 8 卡满载约 16kW · 已出货 56 万片</text>

    <rect x="96" y="316" width="1094" height="36" rx="4" fill="{B}"/>
    <text x="640" y="340" text-anchor="middle" font-family="{F}" font-size="{FH}" font-weight="bold" fill="{W}">部署规划与负载特征</text>

    <rect x="96" y="368" width="356" height="40" rx="4" fill="{B}"/>
    <text x="274" y="393" text-anchor="middle" font-family="Arial, sans-serif" font-size="{FH}" font-weight="bold" fill="{W}">2026.09：2 台上线</text>
    <text x="460" y="393" font-family="Arial, sans-serif" font-size="{FH}" fill="{B}">→</text>
    <rect x="480" y="368" width="356" height="40" rx="4" fill="{B}"/>
    <text x="658" y="393" text-anchor="middle" font-family="Arial, sans-serif" font-size="{FH}" font-weight="bold" fill="{W}">2027.Q1：扩容至 8 台</text>
    <text x="844" y="393" font-family="Arial, sans-serif" font-size="{FH}" fill="{B}">→</text>
    <rect x="864" y="368" width="326" height="40" rx="4" fill="{B}"/>
    <text x="1027" y="393" text-anchor="middle" font-family="Arial, sans-serif" font-size="{FH}" font-weight="bold" fill="{W}">2028：可扩展至 24 台</text>

    <text x="112" y="450" font-family="{F}" font-size="{FB}" fill="{D}"><tspan font-weight="bold" fill="{B}">负载：</tspan>LLM 推理为主，兼有训练。推理延迟数百 ms 级，网络 &lt; 10%，训练不敏感</text>
    <text x="112" y="480" font-family="{F}" font-size="{FB}" fill="{D}"><tspan font-weight="bold" fill="{B}">选型：</tspan>2 台已发中选通知书，6 台已上报需求。模型部署成都在地完成，不依赖专线传大文件</text>

    <rect x="96" y="512" width="1094" height="36" rx="4" fill="#F0F4FF" stroke="#BBE2FF" stroke-width="1"/>
    <text x="640" y="536" text-anchor="middle" font-family="{F}" font-size="{FS}" fill="{B}">分析维度：成本 · 技术 · 运维 · 风险，结合贵州机房生产运行经验作为延迟参照基准</text>"""
s = content_page("04", "01", "背景说明", body)
save("04_background.svg", s)

# ═══════════════════════════════════════
# 5. Cost table
# ═══════════════════════════════════════
rows = [
    ("维度", "北京", "成都", "差异"),
    ("电价（元/度）", "0.87", "0.78", "成都低 10.3%"),
    ("单机月电费（50% / 额定）", "0.95 / 1.90 万", "0.85 / 1.70 万", "月省 0.10 / 0.20 万"),
    ("8台年度电费（50% / 额定）", "91.2 / 182.4 万", "81.6 / 163.2 万", "年省 9.6 / 19.2 万"),
    ("交换机（24台规模）", "2对 ≈ 214 万", "1对 ≈ 134 万", "成都省 60%"),
    ("专线扩容（150→200M）", "—", "+3.63 万/月", "仅带宽不足时触发"),
    ("配电改造", "设备已包含", "设备已包含", "无差异"),
]
cx_t = [96, 340, 560, 760]
cw_t = [235, 210, 190, 430]
row_h = 60
body = ""
for ri, row in enumerate(rows):
    y = 128 + ri * row_h
    is_h = ri == 0
    for ci, cell in enumerate(row):
        bg = B if is_h else (LG if ri % 2 == 1 else W)
        fg = W if is_h else (B if ci == 3 else D)
        fw = "bold" if (is_h or ci == 3) else "normal"
        fs = FH if is_h else FB
        body += f'<rect x="{cx_t[ci]}" y="{y}" width="{cw_t[ci]}" height="{row_h}" fill="{bg}" stroke="#E5E6EB" stroke-width="0.5"/>\n'
        body += f'<text x="{cx_t[ci]+12}" y="{y+38}" font-family="{F}" font-size="{fs}" font-weight="{fw}" fill="{fg}">{cell}</text>\n'
body += f'<text x="96" y="{128 + len(rows)*row_h + 20}" font-family="{F}" font-size="{FN}" fill="{G}">注：成都大工业用电 0.78 元/度。单机额定功率约 30kW（含主机 + 制冷 + 交换机）。实际负载按 50% 预估。</text>'
s = content_page("05", "02", "成本维度对比", body)
save("05_cost.svg", s)

# ═══════════════════════════════════════
# 6. Tech + Latency
# ═══════════════════════════════════════
body = f"""<rect x="96" y="128" width="1094" height="36" rx="4" fill="{B}"/>
    <text x="640" y="152" text-anchor="middle" font-family="{F}" font-size="{FH}" font-weight="bold" fill="{W}">技术维度：两地技术条件相当，成都组网与扩展性更优</text>

    <!-- 3 tech cards -->
    <rect x="96" y="176" width="355" height="96" rx="6" fill="#F0F4FF" stroke="#BBE2FF" stroke-width="1"/>
    <text x="112" y="204" font-family="{F}" font-size="{FH}" font-weight="bold" fill="{B}">网络延迟</text>
    <text x="112" y="228" font-family="{F}" font-size="{FB}" fill="{D}">北京 &lt; 2ms · 成都 18–25ms</text>
    <text x="112" y="252" font-family="{F}" font-size="{FS}" fill="{B}">✓ 贵州 22–28ms 已验证可行</text>

    <rect x="463" y="176" width="355" height="96" rx="6" fill="#F0F4FF" stroke="#BBE2FF" stroke-width="1"/>
    <text x="479" y="204" font-family="{F}" font-size="{FH}" font-weight="bold" fill="{B}">专线带宽</text>
    <text x="479" y="228" font-family="{F}" font-size="{FB}" fill="{D}">150M 专线，峰值利用率 90%</text>
    <text x="479" y="252" font-family="{F}" font-size="{FS}" fill="{B}">✓ 8 台仅需 8M，无需立即扩容</text>

    <rect x="830" y="176" width="360" height="96" rx="6" fill="#F0F4FF" stroke="#BBE2FF" stroke-width="1"/>
    <text x="846" y="204" font-family="{F}" font-size="{FH}" font-weight="bold" fill="{B}">PUE · 供电 · 灾备</text>
    <text x="846" y="228" font-family="{F}" font-size="{FB}" fill="{D}">成都独立区域 PUE 预期更优</text>
    <text x="846" y="252" font-family="{F}" font-size="{FS}" fill="{B}">✓ 供电已含改造 · 备用专线就绪</text>

    <!-- Latency chain -->
    <rect x="96" y="288" width="1094" height="36" rx="4" fill="{B}"/>
    <text x="640" y="312" text-anchor="middle" font-family="{F}" font-size="{FH}" font-weight="bold" fill="{W}">LLM 推理端到端延迟构成（网络占比 &lt; 10%）</text>

    <rect x="96" y="340" width="200" height="56" rx="6" fill="{B}"/>
    <text x="196" y="367" text-anchor="middle" font-family="{F}" font-size="{FS}" fill="{W}">用户请求</text>
    <text x="196" y="386" text-anchor="middle" font-family="Arial, sans-serif" font-size="{FN}" fill="#B0C4DE">5–20 ms</text>

    <text x="304" y="373" font-family="Arial, sans-serif" font-size="{FH}" fill="{B}">→</text>

    <rect x="325" y="340" width="190" height="56" rx="6" fill="{B}"/>
    <text x="420" y="367" text-anchor="middle" font-family="{F}" font-size="{FS}" fill="{W}">API 网关</text>
    <text x="420" y="386" text-anchor="middle" font-family="Arial, sans-serif" font-size="{FN}" fill="{W}" fill-opacity="0.7">业务逻辑</text>

    <text x="523" y="373" font-family="Arial, sans-serif" font-size="{FH}" fill="{B}">→</text>

    <rect x="544" y="340" width="210" height="56" rx="6" fill="{B}"/>
    <text x="649" y="367" text-anchor="middle" font-family="{F}" font-size="{FS}" fill="{W}">专线往返</text>
    <text x="649" y="386" text-anchor="middle" font-family="Arial, sans-serif" font-size="{FN}" fill="{W}" fill-opacity="0.85">18–25 ms</text>

    <text x="762" y="373" font-family="Arial, sans-serif" font-size="{FH}" fill="{B}">→</text>

    <rect x="783" y="340" width="210" height="56" rx="6" fill="{B}"/>
    <text x="888" y="367" text-anchor="middle" font-family="{F}" font-size="{FS}" fill="{W}">Token 生成</text>
    <text x="888" y="386" text-anchor="middle" font-family="Arial, sans-serif" font-size="{FN}" fill="#B0C4DE">200–800 ms</text>

    <text x="1001" y="373" font-family="Arial, sans-serif" font-size="{FH}" fill="{B}">→</text>

    <rect x="1022" y="340" width="168" height="56" rx="6" fill="{B}"/>
    <text x="1106" y="367" text-anchor="middle" font-family="{F}" font-size="{FS}" fill="{W}">响应用户</text>
    <text x="1106" y="386" text-anchor="middle" font-family="Arial, sans-serif" font-size="{FN}" fill="#B0C4DE">&lt; 5 ms</text>

    <!-- Reference -->
    <rect x="96" y="416" width="1094" height="56" rx="6" fill="#F0F4FF" stroke="#BBE2FF" stroke-width="1"/>
    <text x="640" y="438" text-anchor="middle" font-family="{F}" font-size="{FS}" fill="{B}"><tspan font-weight="bold">贵州参照：</tspan>贵州→北京 RTT 22–28ms，已稳定支撑 11 台生产推理。成都延迟 ≤ 贵州，验证可行。</text>
    <text x="640" y="460" text-anchor="middle" font-family="{F}" font-size="{FN}" fill="{G}">训练任务完全延迟不敏感。模型部署由成都本地完成，不依赖专线传输大文件。</text>

    <!-- 机房改造与组网 -->
    <rect x="96" y="486" width="1094" height="36" rx="4" fill="{B}"/>
    <text x="640" y="510" text-anchor="middle" font-family="{F}" font-size="{FH}" font-weight="bold" fill="{W}">机房改造与组网（24 台规模）</text>

    <rect x="96" y="534" width="543" height="56" rx="6" fill="#F0F4FF" stroke="#BBE2FF" stroke-width="1"/>
    <text x="112" y="558" font-family="{F}" font-size="{FS}" fill="{B}"><tspan font-weight="bold">成都：</tspan>24 台集中同一区域，1 对高速交换机（约 134 万）</text>
    <text x="112" y="580" font-family="{F}" font-size="{FN}" fill="{G}">独立区域无其他负载，供电配额支持 24 台，改造风险低</text>

    <rect x="647" y="534" width="543" height="56" rx="6" fill="#F0F4FF" stroke="#BBE2FF" stroke-width="1"/>
    <text x="663" y="558" font-family="{F}" font-size="{FS}" fill="{B}"><tspan font-weight="bold">北京：</tspan>分两区 8+16 台，2 对交换机（约 214 万，+60%）</text>
    <text x="663" y="580" font-family="{F}" font-size="{FN}" fill="{G}">跨机房不共用交换机，改造需现有业务停电</text>

    <!-- 带宽估算 -->
    <rect x="96" y="604" width="1094" height="36" rx="4" fill="{B}"/>
    <text x="640" y="628" text-anchor="middle" font-family="{F}" font-size="{FH}" font-weight="bold" fill="{W}">带宽估算</text>

    <rect x="96" y="650" width="1094" height="42" rx="6" fill="{LG}" stroke="#E5E6EB" stroke-width="1"/>
    <text x="640" y="676" text-anchor="middle" font-family="{F}" font-size="{FN}" fill="{D}">现有 150M 专线（峰值 90%）· 2 台上线新增约 2M → 91% · 8 台全上线新增约 8M → 95% · 2026.10 评估是否扩容 150→200M（+3.63 万/月）</text>"""
s = content_page("06", "02", "技术维度 · 延迟分析 · 组网 · 带宽", body)
save("06_tech.svg", s)

# ═══════════════════════════════════════
# 7. 运维维度
# ═══════════════════════════════════════
body = f"""<rect x="96" y="128" width="1094" height="36" rx="4" fill="{B}"/>
    <text x="640" y="152" text-anchor="middle" font-family="{F}" font-size="{FH}" font-weight="bold" fill="{W}">运维维度：硬件维保与基础运维由成都负责，系统层以上由AI组负责</text>

    <rect x="96" y="178" width="543" height="220" rx="6" fill="{LG}" stroke="#E5E6EB" stroke-width="1"/>
    <rect x="96" y="178" width="543" height="36" rx="6" fill="{B}"/>
    <text x="367" y="202" text-anchor="middle" font-family="{F}" font-size="{FH}" font-weight="bold" fill="{W}">成都运维 — 硬件层与基础运维</text>
    <text x="112" y="245" font-family="{F}" font-size="{FB}" fill="{D}">• 协助供应商进行 GPU/电源/风扇故障更换</text>
    <text x="112" y="275" font-family="{F}" font-size="{FB}" fill="{D}">• 光模块与线缆更换、整机上下架</text>
    <text x="112" y="305" font-family="{F}" font-size="{FB}" fill="{D}">• 机房环境保障（供电、制冷、物理安全）</text>
    <text x="112" y="335" font-family="{F}" font-size="{FS}" fill="{G}">运维遵循运行维护中心各项管理要求</text>

    <rect x="647" y="178" width="543" height="220" rx="6" fill="{LG}" stroke="#E5E6EB" stroke-width="1"/>
    <rect x="647" y="178" width="543" height="36" rx="6" fill="{B}"/>
    <text x="918" y="202" text-anchor="middle" font-family="{F}" font-size="{FH}" font-weight="bold" fill="{W}">AI组 — 系统层及以上</text>
    <text x="663" y="245" font-family="{F}" font-size="{FB}" fill="{D}">• OS 安装配置与升级、BIOS/固件配置</text>
    <text x="663" y="275" font-family="{F}" font-size="{FB}" fill="{D}">• 系统重启与开关机、算力调度平台运维</text>
    <text x="663" y="305" font-family="{F}" font-size="{FB}" fill="{D}">• 模型部署与推理服务保障</text>
    <text x="663" y="335" font-family="{F}" font-size="{FS}" fill="{G}">• 故障诊断与性能调优</text>

    <rect x="96" y="418" width="1094" height="64" rx="6" fill="#F0F4FF" stroke="#BBE2FF" stroke-width="1"/>
    <text x="640" y="446" text-anchor="middle" font-family="{F}" font-size="{FS}" fill="{B}"><tspan font-weight="bold">协作模式：</tspan>两地通过远程管理通道协作 — AI组在北京完成系统层操作，成都团队负责现场硬件操作</text>
    <text x="640" y="470" text-anchor="middle" font-family="{F}" font-size="{FN}" fill="{G}">带外管理网络与生产网络物理隔离。此模式为数据中心异地运维标准实践，运维遵循运行维护中心各项管理要求。</text>"""
s = content_page("07", "02", "运维维度", body)
save("07_maintenance.svg", s)

# ═══════════════════════════════════════
# 8. Risks + Timeline
# ═══════════════════════════════════════
risks_data = [
    ("中", "带宽占用过高", "2026.10 基于实测评估，触发扩容 +3.63 万/月", "现有余量足够 2 台上线，8 台达 95% 仍可承受"),
    ("低", "成都延迟高于预期", "贵州已验证同类延迟可行；首批 2 台实测验证与优化", "抖动 > 30ms 概率低"),
    ("中", "现有机房无法满足部署要求", "供应商提前现场考察，出具改造方案后再施工", "2026.07–08 实地考察前置，降低实施风险"),
]
rbody = ""
for i, (lv, rn, ra, rd) in enumerate(risks_data):
    col, row = i % 2, i // 2
    cx = 96 + col * 551
    cy = 128 + row * 108
    cw = 543
    lc = B  # all blue now
    rbody += f"""
    <rect x="{cx}" y="{cy}" width="{cw}" height="98" rx="6" fill="#F0F4FF" stroke="#BBE2FF" stroke-width="1"/>
    <rect x="{cx}" y="{cy}" width="44" height="98" rx="6" fill="{lc}"/>
    <text x="{cx+22}" y="{cy+48}" text-anchor="middle" font-family="Arial, sans-serif" font-size="{FS}" font-weight="bold" fill="{W}">{lv}</text>
    <text x="{cx+58}" y="{cy+30}" font-family="{F}" font-size="{FH}" font-weight="bold" fill="{D}">{rn}</text>
    <text x="{cx+58}" y="{cy+56}" font-family="{F}" font-size="{FB}" fill="{D}">{ra}</text>
    <text x="{cx+58}" y="{cy+80}" font-family="{F}" font-size="{FN}" fill="{G}">{rd}</text>"""

ms = [("2026.06 底", "中选通知发出"),
      ("2026.07–08", "实地考察 · 改造方案"),
      ("2026.09", "2 台上线 · 负载验证"),
      ("2026.10", "带宽评估决策点"),
      ("2027.Q1", "扩容至 8 台")]
mw = 195
mgap = 16
rbody += f"""
    <rect x="96" y="356" width="1094" height="36" rx="4" fill="{B}"/>
    <text x="640" y="380" text-anchor="middle" font-family="{F}" font-size="{FH}" font-weight="bold" fill="{W}">关键时间线</text>"""
for i, (t, e) in enumerate(ms):
    mx = 96 + i * (mw + mgap)
    rbody += f"""
    <rect x="{mx}" y="408" width="{mw}" height="62" rx="6" fill="{B}"/>
    <text x="{mx+mw/2}" y="434" text-anchor="middle" font-family="Arial, sans-serif" font-size="{FS}" font-weight="bold" fill="{W}">{t}</text>
    <text x="{mx+mw/2}" y="458" text-anchor="middle" font-family="{F}" font-size="{FN}" fill="{W}" fill-opacity="0.8">{e}</text>"""
    if i < len(ms) - 1:
        rbody += f'<text x="{mx+mw+2}" y="444" font-family="Arial, sans-serif" font-size="{FH}" fill="{B}">→</text>'

rbody += f"""
    <rect x="96" y="492" width="1094" height="56" rx="6" fill="#F0F4FF" stroke="#BBE2FF" stroke-width="1"/>
    <text x="640" y="518" text-anchor="middle" font-family="{F}" font-size="{FS}" fill="{B}"><tspan font-weight="bold">2026.09 首批 2 台上线</tspan> → 10 月带宽评估 → <tspan font-weight="bold">2027.Q1 扩容至 8 台</tspan> → 2028 可扩展至 24 台</text>
    <text x="640" y="540" text-anchor="middle" font-family="{F}" font-size="{FN}" fill="{G}">负载以 LLM 推理为主，兼训练。模型部署成都本地完成，不依赖专线传输大文件。</text>"""
s = content_page("08", "02", "风险与时间线", rbody)
save("08_risks_timeline.svg", s)

# ═══════════════════════════════════════
# 10. Ending (slide 10)
# ═══════════════════════════════════════
s9 = load("04_ending.svg")
s9 = sub(s9, THANK_YOU="谢谢", THANK_YOU_EN="THANK YOU",
        ORGANIZATION=ORG, CONTACT_INFO="")
save("09_ending.svg", s9)

print(f"\nDone: 9 slides → {OUT}/")
