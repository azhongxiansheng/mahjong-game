# 麻将王 — 里程碑 4：Run 流程骨架（brainstorm 草案）

> **状态**：**草案**。里程碑 3（东风战 + 4 人桌 + 牌背 + 归属可视化）由其他同事在做；本 plan 是为里程碑 4 做的**前瞻 brainstorm**，把 spec §7（Run 流程）+ §13.4（一句话定义）+ §14（节点 / 章节 / 血量等可调参数）的散点拢成一份可推进的工作分解。**未启动实装**；落实清单与文件结构会在里程碑 3 收尾后再细化（接口可能因里程碑 3 的最终决定有微调）。

**Spec 锚点**：
- `docs/superpowers/specs/2026-05-01-mahjong-king-design.md`
  - §7 Run 流程（最关键，本 plan 的硬约束源）
    - §7.1 节点 = 一场东风战；按排名扣血
    - §7.2 起始包（火力 / 速胡 / 控场 三选一）
    - §7.3 Run 失败条件（血量归零）
  - §13.4 里程碑 4 一句话定义
  - §14 可调参数（章节数 3、节点数/章 12-15、玩家血量 5、起始包数等 v1 默认值）
  - §4.2 autoload（`SaveSystem` 写 `user://savegame.json`）
  - §4.3 `LocalBattleController` vs `NetworkedBattleController`（v1 走前者）
  - §9 抽卡 / 卡包 / 经济（**里程碑 5 才实装**，本 plan 仅占位接口）

**Goal（来自 spec §13.4）：**
> Run 流程骨架 — StS 风格地图 + 节点切换 + 营地 / 商店占位。

---

## 范围

**In-scope：**
- **Run 级状态对象**：新增 `RunState`（暂名）持单 Run 内跨节点状态：hp、gold、chapter、node_index、deck（`Deck` 资源）、当前章节地图、累计排名记录、随机种子。
- **节点图数据结构**：每章 12-15 节点的有向无环图（DAG），按层级 1..N 排列；节点类型 6 类（普通 / 精英 / 营地 / 商店 / 事件 / Boss）；用 Resource / 纯字典表示，不引 UI 依赖。
- **节点切换循环**：`RunState.start_node()` → 实例化里程碑 3 产出的 `GameState`（仅"普通桌 / 精英桌 / Boss 桌"）→ 收东风战结束事件 → `RunState.complete_node(NodeResult)` → 按排名扣血 → 推进至下一层节点选择。
- **营地 / 商店 / 事件占位**：v1 都是空壳场景（一段标题文字 + "下一步"按钮），不做实际养成 / 经济 / 文字事件逻辑。
- **节点选择 UI 占位**：v1 是文本按钮列表（"下一节点：1. 普通桌 / 2. 精英桌"），不做 StS 视觉地图。
- **起始包占位**：v1 仅 1 套 hardcoded 起始包注入 `Deck`，3 选 1 UI 留壳但只暴露这 1 个有效选项。
- **SaveSystem 接口占位**：仅声明 `save_run() / load_run() / clear_run()` 三个空方法，实装到里程碑 5。
- **Run 结算**：通关章 3 Boss 或 hp ≤ 0，弹"声望 +N"占位文本（数值实装到里程碑 5），返主菜单。

**Out-of-scope：**
- 单局对战内部（里程碑 0-2）、4 人桌渲染（里程碑 3）
- 商店 / 营地 / 事件的实际逻辑（里程碑 4 收尾或里程碑 5）
- 抽卡 / 卡包 / 元进度 / 真实存档（里程碑 5）
- 30+ 牌技能 / 8-10 角色能力 / 3 章 Boss 内容（里程碑 6）
- StS 视觉地图（节点连线渲染 / 路径预览 / 美术）—— 进里程碑 5/6 视优先级再补
- 联机 / 远端权威（spec §4.3 标记 Phase 2）

