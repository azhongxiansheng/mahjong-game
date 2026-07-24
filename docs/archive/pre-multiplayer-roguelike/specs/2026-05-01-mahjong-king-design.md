# 麻将王（Mahjong King）设计规范 — v1 (PvE Roguelike，日麻规则)

- 作者：jingx8885
- 日期：2026-05-01
- 状态：design / awaiting implementation plan
- 仓库：jingx8885/mahjong-game
- 分支：feat/mahjong-king-design

## 1. 概述

把 `mahjong-game` 仓库重设计为 **麻将王 — Mahjong King**，一款把**日本立直麻将（日麻）**与小丑牌（Balatro）触发式技能、集换式卡牌（CCG）卡组构建、Roguelike Run 进度结构融合的单机攻防战游戏。

核心创新：利用麻将"每种牌天然 4 张"的结构 —— 一桌 4 个玩家各自带 1 张，凑成完整 136 张麻将。每张牌：

- 由其**拥有者**（owner）带入对局，**牌背图案**显示归属
- 牌面可带**技能**（拥有者技能 + 持牌者技能两套触发）
- 通过**抽卡 / 营地 / 商店**获得带不同技能的同名牌（"5万·闪电" vs "5万·冰冻"）

设计基调：把日麻"读舍牌、放铳、振听、立直、Dora 流转"这些天然攻防元素与"技能化、可见性操作、反向得分"的卡牌战术叠加，做出**有意思的攻防战**。

## 2. 范围

### 2.1 In-scope (v1)

- 单机 PvE：1 名玩家 vs 3 名 AI（每名 AI 自带主题化卡组）
- **日麻规则**：完整东风战（東風戦），4 局 = 1 个 Run 节点；役 / 符 / 点数 / 立直 / 振听 / Dora / 裏 Dora / 一发 / 王牌 / 海底河底岭上 / 抢杠 / 包牌 / 流局 / 连庄 / 本场，全套
- Roguelike Run：StS 风格节点图，3 章 + 章末 Boss
- 卡组构建：**起始仅几张技能牌 + 1-2 张角色能力**，其余通过抽卡 / 卡包 / 营地 / 商店 在 Run 中逐步填充；卡组容量上限 = 34 个变体槽 + 5 个角色能力槽
- 技能系统：Hybrid 数据模型（`.tres` Resource + 可选 GDScript 勾子）
- 抽卡 + 元进度（"声望"解锁新卡组/AI/关卡）
- 复用现有 80×120 麻将牌 atlas；新画角色能力卡 / UI 框 / 牌背
- 桌面优先（Win/Mac/Linux），1280×720+，鼠标 + 键盘

### 2.2 Out-of-scope (v1)

- 多人 PvP / 联机匹配（架构留扩展点，但 v1 不实现）
- 任何形式的内购、付费抽卡、广告变现
- 移动端 / Web 端（架构允许，但 UI 不为之优化）
- 账户系统、云存档、leaderboard
- 现有仓库里的 `achievement_*` / `leaderboard.tscn` / `network_*.gd` 半成品（v1 不接入）
- 中麻 / 国标麻将规则（现有 `hu_rule.gd` / `win_checker.gd` 是中麻番制，v1 整体替换为日麻引擎）

### 2.3 后续阶段（仅作扩展点说明，不在 v1 实现）

- **Phase 2 PvP**：把 `BattleController` 抽成接口，加 `NetworkedBattleController` 走 server 权威 + 事件回放。事件总线设计从 day 1 就为此预留。
- **Phase 2 半庄战 / 南风战变体**：东风战通过后，作为 Run mode 选项加入。

## 3. 术语表

### 3.1 通用术语

| 术语 | 含义 |
|------|------|
| Tile / 牌 | 麻将牌名（W1..W9 / T1..T9 / S1..S9 / E S W N Z F B），共 34 个 |
| TileInstance | 局内一张实物牌，带 owner_seat 和可选 SkillResource |
| Variant / 变体 | 同一张牌（如 5 万）的不同技能版本，如 "5万·闪电" 与 "5万·冰冻" |
| Owner / 拥有者 | 把牌带入对局的玩家（座位号 0..3） |
| Holder / 持牌者 | 当下持有这张牌的玩家（摸到/吃到/碰到/杠到） |
| 角色能力 (Character Ability) | 卡组里 34 张麻将牌之外的全局/被动效果卡，每个角色能力对应 1 个鲜明人格风格的"超能力"。早期文档中曾用 "Joker" 命名，已统一改为"角色能力" |
| 起始包 / Starter Pack | 新 Run 时玩家选择的初始牌堆，包含少量牌技能和 1-2 张角色能力，其余卡组容量在 Run 内逐步填充 |
| 卡包 / Card Pack | 商店或节点奖励中以"包"形式打开的多张牌捆绑，按稀有度模板出牌，含保底；与单抽是两个独立产出渠道 |
| Run | 一次 Roguelike 通关尝试：选起始卡组 → 推进节点图 → 击败 3 章 Boss 或失败 |
| Seat | 座位号 0..3（0 固定玩家，1..3 AI） |
| Phase | 对局子阶段：DRAW / DISCARD / CLAIM / SETTLE |

### 3.2 日麻术语

