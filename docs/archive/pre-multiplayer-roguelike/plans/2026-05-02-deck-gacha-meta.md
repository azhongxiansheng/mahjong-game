# 麻将王 — 里程碑 5：抽卡 + 卡包 + 元进度 + 存档（实施 plan）

> **状态**：进行中。M0-M4 已完成（PR #11-#26）。本 plan 把 spec §9（抽卡 / 卡包 / 经济）+ §4.2（SaveSystem）+ §13.5（一句话定义）落到可推进的 4 步任务。

**Spec 锚点**：
- `docs/superpowers/specs/2026-05-01-mahjong-king-design.md`
  - §9 抽卡 + 卡包 + 经济（最关键）
    - §9.1 稀有度 4 档（普通 60% / 精良 28% / 史诗 10% / 神话 2%）
    - §9.2 三种获取渠道（节点单抽 / 卡包 / 商店单挑）+ 各自保底
    - §9.3 起始包之外的卡组成长（未填槽位不影响规则可玩性）
    - §9.4 元进度声望线性解锁
  - §4.2 SaveSystem autoload（M4 占位过，M5 实装）
  - §13.5 里程碑 5 一句话定义

**前置依赖（已落地）**：
- M4 完整 Run 流程骨架（PR #23-#26）✅
- `meta/save_system.gd` autoload 占位 + 4 个空 API ✅
- `meta/starter_packs.gd` 占位（v1 仅控场可选）✅
- `meta/run_state.gd` 含 `deck: Dictionary` 字段 ✅

---

## 范围

**In-scope**：
- **抽卡数据层**：`Rarity` 枚举 + 4 档概率；`TileVariant` / `AbilityCard` 单卡；`Deck` 玩家整 Run 卡组
- **抽卡渠道**：`Gacha.draw_node_single` / `Gacha.open_pack` / `Shop.refresh` 三个 v1 实装
- **保底机制**：节点单抽 8 次无史诗+ → 必出；卡包内每包至少 1 张精良+
- **卡牌池**：`CardPool` v1 hardcoded 占位（M1 demo 技能数 + 普通"无技能牌"凑数）；M6 内容化为 `.tres`
- **SaveSystem 真持久化**：`save_run` / `load_run` / `has_save` / `clear_run` 落 `user://savegame.json`；RunState + ChapterMap 全量序列化
- **元进度（声望）**：跨 Run 累计声望 → `user://meta_progress.json`；通关 +50 / 失败 +5（v1 占位数值，M7 平衡）
- **节点结算 hook 抽卡**：`RunFlow.complete_node` 后调 `Gacha.draw_node_single` → 加进 `RunState.deck`
- **商店占位场景升级**：`shop_placeholder.tscn` 改为真 4 槽刷新（节点种子决定）+ 金币消费
- **抽卡 / 卡包 / 商店 UI**：占位级（卡名 + 稀有度 + "确认"按钮）；真动画留 M6 美术

**Out-of-scope**：
- 30+ 牌技能内容生产 / 8-10 角色能力 / 3 章 Boss（M6）
- 抽卡 / 卡包打开动画 / 商店 UI 雕花（M6 美术）
- AIProfile + 行为权重（M7）
- 章节性概率修正（spec §9.1 末段，留 M7 平衡）
- 消耗品（spec §9.2 商店列了"消耗品"槽位，v1 不实装）

---

## 关键设计决策

### D1. 卡组数据结构

**决策**：3 个独立类（`TileVariant` / `AbilityCard` / `Deck`），都 `extends RefCounted` 纯数据。

```gdscript
class_name TileVariant extends RefCounted
var id: StringName              # "thunder_5w_v1" 等（M6 来自 .tres）
var display_name: String        # "5万·闪电"
var description: String
var tile_id: int                # TileId.W5
var rarity: int                 # Rarity.Kind
var skill_resource_path: String # 占位：v1 留空，M6 改 SkillResource

class_name AbilityCard extends RefCounted
var id: StringName
var display_name: String
var description: String
var rarity: int

class_name Deck extends RefCounted
var tile_variants: Dictionary = {}  # TileId → TileVariant
var abilities: Array = []           # Array[AbilityCard]
var max_abilities: int = 5          # spec §14：5 槽
```

