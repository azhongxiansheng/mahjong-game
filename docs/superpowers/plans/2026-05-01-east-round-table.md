# 麻将王 — 里程碑 3：东风战 + 4 人桌 + 牌背 + 归属可视化（实施 plan）

> **状态**：**进行中**。里程碑 2（单局对战 vs 1 AI，PR #13）已合并 main，BattleController API 已稳定。本 plan 自原 brainstorm 草案升级为正式实施 plan：基于 M2 事实把原 5 个开放问题全部写死答案，并细化任务到可勾选粒度。任务按"第 1-4 步"拆批，每批一组 commits（与里程碑 2 风格一致）。

> **文档定位：** 东风战与四人牌桌实现追溯。当前行为以代码、测试和现行多人玩法 PRD / ADR 为准；原始肉鸽总 spec 已归档，不再作为事实源。

**前置依赖（已落地）**：
- 里程碑 0a-0e（规则引擎全栈）✅
- 里程碑 1（技能框架 + 6 demo）✅
- 里程碑 2（`BattleController.run_to_end()` 单局编排 + `SimpleAi.decide_discard(seat)`）✅

**Goal（来自 spec §13.3）：**
> 东风战 + 4 人桌 + 牌背 + 归属可视化 — 4 套牌背贴图 + AI 座位 + 完整东风战流程。

---

## 范围

**In-scope：**
- **完整东风战流程**：东 1-东 4 局；庄家轮转；连庄（庄家胡或听牌流局时）+ 本场计数；立直棒跨局保留；4 局后整场结束（含连庄超时上限处理）。
- **4 人桌 UI 布局**：玩家（seat 0）固定下家；3 个 AI（seat 1/2/3）下/对/上家。每家显示手牌（自家正面 + 他家牌背）、弃牌河、副露区、点数、风牌、立直棒、振听标记。
- **牌背 4 套贴图**：seat 0 金色固定；seat 1-3 按 AI 主题着色。一张 `TileInstance.owner_seat` 直接决定背面贴图（不论当前 holder）。
- **归属可视化（核心创新）**：每张牌"由谁带入"在视觉上始终可辨。
- **印章小图标**：带技能的牌右下角加 rarity 着色 stamp；鼠标悬停 tooltip 显示技能 id / 名 / 描述 / 触发时机。
- **角色能力面板**：屏幕右侧专属垂直面板，5 槽位（v1 默认）。点击展开详情。
- **透明牌可视化**：被 §8.5 类技能 reveal 后，对 owner 端显示半透明牌面；其他玩家仍看牌背。`SkillCtx.revealed_tiles` 是唯一数据源。
- **跨局状态对象**：新增 `GameState`（暂名）持东风战层状态（hand_number / honba / riichi_sticks / cumulative scores），按 hand 重建 `BattleState`。

**Out-of-scope：**
- 单局对战内的对局逻辑、AI 决策、SkillScheduler（里程碑 2）
- Run 节点流程 / 商店 / 卡包 / 抽卡（里程碑 4-5）
- 30+ 技能内容生产（里程碑 6）
- 3 章 Boss + 起始包内容（里程碑 6）
- 联机 / 远端权威（spec §4.3 标记 Phase 2）

**里程碑 2 已固化的事实（来自 PR #13）：**
- `BattleController` 是 **per-hand** 实例化（不是单例）：`_init(seed, dealer_seat)` 自建 BattleState/TurnEngine/SkillRegistry/SkillScheduler/SimpleAi。
- 主入口：`run_to_end() -> {last_event, events}`，跑到 `EXHAUSTIVE_DRAW` 或 `WIN_DECLARED` 退出。
- 公共方法：`apply_ron(winner_seat, ron_tile, discarder_seat) -> bool`（外部驱动用）。
- 结算结果通过最末 `WIN_DECLARED` 事件 `extra` 字段传出（含 `payout`、`han`、`fu`、`base_points`、`yakuman_multiplier`、`winner_total`）—— **`state.scores` 不会被自动更新**，跨局累加由本 plan 引入的 `GameDriver` 负责。
- AI 接口：`SimpleAi.decide_discard(seat: Seat) -> Tile`，**M2 用最弱实现，M7 才会做 `AIProfile` 资源化**。