| 术语 | 含义 |
|------|------|
| 役 (Yaku) | 胡牌成立的"型"，如平和、断幺九、立直、混一色等。日麻无役不能胡 |
| 符 (Fu) | 胡牌时的基础分单位，由对子/刻子/杠/听牌型/和牌方式累计 |
| 番 (Han) | 役的累计计数。番 + 符共同决定点数 |
| 立直 (Riichi) | 门清听牌时声明，下 1000 点棒，限制此后弃牌必须摸切 |
| 一发 (Ippatsu) | 立直后下一次自摸或他人弃牌前胡牌，+1 番 |
| 振听 (Furiten) | 听牌中含有自己曾经弃过的牌时，禁止荣胡（只能自摸） |
| Dora | 宝牌指示牌的下一张为 Dora，每张 +1 番（不构成役） |
| 裏 Dora | 立直胡牌时翻开宝牌指示牌的下一层 |
| 自摸 (Tsumo) | 自己摸到胡牌张 |
| 荣胡 (Ron) | 别人弃牌时胡牌 |
| 包牌 / 责任払 (Pao) | 因特定行为（如喂大三元/大四喜的最后一张）承担全额点数 |
| 王牌 (Dead Wall) | 牌墙末尾固定 14 张：4 张岭上 + 10 张宝牌指示牌位 |
| 海底 / 河底 / 岭上 / 抢杠 | 4 种特殊和牌时机，各 +1 番 |
| 东风战 (East-only) | 东 1 局-东 4 局共 4 局；含连庄可超出 |
| 连庄 / 本场 | 庄家胡牌或流局听牌时连庄，本场数累计，每本场和牌时 +300 点 |
| 流局 | 牌墙摸完未胡。听牌不罚符共享 3000 点（按听牌人数分配）；途中流局 5 种：四风连打、九种九牌、四杠散了、四家立直、三家和了 |

## 4. 架构

### 4.1 工程结构

在现有 `godot/` 工程内重组（**不**新建 Godot 工程）。按职责拆 6 个子包：

```
godot/
├── core/                      # 纯逻辑：无 Godot 节点依赖，便于单测
│   ├── tile/                  # TileId、Wall、Hand、Meld 数据类
│   ├── rules_japanese/        # 日麻规则：役判定、符算、点数公式、振听、Dora、流局
│   │   ├── yaku/              # 各役判定（每个役 1 个文件，约 30+）
│   │   ├── fu_calculator.gd
│   │   ├── score_calculator.gd
│   │   ├── furiten_checker.gd
│   │   ├── dora_indicator.gd
│   │   └── exhaustive_draw.gd
│   └── turn_engine/           # 摸打弃 / 鸣牌 / 立直状态机
├── skills/                    # SkillResource 定义 + 内置勾子脚本 + SkillRegistry
├── battle/                    # 一局对战的状态机、事件总线、技能调度
├── meta/                      # Run 流程、地图、商店、抽卡、存档（SaveSystem）
├── ai/                        # AI 玩家：决策树/启发式 + 主题化 AI 配置
└── ui/                        # 场景、控件、动效。复用现有 hand_display* / card_animator
```

迁移策略：现有 216 个平铺脚本**不一次全搬**，而是在 §13 各里程碑推进时按需搬迁 —— 当一个里程碑要新动某个旧脚本时，先把它搬到目标子包再改；纯新增代码直接落到对应子包。日麻规则引擎是**全新**模块，不复用 `hu_rule.gd` / `win_checker.gd` / `special_win_checker.gd` 的中麻逻辑（搬迁后这些可能被整体替换或归档）。CLAUDE.md 已记录的"WHITE 调制 / NEAREST 过滤 / 80×120 / AtlasTexture"等不变量在搬迁过程中必须严格保留。

### 4.2 Autoload

新增：

- `SkillRegistry` — 启动期扫 `res://skills/data/*.tres` 注册所有 SkillResource，按 id 索引
- `BattleEventBus` — 局内事件总线（仅 battle 场景活跃时实例化，battle 退出时销毁）
- `SaveSystem` — 写 `user://savegame.json`（元进度 + 当前 Run 快照）

保留现有：

- `GameManager` — 用户会话（v1 用作本地玩家档案占位）
- `TextureExtractor` — 麻将牌 atlas 切片（不变量，详见 CLAUDE.md）

### 4.3 PvP 扩展点

`battle/battle_controller.gd` 抽象成接口：

- v1：`LocalBattleController` —— 单机权威，技能在本地解析
- Phase 2：`NetworkedBattleController` —— 走 server 权威 + 事件回放，技能调度同样走事件总线，server 端可重放/裁定

**v1 必须守住的约定**：所有对局副作用都通过 `BattleEventBus` 发出 + `SkillScheduler` 处理，不写"绕过总线直接修改 BattleState"的代码。否则 Phase 2 联机时会出现本地有效果、远端没有的不一致。

## 5. 核心数据类型

