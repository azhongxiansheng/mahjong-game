# 麻将王 — 里程碑 7：平衡迭代（brainstorm 草案）

> **状态**：**草案**。M0-M6 已完成（PR #11-#43，43/44 内容；剩 `tougenkyo_v1` 等本里程碑扩 ctx）。本 plan 把 spec §13.7（一句话）+ §14（数值表）+ PR #39 留下的 **M7 待扩 ctx 清单** 拢成一份可推进的工作分解。**未启动实装**；落实清单与文件结构会在用户拍板后再细化。

**Spec 锚点**：
- `docs/superpowers/specs/2026-05-01-mahjong-king-design.md`
  - §13.7 里程碑 7 一句话："数值表 + 玩家测试反馈"
  - §14 可调参数（v1 默认值，本里程碑系统性调整）
  - §15 已知风险（"日麻规则引擎正确性"已闭环；"数值平衡"是本里程碑核心）
  - §6 事件 & 技能调度（M7 ctx 扩展不破坏 SkillScheduler 调度顺序与链路防护）
- `docs/superpowers/plans/2026-05-02-content-production.md` 末尾 **M7 待扩 ctx 清单**（13 类 API，按出现频次排序）

**前置依赖（已落地）**：
- M0 日麻规则引擎 ✅
- M1-M5 引擎 + UI + Run 流程 + 抽卡 + 存档 ✅
- M6 内容 43/44（28 牌技能 + 9 角色能力 + 3 章 Boss + 3 起始包）✅
- GUT 881/881 PASS

**Goal（来自 spec §13.7）：**
> 数值表 + 玩家测试反馈。

实质工作：
1. 扩 SkillCtx 13+ 个新 API，把 M6 v1 简化（add_han 等价表达）升级为 spec 原效果（multiply_han / set_furiten / scale_payout 等）
2. 把散在 hook / Resource / starter pack 中的硬编码数值集中到一份 BalanceConstants 表
3. 接玩家测试反馈循环（手测会话 / 文本表单 / 自动 simulation）
4. 按反馈迭代数值（稀有度概率、起始 hp、节点奖励、技能强度）

---

## 范围

**In-scope：**
- **SkillCtx 公共 API 扩展**：按 PR #39 列出的 13 类（约 17 个具体 API），分批落地
- **现有 hook 升级**：为已有 ctx 简化版本的 hook 升级到 spec 原效果（约 15-20 个 hook 涉及）
- **`tougenkyo_v1` 实装**：M6 唯一遗留任务（手牌↔弃牌河交换），等本里程碑 `swap_hand_river` ctx API 落地后实装
- **BalanceConstants 集中表**：`meta/balance_constants.gd`，把 §14 v1 默认值 + hook 内的魔数（如 30% / 50% / 8 抽 / +1 番）单一来源化
- **Simulation 工具**：跑 1000-10000 场 vs SimpleAi/中立 deck 的批量 Run，输出胜率 / 平均节点 / 通关率 / 稀有度命中分布
- **玩家测试反馈漏斗**：定 `docs/playtest/<date>-feedback.md` 模板 + alpha/beta 节奏

**Out-of-scope：**
- 联机 / 远端权威（spec §4.3 Phase 2）
- 新内容生产（追加技能 / 角色 / Boss）—— M6 已收口，新增走单独 backlog
- 美术资产升级（牌面 / Boss 立绘）—— 与 M7 解耦
- 半庄战 / 西入 / 国士 13 面待 / 责任编辑（spec §14 末段标注 Phase 2 可选）

**与里程碑 6 的接口约定（已落地）：**
- 所有 hook 已稳定签名：`func on_event(skill, event, ctx) -> void`
- `card_pool.gd` 末尾追加注册模式不变
- `docs/superpowers/plans/2026-05-02-content-production.md` 任务板可继续做活进度追踪
- M7 升级 hook 时只动该 hook 的 .gd（行为）+ 对应 test（覆盖增强）+ 可选 hook 头部注释（删除"M7 增强为..."的 TODO）

---

## 关键设计决策

### D1. SkillCtx 扩展批次切分

**决策**：**按 ctx API "影响面"分 4 批 PR**，每批一个独立 PR + 全套 hook 升级 + 全套 GUT 回归。

