# M8 实施计划 — 半庄战 (Phase 2, 8 局) 作为节点的可选 session 模式

> **范围说明**：用户在 brainstorm 阶段确认 M8 方向 = **半庄战**。M9 暂未定向，本 plan 只覆盖 M8。M9 应在 M8 完成、M7 平衡基线达成后另起 brainstorm（推荐方向：教程 / 新手引导，对应 spec §15"玩家学习曲线"风险，或 HeuristicAi 终局策略升级，对应本 plan Step 9 拆出的 M8.5）。

## Context

`docs/superpowers/specs/2026-05-01-mahjong-king-design.md` §13 实现里程碑只到 M7（平衡迭代），但 §14 参数表脚注明确写过 "Phase 2 可选半庄战（8 局）"。M0-M3 已把日麻规则引擎 + 单局对战 + 东风 4 人桌全部落地，**风圈 / 自风 / 场风役 / 庄家轮转 / 立直棒 / 本场棒 / 流局 / 连庄** 都是可参数化的设计——半庄战不需要新规则，只需把"4 局 + 全程东风"扩展为"8 局 + 前 4 局东 / 后 4 局南"。

加半庄战的目的：
1. **拉长 Run 节点的策略深度** — 8 局允许"南场逆转"等更丰富的玩法体验，对应 CCG/Roguelike 的高潮节点
2. **学习曲线分级** — 章 1-2 维持东风战（spec §15 "学习曲线"风险缓解），章 3 + Boss 上半庄战
3. **平衡 surface 翻倍** — M7 simulation baseline 数据维度只覆盖 4 局，半庄战是天然的 endgame stress test，可暴露 M7 没碰到的失衡

约束：
- M7 旧存档必须能加载（`SAVE_VERSION` 现为 1，硬版本检查会让旧档返 null）
- 复用所有现有日麻规则，不新增规则代码
- 默认**不实装** "南入" (top1 ≥30000 提前结束) — spec 没规定，加 BalanceConstants flag 留位
- TDD 强制（AGENTS.md §"TDD 开发规范"），每步可独立 commit + GUT 0 fail

## 总体架构决策

1. **NodeRef 加 `session_kind: String` 字段**（值：`"east_round"` / `"hanchan"`）
   - 不新增 NodeKind 枚举（避免 `NORMAL/NORMAL_HALF/ELITE/ELITE_HALF/...` 笛卡尔积）
   - String 而非枚举常量 — 存档 JSON 友好 + migration 时填默认值更直接
   - NodeKind 与 session_kind 正交：Boss 节点 + 半庄 = `kind=BOSS, session_kind="hanchan"`

2. **GameDriver 参数化 + 线性 hand_index**
   - 构造注入 `total_hands: int`（默认 4 兼容现有调用）和 `hands_per_round: int`（默认 4）
   - **不重置** `hand_index`（保持 0..total_hands-1 线性递增），`round_wind` 由 `_compute_current_round_wind()` 函数式计算：`hand_index < hands_per_round → TileId.E, else → TileId.S`
   - 终局判定：`hand_index >= total_hands and not renchan`
   - 优势：连庄计数不被风圈切换干扰；UI 显示 "南 X 局" = `hand_index - hands_per_round + 1`

3. **BalanceConstants session 维度（扁平后缀）**
   - 现有 `hands_per_node = 4` 改为 `hands_per_node_east_round = 4` + 新增 `hands_per_node_hanchan = 8`
   - 同样后缀法：`node_rank_hp_delta_east_round / _hanchan`，`node_rank_gold_reward_east_round / _hanchan`
   - 加 helper `BalanceConstants.get_hands_per_node(session_kind: String) -> int` 等
   - 扁平 + 后缀好于 dict-of-dict — 沿用 M7 现有 `lookup(StringName)` 风格，测试改动最小

4. **存档 SAVE_VERSION 1 → 2 + migration（不返回 null）**
   - `RunState._migrate_v1_to_v2(d: Dictionary) -> Dictionary`：给所有 NodeRef dict 注入 `session_kind = "east_round"`
   - 硬约束：M7 旧档必须能加载到 M8 代码运行

## 执行步骤（TDD：每步先红后绿；每步 1 commit；GUT 全套必须 0 fail）