**理由**：解耦内容（M6 .tres 资源）与运行时数据；v1 可仅用 hardcoded 占位填池子。

### D2. 三抽卡渠道实现

**决策**：每渠道单独 static func，输入 seed + 池子 + 保底状态，输出 `GachaResult`。

```gdscript
class_name Gacha

# 节点单抽：1 张牌或角色能力（spec §9.2 第 1 行）
static func draw_node_single(pool: CardPool, pity: PityState, seed: int) -> GachaResult

# 卡包：5 张牌（卡包主题决定池子偏向）
static func open_pack(pool: CardPool, pack_theme: StringName, seed: int) -> GachaResult

# 商店刷新：4 个槽（明牌可挑选）
static func refresh_shop(pool: CardPool, seed: int) -> Array  # Array[GachaResult]

class_name GachaResult extends RefCounted
var kind: StringName    # "tile" / "ability"
var tile_variant: TileVariant
var ability: AbilityCard
var rarity: int
```

### D3. 保底机制

**决策**：`PityState` 跨 Run 持久化。

```gdscript
class_name PityState extends RefCounted
var node_single_no_epic_streak: int = 0  # 节点单抽连续 N 次无史诗+
const NODE_SINGLE_PITY_THRESHOLD: int = 8

func record_draw(rarity: int) -> void:
	if rarity >= Rarity.Kind.EPIC:
		node_single_no_epic_streak = 0
	else:
		node_single_no_epic_streak += 1

func node_single_pity_active() -> bool:
	return node_single_no_epic_streak >= NODE_SINGLE_PITY_THRESHOLD
```

卡包保底直接在 `Gacha.open_pack` 内强制：先抽 4 张普通分布，最后 1 张走"精良+ 池子"。

### D4. CardPool v1 hardcoded

**决策**：v1 池子由 `meta/card_pool.gd` 静态返回 `Array[TileVariant]` 与 `Array[AbilityCard]`。M6 改 `.tres` Resource 加载。

v1 池子大小：
- 牌技能：M1 demo 5 张（thunder_5w / seal_chun / soul_drain / xray_1w / unfuriten_5p）+ 30 张占位"无技能牌"（每 TileId 一个普通占位变体），共 35
- 角色能力：M1 demo 1 张（seabed_hunter）+ 5 张占位

各档稀有度按 spec §9.1 概率分布：60/28/10/2。v1 池子每档至少有内容（占位）。

### D5. SaveSystem 真持久化

**决策**：`user://savegame.json` 存 RunState 全量；`user://meta_progress.json` 存元进度。

序列化：每个数据类加 `to_dict() / from_dict(d)` 方法对。NodeRef / NodeResult / Deck / TileVariant 等都需要这个 pair。SaveSystem 调用顶层 RunState.to_dict() 递归。

ChapterMap 已生成的部分必须保存（程序生成不能仅靠 seed 复现，因为 advance_to 后的 current_node 也变）。

### D6. 元进度（声望）

**决策**：`MetaProgress` 单例（autoload 或纯数据 + SaveSystem.save_meta），含 `renown: int` 字段。Run 结束时调用 `MetaProgress.add_renown(amount)`。

v1 仅累计声望显示在 RunSummary，**不实际解锁内容**（M6 内容生产时再做"声望 ≥ N → 解锁起始包 X"）。

---

## 文件结构（拟）