**与里程碑 3 的接口约定（待对齐）：**
- 里程碑 3 应已定下：`battle/game_state.gd`（`hand_index` / `honba` / `riichi_sticks` / `cumulative_scores: Array[int]` / `dealer_seat` / `advance_or_finish(result)`）+ 4 人桌主场景（`scenes/four_player_table.tscn`）。
- 本 plan 假设：`RunState` 调用形如 `var gs := GameState.new(starting_points, dealer_seat=0, seed)` 创建 `GameState`，把它喂给 4 人桌场景跑一场东风战；东 4 局结束（非连庄）`GameState` 触发"GAME_END"事件回 `RunState`，返回 `cumulative_scores`；`RunState` 据此排名 → 扣血 → 给奖励 → 推进节点。
- 若里程碑 3 没分层（"hand 序列控制"塞进了 `BattleController`），见 D1 备选方案 + 开放问题 1。

---

## 关键设计决策

### D1. 跨 Run 状态对象：新增 `RunState` vs 复用 `GameState`

**决策**：**新增 `RunState`**（在 `meta/run_state.gd`），与里程碑 3 的 `battle/game_state.gd` **明确分层**。

理由：
- `GameState` 文档已声明"东风战层"快照（plan-3 D1）—— 一场东风战内的 4 局序列，跨 Run 信息塞进去违反单一职责。
- `RunState` 持：
  - **生存**：`hp: int`（默认 5，§14）、`gold: int`、`max_hp: int`
  - **进度**：`chapter: int`（1..3）、`node_index: int`（章内层级）、`current_floor_node: NodeRef`、`history: Array[NodeRef]`
  - **资源**：`deck: Deck`（`tile_variants` + `abilities`，§5）、`consumables: Array`
  - **种子**：`run_seed: int`（决定地图生成 + 战斗随机）、`save_slot: int`
  - **当前节点状态**：`active_game_state: GameState`（节点开始时实例化，节点结束后清空）
- 一节点结束 → `RunState.complete_node(result)` 按排名扣血，触发 `node_completed` 信号 → UI 拉下层节点选项。
- hp ≤ 0 触发 `RunState.run_failed` 信号；通关章 3 Boss 触发 `RunState.run_won`。

> **开放问题 1**：里程碑 3 是否真把 `GameState` 做成可独立 new 的对象？还是让 `BattleController` / 4 人桌场景持有？若耦合到场景层，`RunState` 启动节点改成"加载场景 → 注入 RunState 引用 → 由场景内部 new GameState"。**待里程碑 3 完成后核对**。

**备选方案（不选）**：
- 把跨 Run 字段塞进 `GameState` —— 违反 plan-3 D1 已固化的分层；放弃。
- 不要状态对象，全 autoload —— autoload 单例难以单测、难以多 Run 并行（虽然 v1 不需要并行，但接口腐化代价高）；放弃。

### D2. 节点图数据结构：程序生成 + 静态 Resource vs 全静态 Resource vs 全程序生成

**决策**：**程序生成 + Resource 模板**。每章节点种类配比写在 `chapter_<n>.tres`（`ChapterDef`），层数 / 节点数 / 类型权重 / Boss 配置由 Resource 决定；具体节点连接图按 seed 程序生成。

理由：
- §14 "节点数/章 12-15"暗示有随机性（不是每次都 13 节点）；纯静态会失去 Run 重玩价值。
- 纯程序生成又难调平衡（每次 Boss 之前必有 1 营地、每章必有 1 商店等约束需"准固定"位置）。
- 折中：每章 Resource 定"骨架"（层数、各层节点数范围、必有节点位置约束），生成器按 seed 填类型权重。

数据结构：

```gdscript
# meta/chapter_def.gd
class_name ChapterDef extends Resource
@export var chapter_index: int            # 1..3
@export var floor_count: int              # 一般 7-8 层
@export var nodes_per_floor: Vector2i     # 每层节点数范围 (1, 3)
@export var node_weights: Dictionary      # NodeKind -> 权重
@export var fixed_nodes: Array[Dictionary]# [{floor: 0, kind: NORMAL}, {floor: 6, kind: BOSS}]
@export var boss_def: Resource            # BossDef（含 AI 配置 + 特殊规则；里程碑 6 实装）

# meta/chapter_map.gd
class_name ChapterMap extends Resource
var nodes: Array[NodeRef]                 # 所有节点
var edges: Array[Array]                   # edges[i] = [j1, j2, ...] 表 node[i] 可达 node[jX]
var entry_node: int                       # 0
var boss_node: int                        # nodes.size() - 1
var current_node: int                     # 当前位置（-1 表 entry 之前）

# meta/node_ref.gd
class_name NodeRef
var index: int
var floor: int
var kind: NodeKind
var meta: Dictionary                      # 占位（节点级随机参数：精英 AI 主题、商店刷新种子等）
```

