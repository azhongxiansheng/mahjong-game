# 麻将王 — 里程碑 3：东风战 + 4 人桌 + 牌背 + 归属可视化（brainstorm 草案）

> **状态**：**草案**。里程碑 2（单局对战 vs 1 AI）由其他同事在做，本 plan 是为里程碑 3 做的**前瞻 brainstorm**，把 spec §10、§13.3、§14 中关于 4 人桌与归属可视化的散点拢成一份可推进的工作分解。**未启动实装**；落实清单与文件结构会在里程碑 2 收尾后再细化（接口可能因里程碑 2 的最终决定有微调）。

**Spec 锚点**：
- `docs/superpowers/specs/2026-05-01-mahjong-king-design.md`
  - §10 牌背 & 归属可视化（最关键，本 plan 的硬约束源）
  - §13.3 里程碑 3 一句话定义
  - §14 可调参数（包含 5 槽角色能力面板等 v1 默认值）
  - §3.1 术语（Owner / Holder / Seat 区分）

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

**与里程碑 2 的接口约定（待对齐）：**
- 里程碑 2 应已定下：`BattleController` / `LocalBattleController` 接口、AI 决策入口（如 `AIProfile.decide_discard(state, seat) -> Tile`）、BattleState 在 hand 内的完整 lifecycle。本 plan 仅在外层包一个"hand 序列"循环、不重写底层 controller。

---

## 关键设计决策

### D1. 跨局状态对象：新增 `GameState` vs 扩 `BattleState`

**决策**：**新增 `GameState`**（在 `battle/game_state.gd`，与 `core/turn_engine/game_state.gd` 注意命名冲突 —— 后者是旧 scripts/ 内中麻 GameState，必须保证 class_name 不撞）。

理由：
- `BattleState` 文档已声明"一局对战"快照（spec §5），跨局信息塞进去违反单一职责。
- `GameState` 持：`hand_index`（0..3 表东 1..东 4）、`honba`、`riichi_sticks`、`cumulative_scores: Array[int]`、`dealer_seat`、`battle: BattleState`（当前 hand 的活跃实例）。
- 一局结束 → `GameState.advance_or_finish(result)` 决定连庄或下一局，重建 `BattleState`。
- `GameState` 替代 v1 单 hand 模式下里程碑 2 直接持有的 `BattleState`，并向 UI 提供 hand-level 进度。

> **开放问题 1**：里程碑 2 是否已经引入了类似的"hand sequence holder"？若有，本 plan 直接复用、不新建。**待里程碑 2 完成后核对**。

### D2. 4 套牌背贴图来源

spec §10 仅规定"4 套花纹/底色"，未指定来源。

**候选方案**（按里程碑 3 实装时的灵活度排序）：

| 方案 | 来源 | 制作成本 | v1 可接受度 |
|---|---|---|---|
| **A. 纯色 + 角标** | 4 个 16-color 渐变色块 + seat 编号角标，程序化生成（GDScript 画 ImageTexture） | 0 | ✓ 占位 OK，后续可替换 |
| **B. 现有 atlas 复用** | 抽 `mahjong_atlas0_*.png` 中已有的 1 个牌背图，4 色 modulate | 0 | ✓ 但 modulate 与"NEAREST + WHITE 调制"不变量冲突，**不建议** |
| **C. 4 套手绘** | 美术外包 / 自绘 4 张 80×120 PNG | 中 | 最终目标 |
| **D. AI 生成** | Stable Diffusion / Midjourney 出 4 张统一风格 | 低 | 后期可补 |

**初版决策**：**先 A 后 C**。v1 用程序化色块跑通归属可视化的代码路径 + 数据流；美术替换是后续 PR 的纯资源换图，不阻塞功能实装。

> **开放问题 2**：是否允许程序化色块作为 v1 默认？还是必须等手绘到位才合并？**默认按"先 A 再 C"推进，等用户反对再调**。

### D3. AI 主题着色

spec §10：「seat 1..3 AI：随关卡 AI 主题着色」 —— 暗示 AI 有"主题"概念。

**结构**：
- 新增 `AIProfile` 资源类型（`ai/profile.gd`，与里程碑 6 的 AI 内容生产对接），含 `display_name`、`portrait`、`tile_back_color: Color`、`decide_*` 行为入口。
- 4 人桌按"当前关卡的 AI 阵容"装载 3 个 `AIProfile`，分配到 seat 1/2/3，每个的 tile_back_color 决定该 seat 的牌背基色。
- v1 用 3 个内置 AIProfile（如 `default_red`、`default_blue`、`default_green`），里程碑 6 才会扩到 8-10 个角色。

> **开放问题 3**：里程碑 2 是否已经定义了 `AIProfile`？若已存在，复用；否则在本 plan 引入并明确告知里程碑 2 同事。

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

> **开放问题 4**：现有 `scenes/game_ui.tscn` 是单家布局（仅 seat 0），是否扩展它还是新建 `scenes/four_player_table.tscn`？**默认新建**；旧场景留作 1v1 调试场景。

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

---

## 文件结构（拟）