---

## 关键设计决策

### D1. 跨局状态对象：新增 `GameDriver`（不扩 `BattleState`）

**决策（已定）**：新增 `GameDriver`（在 `battle/game_driver.gd`）。**避开 `GameState` 名字** —— `scripts/game_state.gd` 已用 `class_name GameState`（旧中麻代码），按 PR #11 教训不可重名。

理由：
- M2 已确认 `BattleController` 是 per-hand 实例化、`BattleState` 仅描述一局快照。跨局信息塞 `BattleState` 违反单一职责。
- `GameDriver` 是上层驱动器，持东风战层状态：`hand_index`（0..3 表东 1..东 4）、`honba`、`riichi_sticks`、`cumulative_scores: Array[int]`、`dealer_seat`、`battle: BattleController`（当前活跃 hand）、`finished: bool`。
- 命名"驱动器"也呼应 M2 的命名学（`BattleController` 驱动一局；`GameDriver` 驱动多局）。

### D2. 4 套牌背贴图来源

spec §10 仅规定"4 套花纹/底色"，未指定来源。

**候选方案**（按里程碑 3 实装时的灵活度排序）：

| 方案 | 来源 | 制作成本 | v1 可接受度 |
|---|---|---|---|
| **A. 纯色 + 角标** | 4 个 16-color 渐变色块 + seat 编号角标，程序化生成（GDScript 画 ImageTexture） | 0 | ✓ 占位 OK，后续可替换 |
| **B. 现有 atlas 复用** | 抽 `mahjong_atlas0_*.png` 中已有的 1 个牌背图，4 色 modulate | 0 | ✓ 但 modulate 与"NEAREST + WHITE 调制"不变量冲突，**不建议** |
| **C. 4 套手绘** | 美术外包 / 自绘 4 张 80×120 PNG | 中 | 最终目标 |
| **D. AI 生成** | Stable Diffusion / Midjourney 出 4 张统一风格 | 低 | 后期可补 |

**决策（已定）**：**先 A 后 C**。v1 用程序化色块跑通归属可视化的代码路径 + 数据流；美术替换是后续 PR 的纯资源换图，不阻塞功能实装。

### D3. AI 主题着色（不引入 AIProfile）

spec §10：「seat 1..3 AI：随关卡 AI 主题着色」 —— 暗示 AI 有"主题"概念。

**决策（已定）**：M3 **不**引入 `AIProfile` 资源类型（按 M2 plan 的 Out-of-scope 已明确推到 M7）。M3 用：
- 3 个 `SimpleAi` 实例分别给 seat 1/2/3（M2 的现成实现，无需改）。
- 牌背颜色硬编码到 `card_tile_back.gd`：`SEAT_TILE_BACK_COLORS = [GOLD, RED, GREEN, BLUE]`，按 `owner_seat` 取色。
- 文档化：M7 引入 `AIProfile` 时把 `tile_back_color` 字段补上即可，UI 只需把 `SEAT_TILE_BACK_COLORS[i]` 换成 `ai_profiles[i].tile_back_color`，是局部增量修改。

### D4. 4 人桌布局

**决策**：经典正方形布局，seat 0 下方、seat 1 右侧、seat 2 上方、seat 3 左侧；他家手牌随座位旋转 90°/180°/-90°。

| 区域 | 用途 |
|---|---|
| 中心区 | 4 家弃牌河（呈"井"字布置） + 中央信息板（局/本场/Dora 指示牌/牌墙剩余） |
| 自家区（下） | 玩家手牌（正面）+ 副露区 + 立直/振听状态 + 点数 |
| 他家区（左/上/右） | 牌背手牌（旋转）+ 副露区 + 状态 + 点数 |
| 屏幕**右侧**外延 | 角色能力面板（5 槽，垂直） |

