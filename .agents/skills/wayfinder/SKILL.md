---
name: wayfinder
description: 把单个代理会话装不下的大块工作规划成 issue tracker 上的调查议题共享地图，并一次解决一个议题，直到通往目标的路径清晰。
---

一个松散想法出现了：它太大，单个 agent session 装不下，而且前路仍在 fog 中。这个 skill 会把它绘制成 repo issue tracker 上的 **shared map**，然后一次处理一个 ticket。Map 与领域无关：工程工作、课程内容，或任何符合这个形状的事项都可以。

## Refer by name

每张 map 和每个 ticket 都是 issue，因此都有一个 **name**：它的 title。在所有给人看的内容里，包括叙述和 map 的 Decisions-so-far，都用 name 引用它，不要只写裸 id、number 或 slug。一堵 `#42, #43, #44` 很难读；name 一眼就能看懂。Id 和 URL 不会消失，它们被包在 name 的 link 里面，但不单独替代 name。

## The Map

Map 是这个 repo issue tracker 上一个带 `wayfinder:map` label 的单独 issue，是 canonical artifact。它的 tickets 是 map 的 child issues。

Map 是 **index**，不是 store。它列出已经做出的 decisions，并指向保存细节的 tickets；一个 decision 只存在一个地方，也就是它的 ticket。因此 map 不复述细节，只给 gist 和 link。

**Map、child tickets、blocking 和 frontier queries 的物理表达方式取决于 tracker。** 查阅 `docs/agents/issue-tracker.md` 的 "Wayfinding operations" section，了解这个 repo 如何表达它们。如果没有该 doc，默认使用 local-markdown tracker。

### The map body

Map 是低分辨率的全局视图，每个 session 加载一次。Open tickets 不列在里面；它们是 open child issues，通过 query 找到。

```markdown
## Notes

<domain; skills every session should consult; standing preferences for this effort>

## Decisions so far

<!-- the index — one line per closed ticket: enough to judge relevance, then zoom the link for the detail the ticket holds -->

- [<closed ticket title>](link) — <one-line gist of the answer>

## Fog

<!-- see "Fog of war" for what belongs here -->
```

### Tickets

每个 ticket 都是 map 的 **child issue**；tracker 的 issue id 是它的 identity。Body 是一个问题，大小控制在一个 100K token agent session 内：

```markdown
## Question

<the decision or investigation this ticket resolves>
```

每个 ticket 带一个 `wayfinder:<type>` label，取值为 `research`、`prototype`、`grilling`、`task`（见 [Ticket Types](#ticket-types)）。

Session **claim** ticket 的方式，是在任何工作开始前先把 ticket assign 给 driving map 的 dev。这个 assignee 就是 claim：open 且 unassigned 的 ticket 才是 unclaimed。

Blocking 使用 tracker 的 **native** dependency relationship；这很重要，因为 tracker UI 会可视化 frontier，人类不用打开 map 也能看到哪些 ticket 可拿。只有 tracker 没有 native blocking 时，才退回 body convention。一个 ticket 的所有 blockers 都关闭后，它就是 **unblocked**；**frontier** 是 open、unblocked、unclaimed 的 children，也就是已知世界的边缘。

答案不写进 body，而是在 resolution 时记录（见 [Work through the map](#work-through-the-map)）。解决 ticket 时产生的 assets 从 issue 链接出去，不粘贴进 body。

## Ticket Types

- **Research**：阅读 documentation、third-party APIs，或 knowledge bases 等 local resources。创建 markdown summary 作为 linked asset。当需要当前 working directory 外的知识时使用。
- **Prototype**：通过 cheap、rough、concrete artifact 提高讨论 fidelity，例如 outline、rough take、stub，或通过 /prototype skill 写 UI/logic code。Prototype 作为 asset 链接。当核心问题是 "how should it look" 或 "how should it behave" 时使用。
- **Grilling**：与 agent 对话。使用 /grilling 和 /domain-modeling skills。一次问一个问题。默认类型。
- **Task**：讨论推进前必须完成的 literal manual work；没有要决定、prototype 或 research 的内容。例如搬数据、注册服务、配置访问权限。Agent 能自动化就自动化，否则给人类精确 checklist。完成后即 resolved；答案记录做了什么，以及后续 tickets 依赖的事实（credentials location、new URLs、row counts 等）。

## Fog of war

Map 是 _有意_ 不完整的：不要描绘你还看不见的东西。Tickets 之外是 fog：那些你能感觉到以后会来的 decisions 和 investigations，但它们悬在仍未解决的问题之上，暂时还无法钉住。解决一个 ticket 会清掉它前方的一片 fog，把现在已经能说明的问题升级成新的 tickets；一次一个，直到通向目标的路清楚且没有 tickets 剩下。

Map 的 **Fog** section 用来记录这种朦胧视野：怀疑中的问题、之后要回访的区域、暂时推迟的风险。可以按视野允许的粗细来写；它也是协作者阅读这个 effort 走向时的路标。

**Fog or ticket?** 测试标准是你现在能不能把问题说清楚，而不是现在能不能回答它。

- **Ticket when** 问题已经清晰，即使它被 blocked、现在不能处理。
- **Fog when** 你还不能把它说得那么清楚。不要把 fog 预先切成 ticket-sized pieces：fog 比 ticket 粗，frontier 到达后，一片 fog 可能升级成多个 tickets，也可能一个都没有。

Fog 只排除已经决定的内容（Decisions so far）和已经是 ticket 的内容。

## Invocation

两种模式。无论哪种，**每个 session 绝不要 resolve 超过一个 ticket。**

### Chart the map

用户带着松散想法调用。

1. 运行 `/grilling` 和 `/domain-modeling` session，浮现 open decisions。
2. **Create the map**（label `wayfinder:map`）：填好 Notes，Decisions-so-far 为空，Fog 初步勾勒。
3. **Create the tickets you can specify now** 作为 map 的 child issues，然后第二遍再 wire blocking edges（issues 需要 ids 后才能互相引用）。Wiring 会把它们分成 frontier 和 blocked；现在还说不清的都留在 Fog。
4. 停止。Charting the map 是一个 session 的工作；不要同时 resolve tickets。

### Work through the map

用户用 map（URL 或 number）调用。Ticket 是 **optional**；没有 ticket 时，你选择下一个 decision，而不是用户选择。

1. 加载 **map**：低分辨率视图，而不是每个 ticket body。
2. 选择 ticket。用户点名就用它；否则按顺序拿第一个 frontier ticket。**Claim it**：任何工作开始前先 assign 给自己。
3. Resolve it：按需 **zoom**，只在需要时获取相关或已关闭 ticket 的完整 body；调用 `## Notes` block 提到的 skills。不确定时用 `/grilling` 和 `/domain-modeling`。
4. 记录 resolution：把答案作为 **resolution comment** 发布，**close** issue，并向 map 的 Decisions-so-far 追加 context pointer。
5. 添加新浮现的 tickets（create-then-wire）；把答案已经澄清的 fog 升级，并从 Fog 中清掉每个已升级 patch，让它只作为新 ticket 存在。如果这个 decision 使 map 其他部分失效，更新或删除那些 tickets。

用户可能并行运行 unblocked tickets，所以要预期其他 sessions 同时编辑 tracker。