```gdscript
# core/tile/tile_id.gd —— 牌名不可变标识
class_name TileId
# 枚举值：W1..W9, T1..T9, S1..S9, E, S, W, N, Z(白), F(发), B(中)（共 34）

# skills/skill_resource.gd
class_name SkillResource extends Resource
@export var id: StringName              # "thunder_5w_v1"
@export var display_name: String        # "5万·闪电"
@export var description: String         # 玩家可读说明
@export var rarity: int                 # 0=普 1=精 2=史 3=神
@export var attached_tile: TileId       # 这个变体绑定的牌名（如 W5）；角色能力时为特殊值 NONE
@export var is_ability: bool = false    # true 表示这是角色能力卡（不绑定具体牌名，绑定 Seat）
@export var owner_triggers: Array[StringName]   # 例如 ["on_owner_drawn", "on_owner_won"]
@export var holder_triggers: Array[StringName]  # 例如 ["on_held_discarded"]
@export var params: Dictionary = {}     # 数值参数（bonus_han、bonus_fu、duration 等）
@export var hook_script: GDScript       # 可选；为 null 时走 params + 内置 effect 引擎
@export var icon: Texture2D             # 印章/角标小图（可空走 rarity 默认色）

# meta/deck.gd
class_name Deck
var tile_variants: Dictionary           # TileId -> SkillResource，部分填充（0..34 槽）
                                        # 起手仅含几张；缺位的 TileId 在对局 instantiate 时
                                        # 用普通无技能 TileInstance 补满 4 张/牌名
var abilities: Array[SkillResource]     # 角色能力，长度 0..MAX_ABILITIES（默认 5）
                                        # 起手 1-2 张，Run 中逐步获取

# core/rules_japanese/yaku_list.gd —— 一手胡牌的役清单
class_name YakuList
var yaku: Array[YakuEntry]              # [{id: "riichi", han: 1}, {id: "pinfu", han: 1}, ...]
var dora_count: int                     # Dora + 裏 Dora + 赤 Dora 累计
var is_yakuman: bool                    # 役满
var yakuman_multiplier: int             # 单倍/双倍/...

# core/rules_japanese/score_calc.gd —— 点数计算结果
class_name ScoreCalc
var fu: int                             # 符
var han: int                            # 番
var base_points: int                    # 基本点 = fu × 2^(2+han)
var payout: Dictionary                  # {payer_seat: points, ...}（区分自摸/荣胡/包牌）

# battle/riichi_state.gd —— 一座位的立直状态
class_name RiichiState
var declared: bool
var declared_turn: int                  # 立直宣言的圈数
var ippatsu_window: bool                # 是否还在一发窗口
var double_riichi: bool                 # 第一巡立直
var riichi_stick_paid: bool             # 已下 1000 点棒

# battle/dora_indicators.gd
class_name DoraIndicators
var visible: Array[TileInstance]        # 已翻开的宝牌指示牌（杠 1 翻 1）
var hidden_uradora: Array[TileInstance] # 立直胡牌时才翻

# battle/furiten_state.gd —— 一座位的振听判定
class_name FuritenState
var permanent: bool                     # 立直后含弃牌张 → 永久振听本局
var temporary: bool                     # 听牌期间见和未荣胡 → 暂时振听到下次自摸
var waits: Array[TileId]                # 当前听牌张（驱动振听判断）

# battle/battle_state.gd —— 一局快照（纯数据，便于 AI 推演 + 异常 dump）
class_name BattleState
var seats: Array[Seat]                  # 长度恰好 4
var wall: Array[TileInstance]           # 牌墙（剩余可摸）
var dead_wall: Array[TileInstance]      # 王牌：4 岭上 + 10 宝牌位
var dora_indicators: DoraIndicators
var discards_per_seat: Array[Array]     # 每座位的弃牌河（按弃牌顺序）
var current_seat: int                   # 当前回合座位
var phase: BattlePhase                  # DRAW / DISCARD / CLAIM / SETTLE
var round_wind: TileId                  # E（东风战恒为东）
var hand_number: int                    # 1..4（东 1-东 4 局）
var honba: int                          # 本场数
var riichi_sticks: int                  # 桌上立直棒数
var event_chain_depth: int              # 当前事件链深度（防无限循环）

# battle/seat.gd
class_name Seat
var seat_id: int                        # 0..3
var seat_wind: TileId                   # E/S/W/N，由 hand_number 推算
var hand: Array[TileInstance]
var melds: Array[Meld]                  # 已亮出的 chi/peng/ankan/minkan
var points: int                         # 当前点数
var riichi: RiichiState
var furiten: FuritenState
var deck_owner: Owner                   # 0 = 本地玩家、1..3 = AI 配置

# battle/tile_instance.gd —— 局内一张实物牌
class_name TileInstance
var tile: TileId
var owner_seat: int                     # 0..3，决定牌背图案 + owner_triggers 归谁
var skill: SkillResource                # 可空（普通/无技能牌）
var is_red_dora: bool = false           # 赤 Dora（5 万/5 筒/5 索的特殊版本可标）
var is_revealed_to: Array[int]          # 被'透明牌'类技能强制可见的座位列表
```

## 6. 事件 & 技能调度

### 6.1 事件枚举

`BattleEventBus` 发出以下事件，每个携带 `BattleEvent` payload（actor seat、tile_instance、phase context、上一事件链 id）：

**通用对局事件**

| 事件 | 触发时机 |
|------|---------|
| GAME_BEGIN | 一局（hand）开始（洗牌 + 发牌完毕） |
| HAND_END | 一局结束（任意结算路径） |
| ROUND_END | 一场东风战 4 局结束 |
| PHASE_BEGIN | 进入新 phase（DRAW/DISCARD/CLAIM/SETTLE） |
| TILE_DRAWN | 当前 seat 摸了一张牌（含岭上） |
| TILE_DISCARDED | 当前 seat 弃了一张牌 |
| TILE_CLAIMED | 任意 seat 吃/碰/杠了刚弃的牌 |
| MELD_FORMED | chi/peng/ankan/minkan 成立 |
| HAND_FORMED | 听牌或胡牌的 hand pattern 成立 |
| TURN_END | 回合结束（无论是否胡） |

**日麻特有事件**