**ASCII 草图**（按 AGENTS.md 闸门 C 要求）：

```
┌──────────────────────────────────────────────────────┬──────┐
│                                                      │ 角色 │
│                ┌────────────────┐                    │ 能力 │
│                │   Seat 2 (AI) │                    │ 面板 │
│                │   背面手牌    │                    │      │
│                └────────────────┘                    │ ┌──┐ │
│                                                      │ │  │ │
│   ┌──────┐    ┌──────────────┐    ┌──────┐          │ ├──┤ │
│   │Seat 3│    │ 中心信息板   │    │Seat 1│          │ │  │ │
│   │ AI   │    │ 东1局 0本   │    │ AI   │          │ ├──┤ │
│   │弃牌  │    │ Dora: 4m    │    │弃牌  │          │ │  │ │
│   │河    │    │ 牌墙: 70    │    │河    │          │ ├──┤ │
│   │      │    └──────────────┘    │      │          │ │  │ │
│   └──────┘                        └──────┘          │ ├──┤ │
│                                                      │ │  │ │
│                ┌────────────────┐                    │ └──┘ │
│                │ Seat 0 (玩家) │                    │      │
│                │ 正面手牌      │                    │      │
│                │ 点数 25000    │                    │      │
│                └────────────────┘                    │      │
└──────────────────────────────────────────────────────┴──────┘
```

**决策（已定）**：**新建** `godot/ui/four_player_table/four_player_table.tscn`。`scenes/game_ui.tscn` 是中麻旧 UI（M2 plan 已标 legacy），不动。

### D5. 印章 + tooltip + 透明牌

- **印章**：`CardTile` 节点子加一个 `TextureRect` 子节点（80×120 右下角 16×16），仅在该 `TileInstance.skill != null` 时显示；颜色按 `skill.rarity` 取（4 档稀有度色：灰/蓝/紫/金）。
- **tooltip**：复用 Godot 内置 `Control.tooltip_text`，hover 弹技能 `id` / `display_name` / `description` / `triggers`。
- **透明牌**：消费端（`CardTile`）每 frame 检查 `BattleState.revealed_tiles[seat_id]` 中是否有自己的 `TileInstance.id`；命中则换"半透明牌面"渲染（正面贴图 + alpha=0.5），否则维持牌背。**只对 owner=玩家=seat 0 端生效；其他端继续看牌背。**

### D6. 跨局衔接：`hand_done(result)` → `GameState.advance_or_finish`

`GameState` 持局间核心规则：

| 条件 | 行动 |
|---|---|
| 庄家自摸 / 庄家荣胡 / 流局且庄家听牌 | 连庄：`honba += 1`，dealer 不变，hand_index 不变 |
| 闲家自摸 / 闲家荣胡 / 流局且庄家不听 | 流转：`hand_index += 1`，dealer 顺时针旋转，`honba = 0` |
| 流局：摸完所有立直棒在桌 | `riichi_sticks += sum(this_hand_riichi_calls)`；胡牌时由胜者收走 |
| `hand_index >= 4` 且**未连庄** | 整场结束：发出 `GAME_END` 事件，结算总积分 |

**连庄上限**：v1 不限（连庄到底也合法，符合 spec §3.2 注释）；里程碑 6 平衡时再视需要加上限。

**Payout 应用**（M2 留给 M3 的工作）：

`BattleController._settle_xxx` 把 `ScoreCalc.calculate(...)` 的 `result` dict 通过最末 `WIN_DECLARED.extra` 传出，但**未应用到 `BattleController.state.scores`**（M2 plan Out-of-scope）。`GameDriver` 在 `controller.run_to_end()` 返回后，从 `events` 数组找最末 `WIN_DECLARED`，把 `extra.payout` 应用到 `cumulative_scores`：