> **开放问题 2**：每层节点连边规则要不要参考 StS（保证从入口到 Boss 至少 1 条路径、节点不能"交叉"避免视觉混乱）？v1 简化做法是"层 i 的每节点至少连 1 条到层 i+1，且不超过 2 条"，能跑通即可，"美观"留 UI 阶段。

### D3. 节点类型最小实现优先级

spec §7 列了 6 类节点。v1 骨架仅"普通桌 / 精英桌 / Boss 桌"接里程碑 3 的 4 人桌真正可玩；其余 3 类落空壳。

| 节点类型 | v1 状态 | 实装路径 |
|---|---|---|
| 普通桌 | 可玩 | 调里程碑 3 的 4 人桌；3 个 SimpleAi |
| 精英桌 | 可玩 | 调里程碑 3 的 4 人桌；3 个"精英 AI" —— v1 直接复用 SimpleAi（精英级 AI 决策推后到里程碑 6） |
| Boss 桌 | 可玩 | 调里程碑 3 的 4 人桌；3 个 SimpleAi + 占位"特殊规则"标记（实际特殊规则推后到里程碑 6） |
| 营地 | 占位 | `camp_placeholder.tscn` —— 显示"营地（实装 M5）"+ "下一步"按钮 |
| 商店 | 占位 | `shop_placeholder.tscn` —— 显示"商店（实装 M5）"+ "下一步"按钮 |
| 事件 | 占位 | `event_placeholder.tscn` —— 显示"文字事件（实装 M5）"+ "下一步"按钮 |

理由：spec §13.4 一句话明确"营地 / 商店占位"；v1 不做内容生产，把骨架先打通。

### D4. 节点结算 → Run 结算桥

spec §7.1 给了排名映射表，本 plan 数据化：

```gdscript
# meta/node_result.gd
class_name NodeResult
var rank: int                # 1..4
var hp_delta: int            # 1->0, 2->0, 3->-1, 4->-2（spec §7.1）
var gold_reward: int         # v1 简化：rank 1 +30, rank 2 +15, rank 3 +5, rank 4 +0
var card_reward: int         # 节点单抽次数（v1 给 1 抽，但抽卡逻辑空壳）
var final_scores: Array[int] # 4 家最终点数（来自 GameState.cumulative_scores）

# RunState
func complete_node(result: NodeResult) -> void:
    hp = clamp(hp + result.hp_delta, 0, max_hp)
    gold += result.gold_reward
    history.append(current_floor_node)
    if hp <= 0:
        emit_signal("run_failed")
    elif current_floor_node.kind == NodeKind.BOSS and chapter >= 3:
        emit_signal("run_won")
    elif current_floor_node.kind == NodeKind.BOSS:
        chapter += 1
        _generate_chapter_map(chapter)
    else:
        emit_signal("node_completed", _next_node_options())
```

`_next_node_options()` 返回当前层可达的下层节点列表，UI 渲染选项。

### D5. 节点选择 UI 占位：文本按钮 vs StS 地图渲染

**决策**：**文本按钮列表**。屏幕显示当前节点信息 + "下一节点选项：1. 普通桌 / 2. 营地"，玩家点按钮进入。

理由：
- StS 视觉地图（节点连线 / 高亮已访问 / 鼠标 hover 预览）工程量大（需画线、节点 sprite、连线动画），属于 UI 雕花。
- 数据流先打通 → UI 后续美术阶段补；spec §13.4 没有"必须有视觉地图"硬约束。
- 文本列表也能支持开放问题 3 的"提前看到当前层 / 下层 / 全图"等设计探索。

> **开放问题 3**：玩家选择节点时应展示多大范围？StS 是"看全图"；其他 roguelike 也有"只看下一层"的。v1 默认看下一层；后续可加全图预览。