| 事件 | 触发时机 |
|------|---------|
| RIICHI_DECLARED | 某座位声明立直（下棒前） |
| RIICHI_ACCEPTED | 下家接受弃牌后立直成立 |
| DORA_REVEALED | 杠成立翻开新宝牌指示牌 |
| URADORA_REVEALED | 立直胡牌时翻开裏 Dora |
| TSUMO_DECLARED | 自摸 |
| RON_DECLARED | 荣胡 |
| FURITEN_TRIGGERED | 进入振听（永久/暂时） |
| EXHAUSTIVE_DRAW | 牌墙耗尽流局 |
| ABORTIVE_DRAW | 途中流局（四风连打/九种九牌/四杠散了/四家立直/三家和了） |
| CHAMBO_TRIGGERED | 包牌责任成立（大三元/大四喜/字一色等末张喂） |
| KAN_DECLARED | 杠（暗杠/明杠/加杠） |
| HAITEI / HOUTEI / RINSHAN / CHANKAN | 海底/河底/岭上/抢杠时机命中 |
| WIN_DECLARED | 胡牌结算（汇总点数 + 派发） |

### 6.2 SkillScheduler 调度规则

每个事件在 `BattleEventBus.emit(event)` 之后，`SkillScheduler` 执行：

1. **收集候选**：扫遍局内所有 TileInstance（手牌 + 弃牌河 + 露出 meld）+ 所有 Seat 的角色能力，过滤：
   - 麻将牌：`tile.skill.owner_triggers ∩ event.type ≠ ∅` → 触发归 `tile.owner_seat`；`tile.skill.holder_triggers ∩ event.type ≠ ∅` → 触发归 tile 当前 holder（即 hand/meld 所在 seat，弃牌河里的牌没有 holder）
   - 角色能力：`is_ability == true` 的 SkillResource，绑定到 Seat 而非 Tile；owner = holder = 该能力所属 seat（角色能力不会在游戏中转手），owner_triggers 与 holder_triggers 都只对该 seat 触发一次（即同事件下不重复触发）
2. **排序**：先 owner-trigger 后 holder-trigger；同一组内按 (rarity desc, registration order asc)
3. **串行执行**：每个候选技能 `await` 完成（动画 + 副作用），再执行下一个；副作用通过 `BattleState` mutation + 二次 emit 表达
4. **链路防护**：每次 `emit` 把 `BattleState.event_chain_depth += 1`；若 > MAX_EVENT_CHAIN_DEPTH（默认 16）→ 写 warn log + 中止剩余技能 + dump 当前 BattleState。事件返回后 `event_chain_depth -= 1`
5. **静默原则**：技能脚本 throw → 捕获 + log + 跳过该技能本次触发，对局继续；**不**回滚状态（回滚成本超过收益）

### 6.3 技能勾子接口

`hook_script` 必须是继承 `SkillHook` 的 GDScript：

```gdscript
class_name SkillHook
# 子类按需 override；默认全部空实现
func on_register(skill: SkillResource, registry: SkillRegistry) -> void
func on_event(skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void
# SkillCtx 提供受控 mutation API（不让脚本直接拿 BattleState 引用乱改）
# 典型 API：ctx.add_han(seat, n) / ctx.reveal_tile_to(tile, seat) /
#         ctx.cancel_ron(seat) / ctx.steal_score(from_seat, to_seat, points)
```

无 `hook_script` 的 SkillResource 走"内置 effect 引擎" —— 一组用 `params` 描述的原子效果（加番、加符、改弃牌堆顺序、跳过下一回合、强制摸特定牌、显形对手手牌指定位等），由 `skills/builtin_effects.gd` 路由。

## 7. Run 流程

```
新 Run
  ├─ 选起始卡组（3 个预设原型：火力型 / 速胡型 / 控场型）
  ├─ 进入 Chapter 1 节点图（StS 风格分支节点）
  │    ├─ 普通桌      vs 1 主题 AI + 2 杂兵 AI       奖励：1 抽 + 金币
  │    ├─ 精英桌      vs 3 主题 AI                    奖励：1 高稀+ 抽 + 金币
  │    ├─ 营地        休息 / 升级 1 张牌 / 移除 1 角色能力
  │    ├─ 商店        金币换牌 / 卡包 / 角色能力 / 消耗品
  │    ├─ 事件        文字小事件（改卡组、获得遗物等）
  │    └─ Boss 桌     章末 1 个，特殊 AI + 特殊规则
  ├─ 击败 Chapter 1 Boss → Chapter 2 → Chapter 3
  └─ 通关 / 败北 → 结算"声望" → 沉淀解锁
```

### 7.1 节点 = 一场东风战

每节点按完整东风战规则跑：

```
东 1 局 → 东 2 局 → 东 3 局 → 东 4 局，每局结束按以下分支：

  庄家和牌                → 连庄，局编号不变，本场 +1
  闲家和牌                → 进下一局，本场清零（点棒结算时立直棒归胜者）
  流局（庄家听牌）        → 连庄，局编号不变，本场 +1
  流局（庄家未听牌）      → 进下一局，本场 +1（立直棒留在桌上下次胜者收）
  途中流局（5 种之一）    → 重开本局，连庄，本场 +1（立直棒退还）

节点结算 = 进入"东 4 局结束"分支后（即闲家在东 4 局和牌、或东 4 局流局且庄家未听）
按 4 家点数排名：
  玩家排名 1 → 节点胜利，奖励高
  玩家排名 2 → 节点小胜，奖励中
  玩家排名 3 → 节点失败，扣 1 血
  玩家排名 4 → 节点惨败，扣 2 血
```

注：东 4 局庄家可能因连庄无限延长（西入条件 v1 不实现，即使庄家最高分也不强制结束节点；仅在闲家和牌或流局未听时才推进出东 4）。

预估时长：20-30 分钟/节点（含连庄 + 立直 + 杠等延长事件）。

### 7.2 起始包（Starter Pack，v1 三选一）

每个起始包由**少量**牌技能 + 1-2 张角色能力组成（具体张数见 §14），占据 34 牌槽和 5 角色能力槽中的一小部分；其余槽位通过卡包 / 抽卡 / 营地 / 商店在 Run 中逐步填充。这样保留前期抽卡随机性，避免开局即"一套完整体系"。