```gdscript
# 简化伪代码
for ev in events.reverse_iter():
    if ev.type == &"WIN_DECLARED":
        var payout: Dictionary = ev.extra.get("payout", {})
        for seat_id in payout:
            cumulative_scores[seat_id] += payout[seat_id]
        cumulative_scores[ev.actor_seat] += extra.get("winner_total", 0)
        break
```

流局立直棒：`riichi_sticks` 在流局时跨局保留；下次胡牌（自摸或荣胡）由胜者收走。这部分逻辑已在 `ScoreFormula` 内核计算 winner_total 时考虑（包含 `state.riichi_sticks * 1000`）—— 我们只需在流局路径下让 `riichi_sticks` 跨 hand 保留即可。

---

## 文件结构（最终）

```
godot/
├── battle/
│   └── game_driver.gd                # 新：跨局 (东 1..4) 驱动器（D1）
├── ui/
│   └── four_player_table/
│       ├── four_player_table.tscn    # 新：4 人桌主场景
│       ├── four_player_table.gd
│       ├── seat_panel.tscn/.gd       # 子组件：单 seat 区域（含旋转）
│       ├── center_info_panel.tscn    # 子组件：局/本场/Dora/牌墙剩余
│       ├── ability_panel.tscn/.gd    # 角色能力 5 槽面板
│       ├── card_tile_back.gd         # 牌背色块 + 透明牌（D2/D5）
│       └── tile_stamp.gd             # 技能印章 + tooltip（D5）
├── tests/
│   ├── battle/
│   │   └── test_game_driver.gd       # 新：连庄 / 流转 / 流局 / 跨局立直棒
│   └── scenes/
│       └── four_player_table_smoke.tscn  # F6：占位 BattleState 渲染 4 家
└── docs/superpowers/plans/
    └── 2026-05-01-east-round-table.md   # 本文档
```

---

## 任务清单（按 4 步分批，每步一组 commits）

### 第 1 步：GameDriver 数据层（纯 GDScript + GUT，无 UI）

- [ ] `godot/battle/game_driver.gd`：`class_name GameDriver`，持 `hand_index` / `honba` / `riichi_sticks` / `cumulative_scores: Array[int]` / `dealer_seat: int` / `seed: int` / `battle: BattleController` / `finished: bool`
- [ ] API：
  - `_init(p_seed: int = 0)` 初始化 cumulative_scores=[25000]×4
  - `start_hand() -> BattleController` 用 `seed + hand_index` 实例化 BC，把 cumulative_scores 注入 `battle.state.scores`
  - `apply_result(events: Array) -> Dictionary` 从最末 `WIN_DECLARED` 取 `extra.payout` 应用到 cumulative_scores；返 {kind, winner_seat?, payout?, han?, fu?}
  - `advance_or_finish(run_result: Dictionary) -> Dictionary` 解析 last_event；连庄/流转/结束三分支；返 {finished, renchan, kind}
  - 流局路径：调 `ExhaustiveDraw.calculate(...)`（已在 0d 实装）拿罚符 + 庄家是否听牌
- [ ] 单测 `tests/battle/test_game_driver.gd` 覆盖：
  - 庄家自摸 → renchan，honba+=1，scores 更新
  - 闲家自摸 → 流转，honba=0，dealer 顺转
  - 闲家荣胡庄家 → 流转，honba=0
  - 流局庄家听 → renchan，honba+=1
  - 流局庄家不听 → 流转，honba=0
  - 流局立直棒留台 → riichi_sticks 跨 hand 保留；下次胡牌由胜者收走
  - 整场结束：东 4 局且不连庄 → finished=true
  - 整场不结束：东 4 局连庄 → finished=false（不限上限，spec §3.2）
  - 点数守恒：sum(cumulative_scores) + riichi_sticks*1000 == 100000

### 第 2 步：4 人桌 UI 主场景 + seat_panel + center/ability_panel 占位