### Step 1 — BalanceConstants 扩字段 + helper
- **改**: [godot/meta/balance_constants.gd:51](godot/meta/balance_constants.gd:51) (`hands_per_node` → `hands_per_node_east_round`)，新增 `hands_per_node_hanchan: 8`，新增 `node_rank_hp_delta_hanchan: [0,0,-2,-4]`，`node_rank_gold_reward_hanchan: [60,30,10,0]`，flag `enable_south_exit_top30k: false`
- **加 helper**: `get_hands_per_node(session_kind) / get_node_rank_hp_delta(session_kind) / get_node_rank_gold_reward(session_kind)`
- **测试**: [godot/tests/meta/test_balance_constants.gd:36](godot/tests/meta/test_balance_constants.gd:36) 改 `hands_per_node==4` 为 `get_hands_per_node("east_round")==4`；新增 `test_hanchan_hands_eq_8 / test_hanchan_hp_delta_doubles / test_hanchan_gold_reward / test_unknown_session_kind_raises`

### Step 2 — GameDriver 参数化 + 风圈推进 ★核心
- **改**: [godot/battle/game_driver.gd:18](godot/battle/game_driver.gd:18) 删 `const NUM_HANDS_EAST_ROUND: int = 4`；改实例字段 `var total_hands: int = 4 / var hands_per_round: int = 4`；`_init` 接受这两个参数（默认值兼容现有调用）
- **加函数**: `_compute_current_round_wind() -> int { return TileId.E if hand_index < hands_per_round else TileId.S }`
- **改 BattleState 注入**: 每次 `_start_next_hand` 时把 `next_state.round_wind = _compute_current_round_wind()` 而非工厂 `for_east_round` 写死
- **改终局**: [godot/battle/game_driver.gd:76](godot/battle/game_driver.gd:76) `if not renchan and hand_index >= total_hands`
- **新测**: [godot/tests/battle/test_game_driver_hanchan.gd](godot/tests/battle/test_game_driver_hanchan.gd)
  - `test_hand_5_is_south_1()` — total_hands=8 时 hand_index=4 的 round_wind == TileId.S
  - `test_hand_4_still_east()` — 边界 hand_index=3 仍是东
  - `test_hanchan_finishes_at_hand_8_no_renchan()`
  - `test_renchan_at_east_4_keeps_east_round_extends_past_4()` — 4 连庄不切南
  - `test_renchan_at_south_4_extends_past_total()` — 8 连庄触发 HAND_LIMIT 防护
  - `test_riichi_sticks_carry_e4_to_s1()` — 立直棒跨场风
  - `test_honba_carries_through_round_switch()` — 本场棒不在 E4→S1 重置
- **撞测试**: [godot/tests/battle/test_game_driver.gd:209-230](godot/tests/battle/test_game_driver.gd:209) 4 局测试改为显式构造 `GameDriver.new(..., total_hands=4)`；[godot/tests/integration/test_east_round_e2e.gd:85](godot/tests/integration/test_east_round_e2e.gd:85) `hand_index >= 4` 改为 `>= 4` 显式说明这是东风战

### Step 3 — BattleNodeRunner 接 session_kind
- **改**: [godot/meta/battle_node_runner.gd:12](godot/meta/battle_node_runner.gd:12) `HAND_LIMIT: 30 → 60`（半庄连庄余量，8 局 × 7.5 倍）
- **改**: `run_with_stats / run_battle_to_node_result` 增 `session_kind: String = "east_round"` 参数，从 BalanceConstants 查 `total_hands`，传给 GameDriver
- **测试**: [godot/tests/meta/test_battle_node_runner.gd](godot/tests/meta/test_battle_node_runner.gd) 加 `test_runner_hanchan_runs_8_hands()`、`test_runner_east_round_default_runs_4_hands()`

### Step 4 — NodeRef.session_kind + ChapterMapGenerator 配置（与 Step 1 可并行）
- **改**: [godot/meta/node_ref.gd](godot/meta/node_ref.gd) 加 `var session_kind: String = "east_round"`；`_init` / `to_dict` / `from_dict` 同步
- **改**: [godot/meta/chapter_map_generator.gd:75-96](godot/meta/chapter_map_generator.gd:75) `_pick_kind_for_floor` 之后调 `_pick_session_kind(chapter_index, kind) -> String`：章 3 全 hanchan，章 1-2 全 east_round，跨章 BOSS 节点强制 hanchan
- **测试**: [godot/tests/meta/test_chapter_map_generator.gd](godot/tests/meta/test_chapter_map_generator.gd) 加 `test_chapter_3_all_hanchan / test_chapter_1_2_all_east_round / test_boss_in_chapter_3_is_hanchan`；NodeRef 的 `test_node_ref.gd` 加 `test_session_kind_default / test_session_kind_roundtrip`