- **火力型起始包** — 1-2 张增番系牌 + 1 张 §8.10 偏火力的角色能力（如"統率"或"立直加護"）
- **速胡型起始包** — 1-2 张加速胡 / Dora 系牌 + 1 张偏速胡的角色能力（如"嶺上の鬼"或"山眼"）
- **控场型起始包** — 1-2 张阻胡 / 透明牌系牌 + 1 张偏控场的角色能力（如"听牌看穿"或"流局誘導"）

未填充的牌名在对局 instantiate 时**用普通无技能 TileInstance 补满**（每牌名 4 张），保证日麻规则总是有完整 136 张可摸打。

> **后续演进方向**：Phase 2 可演进为"角色"系统 —— 每个角色 = 1 个起始包 + 1 张签名角色能力（直接绑定不可替换）。新角色作为元进度解锁奖励。

### 7.3 Run 失败条件

- 玩家"血量"为唯一败北判定（按 §7.1 节点排名扣血）
- 玩家血量归零 → Run 失败
- 失败后结算"声望"，可解锁新内容
- 连续节点排名 1 给"连胜"奖励金币加成（具体值见 §14）

## 8. 技能方向示例

按用户给定的方向以及日麻特有空间，**牌技能**可分以下 9 类（§8.1-§8.9，绑 TileId），**角色能力** 灵感库见 §8.10（绑 Seat）。每类列 2-3 个具象例子，便于内容生产时 reuse 模板。**这一节属于设计灵感库，不是 v1 全量实现表**；首发会从其中精选 30 张牌技能 + 8-10 张角色能力落地（详见 §13 里程碑）。

### 8.1 增番系（Yaku Boost）

- **5万·闪电** [史] — owner 持有此牌胡牌时，役加 1 番（不构成役）
- **白板·圣光** [精] — 任何人持此牌作三元牌一员胡牌时，番数 ×1.5
- **东风·王者气** [史] — 庄家持此牌胡牌时 +2 番

### 8.2 加速胡牌系（Tempo）

- **9筒·速胡** [精] — 持牌者每弃此牌一次，下次摸牌可摸 2 张选 1
- **3索·跳跃** [精] — owner 听牌后弃此牌一次可跳过下家 1 巡
- **南风·风行** [史] — 持牌者已立直时，每自摸 +1 张多看 1 张牌墙

### 8.3 阻止对方胡牌系（Defense）

- **中·封印** [史] — 当对手宣告 RON_DECLARED 而胡牌张是 owner 弃出，可消耗此牌取消对手荣胡（变流局）
- **9万·铁壁** [精] — owner 持此牌时，本局对其荣胡的役-1 番；若降至 0 番（无役）→ 取消胡牌
- **西风·镜像** [史] — owner 立直时，此牌防一次振听（清除 FuritenState.permanent）

### 8.4 抓马反向得分系（Counter / Pao）

- **发·吸魂** [神] — 当任意对手胡牌时，owner 反获得对手得分的 30%（被胡也得分）
- **东·镜抓** [史] — owner 放铳时（自己弃牌被荣胡），对方所得分数 ×0.5，差额返还 owner
- **8索·替罪** [精] — 当 CHAMBO_TRIGGERED 触发针对 owner 时，转嫁责任给随机其他 AI

### 8.5 透明牌 / 信息系（Reveal）

- **1万·透视** [精] — owner 摸到此牌时，强制将下家手牌 1 张设为对 owner 可见（is_revealed_to）
- **白·占卜** [精] — 持牌者每巡可花 1 巡查看任意 1 张未翻 Dora 指示牌
- **2筒·诈和** [史] — owner 副露此牌时，将自己手牌 2 张伪装为随机不存在的牌显示给对手

### 8.6 立直系（Riichi）

- **南·先制立直** [神] — owner 在第 1 巡未鸣牌即可宣告立直（无需听牌）；胡牌时强加 W 立直 + 一发
- **5筒·解除振听** [史] — owner 立直后违反摸切发生振听时，可消耗此牌清除 FuritenState
- **F(发)·点棒返还** [精] — owner 立直棒被他人取走时，立即返还 1000 点

### 8.7 振听操控系（Furiten Manipulation）

- **东·迷踪** [史] — owner 弃此牌后，下家进入 1 巡暂时振听（FuritenState.temporary）
- **2万·诱铳** [史] — owner 弃此牌时，伪装成对手听牌张张型（AI 提示放铳）
- **B(中)·替身** [精] — owner 振听时，可指定一名对手承担当前振听效果

### 8.8 Dora 系（Dora）

- **6万·夺宝** [神] — owner 摸到此牌时，立即翻开 1 张额外 Dora 指示牌；该 Dora 仅 owner 享受
- **白·赤变** [精] — owner 持此牌时，将手中任意 1 张 5 万/5 筒/5 索改为赤 Dora
- **4索·指示牌操纵** [史] — owner 立直胡牌时，可重选 1 张裏 Dora 指示牌

### 8.9 役满 / 终局系（Yakuman / Endgame）

- **N(北)·一扫** [神] — owner 胡牌为役满时，全场 4 家承担（不论自摸/荣胡）
- **白·役满下限** [神] — owner 任意胡牌至少计为满贯；本局结束后此牌从牌组移除（消耗品化）
- **9筒·龙断** [神] — owner 进入海底/河底时役 ×2

> 命名 / 数值仅作示意，平衡阶段会全部迭代。每张技能牌在内容生产时必须配 §12.2 测试场景。

