# 麻将王 — 里程碑 2：单局对战 vs AI（事件总线串通）实现计划

> **Spec 锚点：** `docs/superpowers/specs/2026-05-01-mahjong-king-design.md` §13 第 2 项
> **前置依赖：** 里程碑 0a-0e（规则引擎全栈）✅、里程碑 1（技能框架 + 5 demo + 1 角色能力 + 6 F6 测试场景）✅
> **下一里程碑：** §13 第 3 项「东风战 + 4 人桌 + 牌背 + 归属可视化」

## Context（为什么做这件事）

里程碑 0 实现了纯日麻规则引擎（役/符/点数/振听/Dora/流局/立直），里程碑 1 实现了技能框架本身（SkillResource / SkillScheduler / SkillCtx / SkillHook + 6 个 F6 单技能场景）。但 **两块代码至今没有真正串到一起**：

- `TurnEngine.draw_for_current()` 等 `apply_xxx` 方法不发任何事件；
- `SkillScheduler.emit_event()` 等待外部喂 `BattleEvent`，但没有人喂；
- 没有 `BattleController` / `GameDriver` 编排「摸→弃→鸣牌窗口→下家→...→流局/胡牌」整局循环；
- 没有最小日麻 AI；旧 `ai_player.gd` 是中麻、不可复用。

里程碑 2 把这条端到端链路打通到「能在 F6 跑完一整局，看到役/符/点数结算」的最小可验证状态，并通过集成测试钉住 owner / holder 触发归属在真实日麻流程下的正确性（spec §13 第 2 项原话）。**本里程碑不追求漂亮 UI，也不追求多样化 AI**——这两件事分别在里程碑 3、6 处理。

## 已落地范围

1. **TurnEngine 公共方法签名一字不动**。所有 emit 行为放在 BattleController：BC 调 `engine.draw_for_current()` 拿 Tile 之后，自己 `scheduler.emit_event(BattleEvent.make(TILE_DRAWN, ...))`。0e 的 17 条 turn_engine 单测无需改。
2. **`battle/battle_controller.gd`（新建，269 行）**：
   - `_init(seed, dealer_seat)` 自建 BattleState/TurnEngine/SkillRegistry/SkillScheduler/SimpleAi
   - `run_to_end()` 编排 DRAW→DISCARD→CLAIM(skip)→ADVANCE 循环，emit `GAME_BEGIN` / `TILE_DRAWN` / `TILE_DISCARDED` / `EXHAUSTIVE_DRAW` / `TSUMO_DECLARED` / `RON_DECLARED` / `WIN_DECLARED`
   - `apply_ron(winner_seat, ron_tile, discarder_seat)` 公开方法（外部 driver 调用，绕过主循环）
   - `_check_tsumo` / `_check_ron`：WinPattern.detect → YakuEvaluator.evaluate → 无役校验
   - `_settle_tsumo` / `_settle_ron`：ScoringWinContext 字段填充 → ScoreCalc.calculate → emit WIN_DECLARED with payout
   - `_adapt_yaku_list`：把 `yaku/YakuList`（YakuEvaluator 出口，含 entries: Array[YakuEntry]）桥接为 `ScoringYakuList`（ScoreCalc 入口，含 yaku: Array[Dict] + is_yakuman: bool）
3. **`ai/simple_ai.gd`（新建，19 行）**：`decide_discard(seat) -> Tile` 随机弃手牌一张。不立直、不鸣牌、不杠、不主动宣告自摸（结算由 BC 自动判定）。**有意做最弱**——本里程碑只验证 pipeline。
4. **`tests/integration/test_battle_e2e.gd`（新建，4 路径）**：
   - 路径 A：随机种子跑完一局，最末事件 ∈ {EXHAUSTIVE_DRAW, WIN_DECLARED}、scores 守恒 100000、event_chain_depth 归零
   - 路径 B：fixture 七対子手 + wall 顶牌 = W9 → 自摸 → 验证 WIN_DECLARED.extra 含 payout/winner_seat、han > 0
   - 路径 C：fixture 同 B + 调 `BC.apply_ron(0, W9, 1)` → 验证 `event.actor_seat=0` ≠ `event.tile_instance.owner_seat=1` 且中间存在 RON_DECLARED
   - 路径 D：在 path C 之上注册「中·封印」demo（seat 1 名下）→ apply_ron 返 false、`ron_cancelled[0]=true`、最末事件不是 WIN_DECLARED、技能被消耗