```
[ASCII 草图 — UI 占位布局]

┌────────────────────────────────────────────────┐
│  Chapter 1 / Floor 3                  HP: 5/5 │
│                                       金币: 35 │
├────────────────────────────────────────────────┤
│  上一节点：普通桌（排名 2，无血损）             │
│                                                │
│  下一节点选项：                                 │
│   [1] 普通桌    （vs 3 SimpleAi）              │
│   [2] 营地      （占位 — M5 实装）             │
│   [3] 精英桌    （vs 3 SimpleAi）              │
│                                                │
│                              [查看卡组] [设置] │
└────────────────────────────────────────────────┘
```

### D6. SaveSystem 占位

spec §4.2 列 `SaveSystem` 为 autoload。本里程碑**仅声明接口**，实装到里程碑 5。

```gdscript
# meta/save_system.gd（autoload）
class_name SaveSystem extends Node

func save_run(run_state: RunState) -> Error:
    push_warning("SaveSystem.save_run: 未实装（M5）")
    return OK

func load_run() -> RunState:
    push_warning("SaveSystem.load_run: 未实装（M5）")
    return null

func has_save() -> bool:
    return false

func clear_run() -> void:
    pass
```

v1 内存里跑完一 Run 即 reset；杀进程 = 失去当前 Run（用户体验差，但里程碑 4 不修，由里程碑 5 SaveSystem 解决）。

### D7. 起始包占位

spec §7.2 / §14 要求 3 套起始包（火力 / 速胡 / 控场）。v1 **仅 hardcoded 1 套**（推荐"控场型"，因为透明牌系是已有 demo 技能 §8.5 范畴），3 选 1 UI 留壳但只 1 个有效。

理由：
- 起始包内容生产是里程碑 6 的范围；本里程碑只走 `Deck` 注入流程。
- 控场型刚好对接里程碑 1 已有的"透明牌"demo 技能，零新内容。

```gdscript
# meta/starter_packs.gd
const CONTROL_PACK := {
    "id": &"starter_control",
    "display_name": "控场型",
    "tile_variants": {
        # 例：W5 → 透明牌·5 万（id = "reveal_5w_v1"，里程碑 1 已有）
        TileId.W5: preload("res://skills/data/reveal_5w_v1.tres"),
        # ... 1-2 张 + ?
    },
    "abilities": [
        # 例：流局誘導（§8.10 灵感库；具体 SkillResource 待里程碑 6 出资源）
        # v1 留空数组也合法；空数组 = 无角色能力，依然能跑
    ],
}
```

> **开放问题 4**：v1 起始包是否必须含 1 张角色能力？若里程碑 1 没出可用的角色能力 SkillResource，起始角色能力数组留空也合法（依然能跑骨架）。

---

## 与里程碑 3 / 5 的接口约定

### 与里程碑 3（被消费）

```gdscript
# RunState 启动节点
func start_node(node_ref: NodeRef) -> void:
    match node_ref.kind:
        NodeKind.NORMAL, NodeKind.ELITE, NodeKind.BOSS:
            var scene := preload("res://scenes/four_player_table.tscn").instantiate()
            scene.start_with(GameState.new(25000, 0, run_seed + node_ref.index), deck)
            scene.connect("game_finished", _on_game_finished)
            get_tree().root.add_child(scene)
        NodeKind.CAMP:
            _push_placeholder("res://ui/run/camp_placeholder.tscn")
        # ...
```

里程碑 3 需暴露的 API（待 M3 同事确认）：
- `GameState.new(starting_points: int, dealer_seat: int, seed: int) -> GameState`
- `four_player_table.tscn` 主脚本暴露 `start_with(game_state: GameState, deck: Deck)` + `signal game_finished(scores: Array[int])`

### 与里程碑 5（占位接口先暴露）

- `SaveSystem.save_run(run_state)` —— 节点结束时调一次（M5 实装）
- 抽卡入口：`RunState.grant_card_reward(count: int)` —— 节点结束时给（M5 实装真抽卡逻辑；M4 仅打 log）
- 商店刷新：`shop_placeholder` 内 hardcoded 4 槽（M5 改为 `Shop.new(seed).refresh(4)`）

---

## 文件结构（拟）

