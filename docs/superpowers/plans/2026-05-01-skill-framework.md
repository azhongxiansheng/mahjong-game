# 麻将王 — 里程碑 1：技能框架 + 5 demo 技能 + 1 角色能力 实现计划（追溯文档）

> **状态**：实装已完成（commits 3be3160 / 5afb497 / 077b25b / f290905）。本文档为**追溯式 plan**，固化里程碑 1 的范围、任务清单、覆盖现状与遗留观察项。后续里程碑可据此引用。

**Spec 锚点：** `docs/superpowers/specs/2026-05-01-mahjong-king-design.md` §13 里程碑 1 / §6.1 事件枚举 / §8.1-§8.10 技能灵感库

**Goal（来自 spec §13.1）：**
> 技能框架 + 5 个 demo 技能 + 1 个 demo 角色能力 — 不接对局，独立场景验证 SkillScheduler 调度顺序、链路防护、双触发；5 demo 选自 §8.1-§8.9 的 5 个不同方向（增番 / 阻胡 / 抓马 / 透明牌 / 立直系各一），角色能力选 §8.10 中 1 张验证 is_ability 路径。

---

## 范围

**In-scope：**
- 数据类型：`SkillResource` / `SkillHook`（接口约定）/ `SkillRegistry` / `BattleEvent` / `TileInstance` / `SkillCtx`
- 调度器：`SkillScheduler`（owner/holder 分组排序、链路深度防护、双触发去重、静默原则、abort 路径）
- 5 demo 牌技能（`godot/skills/hooks/`）：覆盖 §8.1-§8.9 五个不同方向
- 1 demo 角色能力：验证 `is_ability` 路径
- F6 手测场景（`godot/tests/scenes/skills/`）：每技能/能力 1 个 .tscn

**Out-of-scope：**
- 接入真实日麻引擎对局（属里程碑 2）
- AI 决策（里程碑 2）
- UI 接入（里程碑 3）
- 完整技能内容（30+ 牌技能 / 8-10 角色能力，属里程碑 6）

---

## 文件结构（实装）

| 路径 | 用途 |
|---|---|
| `godot/battle/battle_event.gd` | `BattleEvent.make(name, actor_seat)` 事件值对象 |
| `godot/battle/skill_ctx.gd` | 技能可读写的"本次事件上下文"（han_deltas / ron_cancelled / haitei_forced_seat / transferred_points / revealed_to / furiten_cleared 等） |
| `godot/battle/skill_scheduler.gd` | 调度器：emit_event → _collect → _sort → _dispatch |
| `godot/battle/tile_instance.gd` | 牌实例（owner_seat / holder_seat / skill 绑定） |
| `godot/skills/skill_resource.gd` | 技能定义（id / triggers / rarity / is_ability / hook_script / consumed） |
| `godot/skills/skill_hook.gd` | hook 接口约定 |
| `godot/skills/skill_registry.gd` | 注册表（含 reg_order 单调计数） |
| `godot/skills/hooks/{thunder_5w,seal_chun,soul_drain_hatsu,xray_1w,unfuriten_5p,seabed_hunter}_hook.gd` | 6 个 demo hook |
| `godot/tests/battle/test_skill_*.gd` + `test_battle_*.gd` + `test_tile_instance.gd` | 调度器与基础类型 GUT 单测 |
| `godot/tests/skills/test_*.gd` | 6 个 demo 各自单测 |
| `godot/tests/scenes/skills/skill_*_test.tscn/.gd` + `_test_scene_base.gd` | 6 个 F6 手测场景 |
| `godot/tests/_fixtures/spy_hook.gd` | scheduler 测试用 spy fixture |

---

## 任务清单与完成状态

### Step 1 — 技能框架基础类型 ✅ commit `3be3160`
- [x] `BattleEvent` 值对象（name / actor_seat）
- [x] `TileInstance`（包 Tile + owner_seat / holder_seat / skill）
- [x] `SkillResource`（owner_triggers / holder_triggers: `Array[StringName]`，rarity, is_ability, hook_script, consumed）
- [x] `SkillHook` 接口约定 + `SkillRegistry`（含 reg_order 单调计数）
- [x] `SkillCtx`（mutation API：add_han / cancel_ron / transfer_points / clear_furiten / force_tsumo / reveal_tile_to）
- [x] 27 个基础类型 GUT 用例

### Step 2 — SkillScheduler 调度器 ✅ commit `5afb497`
- [x] `emit_event(BattleEvent) -> SkillCtx` 入口
- [x] 三步派发：`_collect` → `_sort` → `_dispatch`
- [x] 排序规则：`(group asc, rarity desc, reg_order asc)`，group=0 为 owner+ability，group=1 为 holder
- [x] 链路深度防护：`event_chain_depth` 超过 MAX(16) → 警告 + dump_state + 不派发剩余
- [x] 双触发去重：同 ability 一次事件中即使 owner+holder 两个组都匹配，只触发一次（`seen_ability_ids`）
- [x] 静默原则：单个 hook 抛错不影响后续 hook、不污染 chain_depth
- [x] 边界过滤：`consumed=true` / `hook=null` / `holder_seat<0` / event 不匹配 都正确跳过
- [x] **20 个调度器 GUT 用例**（test_skill_scheduler.gd）+ **本计划新增 2 个补盲用例**：
  - `test_holder_group_reg_order_tiebreak_within_same_rarity`（holder 组同 rarity 的 reg_order tiebreak）
  - `test_ability_and_normal_owner_sort_by_rarity_then_reg_order`（ability 与普通 owner 牌技能的混排）
  - 合计 **22/22 passed**

