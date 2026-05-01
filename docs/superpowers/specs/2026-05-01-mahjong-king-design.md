# 麻将王（Mahjong King）设计规范 — v1 (PvE Roguelike)

- 作者：jingx8885
- 日期：2026-05-01
- 状态：design / awaiting implementation plan
- 仓库：jingx8885/mahjong-game
- 分支：feat/mahjong-king-design

## 1. 概述

把 `mahjong-game` 仓库重设计为 **麻将王 — Mahjong King**，一个把传统中式麻将与小丑牌（Balatro）触发式技能、集换式卡牌（CCG）卡组构建、Roguelike Run 进度结构融合的单机游戏。

核心创新：利用麻将"每种牌天然 4 张"的结构 —— 一桌 4 个玩家各自带 1 张，凑成完整 136 张麻将。每张牌：

- 由其**拥有者**（owner）带入对局，**牌背图案**显示归属
- 牌面可带**技能**（拥有者技能 + 持牌者技能两套触发）
- 通过**抽卡 / 营地 / 商店**获得带不同技能的同名牌（"5万·闪电" vs "5万·冰冻"）

## 2. 范围

### 2.1 In-scope (v1)

- 单机 PvE：1 名玩家 vs 3 名 AI（每名 AI 自带主题化卡组）
- Roguelike Run：StS 风格节点图，3 章 + 章末 Boss
- 卡组构建：34 个变体槽 + 5 个 Joker 槽（默认 N=5）
- 技能系统：Hybrid 数据模型（`.tres` Resource + 可选 GDScript 勾子）
- 抽卡 + 元进度（"声望"解锁新卡组/AI/关卡）
- 复用现有 80×120 麻将牌 atlas；新画 Joker 卡 / UI 框 / 牌背
- 桌面优先（Win/Mac/Linux），1280×720+，鼠标 + 键盘

### 2.2 Out-of-scope (v1)

- 多人 PvP / 联机匹配（架构留扩展点，但 v1 不实现）
- 任何形式的内购、付费抽卡、广告变现
- 移动端 / Web 端（架构允许，但 UI 不为之优化）
- 账户系统、云存档、leaderboard
- 现有仓库里的 `achievement_*` / `leaderboard.tscn` / `network_*.gd` 半成品（v1 不接入）

### 2.3 后续阶段（仅作扩展点说明，不在 v1 实现）

- **Phase 2 PvP**：把 `BattleController` 抽成接口，加 `NetworkedBattleController` 走 server 权威 + 事件回放。事件总线设计从 day 1 就为此预留。

## 3. 术语表

| 术语 | 含义 |
|------|------|
| Tile / 牌 | 麻将牌名（W1..W9 / T1..T9 / S1..S9 / E S W N Z F B），共 34 个 |
| TileInstance | 局内一张实物牌，带 owner_seat 和可选 SkillResource |
| Variant / 变体 | 同一张牌（如 5 万）的不同技能版本，如 "5万·闪电" 与 "5万·冰冻" |
| Owner / 拥有者 | 把牌带入对局的玩家（座位号 0..3） |
| Holder / 持牌者 | 当下持有这张牌的玩家（摸到/吃到/碰到/杠到） |
| Joker | 卡组里 34 张麻将牌之外的全局/被动加成卡 |
| Run | 一次 Roguelike 通关尝试：选起始卡组 → 推进节点图 → 击败 3 章 Boss 或失败 |
| Seat | 座位号 0..3（0 固定玩家，1..3 AI） |
| Phase | 对局子阶段：DRAW / DISCARD / CLAIM / SETTLE |

## 4. 架构

### 4.1 工程结构

在现有 `godot/` 工程内重组（**不**新建 Godot 工程）。按职责拆 6 个子包：

```
godot/
├── core/          # 纯逻辑：mahjong 规则、听胡、turn-engine。无 Godot 节点依赖
├── skills/        # SkillResource 定义 + 内置勾子脚本 + SkillRegistry
├── battle/        # 一局对战的状态机、事件总线、技能调度
├── meta/          # Run 流程、地图、商店、抽卡、存档（SaveSystem）
├── ai/            # AI 玩家：决策树/启发式 + 主题化 AI 配置
└── ui/            # 场景、控件、动效。复用现有 hand_display* / card_animator
```