|批 | API 组 | 涉及 hook 数 | 风险 |
|---|---|---|---|
| **B1 — 软扩展** | `consume_self()` / `set_furiten(seat, turns)` / `clear_furiten_to(seat, turns)` | 6-8 | 低（兼容旧写法） |
| **B2 — Dora 系** | `mark_extra_dora_for_seat` / `mark_red_dora_for_tile` / `reroll_uradora` | 3 | 中（接 DoraIndicators） |
| **B3 — 计分系** | `multiply_han` / `scale_payout(factor)` / `mark_all_pay` / `mark_pao_transfer` / `force_yakuman` / `ensure_mangan` | 8-10 | 高（改 ScoreFormula / PayoutCalculator） |
| **B4 — 信息 + 大状态** | `reveal_wall_segment_to(n, seat)` / `reveal_next_draw(seat)` / `reveal_tenpai_tiles(seat)` / `inject_meld_at_start(seat, meld)` / `swap_hand_river(seat)` / `draw_choose_n_of_m(n, m)` | 6-8 | 高（改 BattleState / Wall / Hand） |

> **开放问题 1**：B3/B4 的高风险 API 是否拆得更细（每个 API 1 PR）？默认按上表批量；若用户偏好更细粒度可拆。

### D2. 平衡数值集中化

**决策**：新增 `meta/balance_constants.gd`（class_name `BalanceConstants`），把 §14 v1 默认值 + hook 内魔数 + 起始包参数 + 抽卡概率 集中到一份字典。

```gdscript
class_name BalanceConstants

# 来自 spec §14 + hook 内魔数
const VALUES := {
    # 经济
    "starting_points": 25000,
    "starting_hp": 5,
    "riichi_stick": 1000,
    "honba_stick": 300,

    # 抽卡（spec §9.1 / §14）
    "rarity_weights": [60, 28, 10, 2],   # 普 / 精 / 史 / 神
    "epic_pity_threshold": 8,
    "pack_size": 5,
    "pack_uncommon_floor": 1,

    # 节点
    "chapters": 3,
    "nodes_per_chapter": [12, 15],       # range
    "node_rank_hp_delta": [0, 0, -1, -2], # rank 1-4
    "node_rank_gold_reward": [30, 15, 5, 0],

    # 技能数值（hook 引用，逐步替换魔数）
    "soul_drain_fraction": 0.30,
    "mirror_chambo_refund": 0.50,
    "iron_wall_han_penalty": -1,
    "thunder_han_bonus": 1,
    # ...
}

static func get(key: String) -> Variant:
    assert(VALUES.has(key), "BalanceConstants 缺 key: %s" % key)
    return VALUES[key]
```

升级路径：每个 hook 用 `BalanceConstants.get("xxx")` 替换 `const FRACTION := 0.3` 等魔数；`gacha.gd` / `meta_progress.gd` / `node_result.gd` 等等同。

> **开放问题 2**：是否引入 .tres Resource 替代 const dict？Resource 可热加载、可有多套（v1 / 高难度模式 / 玩家自定义）；但 v1 暂时不需要多套，dict 足够简单。**默认 dict + static get**，未来需要多套再升级 Resource。

### D3. 玩家测试反馈漏斗

**决策**：**两层反馈**：
- **Alpha（开发组内）**：每 1-2 周一次"手测会话"，跑 3-5 个 Run，结束后写 `docs/playtest/2026-MM-DD-alpha-N.md`，模板含：场次描述 / 卡组组合 / 节点排名 / 主观评分（1-5）/ 不爽点 / 期望调整
- **Beta（外部 ≤ 5 人）**：M7 中段后开放给外部 playtester；走 GitHub Discussion 或 Google Form（Issues 已禁用）；每周收集一次

```
docs/playtest/
├── _template.md                      # 反馈模板
├── 2026-05-15-alpha-1.md
├── 2026-05-29-alpha-2.md
├── 2026-06-12-beta-batch-1.md
└── ...
```

> **开放问题 3**：beta 反馈用什么承载（Google Form / Discussion / Discord）？默认 Discussion（已经在 GitHub），等用户决定。
> **开放问题 4**：alpha 期间是否引入"自动数值评估"（参看 D4 simulation）作为快速反馈？默认是。

### D4. Simulation 工具

**决策**：新增 `tools/simulate_runs.gd`（一次性 CLI 工具），跑批量 Run vs 现成 SimpleAi，输出统计：

```bash
godot --headless --path godot --script tools/simulate_runs.gd \
    -- --runs=1000 --seed=42 --starter=control --output=tools/sim_results/run_1000_seed42.json
```

输出指标：
- 总 Run 数 / 通关率（章 3 Boss 击败）/ 失败率（hp ≤ 0）
- 平均通关用时（节点数）/ 节点排名分布（1/2/3/4 各占比）
- 抽卡稀有度分布（vs 期望 60/28/10/2）
- 史诗保底触发次数 / 平均触发间距
- 起始包之间的胜率差异（控场 vs 火力 vs 速胡）
- 角色能力槽 5 占满率 / 各角色能力使用频率