### Step 5 — 存档 migration（依赖 Step 4）
- **改**: [godot/meta/run_state.gd:106-140](godot/meta/run_state.gd:106) `SAVE_VERSION = 2`；`from_dict` 检测 `version==1` 时调 `_migrate_v1_to_v2(d)` 而非返 null
- **加**: `static func _migrate_v1_to_v2(d: Dictionary) -> Dictionary`：遍历 `current_map.nodes` 给每个 NodeRef dict 填 `session_kind = "east_round"`；history 同理
- **测试**: [godot/tests/meta/test_run_state.gd](godot/tests/meta/test_run_state.gd) 加 inline v1 JSON fixture，断言 `test_load_v1_save_injects_east_round` / `test_load_v2_save_roundtrip`

### Step 6 — NodeResult HP/Gold 按 session_kind 分流（依赖 Step 1 + Step 4）
- **改**: [godot/meta/node_result.gd:30-32](godot/meta/node_result.gd:30) `_hp_delta_for_rank` 接 `session_kind` 参数，从 BalanceConstants 查对应数组；`from_battle / _init` 接 session_kind
- **测试**: [godot/tests/meta/test_node_result.gd](godot/tests/meta/test_node_result.gd) 加 `test_hanchan_4th_loses_4hp / test_hanchan_1st_gets_60_gold / test_east_round_unchanged_from_m7`

### Step 7 — UI 风圈显示（与 Step 5/6 可并行，依赖 Step 2）
- **改**: [godot/ui/four_player_table/center_info_panel.gd:64-67](godot/ui/four_player_table/center_info_panel.gd:64) `round_name(hand_index)` 改为 `round_name(hand_index, hands_per_round=4) -> String`：`hand_index < hands_per_round → "东 X 局"`，`else → "南 X 局"`（其中 X = `hand_index - hands_per_round + 1`）
- **bind_state 改**: 接受 `total_hands / hands_per_round` 参数，或直接读 BattleState.round_wind 来决定显示
- **测试**: [godot/tests/scenes/](godot/tests/scenes/) 或新建 `test_center_info_panel.gd`：`test_hand_5_shows_south_1 / test_hand_4_still_east_4 / test_hand_8_shows_south_4`
- **chapter_map_view**：在 hanchan 节点画 "南" 标记或不同色边框（ASCII 草图见下）

```
chapter map node icons (ASCII):
  east round:           hanchan:
   ┌────┐                ┌════┐
   │ 战 │                │ 战 │  ← 双线边框 + 暗红
   └────┘                └════┘
   floor 5 (east)        floor 12 (south)
```

### Step 8 — Simulation baseline 6（依赖 Step 1-6 全部）
- **跑**: [godot/tools/simulation_harness.gd](godot/tools/simulation_harness.gd) 改默认 max_nodes_per_run 为 200（已是），多运行批量章 3 全 hanchan 配置
- **产出**: 人工写 `docs/playtest/2026-05-04-baseline-6-hanchan.md`（按 `docs/playtest/_template.md` 格式）
- **关注指标**: 平均局数（含连庄）、HAND_LIMIT 触发率（应 < 0.5%）、HP 终值分布、立直率/和牌率对比 baseline 5、跨章节胜率
- **不写代码** — 这步是数据采集 + 平衡观察，结果驱动 M8.5 / M9 方向

### Step 9 — HeuristicAi 终局策略（**拆 M8.5，不阻塞 M8 主线**）
- 当前 [godot/ai/heuristic_ai.gd](godot/ai/heuristic_ai.gd) 是纯单局 evaluator，无"剩余局数 / 排名 / 点数差"输入
- 半庄战南场（hand 5-8）应有 "防守领先 / 拼搏垫底" 策略 — `decide_riichi` 阈值按排名调整、`decide_discard` 加防守权重
- 改造面较大（evaluator 签名变更），独立 milestone 推进
- **M8 验收**: AI 仍用单局 evaluator 但能跑通 8 局；记 P2 known limitation 写进 baseline 6 报告

## 端到端验证

新文件 [godot/tests/integration/test_chapter_3_hanchan_boss_e2e.gd](godot/tests/integration/test_chapter_3_hanchan_boss_e2e.gd)：

1. 构造 RunState，跳到章 3 Boss 节点
2. assert NodeRef.session_kind == "hanchan" 且 NodeKind.kind == BOSS
3. 用固定 seed 通过 BattleNodeRunner.run_battle_to_node_result 跑完
4. assert hand_index 走过 1..8（含至少 1 次 round_wind 切换 E→S）—— 中途记录 round_wind 历史
5. assert NodeResult.hp_delta ∈ `[0, 0, -2, -4]` 范围
6. assert RunState 存档可 v2 roundtrip
7. assert center_info_panel.round_name 在 hand 5-8 期间返回 "南 X 局"