- [ ] `four_player_table.tscn` 主布局（参见 D4 ASCII 草图）
- [ ] `seat_panel.tscn/.gd` 子组件，参数 `seat_id`，按 `seat_id ∈ {1,2,3}` 旋转 -90/180/+90；显示手牌（自家正面、他家牌背）+ 弃牌河 + 副露区 + 点数 + 风牌 + 立直/振听标记
- [ ] `center_info_panel.tscn/.gd` 显示局/本场/Dora 指示牌列/牌墙剩余
- [ ] `ability_panel.tscn/.gd` 5 槽空容器（M3 内不放真实 ability，留接口）

### 第 3 步：归属可视化（牌背色块 + 印章 + 透明牌）

- [ ] `card_tile_back.gd`：常量 `SEAT_TILE_BACK_COLORS = [GOLD, RED, GREEN, BLUE]`，按 `tile_instance.owner_seat` 程序化生成 80×120 ImageTexture（D2 方案 A）
- [ ] `card_tile_back.gd` 透明牌路径：每帧/每事件检查 `BattleState.revealed_tiles[viewer_seat]` 中是否含本 TileInstance.id；命中则换正面贴图 + alpha=0.5；只对 viewer=seat 0 生效
- [ ] `tile_stamp.gd`：80×120 牌右下角 16×16 `TextureRect`，仅 `tile_instance.skill != null` 时显示；颜色按 `skill.rarity ∈ {0,1,2,3}` 取灰/蓝/紫/金；hover tooltip 显示 `id / display_name / description / triggers`

### 第 4 步：集成 + F6 端到端 demo

- [ ] `four_player_table.gd` 接入 `GameDriver`：`_ready` 创建 driver，`Button.pressed` 触发 `start_hand → run_to_end → apply_result → advance_or_finish` 一局；on-screen 更新 cumulative_scores、hand_index、honba
- [ ] F6：`tests/scenes/four_player_table_smoke.tscn` 用 driver 跑一整场东风战；事件 log 至少含 1 次连庄、1 次流局、1 次胡牌
- [ ] 验收：sum(cumulative_scores) + riichi_sticks*1000 == 100000；UI 4 家正确旋转、归属色块按 owner_seat 区分

---

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| BattleController 不应用 payout 到 state.scores | GameDriver 自己解析最末 WIN_DECLARED 的 extra.payout 应用到 cumulative_scores（D6 已写明）；点数守恒 GUT 强制 |
| 4 家 UI 旋转 + 弃牌河"井字"布局工程量大 | 拆 `seat_panel` 为子组件，参数 `seat_id` 决定旋转角；旋转通过 Godot 节点 `rotation_degrees` 属性，不重写贴图 |
| 牌背贴图美术 v1 不到位影响"归属可视化"卖点 | D2 方案 A 程序化色块 v1 验证流程；美术补 PR 不阻塞 |
| 透明牌 reveal 路径与 SkillCtx.revealed_tiles 数据源未连通 | M1 已定义 `SkillCtx.reveal_tile_to`；UI 端只读 `BattleState.revealed_tiles`，单向数据流 |
| 跨局立直棒收走遗漏（导致点数不守恒） | `test_game_driver.gd` 强制覆盖；assert 每 hand 结束时 sum(cumulative_scores) + riichi_sticks*1000 == 100000 |
| `class_name GameDriver` 与现有名字重复 | 已 grep 验证无冲突（PR #11 教训：先 grep 再加 class_name） |

---

## 验证

- **plan 阶段（本 PR 第一个 commit）**：仅 plan 文档更新；无代码改动；不跑测试。
- **第 1 步实装（本 PR 第二个 commit）**：
  - GUT：`test_game_driver.gd` 全套 PASS；现有 ~94 个测试零回归
- **第 2-4 步实装（后续 PR）**：
  - F6：`four_player_table_smoke.tscn` 4 家正确显示、归属色块不串、点击 advance 进入下一局
  - 端到端：手动跑一场东风战，至少含一次连庄、一次流局、一次立直，结算正确