### 8.10 角色能力灵感库（超能力麻将系参考）

灵感来源：**天才麻将少女（咲-Saki-）**、**アカギ**、**哲也**、**ムダヅモ無き改革** 等"超能力麻将" / オカルト麻雀作品。共同特征：能力作用域大、规则破坏强、人格化鲜明 —— 在 v1 数据模型上是 `SkillResource (is_ability = true)` 绑定 Seat，但表达力允许整局/整 Run 级的规则变更。

**重要约束**：

- **命名仅作设计占位**：实现时全部用原创化中性名（避免直接借用商标人物 / 招式名）。本表保留灵感原型列只为创作期定位风格，实装资源里不使用
- 役满 / 跳满级效果统一受 §14 "役满倍数上限 = 2 倍役满" 钳制
- 这一类角色能力默认稀有度 ≥ 史诗，每 Run 同名角色能力最多持有 1 张（避免叠层失控）

| # | 灵感原型（创作期定位） | 角色能力占位名 | 类别（对照 §8.1-9） | 稀有度 | 效果概要 |
|---|------------------------|-------------|--------------------|--------|---------|
| 1 | 咲（嶺上開花） | 嶺上の鬼 | §8.6 / §8.9 | 神 | owner 每次成立杠后，岭上摸牌从牌墙顶 5 张内自由选 1（含暗杠/明杠/加杠） |
| 2 | 衣（海底狩） | 海底狩人 | §8.9 | 神 | 牌墙最后 1 张被摸时，强制改为 owner 自摸（即使非 owner 回合）；可消耗本能力 1 次 / 节点 |
| 3 | 穏乃 / まこ（山読） | 山眼 | §8.5 | 史 | 每局 GAME_BEGIN 时，owner 看到牌墙顶 10 张顺序（仅 owner 端可见） |
| 4 | Toki（一巡先見） | 一巡先見 | §8.5 | 神 | owner 每巡可花 1 巡查看自己下次摸牌；查看后可选择不摸（让给下家） |
| 5 | 加治木（読み） | 听牌看穿 | §8.5 / §8.7 | 史 | 任意对手 HAND_FORMED（听牌成立）时，owner 看到该对手听牌张列表 |
| 6 | 鶴田（流局誘導） | 流局誘導 | §8.3 | 史 | 巡数 ≥ 12 后，owner 弃牌时可消耗本能力强制本局判定为流局 |
| 7 | 大星淡（奇跡） | 三局一奇跡 | §8.1 / §8.9 | 神 | 节点内每 3 局 1 次：GAME_BEGIN 时 owner 起手 14 张含至少 1 个役牌刻子 |
| 8 | 末原（能力増幅） | 統率 | §8.1 | 史 | owner 其他角色能力的 owner_triggers 触发额度 +1 次/局（突破单事件去重） |
| 9 | 福路（一発確実） | 立直加護 | §8.6 | 史 | owner 立直后一发窗口延长至 2 巡；本能力触发后下局停用 1 局 |
| 10 | 染谷（積み込み） | 山仕込み | §8.6 | 史 | 每局 GAME_BEGIN 时，owner 可指定 1 张牌被洗到自己起手 14 张内 |
| 11 | アカギ（無謀の極） | 死中求活 | §8.1 / §8.4 | 神 | owner 点棒 < 5000 时，所有役 +2 番（含 Dora 加分）；点棒 ≥ 5000 时本能力沉默 |
| 12 | 哲也（替え玉） | 偷天换日 | §8.5 / §8.7 | 神 | 每局 1 次：将 owner 手牌 1 张与弃牌河任意 1 张交换（弃牌河那张属性归 owner） |
| 13 | デジタル（確率支配） | 確率の支配 | §8.8 | 精 | owner 翻 Dora 指示牌时强制看 3 张选 1 |
| 14 | 江口セーラ（常時听牌） | 不动听 | §8.2 / §8.3 | 神 | owner 起手即视为听牌 1 张随机牌；正常摸打仍进行，听牌张随手牌动态重算 |
| 15 | Awai（ダブル立直系） | 一発双倍 | §8.6 | 史 | owner 双立直成立时，一发番数额外 +2，且裏 Dora 多翻 1 张 |
| 16 | 上重漫（清一色寄） | 一色染心 | §8.1 | 史 | owner 起手 14 张里同色牌 ≥ 8 张时，强制清一色路线，且清一色番 +2 |

**生产指导**：上表 16 个灵感样例覆盖了 §8.1-§8.9 全部 9 类。内容里程碑（§13 第 6 步）按以下比例选取 8-10 个落地：

- 神级 4-5 个（每章 1 个 boss 奖励）
- 史诗 4-5 个（普通节点稀有奖励）
- v1 不上精良级角色能力（精良级以"加 1 番"这种小效果为主，落到牌技能上更合适）

**测试要求**：每个角色能力的 SkillResource + hook_script 都必须配 §12.2 测试场景，且涉及"规则破坏"（如 #2 强制海底归属、#7 起手保证刻子）的必须有 Property-Based Test 验证至少 100 次随机洗牌下行为一致。

## 9. 抽卡 & 卡包 & 经济

### 9.1 稀有度

| 稀有度 | 概率（单抽） | 标识 |
|--------|--------------|------|
| 普通   | 60%          | 灰色印章 |
| 精良   | 28%          | 蓝色印章 |
| 史诗   | 10%          | 紫色印章 |
| 神话   | 2%           | 金色印章 |

概率可被角色能力 / 章节修正（如 Chapter 3 普通牌概率衰减）。

### 9.2 三种获取渠道