调参循环：simulation → 看哪个数值偏离设计目标（如通关率 > 80% → 太简单）→ 改 BalanceConstants → 再 simulation。

> **开放问题 5**：simulation 用 SimpleAi vs SimpleAi 还是接 M6 实装的 Boss / 主题 AI？SimpleAi 不会立直 / 鸣牌，与人类对战行为差距大；但作为快速回归比较有意义。**默认 SimpleAi**，beta 阶段补"中级 AI" simulation。

### D5. Hook 升级路径

**决策**：每个 hook 升级是**独立小 PR**（参考 M6 batch 模式），按 D1 批次内分组合并：

模板：
```
1. 在 ctx 已有相应 API 后（B1-B4 已落 + GUT 绿）
2. 改 hook：
   - 把 v1 简化的 `ctx.add_han(-1)` 改为 `ctx.multiply_han(0.5)` 等 spec 原效果
   - 删除 hook 头部 "M7 增强为..." 注释
3. 改 test：
   - 增加 1-2 case 覆盖 spec 原效果（如 ×0.5 边界值）
   - 旧 test 保持，验证向后兼容（除非新效果完全替代）
4. 跑 GUT 全套确认零回归
```

> **开放问题 6**：hook 升级 commit message 规范？默认 `feat(m7/<category>): 升级 §8.X "<牌名>" 到 spec 原效果（<旧 v1 简化> → <新 spec 效果>）`。

### D6. 数值调整工作流

**决策**：每次平衡调整走"假设 → 验证 → 决策"三步：

```
1. 假设：从 alpha 反馈或 simulation 输出提取一条具体观察
   例："5 局 alpha 通关率 100%，远高于设计目标 30-50%"

2. 验证：跑 simulation 复现，确认观察不是个例
   simulate_runs --runs=1000 → 通关率统计

3. 决策：
   a) 调 BalanceConstants 中相关 key（hp 5 → 4 / 起始 gold 0 → 0 不变）
   b) 跑 simulation 验证调整后回到目标范围
   c) 提 PR：commit message 含 "假设 X / 验证 Y / 决策 Z"
   d) alpha 复跑确认主观体感对齐
```

> **开放问题 7**：v1 数值通关率目标？默认 30-50%（标准 roguelike），等用户拍板。

### D7. M7 收尾标准

**决策**：
- 全套 GUT PASS 维持
- BalanceConstants 覆盖率 ≥ 90%（hook 内魔数全部用 BalanceConstants.get）
- 至少 5 次 alpha + 1 次 beta 反馈循环
- simulation 通关率落在用户拍板的目标范围
- M6 待办 `tougenkyo_v1` 实装收尾

---

## 文件结构（拟）

```
godot/
├── battle/
│   └── skill_ctx.gd                    # 改：扩 13+ 个新 API（按 D1 4 批）
├── meta/
│   └── balance_constants.gd            # 新：集中数值表（D2）
├── skills/hooks/                       # 改：~15-20 个 hook 升级到 spec 原效果（D5）
│   ├── seal_chun_hook.gd               # 改：用 ctx.consume_self()
│   ├── soul_drain_hatsu_hook.gd        # 改：常量从 BalanceConstants 取
│   ├── east_phantom_hook.gd            # 改：用 ctx.set_furiten(seat, 1)
│   ├── tougenkyo_hook.gd               # 新：M6 遗留 tougenkyo_v1（用 ctx.swap_hand_river）
│   └── ... （每个 hook 头部 "M7 增强" 注释逐个移除）
├── tests/
│   ├── battle/
│   │   └── test_skill_ctx_extensions.gd # 新：4 批 ctx API 各自单测
│   ├── meta/
│   │   └── test_balance_constants.gd   # 新：key 完整性 / 默认值 / get 异常路径
│   └── skills/
│       └── test_*.gd                   # 改：升级后 hook 的 spec 效果覆盖
├── tools/
│   ├── simulate_runs.gd                # 新：批量 Run simulation（D4）
│   └── sim_results/                    # 输出目录（gitignore）
└── docs/
    ├── playtest/                       # 新：alpha / beta 反馈记录（D3）
    │   ├── _template.md
    │   └── 2026-MM-DD-alpha-N.md
    └── superpowers/plans/
        └── 2026-05-03-balance-iteration.md  # 本文档
```

---