5. **`tests/scenes/battle_e2e_demo.tscn` + `.gd`（新建，F6 手测）**：极简 UI（4 Label + RichTextLabel + 「重跑」Button）；不引用 atlas / TextureExtractor，避开纹理不变量。
6. **`scripts/test_run_core.sh`**：`-gdir` 增加 `res://tests/integration`。

### 副带修的 main 旧债（必要前置）

里程碑 2 串接 YakuEvaluator → ScoreCalc 时撞到 PR #7 合并冲突遗留的 class_name 重名：

- `core/rules_japanese/win_context.gd` 与 `core/rules_japanese/yaku/win_context.gd` 同声明 `class_name WinContext`
- `core/rules_japanese/yaku_list.gd` 与 `core/rules_japanese/yaku/yaku_list.gd` 同声明 `class_name YakuList`

`Class "X" hides a global script class` parse error 让 `test_score_calc` / `test_fu_calculator` / `test_payout_calculator` / `test_win_context` / `test_yaku_list` 5 个测试文件被 GUT **静默忽略**（main 上 8 failing tests + ~50 个被忽略的 assertion）。

把 ScoreCalc 端（数量较少）改名：
- `core/rules_japanese/win_context.gd`: `class_name WinContext` → `ScoringWinContext`
- `core/rules_japanese/yaku_list.gd`: `class_name YakuList` → `ScoringYakuList`
- `score_calc` / `fu_calculator` / `payout_calculator` 同步类型注解
- 5 个相关测试文件批量替换符号

YakuEvaluator 端（30+ detector + 20+ test）保持 `WinContext` / `YakuList` 不变。

## Out-of-scope（推迟到后续里程碑）

- 4 套牌背贴图、归属可视化（→ 里程碑 3）
- 高质量 AI（弃牌评分、立直决策、鸣牌权衡）（→ 里程碑 7）
- Run / 节点 / 抽卡 / 商店（→ 里程碑 4-6）
- 完整子事件：`HAITEI`/`HOUTEI`/`RINSHAN`/`CHANKAN`/`URADORA_REVEALED`（已由规则引擎层算，但本里程碑 BC 不显式 emit）
- `BattleEventBus` 抽成独立类（spec 给出的命名仅是概念；当下复用 `SkillScheduler` 已够；里程碑 3 引入 PvP 接口前再分离）
- 中麻 `ai_player.gd` / `hand_display*` / `card_*` 旧脚本（不动、不删，留给将来 `legacy/` 搬迁专门 plan）
- `Tile.owner_seat` 字段（commit 2b87929 在 PR #9 合并里被吃掉，当前 milestone 2 通过 BC 维护 TileInstance.owner_seat 绕过；里程碑 3 引入卡组系统时一并修）

## 验证方式

1. `bash scripts/test_run_core.sh` 全绿 — 540+ tests passing（修复 class_name 冲突后从 491 涨到 542）。
2. `godot --headless --path godot -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration -gexit` 通过 — 4/4 路径全过。
3. 编辑器打开 `tests/scenes/battle_e2e_demo.tscn`，按 F6：
   - 看到 4 座手牌发出 13 张；
   - 事件 log 含 `GAME_BEGIN` 起、`EXHAUSTIVE_DRAW` 或 `WIN_DECLARED` 收尾；
   - 多按几次「重跑（seed +1）」，无 crash、无 assert。

## 提交清单（实际落地）

| commit | 内容 |
|--------|------|
| `chore: 补 plan 0b yaku 测试漏 commit 的 .gd.uid 文件` | 7 个 yakuman 役満测试 .gd 已 commit 但 .gd.uid 漏了 |
| `feat(battle): 里程碑 2 第 1 步 — BattleController 最小循环 + SimpleAi` | path A green |
| `fix(rules): WinContext/YakuList class_name 冲突 — 改名 ScoringWinContext/ScoringYakuList` | 副带修 main 旧债 |
| `feat(battle): 里程碑 2 第 2 步 — BC 自摸结算 + 路径 B 集成测试` | path B green |
| `feat(battle): 里程碑 2 第 3 步 — apply_ron + 路径 C owner/holder 归属` | path C green |
| `feat(battle): 里程碑 2 第 4 步 — 路径 D cancel_ron 技能干预` | path D green |
| `feat(battle): 里程碑 2 第 5 步 — F6 demo 场景 + 同步 plan 至 docs/` | demo + plan markdown |