| 渠道 | 来源 | 形态 | 保底 |
|------|------|------|------|
| **节点单抽** | 节点结算自动给 1 抽 | 1 张牌或 1 张角色能力 | 节点抽卡连续 8 次无史诗+ → 下一抽必史诗+ |
| **卡包** | 商店购买 / 精英节点奖励 | 5 张牌的捆绑包，至少 1 张精良+；卡包有主题（火力包 / 速胡包 / 控场包），出牌偏向该主题的牌技能 | 每个卡包内独立保底 |
| **商店单挑** | 商店刷新 4 个槽 | 1 张牌 / 1 张角色能力 / 1 张消耗品 | 无保底，明牌可挑选 |

### 9.3 起始包之外的卡组成长

新 Run 起手仅含起始包（§7.2，约 8-10 张牌 + 1-2 角色能力），剩余 26+ 个 TileId 槽 + 3-4 个角色能力槽通过上述三种渠道在 Run 中填充。**未填充槽位不影响日麻规则可玩性**（§7.2 末段已说明：用普通无技能牌补满 4 张/牌名）。

### 9.4 元进度

"声望"线性解锁起始包、卡包主题、角色能力池、AI 主题、节点变体；不引入付费。

## 10. 牌背 & 归属可视化

- `TileInstance.owner_seat` 直接驱动牌背贴图：4 个 seat 对应 4 套花纹/底色
  - Seat 0 玩家：金色固定
  - Seat 1..3 AI：随关卡 AI 主题着色
- 正面 = 复用现有 atlas，**完全不变**（80×120、0 padding、AtlasTexture、WHITE 调制、NEAREST 过滤）
- 带技能的牌右下角加一个"印章"小图标（rarity 着色）；鼠标悬停弹 tooltip 显示技能 id / 名称 / 描述 / 触发时机
- 角色能力在 UI 屏幕**右侧**专属垂直面板展示（默认 5 个槽位竖排），不与麻将牌混排；点击角色能力弹详情
- **透明牌可视化**：被 §8.5 类技能强制可见的对手牌，对 owner 端显示半透明牌面（其他玩家仍看到正常牌背）；is_revealed_to 列表是该可视化的唯一数据源

## 11. 错误处理

| 场景 | 处理 |
|------|------|
| SkillResource 加载失败（缺字段、引用 missing 脚本） | `SkillRegistry` 启动期标 invalid 并跳过；红字日志写 `user://logs/skill_registry.log`；不阻断主菜单 |
| 技能勾子运行时异常 throw | `SkillScheduler` 捕获 + 写 `user://logs/battle.log` + 跳过该技能本次触发；对局继续 |
| 状态机非法跃迁（如 DISCARD 时调 CLAIM） | `assert` + 友好错误对话框 + 自动 dump `BattleState` 到 `user://crash/battle_state_<ts>.json` |
| 事件链 > MAX_EVENT_CHAIN_DEPTH | warn log + 中止剩余技能 + dump BattleState |
| 振听 / Dora 状态不一致 | core 层 assert + 写 `user://logs/rules.log`；这一类是规则引擎正确性 bug，必须复现修复，不静默 |
| 听牌 / 役判定异步检查 | 走专门的 yaku/furiten checker（避免主线程阻塞），技能事件不在 check 期间 emit |

## 12. 测试策略

仓库现状无 CI、无 GDScript test runner（详见 `CLAUDE.md`）。引入分层测试：

### 12.1 核心层单测（`core/`）