## 任务清单（待用户拍板后细化）

### A. SkillCtx 扩展（D1 4 批 PR）
- [ ] B1 软扩展：`consume_self` / `set_furiten` / `clear_furiten_to`（已有先导 PR draft）
- [ ] B2 Dora 系：3 个 API + DoraIndicators 集成
- [ ] B3 计分系：6 个 API + ScoreFormula / PayoutCalculator 集成
- [ ] B4 信息 + 大状态：6 个 API + BattleState / Wall / Hand 集成

### B. BalanceConstants（D2）
- [ ] `meta/balance_constants.gd` + 字典 + `get()` + 单测
- [ ] 替换 `gacha.gd` / `meta_progress.gd` / `node_result.gd` 内魔数
- [ ] 替换 6-8 个 hook 内魔数（每个 hook 1 个小 PR）

### C. tougenkyo_v1（M6 遗留）
- [ ] 等 B4 `swap_hand_river` ctx API 落地后实装 hook + 测试 + CardPool 注册
- [ ] 任务板对应行勾选；M6 整体进度 → 100%

### D. Simulation 工具（D4）
- [ ] `tools/simulate_runs.gd` CLI + 输出 JSON
- [ ] sample 输出文档化（`docs/playtest/_simulation_baseline.md`）
- [ ] 跑首次 baseline，定义"目标范围"

### E. 玩家测试漏斗（D3）
- [ ] `docs/playtest/_template.md` 模板
- [ ] alpha 1（开发组内 5 个 Run），写 2026-05-XX-alpha-1.md
- [ ] beta 节奏对齐（用户拍板渠道后启动）

### F. 数值迭代（D6）
- [ ] 按 alpha + simulation 输出列每周"假设 → 验证 → 决策" PR
- [ ] M7 收尾验收（D7 全部满足）

---

## 开放问题（待对齐）

1. B3/B4 高风险 API 拆更细（1 API/PR）还是按批合？
2. BalanceConstants 用 const dict 还是 .tres Resource？
3. Beta 反馈承载渠道（GitHub Discussion / Google Form / Discord）？
4. Alpha 期间是否引入"自动数值评估"作为快速反馈？
5. Simulation 用 SimpleAi 还是接主题 AI？
6. Hook 升级 commit message 规范是否同 D5 模板？
7. v1 数值通关率目标范围？
8. M7 是否同时启动半庄战 / 西入 / 国士 13 面 / 责任编辑等 spec §14 标注的 Phase 2 可选项？默认否。

---

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| SkillCtx 扩展破坏现有 hook 行为（兼容回归） | 每批 ctx PR 跑全套 GUT；hook 升级与 ctx 扩展是分开 PR，可独立 revert |
| BalanceConstants 替换魔数遗漏 → 部分代码用旧值 | grep 检查 `0.30 / 0.50 / 8` 等魔数残留；CI 一旦有就加 lint |
| Simulation 与真人差距大 → 数值调过头 | alpha + simulation 双轨；任何调整必须两端都验证 |
| 反馈漏斗运营成本高（写模板、整理） | 模板尽量结构化；alpha 控制在 30 分钟会话以内 |
| `tougenkyo_v1` 是 spec §8.10 旗帜性效果，B4 ctx 实装难度高 | 排到 B4 末尾；若 swap_hand_river 太复杂可先实装"swap_hand_with_3_random_river"等中间态 |
| M7 跨度长，节奏丢 | 每 2 周一次 alpha + simulation 节点；用户可中途调优先级 |

---

## 验证

- **plan 阶段（本 PR）**：仅文档化；无代码改动；不跑测试。
- **实装阶段（未来 PR）**：
  - 每批 ctx 扩展跑全套 GUT 0 fail
  - BalanceConstants 单测覆盖 key 完整性 + 异常路径
  - simulation 输出可重现（同 seed 同 deck → 同 JSON）
  - alpha / beta 反馈每次都落到 docs/playtest/
  - 数值迭代 PR 描述含"假设 / 验证 / 决策"三段
  - M6 唯一遗留 `tougenkyo_v1` 收尾时 M6 进度 → 44/44

---

## 后续动作

用户拍板后：
1. 用 `superpowers:writing-plans` 把本 brainstorm 转正式实现计划
2. 对齐 8 条开放问题，把答案直接编辑回本文档
3. 启动 M7 实装；优先级 B（BalanceConstants 先）→ A B1（软扩展）→ D（simulation baseline）→ E（首次 alpha）→ A B2/B3/B4（按反馈数据驱动）→ C（tougenkyo）→ F（数值迭代）