迁移策略：现有 216 个平铺脚本**不一次全搬**，而是在 §12 各里程碑推进时按需搬迁 —— 当一个里程碑要新动某个旧脚本时，先把它搬到目标子包再改；纯新增代码直接落到对应子包。这样避免大爆炸式 rename PR。CLAUDE.md 已记录的"WHITE 调制 / NEAREST 过滤 / 80×120 / AtlasTexture"等不变量在搬迁过程中必须严格保留。

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
# core/tile_id.gd —— 牌名不可变标识
class_name TileId
# 枚举值：W1..W9, T1..T9, S1..S9, E, S, W, N, Z, F, B（共 34）

# skills/skill_resource.gd
class_name SkillResource extends Resource
@export var id: StringName              # "thunder_5w_v1"
@export var display_name: String        # "5万·闪电"
@export var description: String         # 玩家可读说明
@export var rarity: int                 # 0=普 1=精 2=史 3=神
@export var attached_tile: TileId       # 这个变体绑定的牌名（如 W5）；Joker 时为特殊值 NONE
@export var is_joker: bool = false      # true 表示这是 Joker 卡（不绑定具体牌名）
@export var owner_triggers: Array[StringName]   # 例如 ["on_owner_drawn", "on_owner_won"]
@export var holder_triggers: Array[StringName]  # 例如 ["on_held_discarded"]
@export var params: Dictionary = {}     # 数值参数（damage、bonus_fan、duration 等）
@export var hook_script: GDScript       # 可选；为 null 时走 params + 内置 effect 引擎
@export var icon: Texture2D             # 印章/角标小图（可空走 rarity 默认色）

# meta/deck.gd
class_name Deck
var tile_variants: Dictionary           # TileId -> SkillResource (恰好 34 个槽，每个 TileId 一个)
var jokers: Array[SkillResource]        # 长度 0..MAX_JOKERS（默认 5）

# battle/battle_state.gd —— 一局快照（纯数据，便于 AI 推演 + 异常 dump）
class_name BattleState
var seats: Array[Seat]                  # 长度恰好 4
var wall: Array[TileInstance]           # 牌墙（剩余可摸）
var discards: Array[TileInstance]       # 已弃牌堆（按弃牌顺序）
var current_seat: int                   # 当前回合座位
var phase: BattlePhase                  # DRAW / DISCARD / CLAIM / SETTLE
var event_chain_depth: int              # 当前事件链深度（防无限循环）

# battle/seat.gd
class_name Seat
var seat_id: int                        # 0..3
var hand: Array[TileInstance]
var melds: Array[Meld]                  # 已亮出的 chi/peng/gang
var deck_owner: Owner                   # 0 = 本地玩家、1..3 = AI 配置

# battle/tile_instance.gd —— 局内一张实物牌
class_name TileInstance
var tile: TileId
var owner_seat: int                     # 0..3，决定牌背图案 + owner_triggers 归谁
var skill: SkillResource                # 可空（普通/无技能牌）
```

## 6. 事件 & 技能调度

### 6.1 事件枚举

`BattleEventBus` 发出 10 类事件，每个携带 `BattleEvent` payload（actor seat、tile_instance、phase context、上一事件链 id）：

| 事件 | 触发时机 |
|------|---------|
| GAME_BEGIN | 一局开始（洗牌 + 发牌完毕） |
| ROUND_END | 一圈结束 |
| PHASE_BEGIN | 进入新 phase（DRAW/DISCARD/CLAIM/SETTLE） |
| TILE_DRAWN | 当前 seat 摸了一张牌 |
| TILE_DISCARDED | 当前 seat 弃了一张牌 |
| TILE_CLAIMED | 任意 seat 吃/碰/杠了刚弃的牌 |
| MELD_FORMED | chi/peng/gang 三种顺/刻子成立 |
| HAND_FORMED | 听牌或胡牌的 hand pattern 成立 |
| WIN_DECLARED | 胡牌（自摸或荣胡） |
| TURN_END | 回合结束（无论是否胡） |

### 6.2 SkillScheduler 调度规则

每个事件在 `BattleEventBus.emit(event)` 之后，`SkillScheduler` 执行：

1. **收集候选**：扫遍局内所有 TileInstance（手牌 + 弃牌 + 露出 meld）+ 所有 Seat 的 jokers，过滤：
   - 麻将牌：`tile.skill.owner_triggers ∩ event.type ≠ ∅` → 触发归 `tile.owner_seat`；`tile.skill.holder_triggers ∩ event.type ≠ ∅` → 触发归 tile 当前 holder（即 hand/meld 所在 seat，弃牌堆里的牌没有 holder）
   - Joker：`is_joker == true` 的 SkillResource，绑定到 Seat 而非 Tile；owner = holder = 该 Joker 所属 seat（Joker 不会在游戏中转手），owner_triggers 与 holder_triggers 都只对该 seat 触发一次（即同事件下 Joker 不重复触发）
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
```