### Step 3 — 5 demo 牌技能 + 1 demo 角色能力 ✅ commit `077b25b`
| Demo | 类别（spec §8.X） | 触发组 / 事件 | hook 文件 | 单测 |
|---|---|---|---|---|
| 5万·闪电 | §8.1 增番 | owner / WIN_DECLARED | `thunder_5w_hook.gd` | `test_thunder_5w.gd` (2) |
| 中·封印 | §8.3 阻胡 | owner / RON_DECLARED + discarder 检查 | `seal_chun_hook.gd` | `test_seal_chun.gd` (3) |
| 发·吸魂 | §8.4 抓马 | holder / WIN_DECLARED | `soul_drain_hatsu_hook.gd` | `test_soul_drain_hatsu.gd` (2) |
| 1万·透视 | §8.5 透明牌 | owner / TILE_DRAWN | `xray_1w_hook.gd` | `test_xray_1w.gd` (2) |
| 5筒·解振听 | §8.6 立直系 | owner / FURITEN_TRIGGERED | `unfuriten_5p_hook.gd` | `test_unfuriten_5p.gd` (3) |
| 海底狩人 | §8.10 角色能力 | owner（ability）/ HAITEI_TRIGGERED | `seabed_hunter_hook.gd` | `test_seabed_hunter.gd` (2) |
- [x] 14 个 demo 技能 GUT 用例

### Step 4 — F6 手测场景 ✅ commit `f290905`
- [x] `_test_scene_base.gd` 程序化 UI 基类（Node2D + Label + Buttons + on-screen 断言）
- [x] 6 个 .tscn 场景（每技能/能力 1 个）：正路按钮 + 反例按钮 + on-screen PASS/FAIL
- [x] 在 Godot 编辑器中分别按 F6 验证：所有 demo 行为符合 spec

### Step 5 — 收尾（本 PR）
- [x] 补 2 个调度器边界测试（见 Step 2）
- [x] 写本 plan 文档作为追溯记录
- [x] 完整 GUT 套件回归 100% 通过

---

## 关键设计决策

1. **三层稳定排序**`(group, -rarity, reg_order)`：保证 owner 优先于 holder、稀有度高的先触发、同 rarity 按注册顺序，避免随机性。
2. **静默原则**：单个 hook 抛错只 log，不打断同事件其他 hook 的派发，也不污染 chain_depth。让一张坏牌不能 brick 整局。
3. **链路深度 16**：避免技能之间相互触发导致死循环；超限时 dump 一份 BattleState 关键字段（scores / furiten_flags / ron_cancelled / haitei_forced_seat）便于事后定位。
4. **不引入 EventBus**：技能调度是一个 emit 同步派发流程，不做 publish/subscribe 总线。状态机直接 `_sched.emit_event(...)` 即可。
5. **owner 与 holder 分组**：spec §8 对每张牌的"持有者效果 / 弃出后效果"分得很清，分组比统一队列更不容易写错。
6. **ability 与普通牌混排进 owner 组**：is_ability=true 也用 group=0。让"角色能力 vs 增番牌技能"都按 rarity/reg_order 排序，无须特殊路径。

---

## 测试覆盖矩阵

| spec §13.1 验证点 | 实装覆盖 |
|---|---|
| 调度顺序 | owner 先 holder ✓ / 同组 rarity 降序 ✓ / 同 rarity reg_order 升序 ✓（owner 与 holder 各一） / ability + 普通牌混排 ✓ |
| 链路防护 | depth 增减 ✓ / 15→16 正常 ✓ / 16→17 abort ✓ / hook 抛错不污染 depth ✓ |
| 双触发 | 单 ability owner+holder 仅 1 次 ✓ / 多 ability 各 1 次 ✓ / consumed 跳过 ✓ |
| 静默原则 | 抛错不影响下一 hook ✓ / null hook 优雅跳过 ✓ |
| 过滤 | 错事件不触发 ✓ / holder_seat=-1 不入 holder 组 ✓ / 空 trigger 列表不触发 ✓ |

总测试数：**61 GUT cases**（基础类型 27 + 调度器 22 + 6 demo skills 14）+ **6 F6 手测场景**

---

## 遗留观察（不阻塞里程碑 1，留给后续）

1. **dump_state 字段无单测**：链路超限时 `_dump_state()` 输出的 dict 内容（scores / furiten_flags / ron_cancelled / haitei_forced_seat）目前只通过 GUT log 间接验证。若未来要做"事故现场恢复"，需把 _dump_state 暴露为可测 API。当前作为诊断日志已足够。
2. **xray_1w 的 stub_tile**：`xray_1w_hook.gd:8-12` 当前合成一个占位 Tile 用于 `reveal_tile_to`；真正在对局中应从下家手牌实际取牌。**留到里程碑 2 接入对局时改造**。
3. **F6 复合场景**：当前每个场景只验证一张技能在隔离条件下的行为；两张技能在同一事件中（如 thunder_5w + soul_drain_hatsu 同时 WIN_DECLARED）的可视化交互未做 .tscn。**单测已覆盖（test_owner_group_fires_before_holder_group），所以非必需**。

---

## 验证

- `godot --headless --path godot --import` 重建 class cache
- `godot --headless --path godot -d -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` → **0 fail / 0 parse error**
- 在 Godot 编辑器中逐一打开 6 个 `tests/scenes/skills/*.tscn` 按 F6，每个场景的"正路按钮"显示 PASS、"反例按钮"显示 PASS（已在合并到 main 之前手测过；本 PR 仅追加文档与单测，不改 scene 行为）