跑通命令：
```bash
godot --headless --path godot --import  # 必须先重建 class cache
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
    -gdir=res://tests -ginclude_subdirs -gexit
```

## 可并行步骤

```
Step 1 ⇄ Step 4              （独立）
Step 2 → Step 3              （串行 — Step 3 调 Step 2 的 GameDriver 新签名）
Step 5 ⇄ Step 6 ⇄ Step 7    （都依赖 Step 4，但彼此独立）
Step 8                       （依赖前 7 步全部）
Step 9                       （拆独立 M8.5）
```

最大并行度：第一波 (Step 1, Step 2, Step 4) 三人并行，第二波 (Step 3, Step 5, Step 6, Step 7) 四人并行。

## 风险与已知坑

1. **Boss 签名能力跨南场假设** — 已 grep `godot/skills/` 全目录，**无 `hand_index` 引用**，Boss 能力跨南场无硬编码风险。但 Step 4 前再次 `grep -rn 'hand_index\s*==' godot/skills/ godot/scripts/` 兜底确认。
2. **立直棒跨场风** — GameDriver 现有逻辑通过 BattleState 携带 riichi_sticks，理论已正确，但 Step 2 必须新增 `test_riichi_sticks_carry_e4_to_s1()` 显式覆盖。
3. **本场棒在节点边界清零** — 半庄战 8 局结束后 honba 不延续到下个节点（spec 默认行为）。检查 [godot/meta/battle_node_runner.gd](godot/meta/battle_node_runner.gd) honba 起始为 0；Step 3 验收时新增 `test_node_runner_starts_honba_at_zero`。
4. **HAND_LIMIT=60 极端连庄** — 理论无上限；60 是 8×7.5 余量，触发即 abort 并记 sim 异常（log warning）。
5. **章 1-2 默认东风战配置遗漏** — Step 4 配置必须**显式**列章 1-2 = "east_round"，否则 NodeRef 默认值（也是 east_round）会掩盖配置 bug；测试用 `test_chapter_1_2_session_explicitly_configured_in_generator` 锁定。
6. **center_info_panel 调用方** — Step 7 改 `bind_state` 签名时要 grep 全部调用方，确保所有 caller 都传 hands_per_round（默认值 = 4 让 M7 调用兼容）。
7. **GUT class cache** — 修改 `class_name` 字段（NodeRef 加新字段不算，但若新增 class 要排重）后必须 `godot --headless --path godot --import` 重建。CLAUDE.md 已明示。

## Critical Files

修改：
- [godot/battle/game_driver.gd](godot/battle/game_driver.gd) — Step 2 核心
- [godot/meta/balance_constants.gd](godot/meta/balance_constants.gd) — Step 1
- [godot/meta/battle_node_runner.gd](godot/meta/battle_node_runner.gd) — Step 3
- [godot/meta/node_ref.gd](godot/meta/node_ref.gd) — Step 4
- [godot/meta/chapter_map_generator.gd](godot/meta/chapter_map_generator.gd) — Step 4
- [godot/meta/run_state.gd](godot/meta/run_state.gd) — Step 5
- [godot/meta/node_result.gd](godot/meta/node_result.gd) — Step 6
- [godot/ui/four_player_table/center_info_panel.gd](godot/ui/four_player_table/center_info_panel.gd) — Step 7

新增测试：
- [godot/tests/battle/test_game_driver_hanchan.gd](godot/tests/battle/test_game_driver_hanchan.gd) — Step 2
- [godot/tests/integration/test_chapter_3_hanchan_boss_e2e.gd](godot/tests/integration/test_chapter_3_hanchan_boss_e2e.gd) — 端到端

新增文档：
- `docs/superpowers/specs/2026-05-04-half-honba-design.md` — 简短补充 spec（spec §13 加 M8 一项），可选
- `docs/superpowers/plans/2026-05-04-half-honba.md` — 本 plan 落到项目仓库的副本（按 spec §16 "新增计划应放此目录"约束）
- `docs/playtest/2026-05-04-baseline-6-hanchan.md` — Step 8 产出

## 后续动作（非本 plan 范围）

- M8.5：HeuristicAi 终局策略（半庄南场战略）
- M9：待 baseline 6 数据出后另起 brainstorm（候选：教程/新手引导 / 联机 / 移动端 / 半庄数值精调）