```
godot/meta/
├── rarity.gd                # 第 1 步
├── tile_variant.gd          # 第 1 步
├── ability_card.gd          # 第 1 步
├── deck.gd                  # 第 1 步
├── card_pool.gd             # 第 1 步
├── gacha.gd                 # 第 1 步
├── gacha_result.gd          # 第 1 步
├── card_pack.gd             # 第 1 步
├── pity_state.gd            # 第 1 步
├── save_system.gd           # 第 2 步：实装真持久化（替占位）
└── meta_progress.gd         # 第 2 步：跨 Run 声望

godot/ui/run/
├── shop_view.tscn/.gd       # 第 3 步：4 槽刷新 + 金币消费（替 placeholder）
├── pack_open_view.tscn/.gd  # 第 3 步：5 张牌占位展示
└── meta_progress_view.tscn/.gd  # 第 3 步（M5 收尾）：声望 + 解锁列表占位

godot/tests/meta/
├── test_rarity.gd
├── test_deck.gd
├── test_card_pool.gd
├── test_gacha.gd
├── test_pity_state.gd
├── test_save_system.gd      # 现有占位测试改为真持久化测试
└── test_meta_progress.gd
```

---

## 任务清单

### 第 1 步：抽卡 + 卡包 数据层（本 PR）

- [ ] `Rarity` 4 档枚举 + 概率常量 + helper
- [ ] `TileVariant` / `AbilityCard` 单卡数据
- [ ] `Deck` 卡组容器（add / remove / has / by_tile_id）
- [ ] `CardPool` v1 hardcoded（5 demo skill + 30 占位 + 6 ability 占位）
- [ ] `PityState` 跨抽卡保底状态
- [ ] `GachaResult` 单次抽卡结果
- [ ] `Gacha.draw_node_single` / `Gacha.open_pack` / 一个 helper `Gacha.refresh_shop`
- [ ] `CardPack` 卡包主题（火力 / 速胡 / 控场 主题权重）
- [ ] GUT 单测：8 个文件，覆盖概率边界、保底触发、卡包主题、deck add/remove

### 第 2 步：SaveSystem 真持久化 + MetaProgress（后续 PR）

- [ ] 各数据类补 to_dict / from_dict
- [ ] SaveSystem 真 4 API + JSON 读写 + 错误处理
- [ ] MetaProgress.add_renown / save_meta / load_meta
- [ ] GUT：roundtrip 测（RunState save → load 对比）

### 第 3 步：UI + 节点 hook（后续 PR）

- [ ] RunFlow 内节点结算 hook `Gacha.draw_node_single`
- [ ] `shop_view.tscn` 真 4 槽刷新（节点 seed 决定）+ 金币消费
- [ ] `pack_open_view.tscn` 5 张牌占位展示
- [ ] `meta_progress_view.tscn` 声望显示

### 第 4 步：F6 e2e + Run 间存档恢复（后续 PR）

- [ ] F6 跑通"开 Run → 节点抽卡 → 商店买卡 → 退出 → 重启 → load → 继续"
- [ ] e2e GUT 集成

---

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| v1 池子内容贫乏（仅 6 demo + 占位） | 占位牌"无技能"合法（spec §9.3 末段保证），不阻塞流程；M6 填内容 |
| ChapterMap 序列化复杂（NodeRef / 边表 / current_node） | to_dict/from_dict 严格成对；GUT roundtrip 强制 |
| SaveSystem 文件损坏处理 | M5 v1 简化：load 失败返 null，UI 提示"存档损坏"；M7 加版本号迁移 |
| 抽卡概率分布偏差 | 每档稀有度 GUT 测样本 1000 次，验证频率 ±5% 内 |
| Run 中途存档与 SkillRegistry 状态绑定（技能 consumed 标志等） | v1 暂只存 deck（卡组内容），不存技能 runtime consumed 状态；玩家在节点中途退出 = 该节点重新开始（M5 不修这种细节）|

---

## 验证

- **plan + 第 1 步（本 PR）**：GUT 全套 ≥107 文件 + ~50 个新 cases 全绿；现有 0 回归
- 后续 PR 按步走