- 引入 [GUT](https://github.com/bitwes/Gut) 作 dev 依赖（仅 `addons/gut/`，发布构建排除）
- **重点 1：日麻规则正确性** — 每个役 1 个测试文件，包含至少 5 个正例 + 5 个反例；符算（9 种符源）每种 2 例；点数公式（满贯/跳满/倍满/三倍满/役满/双倍役满）每档 3 例
- **重点 2：振听 / Dora / 流局 / 立直 / 包牌** — 每条规则独立测试套
- **重点 3：牌谱回归测试** — 抓真实日麻牌谱（公开来源如天凤天牌人对局）做 golden test，对每张胡牌验证我们引擎给出的役 / 符 / 番 / 点数与牌谱一致
- 命令：`godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/core`
- 包装脚本：`scripts/test_run_core.sh`

### 12.2 技能集成场景（`tests/scenes/`）

- **每个新技能强制配** 1 个 `tests/scenes/skill_<id>_test.tscn`：
  - 固定布局（手牌 + 弃牌河 + 立直状态 + Dora 等预置）
  - 一键按钮触发预期事件链
  - on-screen Label 输出 assert 结果（包含触发顺序、最终役 / 番 / 点数）
- 不接 GUT —— 是手测场景，按 F6 跑
- 涉及"技能改变规则裁定"的场景（如 §8.3 取消荣胡），必须额外覆盖"无技能时本应 RON_DECLARED 触发"的反例对照

### 12.3 异常 dump

- `BattleState` 是纯数据 → 异常时自动 `to_json` dump 到 `user://crash/`
- bug 复现脚本能从 dump 恢复 BattleState 进入对局

## 13. 实现里程碑

按以下顺序拆 implementation plan（每个里程碑通过 `superpowers:writing-plans` 单独生成 plan，走 TDD + 闸门）：

0. **日麻规则引擎重写** — `core/rules_japanese/` 全栈新建：役判定（30+ 役）、符算、点数公式、振听、Dora、流局、立直、连庄、本场。GUT 单测覆盖率 ≥ 90%。**这是所有后续里程碑的前置依赖**
1. **技能框架 + 5 个 demo 技能 + 1 个 demo 角色能力** — 不接对局，独立场景验证 SkillScheduler 调度顺序、链路防护、双触发；5 demo 选自 §8.1-§8.9 的 5 个不同方向（增番 / 阻胡 / 抓马 / 透明牌 / 立直系各一），角色能力选 §8.10 中 1 张验证 is_ability 路径
2. **单局对战 vs 1 个 AI** — 接入日麻规则引擎 + 事件总线，验证 owner / holder 触发归属在真实日麻流程下正确
3. **东风战 + 4 人桌 + 牌背 + 归属可视化** — 4 套牌背贴图 + AI 座位 + 完整东风战流程
4. **Run 流程骨架** — StS 风格地图 + 节点切换 + 营地 / 商店占位
5. **抽卡 + 卡包 + 元进度 + 存档** — SaveSystem + §9.2 三渠道抽卡 + 卡包打开动画 + 声望解锁
6. **30+ 牌技能 + 8-10 角色能力 + 3 章 Boss + 3 起始包** — 内容生产：牌技能按 §8.1-§8.9 9 类各精选 3-4 张；角色能力从 §8.10 灵感库精选 8-10 张（4-5 神 + 4-5 史诗）；3 章 Boss 各配 1 张签名规则破坏角色能力
7. **平衡迭代** — 数值表 + 玩家测试反馈

## 14. 可调参数（v1 默认值）

| 参数 | 默认 | 备注 |
|------|------|------|
| `MAX_ABILITIES` | 5 | 卡组角色能力槽数（上限） |
| `MAX_TILE_VARIANTS` | 34 | 卡组牌技能槽数（上限，34 个 TileId 各 1） |
| 起始包牌技能数 | 8-10 | 新 Run 起手含的带技能麻将牌数（占 34 槽中 ~25%） |
| 起始包角色能力数 | 1-2 | 新 Run 起手含的角色能力数（占 5 槽中 ~30%） |
| 卡包标准张数 | 5 | 1 个卡包包含 5 张牌技能 |
| 卡包内保底 | 至少 1 张精良+ | 每个卡包独立保底 |
| `MAX_EVENT_CHAIN_DEPTH` | 16 | 事件链深度上限 |
| 起始包种类数 | 3 | 火力型 / 速胡型 / 控场型 |
| 章节数 | 3 | Chapter 1..3 |
| 节点数/章 | 12-15 | 含 1 Boss |
| 稀有度概率 | 60/28/10/2 | 普/精/史/神（单抽） |
| 史诗保底 | 8 抽 | 节点单抽连续 8 抽未出史诗+ 必出 |
| 玩家血量 | 5 | 节点排名 3 扣 1 血、排名 4 扣 2 血 |
| 起家点数 | 25000 | 标准日麻 |
| 立直棒 | 1000 | 标准日麻 |
| 本场棒 | 300 | 每本场和牌时 +300 |
| 赤 Dora | 各色 5 各 1 张 | 共 3 张赤 5 |
| 役满倍数上限 | 2 倍役满 | 多役满累计封顶 |
| 节点 = 东风战局数 | 4 局 | Phase 2 可选半庄战（8 局） |

数值非架构性，平衡阶段会全部迭代。

## 15. 已知风险

| 风险 | 缓解 |
|------|------|
| **日麻规则引擎正确性**（最高优先级） | 里程碑 0 单独完成；GUT 单测覆盖 ≥ 90%；引入真实牌谱 golden test 做回归；役 / 符 / 点数三层独立测试套 |
| 技能与日麻规则交互复杂（如"取消荣胡"涉及振听 / 一发 / 立直棒回收等连锁状态） | 每个 §8.3 / 8.6 / 8.7 类技能必须配反例对照测试场景；SkillCtx mutation API 严格化，禁绕过 |
| 技能间相互作用爆炸（N×N 组合矩阵） | event_chain_depth 防护 + 静默原则 + 强制每技能配测试场景；50+ 技能后做组合 fuzz 测试 |
| 节点时长 20-30 分钟，玩家中途流失 | UI 突出"本节点剩余局数"；连庄/立直/杠用动效压短主观时长；中断恢复存档（Run 中段保存） |
| 现有 216 个平铺脚本搬迁可能破坏 autoload 引用 | 一次只搬一个子包，搬完跑现有手测场景验证 |
| 中麻规则代码（`hu_rule.gd` 等）替换不彻底导致两套规则共存 | 里程碑 0 完成时，原中麻文件统一移到 `legacy/` 目录并加 deprecated 注释；新代码不允许 import |
| AtlasTexture 不变量被无意改动 | spec 多处显式写出，搬迁时由 PR 模板 checklist 强制确认 |
| 玩家学习曲线（日麻 + Roguelike + CCG 三层） | Chapter 1 限制只能用普通/精良技能；新手教程覆盖立直 / 振听 / Dora 三大日麻关键概念 |
| **角色能力的 IP 风险**（§8.10 灵感来自咲 / アカギ / 哲也 等作品） | §8.10 表中"灵感原型"列仅创作期参考，实装命名 / 立绘 / 招式名全部原创化中性化；不直接借用商标人物 / 招式名；上线前过一遍法务审查 |
| 无 CI → 测试漂移 | 至少 `core/` 单测必须本地通过才能 commit；GitHub Actions 后续接入 |

## 16. 后续动作

本 spec 通过用户复核后：

1. 调用 `superpowers:writing-plans` 生成 §13 **里程碑 0**（日麻规则引擎重写）的实现计划
2. 实现按 TDD 推进（feedback_tdd_and_third_party 强制）—— 先写役判定测试 → 写实现 → 通过 → 下一役
3. 里程碑 0 通过后再生成里程碑 1 的实现计划，依此类推
