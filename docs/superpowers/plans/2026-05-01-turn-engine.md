# 麻将王 — 里程碑 0e：BattleState + Seat + turn_engine 实现计划

> **Goal:** 实现一局对战的纯逻辑骨架 —— 数据快照（`BattleState` / `Seat`）+ 摸打弃/鸣牌/立直/流局触发的状态机（`core/turn_engine/`）。**不含**事件总线、技能调度、AI 决策、UI、TileInstance 类升级。

**Spec 锚点:** spec §4.1 工程结构 / §5 数据类型（BattleState / Seat / TileInstance）/ §6.1 事件枚举（仅作触发时机参考，不实装总线）

## 范围

In-scope:
- `Tile` 扩展 `owner_seat` 字段（默认 -1，0a 测试零影响）
- `Wall` 原地扩展 dead wall API（`reserve_dead_wall(14)` / `take_rinshan()` / `dead_wall_indicator(n)`）
- `BattlePhase` 枚举：DRAW / DISCARD / CLAIM / SETTLE
- `Seat` 数据对象（seat_id / seat_wind / hand / melds / points / riichi / furiten / discards）
- `BattleState` 数据对象（seats / wall / dora_indicators / current_seat / phase / round_wind / hand_number / honba / riichi_sticks / turn_count / first_round_active）
- `ClaimValidator` 鸣牌触发条件：can_chi / can_pon / can_minkan / can_ankan / can_added_kan / can_ron / can_tsumo
- `RiichiValidator` 立直触发条件：门清 + 听牌 + 点数≥1000 + 牌墙剩余≥4
- `DrawDetector` 流局触发：包装 0d ExhaustiveDraw / AbortiveDraw 返回是否触发
- `TurnEngine` 状态机入口：摸/弃/phase 流转 + 调度 validators

Out-of-scope:
- TileInstance 新类（替代方案：扩展 Tile 加 owner_seat，[决策见用户确认]）
- BattleEventBus / SkillScheduler（属里程碑 1）
- AI 决策（属里程碑 2）
- UI 接入
- 包牌完整规则（沿用 0c stub）
- 鸣牌动画 / 时间窗口仲裁（玩家选择由调用方驱动）

## 关键决策

1. **不引入 TileInstance**：扩展 0a 的 `Tile` 加 `owner_seat: int = -1`。skill / is_revealed_to 留到里程碑 1。
2. **Wall 原地扩展**：不新建 BattleWall；只加 dead_wall 切片 + rinshan 取牌 + indicator 探针。`shuffle()` / `draw()` / `size()` 行为保持兼容（draw 自动跳过 dead wall）。
3. **巡数维护**：`BattleState.turn_count`（每家摸 1 张计 1 巡 = 1 + 总摸牌数除以 4 取整）。`first_round_active` bool 在 4 家都过第 1 巡后置 false。
4. **TurnEngine API 风格**：纯函数 + 突变 BattleState（无 await，无信号）。事件触发由调用方自己 emit 或后续技能框架接入。
5. **缩进**：TAB（与 0a/0c/0d 一致）。

## 文件清单

新增源 + 测试：

| 路径 | 用途 |
|------|------|
| `godot/battle/battle_phase.gd` | Phase 枚举（独立小文件方便复用） |
| `godot/battle/seat.gd` | Seat 对象 |
| `godot/battle/battle_state.gd` | 顶层快照对象 + 工厂 |
| `godot/core/turn_engine/claim_validator.gd` | 鸣牌/荣胡/自摸合法性 |
| `godot/core/turn_engine/riichi_validator.gd` | 立直触发条件 |
| `godot/core/turn_engine/draw_detector.gd` | 流局触发包装 |
| `godot/core/turn_engine/turn_engine.gd` | 状态机入口 |
| `godot/tests/core/test_*.gd` | 7 个测试文件 |

修改现有：
- `godot/core/tile/tile.gd` 加 `owner_seat: int = -1` + 工厂参数
- `godot/core/tile/wall.gd` 加 dead_wall API（不破坏现有）

## Task 拆分（TDD）

每 task：Red 测试 → Green 最小实现 → commit。

1. **Tile.owner_seat 扩展** — 加字段 + 工厂可选参数 + ~3 测试（默认 -1 / 工厂传入 / clone 保留）
2. **Wall dead_wall API** — `reserve_dead_wall(14)` 在 shuffle 后切；`live_wall_size()` 排除 dead；`take_rinshan()` 从 dead 头取；`dead_wall_indicator(n)` 第 n 张指示牌；~6 测试
3. **BattlePhase 枚举** — DRAW/DISCARD/CLAIM/SETTLE + 简单 to_string；~2 测试
4. **Seat** — 数据 + helper（add_to_hand / discard / make_meld / record_discard）；~8 测试
5. **BattleState** — 4 seat + wall + dora_indicators + phase + 各 counter；工厂 `for_east_round(seed, dealer_seat)`：洗牌 + 拆王牌 + 翻 1 张 dora indicator + 发 13 张 × 4 + phase=DRAW + current=dealer；~8 测试
6. **ClaimValidator** — 7 个 can_xxx 函数。每个纯函数；~14 测试
7. **RiichiValidator** — `can_declare_riichi(seat, wall_remaining) -> bool`；~6 测试
8. **DrawDetector** — `should_exhaustive_draw(state)` / `check_abortive(state) -> Enum.AbortiveType`（NONE/SUUFON/KYUUSYU/...）；~8 测试
9. **TurnEngine** — `start_hand()` / `draw_for_current()` / `discard(seat, tile)` / `apply_chi/pon/kan/ron/tsumo()` 入口；推进 phase + turn_count；~10 测试集成
10. 收尾 + plan 完成记录 + push

预期：~80-100 新测试，累计 ≥316。

## 验证

```bash
scripts/test_run_core.sh
```
- 0a/0c/0d 现有 236 测试不退化
- 0e 新增 ~80-100 测试 100% PASS
- 0a 的 Tile / Wall 测试在扩展后仍通过（兼容性闸门）

## 风险

| 风险 | 缓解 |
|------|------|
| Wall dead_wall API 改坏 0a 现有 7 测试 | 仅追加方法，不动 `_tiles` / `_draw_index` 行为；先跑 test_wall.gd 确认 0 退化 |
| ClaimValidator 鸣牌时机条件复杂（chi 仅下家、pon 任意家、暗杠任意时机） | 每个 can_xxx 列 5+ 测试覆盖正/反例 |
| TurnEngine 集成测试容易脆弱 | 写"单局 mini 流程"集成测试（4 家各摸 1 弃 1 → phase 推进），不写到完整一局对战 |
| Seat.discards 与 BattleState.discards_per_seat 重复 | 取 spec §5 的 BattleState.discards_per_seat 单一来源；Seat 不存 discards |

## 后续

完成后：
1. 进入里程碑 1（技能框架 + 事件总线 + SkillScheduler + 5 demo 技能 + 1 角色能力）—— 0e 的 TurnEngine 改为通过 EventBus emit 事件
2. 之后里程碑 2（单局对战 vs 1 AI）—— 加 AI decision-maker，复用 TurnEngine + ClaimValidator