```
godot/
├── meta/
│   ├── run_state.gd                    # 新：Run 级状态对象
│   ├── chapter_def.gd                  # 新：每章配置 Resource
│   ├── chapter_map.gd                  # 新：节点图数据结构
│   ├── chapter_map_generator.gd        # 新：按 seed 生成节点图
│   ├── node_ref.gd                     # 新：节点引用
│   ├── node_kind.gd                    # 新：节点类型枚举
│   ├── node_result.gd                  # 新：节点结算结构
│   ├── starter_packs.gd                # 新：v1 1 套硬编码 + 3 选 1 UI 数据
│   └── save_system.gd                  # 新：autoload 接口占位（M5 实装）
├── meta/data/
│   ├── chapter_1.tres                  # 新：第 1 章节点配置
│   ├── chapter_2.tres                  # 新：第 2 章
│   └── chapter_3.tres                  # 新：第 3 章
├── ui/run/
│   ├── chapter_map_view.tscn/.gd       # 新：节点选择 UI（文本按钮列表）
│   ├── run_hud.tscn/.gd                # 新：HP / 金币 / 章节 顶栏
│   ├── camp_placeholder.tscn/.gd       # 新：营地空壳
│   ├── shop_placeholder.tscn/.gd       # 新：商店空壳
│   ├── event_placeholder.tscn/.gd      # 新：事件空壳
│   ├── starter_pack_picker.tscn/.gd    # 新：起始包 3 选 1 UI（v1 仅 1 个有效）
│   └── run_summary.tscn/.gd            # 新：Run 结算（通关 / 失败）占位
├── tests/
│   ├── meta/
│   │   ├── test_run_state.gd           # 新：扣血 / 推进 / 失败 / 通关
│   │   ├── test_chapter_map.gd         # 新：地图生成 / 节点连通性 / 必有节点
│   │   └── test_node_result.gd         # 新：排名 → hp_delta 映射
│   └── scenes/
│       └── run_flow_smoke.tscn         # 新：F6 跑通"新 Run → 几个节点"
└── docs/superpowers/plans/
    └── 2026-05-02-run-flow-skeleton.md # 本文档
```

---

## 任务清单（待里程碑 3 收尾后细化）

### A. 数据层
- [ ] `RunState` 类 + 属性 + `start_node` / `complete_node` / 信号
- [ ] `ChapterDef` Resource + 3 章 .tres 配置文件（节点权重、Boss 配置占位）
- [ ] `ChapterMap` + `ChapterMapGenerator`（按 seed 生成 12-15 节点 DAG）
- [ ] `NodeKind` 枚举 / `NodeRef` / `NodeResult` 数据类
- [ ] `StarterPacks.CONTROL_PACK` 硬编码 1 套
- [ ] GUT 单测：扣血、节点推进、Run 失败、Run 通关、地图连通性、排名 → hp_delta 映射

### B. 节点桥接
- [ ] `RunState.start_node(node_ref)` 路由：可玩节点 → 4 人桌 / 占位节点 → 占位场景
- [ ] 4 人桌结束信号 → `RunState.complete_node(NodeResult)`
- [ ] 占位场景"下一步"按钮 → `RunState.complete_node(NodeResult.from_placeholder())`
- [ ] `RunState.run_failed` / `run_won` 信号 → 跳 `run_summary.tscn`

### C. 占位 UI
- [ ] `chapter_map_view.tscn`：文本按钮列表 + 当前节点 / 下层选项
- [ ] `run_hud.tscn`：HP 槽 + 金币 + 章节 / 层信息
- [ ] `camp_placeholder.tscn` / `shop_placeholder.tscn` / `event_placeholder.tscn`：标题文字 + "下一步"按钮
- [ ] `starter_pack_picker.tscn`：3 张卡片，2 张灰显（"M5 实装"），1 张可选
- [ ] `run_summary.tscn`：通关 / 失败 + "声望 +N"占位 + "返回主菜单"

### D. SaveSystem 占位
- [ ] `meta/save_system.gd` autoload + 4 个空方法 + push_warning
- [ ] 注册到 `project.godot` autoload 段

### E. 验收
- [ ] GUT：`test_run_state.gd` / `test_chapter_map.gd` / `test_node_result.gd` 全 PASS；现有 ~360 个测试零回归
- [ ] F6：`run_flow_smoke.tscn` 跑通：起始包选择 → 章 1 第 1 节点（普通桌打 1 局）→ 节点结算 → 选下一节点（营地占位点过）→ ... → 章 1 Boss → 击败 → 章 2
- [ ] 端到端（手测）：完整跑一 Run（章 1-章 3），含至少 1 次节点失败（不至于 hp 归零）；通关后看到 run_summary

