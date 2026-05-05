# Phase 2 联机骨架 brainstorm（2026-05-05）

> **类型**：Phase 2 联机/远端权威 brainstorm doc。spec §4.3 / §15 列为 Phase 2 主题；M9 closure (#101) 也标为"联机 / 远端权威 spec §4.3 Phase 2"。本文档是首次正式 scoping，分阶段拆解 + 路线图 + 关键决策点；不做编码改动。

## TL;DR

- v1 单机权威，所有对局副作用都通过 `_emit` + `SkillScheduler` 处理（spec §4.3 v1 约定 ✅ 已守住）— 这条约束让 Phase 2 联机的"事件回放 / 远端权威"可以直接复用 sim 路径。
- Phase 2 拆 4 阶段：M11 抽象接口 → M12 server 权威骨架 → M13 客户端协议 → M14 反作弊 / 一致性裁决。
- 每阶段独立可 ship；从 M11 开始即可（不需要先决条件）。
- 总体 ~10-20 PR 工作量；预计 2-3 周持续推进（按当前 M9 节奏）。

## 一、当前架构 vs 联机所需

### 当前 v1（M0-M9）

```
玩家 UI (run_flow.gd)
  ↓ 调用
GameDriver (battle/game_driver.gd)
  ↓ start_hand() → 实例化
BattleController (battle/battle_controller.gd)
  ├── BattleState（4 seats, wall, phase, dora_indicators）
  ├── TurnEngine（draw / discard / claim / riichi / win 状态机）
  ├── SkillRegistry + SkillScheduler（事件触发 hook）
  ├── ai (HeuristicAi / SimpleAi)
  └── events: Array[BattleEvent]   ← 当前的"事件总线"是内部 list
  ↓ run_to_end()
返回 {last_event, events}
```

**关键 invariant（spec §4.3）**：所有副作用经 `_emit` → 进 events 数组 + SkillScheduler 解析；不存在"绕过 emit 直接改 state"的路径。

### Phase 2 PvP 联机所需

```
Player A UI                     Server (单一权威源)                   Player B UI
  ↓ Action                        ↓                                    ↓ Action
NetworkedBattleController  ←  WebSocket / WebRTC  →  NetworkedBattleController
  ├── 本地 BattleState（mirror）        BattleState（authoritative）
  ├── 本地预测（可选）                  TurnEngine 仲裁
  ├── 等待 server ack 后 commit         SkillScheduler 在 server 端跑
  └── events: 从 server 接收并回放     events: 广播给所有 client
```

**关键差异**：
- `_emit` 不再直接进 local events；必须**先**走网络到 server，server 验证后**回**广播给所有 client
- AI 决策不能在 client（除非 server 验证）— 玩家 input 同理
- 牌墙信息**只 server 知道**；client 不能见 future tiles（reveal API 需要 server gate）
- 同 seed 才能 deterministic replay（debug / 录像 / 反作弊）

## 二、Phase 2 阶段拆解

### M11：BattleController 接口抽象（~3 PR）

**目标**：把 `BattleController` 拆成 `IBattleController`（abstract）+ `LocalBattleController`（v1 单机），让外部代码（GameDriver / RunFlow / tests）只依赖接口而非具体类。

**改动面**：
- `battle/i_battle_controller.gd` — 抽象基类（`run_to_end()` / `apply_ron()` / `apply_tsumo()` / `state` getter / `events` getter）
- `battle/local_battle_controller.gd` ← 把现有 `battle_controller.gd` 改名 + extends IBattleController
- `battle_controller.gd` ← 保留为兼容 alias：`class_name BattleController` 改 typedef-only 或加 deprecation note
- callers 改用 IBattleController 类型签名

**风险**：
- `class_name BattleController` 全局唯一约束（CLAUDE.md 提醒）— 改名涉及 ~20 个 file 的 typed reference 更新
- `battle.ai is HeuristicAi` 这种 type narrow 仍可用（HeuristicAi 不变）

**验收**：
- GUT 全套 PASS
- sim 跑通（确保 abstract 没漏方法）
- 现有 tests 全部用 LocalBattleController 实例化

**预期 PR**：3
1. `feat(m11): IBattleController 接口抽象 + LocalBattleController rename`
2. `refactor(m11): callers 改用 IBattleController 类型签名`
3. `docs(m11): IBattleController 接口规范 + 方法清单`

### M12：Server 权威骨架（~5-8 PR）

**目标**：实装 `NetworkedBattleController` 雏形，跑"4 个 client + 1 server"流程，server 决定牌序、回放 events。**v1 仅本地 4 个 process 模拟**（不真上 WebSocket 网络），证明 client/server 协议设计正确。

**改动面**：
- `battle/networked_battle_controller.gd` — 实现 IBattleController；本地接口同 LocalBattleController，但 `_emit` 改成"发到 server queue"
- `server/local_loopback_server.gd` — 同 process 跑的"假 server"，实例化 server-side BattleState；从所有 client 收 action，按 turn 顺序处理 → 广播 events
- `protocol/action.gd` — Action 类型（ACTION_DRAW / ACTION_DISCARD / ACTION_RIICHI / ACTION_RON / ACTION_TSUMO / ACTION_PASS_CLAIM）
- `protocol/event.gd` — 复用现有 BattleEvent，加 `server_seq: int` 序号字段
- `tests/integration/test_networked_local_loopback.gd` — 4 client 跑通一局，最终 state 与 LocalBattleController 等价

**关键设计决策**（待定）：
1. **预测 vs 不预测**：client 是否在 ack 前先本地预演？v1 简化版 = 不预测，等 server 确认；profile 显示 latency 不可接受时再加。
2. **reveal API gating**：spec §4.3 reveal API（peek_dora / peek_uradora / wall_segment）是 cheating risk — server 必须签名所有 reveal 让 client 不能凭空构造。
3. **断线重连**：server 维护"events 历史"，client 重连后从最后已知 seq 拉。
4. **AI 在哪跑**：v1 联机假设全人类玩家。v2 加"AI 玩家"时 AI 也跑 server 端（或 server-trusted bot service）。

**预期 PR**：5-8
1. `feat(m12): protocol.Action / protocol.NetworkedEvent 数据类型`
2. `feat(m12): LocalLoopbackServer 单 process 仲裁器骨架`
3. `feat(m12): NetworkedBattleController client 半边`
4. `feat(m12): server 端 BattleState 镜像 + TurnEngine 调度`
5. `feat(m12): 4-client local loopback 集成测`
6. `feat(m12): server 端 SkillScheduler + reveal gating`
7. `feat(m12): 断线重连 + events 历史回放`
8. `docs(m12): 联机协议规范 + 边界条件`

### M13：真网络协议（WebSocket）（~3-5 PR）

**目标**：把 LocalLoopbackServer 替换为真 WebSocket server（Go / Rust / Godot Server build）；玩家从两个不同 client process 跑通一局对战。

**改动面**：
- 重写 `main.go`（当前是 stub） → 真 WebSocket server，实例化 `BattleAuthority`（移植 LocalLoopbackServer 逻辑到 Go）
  - **决策**：server 用 Go 还是 Godot Server Build？Go 版需要在 Go 端重新实装 TurnEngine + SkillScheduler — 巨大 cost。Godot Server Build 直接复用 GDScript — 推荐。
- `protocol/serializer.gd` — JSON / msgpack 编解 Action / NetworkedEvent
- `network/websocket_client.gd` — Godot WebSocket client + 重连
- `auth/` — 简化版 player auth（v1 sticker token）

**预期 PR**：3-5

### M14：反作弊 / 一致性（~2-4 PR）

**目标**：
- 牌墙不可见 — server 不向 client 发未抽的牌
- 客户端 RNG seed 不暴露 — server 控所有 randomness
- 重放检测 — 同 seed + 同 actions → 同 events，server 录所有局

**预期 PR**：2-4

## 三、首发 PR：M11 第 1 步

**先做**：`feat(m11): IBattleController 接口抽象 + LocalBattleController rename`

具体：
1. 新文件 `battle/i_battle_controller.gd`：abstract 基类，列 30+ public method 签名
2. 新文件 `battle/local_battle_controller.gd`：extends IBattleController，把现 BattleController 460 行内容搬过来
3. 旧 `battle/battle_controller.gd` 内容清空，留 deprecation comment + class_name alias（如能做）
4. caller 用 IBattleController 类型，instantiate 时用 LocalBattleController.new()

**rollback 保险**：先 mass-grep `BattleController.new` → 全替换 `LocalBattleController.new`。GUT 跑通后再 promote。

## 四、为什么从 M11 开始最稳

1. **M11 是纯 refactor，零功能改动**。GUT 跑过即知没破。
2. **不需要 M12+ 任何新基础设施**（不需 server、不需协议）。
3. **解锁 M12 同时进**：M11 ship 后，server 骨架可与 v1 单机继续运行并行开发。
4. **失败成本低**：如发现接口抽象有反弹（如 v1 隐式依赖具体类），可还原。

## 五、与 spec 已有约束对齐

| spec 条目 | M11+ 影响 |
|---|---|
| §4.3 v1 约定（所有副作用走 BattleEventBus + SkillScheduler） | ✅ 已守住，无需改 |
| §15 风险点 "中麻规则代码替换不彻底" | ✅ M9 第 1-4 批 legacy 已闭环 |
| §15 风险点 "学习曲线" | ⚠️ 未做（与联机 orthogonal） |
| §13 milestone 列表 | M11+ 不在 spec §13；M9 closure 标为 Phase 2 |

## 六、总成本评估

| 阶段 | PR 数 | 工时（按当前 PR/小时节奏） | 关键依赖 |
|---|---|---|---|
| M11 接口抽象 | 3 | 0.5 天 | 无 |
| M12 server 骨架 | 5-8 | 3-5 天 | M11 |
| M13 真网络 | 3-5 | 2-3 天 | M12 + Go/Godot server build 决策 |
| M14 反作弊 | 2-4 | 1-2 天 | M13 |
| **合计** | **13-20** | **7-11 天** | — |

## 七、决策点（待 user 确认）

1. **M11 启动确认**：是否进入 Phase 2 联机线，先做 BattleController 接口抽象？
2. **server 实现选型**：Go（重写 SkillScheduler）vs Godot Server Build（复用）— 决策点放 M13，M11/M12 阶段可推迟。
3. **首发 server 仅 P2P loopback**：M12 是否先做 LocalLoopbackServer 跑通 protocol 设计，再上真网络？建议是。
4. **Phase 2 优先级 vs 教程 / 新手引导**：spec §15 也列教程为 Phase 2；联机 vs 教程哪个先？建议联机先（学习曲线在单机 alpha 反馈阶段更好处理）。

## 八、本 doc 不做的事

- 不开 PR 写代码 — 只规划
- 不锁定 server 选型（Go vs Godot Server Build）— M13 才决
- 不细化协议字段 — M12 第 1 个 PR 时落
- 不 deprecate `BattleController` class_name — M11 第 3 个 PR 才动

下一步：等 user 拍板是否进入 M11，进入后开第 1 个 PR `feat(m11/p1): IBattleController 接口抽象`。