无 `hook_script` 的 SkillResource 走"内置 effect 引擎" —— 一组用 `params` 描述的原子效果（加番、改弃牌堆顺序、跳过下一回合、强制摸特定牌等），由 `skills/builtin_effects.gd` 路由。

## 7. Run 流程

```
新 Run
  ├─ 选起始卡组（3 个预设原型：番牌型 / 速胡型 / 控场型）
  ├─ 进入 Chapter 1 节点图（StS 风格分支节点）
  │    ├─ 普通桌      vs 1 主题 AI + 2 杂兵 AI       奖励：1 抽 + 金币
  │    ├─ 精英桌      vs 3 主题 AI                    奖励：1 高稀+ 抽 + 金币
  │    ├─ 营地        休息 / 升级 1 张牌 / 移除 1 Joker
  │    ├─ 商店        金币换牌 / Joker / 消耗品
  │    ├─ 事件        文字小事件（改卡组、获得遗物等）
  │    └─ Boss 桌     章末 1 个，特殊 AI + 特殊规则
  ├─ 击败 Chapter 1 Boss → Chapter 2 → Chapter 3
  └─ 通关 / 败北 → 结算"声望" → 沉淀解锁
```

每节点 = 一局完整麻将（4 风圈或单圈，由节点配置决定）。

### 7.1 起始卡组原型（v1 三选一）

- **番牌型** — 大番倍率技能多，慢节奏高爆发
- **速胡型** — 摸牌/听牌加速、跳过对手回合
- **控场型** — 影响对手手牌、改弃牌堆、强制对手暴露信息

### 7.2 失败条件

- 玩家"血量"为唯一败北判定（每局败局扣 1 血，血量见 §13）
- 一局败北 = 玩家未胡且本局结束（流局或对手胡）
- 玩家血量归零 → Run 失败
- 失败后结算"声望"，可解锁新内容
- "败北扣血量" vs "对手胡的番数惩罚"作为后续平衡参数（v1 默认仅扣 1 血，番数不影响血量）

## 8. 抽卡 & 经济

| 稀有度 | 概率 | 标识 |
|--------|------|------|
| 普通   | 60%  | 灰色印章 |
| 精良   | 28%  | 蓝色印章 |
| 史诗   | 10%  | 紫色印章 |
| 神话   | 2%   | 金色印章 |

- 概率可被 Joker / 章节修正（如 Chapter 3 普通牌概率衰减）
- **保底**：连续 8 次抽卡未出史诗+ → 下一抽必出史诗+
- 商店刷新 4 个槽（牌 + Joker + 消耗品混搭），金币不足显灰
- 元进度："声望"线性解锁起始卡组、AI 主题、节点变体；不引入付费

## 9. 牌背 & 归属可视化

- `TileInstance.owner_seat` 直接驱动牌背贴图：4 个 seat 对应 4 套花纹/底色
  - Seat 0 玩家：金色固定
  - Seat 1..3 AI：随关卡 AI 主题着色
- 正面 = 复用现有 atlas，**完全不变**（80×120、0 padding、AtlasTexture、WHITE 调制、NEAREST 过滤）
- 带技能的牌右下角加一个"印章"小图标（rarity 着色）；鼠标悬停弹 tooltip 显示技能 id / 名称 / 描述 / 触发时机
- Joker 在 UI 屏幕**右侧**专属垂直面板展示（默认 5 个槽位竖排），不与麻将牌混排；点击 Joker 弹详情

## 10. 错误处理

| 场景 | 处理 |
|------|------|
| SkillResource 加载失败（缺字段、引用 missing 脚本） | `SkillRegistry` 启动期标 invalid 并跳过；红字日志写 `user://logs/skill_registry.log`；不阻断主菜单 |
| 技能勾子运行时异常 throw | `SkillScheduler` 捕获 + 写 `user://logs/battle.log` + 跳过该技能本次触发；对局继续 |
| 状态机非法跃迁（如 DISCARD 时调 CLAIM） | `assert` + 友好错误对话框 + 自动 dump `BattleState` 到 `user://crash/battle_state_<ts>.json` |
| 事件链 > MAX_EVENT_CHAIN_DEPTH | warn log + 中止剩余技能 + dump BattleState |
| 听牌检查 | 走现有 `async_ting_checker`（避免主线程阻塞），技能事件不在 ting check 期间 emit |