---

## 开放问题（待对齐）

1. **里程碑 3 的 `GameState` 接口形态**：是否真做成可独立 new 的纯数据对象？还是耦合到 `four_player_table.tscn`？决定 `RunState.start_node()` 的对接方式。
2. **节点图连边规则**：v1 只要保证连通性就够，还是要参考 StS 做"无交叉 / 视觉美观"约束？
3. **节点选择展示范围**：v1 默认只看下一层；是否需要全图预览？
4. **v1 起始包是否必须含 1 张角色能力**？若里程碑 1 没出可用的角色能力 SkillResource 资源，留空数组合法吗？
5. **Run 中途存档行为**：v1 仅声明 SaveSystem 接口；玩家中途退出 = 失去当前 Run，是否在 UI 提示？
6. **章节 Boss 特殊规则**：spec §13.6 才落地 3 章签名规则破坏角色能力；本里程碑 Boss 是否就是"普通 4 人桌挂个名字"？（默认是。）
7. **v1 排名 → 金币奖励**：本 plan 拍了 30/15/5/0；spec §14 没明确，需要用户拍板或推迟到里程碑 7 平衡。

---

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| 与里程碑 3 接口耦合度高，可能因 M3 改动需返工 | 本文为草案；实装在 M3 收尾后启动；接口决策列在"开放问题"等用户对齐 |
| 节点图程序生成约束多（每章必有 1 营地、Boss 之前必有 1 营地等），生成器复杂度爆炸 | v1 简化：仅"必有节点位置"约束（floor 0 = 入口、最后 floor = Boss、Boss 之前 1 floor 必有 1 营地），其余按权重抽；测试只覆盖这几条硬约束 |
| SaveSystem 推迟到 M5 → 用户中途退出丢 Run，体验差 | 在 `run_flow_smoke.tscn` 跑通后向用户暴露此约束；UI 提示"v1 不支持中途存档"；不阻塞骨架推进 |
| 起始包内容贫乏（v1 仅 1 套）→ 体验单调 | v1 是骨架验证，不是内容验证；3 选 1 UI 已留壳，里程碑 6 内容生产时直接填 |
| StS 视觉地图缺位 → 用户感知"不像 roguelike" | 本里程碑职责是"流程骨架"非"美术雕花"；视觉地图是后续 PR 增量；spec §13.4 也只要求"地图 + 节点切换 + 营地商店占位" |
| 节点排名 → hp_delta 映射 spec 死定，无配置化空间 | spec 数值非架构性（§14 末段已注），里程碑 7 平衡时改；v1 严格按 §7.1 实装 |
| 4 人桌（M3）只支持 1 局对战 vs 完整东风战 | M3 spec §13.3 明确"完整东风战流程"是 M3 范围；若 M3 实装时缩了范围，本里程碑接口在"开放问题 1"中显式列出，等用户对齐 |

---

## 验证

- **plan 阶段（本 PR）**：仅文档化；无代码改动；不跑测试。
- **实装阶段（未来 PR）**：
  - GUT：`test_run_state.gd` / `test_chapter_map.gd` / `test_node_result.gd` 全套 PASS；现有 ~360 个测试零回归
  - F6：`run_flow_smoke.tscn` 跑通起始包选择 → 章 1 第 1 节点 → 节点结算 → 推进 → ... → Boss → 章 2
  - 端到端（手测）：完整一 Run（章 1-章 3），含至少 1 次节点失败 + 1 次连胜，通关后看到 run_summary
  - 不变量自检：sum(scores) + riichi_sticks * 1000 ≡ 100000 在所有节点结算点成立（继承 plan-3 约束）

---

## 后续动作

里程碑 3 收尾后：
1. 用 `superpowers:writing-plans` 把本 brainstorm 转成正式实现计划（细化到任务粒度 / TDD 工序 / 具体 commit 切分）
2. 对齐 7 条开放问题，把答案直接编辑回本文档（保留"草案 → 定稿"轨迹）
3. 启动里程碑 4 实装；优先级 A → D → B → C → E（数据 → autoload → 桥接 → UI → 验收）
