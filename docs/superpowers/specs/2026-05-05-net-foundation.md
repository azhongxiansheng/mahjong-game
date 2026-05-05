# M10 Net Foundation — spec §4.3 Phase 2 联机预备

> **状态**：foundation 落地（PR #109+），生产联机实现是 M11+ Phase 2 工作。
>
> 本 doc 记录 v1 day-1 锁住的"事件总线 = 单一事实源"承诺如何通过序列化 +
> 决定性测试硬约束兜底。

## 设计目标

spec §4.3 明确 v1 / Phase 2 分层：

| 层 | v1 实现 | Phase 2 实现 |
|---|---|---|
| 权威源 | LocalBattleController（单机解析） | 远端 server + 事件回放 |
| 状态分发 | 同进程读 BattleState | server 推 events，client 重放 |
| 反作弊 | 无 | server 端裁定 + 状态 hash |

约束（spec §4 line 134）："所有对局副作用都通过 BattleEventBus 发出 +
SkillScheduler 处理，不写绕过总线直接修改 BattleState 的代码"。本 doc
锁住此约束的两个机器可验形式。

## 落地内容

### 1. BattleEvent / TileInstance 序列化

`BattleEvent.to_dict()` / `from_dict()` + `TileInstance.to_dict()` /
`from_dict()` 提供 JSON 友好的 wire format。skill 字段不进 dict — server
权威下 client 通过本地 `SkillRegistry` 反查 (id, owner_seat)，避免 wire
携带 hook 实现引用。

测试（`test_event_serialization.gd`）：
- TileInstance roundtrip 全字段保留
- BattleEvent roundtrip 含 type / actor / tile / extra / chain_id
- `JSON.stringify(ev.to_dict())` 不崩 → JSON 友好性

### 2. 决定性 smoke test

```gdscript
test_same_seed_produces_identical_event_sequence:
    bc1 := BattleController.new(42, 0, true)
    bc2 := BattleController.new(42, 0, true)
    bc1.run_to_end()
    bc2.run_to_end()
    # 比较两份 events 的 to_dict() JSON 串
    for i in range(events.size()):
        assert_eq(JSON.stringify(bc1.events[i].to_dict()),
                  JSON.stringify(bc2.events[i].to_dict()))
```

这是 spec §4.3 联机权威化的硬前提：**server 与 client 在同 seed 下必须
产生 byte-identical 事件序列**。否则 replay 永远无法收敛。

反向锁（`test_different_seeds_produce_different_event_sequences`）也加了，
确保 seed 真在洗牌路径分支，不会因为某个常量化错误导致同输出。

## Phase 2 后续工作（不在本 PR）

1. **抽接口**：`IBattleController` 抽象 `run_to_end()` / `start_hand()` /
   事件流；`LocalBattleController` 当前实现，`NetworkedBattleController`
   走 server replay
2. **Server**：Go / Node / Godot headless server 接收 client 输入，跑权威
   BattleController，推 BattleEvent stream
3. **Client replay**：从 server 接 events.from_dict() → 重放到本地 state
   → UI 渲染只看 BattleState，不直接调 BattleController
4. **状态 hash**：在 GAME_BEGIN / WIN_DECLARED 时 emit `BattleState.snapshot_hash()`
   对比，发现 desync 立即 disconnect + log
5. **Skill 反查**：client 接 event 时遇 tile_instance 含 skill_id，从本地
   registry 查实例（保证 server / client 用相同 hook 实现）

## 风险

- **AI 决策不在事件流里**：当前 `SimpleAi.decide_discard` / `HeuristicAi.decide_discard`
  是 stateless RNG-driven 函数。client 重放时若用本地 AI 会得到相同决策（因
  为 seed 相同 + 决策函数 deterministic），但 spec §4.3 隐含 player 操作走
  client → server 路径。Phase 2 应把 player 决策包成 `PlayerAction` event
  并在 events stream 里传输。本 PR 不动这部分。
- **剃须 ctx mutation**：信息系 reveal API（PR #108）已经全走 ctx + event；
  其他 hook 也基本走 ctx；这个不变量值得在 PR 模板里加 checklist。

## 与 PR #107 / #108 的关系

- #107 (is_tenpai)：UI 提示 / AI 决策辅助，与 net 无关
- #108 (reveal API)：所有 reveal 走 ctx → event → state 路径，反过来证明
  事件总线是充分的（reveal 是典型的"信息变化"，能走 event 说明所有副作用
  都能走 event）
- 本 PR (net foundation)：上述两条的兜底证明 + 序列化前置工作

## 验收

- [x] BattleEvent / TileInstance roundtrip 单测
- [x] 同 seed → byte-identical 事件序列（决定性硬约束）
- [x] 不同 seed → 事件序列有差异（seed 真分支）
- [x] JSON 友好性（wire format 准备）
- [x] 全套 GUT 1142+/1142+ 0 fail