```
godot/
├── battle/
│   ├── game_state.gd              # 新：跨局 (东 1..4) 状态对象
│   └── ai_profile.gd              # 新：AI 个性 + 牌背色 + 决策入口（待对齐里程碑 2）
├── ui/
│   ├── four_player_table/
│   │   ├── four_player_table.tscn # 新：4 人桌主场景
│   │   ├── four_player_table.gd
│   │   ├── seat_panel.tscn/.gd    # 子组件：单 seat 区域
│   │   ├── center_info_panel.tscn # 子组件：局/本场/Dora/牌墙剩余
│   │   └── ability_panel.tscn/.gd # 角色能力 5 槽面板
│   ├── card_tile_back.gd          # 新：牌背贴图选择 + 透明牌渲染（消费 owner_seat + revealed_tiles）
│   └── tile_stamp.gd              # 新：技能印章 + tooltip
├── tests/
│   ├── battle/
│   │   └── test_game_state.gd     # 新：连庄 / 流转 / 流局 / 跨局立直棒等
│   ├── scenes/
│   │   └── four_player_table_smoke.tscn  # F6：把 4 家用占位 BattleState 渲染一遍
└── docs/superpowers/plans/
    └── 2026-05-01-east-round-table.md   # 本文档
```

---

## 任务清单（待里程碑 2 收尾后细化）

### A. 数据层（与里程碑 2 对接）
- [ ] 核对里程碑 2 是否已引入"hand 序列"对象；若无，新增 `GameState`
- [ ] 实装 `GameState.advance_or_finish(result)` + 单测（连庄 / 流转 / 流局 / 立直棒收走）
- [ ] 核对里程碑 2 的 `AIProfile`；若无，引入并对接 AI 决策入口

### B. UI 层
- [ ] `four_player_table.tscn` 主布局（4 区 + 中心 + 右侧能力面板）
- [ ] `seat_panel` 旋转手牌渲染（90/180/-90 三档）
- [ ] `center_info_panel` 显示局 / 本场 / Dora 指示牌列 / 牌墙剩余
- [ ] `ability_panel` 5 槽 + 详情弹窗

### C. 归属可视化
- [ ] `card_tile_back.gd` v1：按 `owner_seat` 取程序化 4 色 ImageTexture（D2 方案 A）
- [ ] `card_tile_back.gd` 透明牌路径：消费 `BattleState.revealed_tiles`
- [ ] `tile_stamp.gd` 印章 + tooltip

### D. 集成
- [ ] 把里程碑 2 的 `LocalBattleController` 包进 `GameState` 循环
- [ ] hand → battle 实例化 → 战斗结束 → `advance_or_finish` → 下 hand
- [ ] F6 smoke 场景：用占位 BattleState（4 家发好 13 张）渲染 4 人桌、按按钮触发 advance

### E. 验收测试
- [ ] GUT：`test_game_state.gd` 覆盖 5 种 hand 结束路径 × 3 种庄家位置
- [ ] F6：`four_player_table_smoke.tscn` 4 家旋转无错位、能力面板可点开、印章 + tooltip 在带技能牌上显示
- [ ] 整场东风战 e2e 跑通（手测）：东 1 → 东 4，含至少一次连庄、一次流局、一次立直

---

## 开放问题（待对齐）

1. 里程碑 2 是否已经定义"hand 序列对象" / `AIProfile`？若有，复用；否则本 plan 引入。
2. 牌背贴图是否接受程序化色块作为 v1 默认（D2 方案 A）？还是必须等手绘到位再合并？
3. 4 人桌是新建 `scenes/four_player_table.tscn` 还是扩 `scenes/game_ui.tscn`？
4. v1 是否限制连庄上限？（spec 未限）
5. AI 主题着色是硬编码 3 色，还是从 `AIProfile` 动态读取？

---

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| 与里程碑 2 接口耦合度高，可能因 M2 改动需返工 | 本文为草案；实装在 M2 收尾后启动；接口决策列在"开放问题"等用户对齐 |
| 4 家 UI 旋转 + 弃牌河"井字"布局工程量大 | 拆 `seat_panel` 为子组件，先做单家布局；旋转通过 Godot 节点 `rotation` 属性，不重写贴图 |
| 牌背贴图美术 v1 不到位影响"归属可视化"卖点 | D2 方案 A 程序化色块 v1 验证流程；美术补 PR 不阻塞 |
| 透明牌 reveal 路径与 SkillCtx.revealed_tiles 数据源未连通 | 里程碑 1 已定义 `SkillCtx.reveal_tile_to`；本 plan UI 端只读 `BattleState.revealed_tiles`，单向数据流 |
| 跨局立直棒收走遗漏（导致点数不守恒） | `test_game_state.gd` 强制覆盖；assert 局结束时 sum(scores) + riichi_sticks * 1000 == 100000 |

---

## 验证

- **plan 阶段（本 PR）**：仅文档化；无代码改动；不跑测试。
- **实装阶段（未来 PR）**：
  - GUT：`test_game_state.gd` 全套 PASS；现有 ~94 个测试零回归
  - F6：`four_player_table_smoke.tscn` 4 家正确显示、归属色块不串、点击 advance 进入下一局
  - 端到端：手动跑一场东风战，至少含一次连庄、一次流局、一次立直，结算正确