## 11. 测试策略

仓库现状无 CI、无 GDScript test runner（详见 `CLAUDE.md`）。引入分层测试：

### 11.1 核心层单测（`core/`）

- 引入 [GUT](https://github.com/bitwes/Gut) 作 dev 依赖（仅 `addons/gut/`，发布构建排除）
- 范围：mahjong 规则、听胡判定、turn-engine、`BattleState` 操作
- 命令：`godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/core`
- 包装脚本：`scripts/test_run_core.sh`

### 11.2 技能集成场景（`tests/scenes/`）

- **每个新技能强制配** 1 个 `tests/scenes/skill_<id>_test.tscn`：
  - 固定布局（手牌 + 弃牌堆预置）
  - 一键按钮触发预期事件链
  - on-screen Label 输出 assert 结果
- 不接 GUT —— 是手测场景，按 F6 跑

### 11.3 异常 dump

- `BattleState` 是纯数据 → 异常时自动 `to_json` dump 到 `user://crash/`
- bug 复现脚本能从 dump 恢复 BattleState 进入对局

## 12. 实现里程碑

按以下顺序拆 implementation plan（每个里程碑通过 `superpowers:writing-plans` 单独生成 plan，走 TDD + 闸门）：

1. **技能框架 + 5 个 demo 技能** — 不接对局，独立场景验证 SkillScheduler 调度顺序、链路防护、双触发
2. **单局对战 vs 1 个 AI** — 复用现有规则引擎，接入事件总线，验证 owner / holder 触发归属
3. **牌背 + 归属可视化 + 4 人桌** — 4 套牌背贴图 + AI 座位
4. **Run 流程骨架** — StS 风格地图 + 节点切换 + 营地 / 商店占位
5. **抽卡 + 元进度 + 存档** — SaveSystem + 抽卡概率 + 声望解锁
6. **30+ 技能内容 + 3 章 Boss + 3 起始卡组** — 内容生产
7. **平衡迭代** — 数值表 + 玩家测试反馈

## 13. 可调参数（v1 默认值）

| 参数 | 默认 | 备注 |
|------|------|------|
| `MAX_JOKERS` | 5 | 卡组 Joker 槽数 |
| `MAX_EVENT_CHAIN_DEPTH` | 16 | 事件链深度上限 |
| 起始原型卡组数 | 3 | 番牌型 / 速胡型 / 控场型 |
| 章节数 | 3 | Chapter 1..3 |
| 节点数/章 | 12-15 | 含 1 Boss |
| 稀有度概率 | 60/28/10/2 | 普/精/史/神 |
| 史诗保底 | 8 抽 | 连续 8 抽未出史诗+ 必出 |
| 玩家血量 | 3 | 败 1 局扣 1 血 |

数值非架构性，平衡阶段会全部迭代。

## 14. 已知风险

| 风险 | 缓解 |
|------|------|
| 技能间相互作用爆炸（N×N 组合矩阵） | event_chain_depth 防护 + 静默原则 + 强制每技能配测试场景；50+ 技能后做组合 fuzz 测试 |
| 现有 216 个平铺脚本搬迁可能破坏 autoload 引用 | 一次只搬一个子包，搬完跑现有手测场景验证 |
| AtlasTexture 不变量被无意改动 | spec 多处显式写出，搬迁时由 PR 模板 checklist 强制确认 |
| 玩家学习曲线（中麻 + Roguelike + CCG 三层） | 起始原型卡组限制为 3，前期事件链深度限低（5-8），章节渐进开放 |
| 无 CI → 测试漂移 | 至少 `core/` 单测必须本地通过才能 commit；GitHub Actions 后续接入 |

## 15. 后续动作

本 spec 通过用户复核后：

1. 调用 `superpowers:writing-plans` 生成 §12 第 1 个里程碑（技能框架 + 5 demo 技能）的实现计划
2. 实现按 TDD 推进（feedback_tdd_and_third_party 强制）
3. 后续里程碑按需重复 1-2
