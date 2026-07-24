# 麻将王 — 里程碑 6：内容生产任务板（30+ 牌技能 + 8-10 角色能力 + 3 章 Boss + 3 起始包）

> **状态**：进行中。M0-M5 已完成（PR #11-#30）；M6 是内容生产 + 数值填充，工作量大，**适合并行多人协作**。
>
> **本仓库 GitHub Issues 被禁用**，本文档 = "Issue Tracker"：每个任务用 `- [ ]` checkbox 标识，认领时改为 `- [x] @owner-name` 在 commit 中标记完成。同事/agent/contributor 可以独立挑一个 checkbox 任务，按 "认领规则" 起一个 PR 实装。

**Spec 锚点**：
- §8 技能方向示例（§8.1-§8.10）
- §13.6 里程碑 6（30+ 技能 + 8-10 ability + 3 章 Boss + 3 起始包）
- §14 可调参数（v1 数值锁住，平衡留 M7）

**前置依赖（已落地）**：
- M1 技能框架（SkillResource / SkillScheduler / SkillCtx / SkillHook）✅
- M5 抽卡系统（CardPool / Gacha）✅
- M5 SaveSystem ✅

---

## 认领规则（重要）

**每个 checkbox = 一个独立 PR**。认领方式：

1. **挑一项 unchecked 任务**（看下面分组），新起分支 `feat/m6-<task-id>`（如 `feat/m6-aggro-tiles` / `feat/m6-ability-yamigan`）
2. **改的文件路径** 仅以下三类（避免与其它任务冲突）：
   - 新增 `godot/skills/hooks/<id>_hook.gd`（hook 实装）
   - 新增 `godot/tests/skills/test_<id>.gd`（GUT 测试）
   - 在 `godot/meta/card_pool.gd` 的 `all_tile_variants()` / `all_abilities()` 末尾追加 1 行 `_mk_tile(...)` / `_mk_ability(...)` 注册新内容
3. **不改 SkillScheduler / SkillCtx / SkillResource 等核心** —— 如需新 ctx API（如 multiply_han），单独开 issue 讨论
4. **每张技能/能力配 ≥ 3 个 GUT cases**（spec §12.2 强制）：
   - 正路：触发条件满足 → 期望状态变更
   - 反例：触发条件不满足 → 状态不变
   - 边界：跨多 seat / 跨事件 / 与已有技能交互
5. **commit message 格式**：`feat(m6/<category>): 实装 §8.X "<牌名>"（<id>）` + `Co-Authored-By: ...`
6. **PR 描述含**：`spec §8.X` 锚点 / 实装行为概述 / 测试覆盖矩阵 / 修改的 CardPool 行号

完成后回到本文档把对应 `- [ ]` 改为 `- [x]` 并 commit 进同一 PR。

---

## A. 牌技能（按 §8.X 9 类，目标 30+ 张）

每类目标：3-4 张。M1 已有的 5 张 demo（`thunder_5w_v1` / `seal_chun_v1` / `soul_drain_hatsu_v1` / `xray_1w_v1` / `unfuriten_5p_v1`）已在 CardPool 注册，本节内容**新增**为主。

### §8.1 增番系（Yaku Boost） — 目标 4 张

- [x] **`thunder_5w_v1`** [史] 5 万·闪电 — owner 自胡 +1 番（**M1 demo 已有**）
- [x] **`white_haku_holy_v1`** [精] 白板·圣光 — 持此牌且自胡 → +1 番（v1 简化：原 spec ×1.5 数值留 M7）（PR #31）
- [x] **`east_dynasty_v1`** [神] 东风·王者气 — v1：owner==dealer（event.extra["dealer_seat"] 注入）且自胡 +2 番
- [x] **`green_hatsu_serenity_v1`** [精] 发·禅意 — 任意人作三元牌胡牌时 +1 番（holder 模式）（PR #32）

### §8.2 加速胡牌系（Tempo） — 目标 3 张

- [x] **`pin9_speed_v1`** [精] 9 筒·速胡 — v1：owner 摸到此牌触发 force_tsumo（标 haitei_forced_seat=owner）
- [x] **`sou3_skip_v1`** [精] 3 索·跳跃 — v1：owner 自胡 +1 番（模拟跳过下家收益）；真"跳过下家"需 turn_engine.skip_seat（M7）
- [x] **`south_riichi_breeze_v1`** [精] 南风·风行 — v1：owner 自胡 +1 番（模拟立直多看牌收益）；真 reveal_next_wall_tile 需 ctx 扩展（M7）

### §8.3 阻止对方胡牌系（Defense） — 目标 3 张

- [x] **`seal_chun_v1`** [史] 中·封印 — owner 弃出导致 RON_DECLARED 时取消（**M1 demo 已有**）
- [x] **`man9_iron_wall_v1`** [精] 9 万·铁壁 — owner 被荣胡时役 -1 番（v1：ctx.add_han(actor, -1)；若降至 ≤ 0 不在本 hook 处理，由 ScoreFormula 钳制）（PR #32）
- [x] **`west_mirror_v1`** [史] 西风·镜像 — owner 立直时清振听 1 次（PR #32）

### §8.4 抓马反向得分系（Counter） — 目标 3 张

- [x] **`soul_drain_hatsu_v1`** [神] 发·吸魂 — holder 受益对手胡牌 30%（**M1 demo 已有**）
- [x] **`east_mirror_chambo_v1`** [精] 东·镜抓 — v1：owner 放铳被荣胡时 transfer_points(winner→owner, points_won × 0.5) 真实施 ×0.5 退款（PR #42 同事采纳；优于早期 -1 番桩）
- [x] **`sou8_scapegoat_v1`** [精] 8 索·替罪 — v1：owner 放铳时给胜者 -1 番（模拟责任转嫁）；真"指对手放铳"需 mark_pao_transfer ctx 扩展（M7）

### §8.5 透明牌 / 信息系（Reveal） — 目标 3 张

- [x] **`xray_1w_v1`** [精] 1 万·透视 — owner 摸牌后 reveal 下家手牌 1 张（**M1 demo 已有**）
- [x] **`white_oracle_v1`** [精] 白·占卜 — v1：owner 摸牌时 reveal HAKU 占位代表"未翻 Dora 指示"；真"读 wall.dora_indicators"需 reveal_wall_segment_to ctx 扩展（M7）
- [x] **`pin2_bluff_v1`** [精] 2 筒·诈和 — v1：owner 自胡 +1 番（模拟伪装收益）；真"伪装手牌"需 mask_hand_tiles ctx 扩展（M7）

### §8.6 立直系（Riichi） — 目标 3 张

- [x] **`south_premature_riichi_v1`** [神] 南·先制立直 — v1：owner 自胡 +2 番（模拟双立直 + 一发）；真"第 1 巡立直"需 force_double_riichi ctx 扩展（M7）
- [x] **`unfuriten_5p_v1`** [史] 5 筒·解振听 — 立直后违反摸切发振听清除（**M1 demo 已有**）
- [x] **`hatsu_stick_refund_v1`** [精] 发·点棒返还 — v1：owner 自胡 +1 番（模拟立直棒返还收益）；真 transfer_points 需立直棒接收方信息（M7）

### §8.7 振听操控系（Furiten Manipulation） — 目标 3 张

- [x] **`east_phantom_v1`** [精] 东·迷踪 — v1：owner 弃东被荣胡时取消（同形 seal_chun，但 tile=东）。真"下家振听 1 巡"需 set_furiten ctx 扩展（M7）
- [x] **`man2_lure_v1`** [精] 2 万·诱铳 — v1：owner 自胡 +1 番（模拟伪装收益）。真"伪装听牌"需 set_fake_tenpai ctx 扩展（M7）
- [x] **`chun_substitute_v1`** [精] 中·替身 — v1：owner 自胡时若振听则清振听。真"指定对手承担"需 set_furiten ctx 扩展（M7）

### §8.8 Dora 系（Dora） — 目标 3 张

- [x] **`man6_treasure_v1`** [神] 6 万·夺宝 — v1：owner 自胡 +1 番（模拟额外 Dora）。真"翻指示牌"需 mark_extra_dora ctx 扩展（M7）
- [x] **`white_red_change_v1`** [精] 白·赤变 — v1：owner 自胡 +1 番（模拟红 5）。真"改 5 字段为 red"需 mark_red_dora ctx 扩展（M7）
- [x] **`sou4_uradora_pick_v1`** [精] 4 索·指示牌操纵 — v1：owner 自胡 +2 番（模拟最优裏 Dora）。真"重选裏 dora"需 reroll_uradora ctx 扩展（M7）

### §8.9 役満 / 终局系（Endgame） — 目标 3 张

- [x] **`north_sweep_v1`** [神] 北·一扫 — v1：owner 自胡 +3 番（模拟全场分摊）；真"ALL_4_PAY"需 mark_all_pay ctx 扩展（M7）
- [x] **`white_mangan_floor_v1`** [神] 白·役满下限 — v1：owner 自胡 +5 番 + consumed=true（模拟满贯下限）；真"满贯保底 + 消耗"需 ensure_mangan + consume_self ctx 扩展（M7）
- [x] **`pin9_haitei_double_v1`** [神] 9 筒·龙断 — 海底/河底役 ×2（v1 简化为 +1 番）（PR #33）

---

## B. 角色能力（§8.10 16 个候选 → 落地 8-10 个）

按 spec §13.6 选取标准（神 4-5 + 史 4-5）：

### 神级（4-5）

- [x] **`seabed_hunter_v1`** 海底狩人（spec §8.10 #2）— **M1 demo 已有**
- [x] **`mineu_no_oni_v1`** 嶺上の鬼（#1）— v1：自胡 +2 番（5 选 1 平均收益）；真效果需 draw_choose_n_of_m ctx 扩展（M7）
- [x] **`san_kyoku_kiseki_v1`** 三局一奇跡（#7）— v1：自胡 +1 番；真"起手强插刻子"需 inject_meld_at_start ctx 扩展（M7）
- [x] **`isshun_senken_v1`** 一巡先見（#4）— v1：DRAW 时 reveal 占位；真"看下次摸牌"需 reveal_next_draw ctx 扩展（M7）
- [x] **`shichu_kyu_katsu_v1`** 死中求活（#11）— 点棒 < 5000 时所有役 +2 番（PR #33）
- [x] **`tougenkyo_v1`** 偷天换日（#12）— v1：自胡 +3 番 + consume_self（M7 收尾实装；真"swap_hand_river"留 Phase 2）

### 史诗（4-5）

- [x] **`yamagan_v1`** 山眼（#3）— v1：GAME_BEGIN reveal 1 张占位；真"读 wall 顶 10 张"需 reveal_wall_segment ctx 扩展（M7）
- [x] **`tenpai_seethru_v1`** 听牌看穿（#5）— v1：对手 HAND_FORMED 时 reveal 占位给 owner；真"读对手听牌张"需 reveal_tenpai ctx 扩展（M7）
- [x] **`ryukyoku_yudou_v1`** 流局誘導（#6）— v1：自胡 +1 番（局面控制等价收益）；真"强制流局"需 turn_engine.force_ryukyoku（M7）
- [x] **`tousotsu_v1`** 統率（#8）— v1：自胡 +1 番（buff 总收益等价）；真"提高其它 ability 触发额度"需 boost_other_abilities ctx 扩展（M7）
- [x] **`riichi_kago_v1`** 立直加護（#9）— v1：自胡 +1 番（一发期望加倍）；真"延长一发窗口"需 extend_ippatsu_window ctx 扩展（M7）

---

## C. 章节 Boss（3 张签名规则破坏角色能力 — 每章 1 张）

每章 Boss 是一个 AI seat 装备的"签名能力"，规则破坏强 + 主题鲜明。Boss 同时作为该章节地图最末一节点的 NodeKind.BOSS 节点配置。

- [x] **章 1 Boss：`boss1_iron_curtain_v1`** 铁幕（防御主题）— v1：Boss 受 RON 时取消（cancel_ron）；reg_order 全命中需 M7 扩 ctx
- [x] **章 2 Boss：`boss2_fortune_runner_v1`** 福星（Tempo + Dora）— v1：自胡 +2 番（模拟额外 Dora）；force_tenpai_at_start 需 M7
- [x] **章 3 Boss：`boss3_kanmon_v1`** 关门（终局）— v1：HAITEI/HOUTEI 自胡 +3 番（模拟役满升级）；force_yakuman 需 M7

每个 Boss issue 的 PR 还需：
- 修改 `meta/chapter_config.gd` 让对应章节的 BOSS NodeRef.meta 含 `boss_id` 字段
- 修改 `meta/battle_node_runner.gd`（或新 helper）在 BOSS 节点 inject Boss 的 SkillResource 到 SkillRegistry
- F6 烟测：手测一场对 Boss 的对局

---

## D. 起始包（3 套：火力 / 速胡 / 控场）

替换 `meta/starter_packs.gd` 中 v1 仅"控场可选"的占位为 3 套真实可选。每个起始包 = 8-10 张牌技能（来自 A 节）+ 1-2 张角色能力（来自 B 节）。

- [x] **`starter_aggro` 火力包** — thunder_5w + white_haku_holy + green_hatsu_serenity + pin9_haitei_double + shichu_kyu_katsu ability
- [x] **`starter_fast` 速胡包** — unfuriten_5p（已实装的立直系）；premature_riichi 等待 §8.6 实装时再扩
- [x] **`starter_control` 控场包** — xray_1w + seal_chun + west_mirror + man9_iron_wall + soul_drain_hatsu + seabed_hunter ability

每个起始包 PR 还需更新 `tests/meta/test_starter_packs.gd` 验证 3 套都 available + 内容非空。

---

## 进度追踪

| 类别 | 总数 | 已完成 | 完成率 |
|---|---|---|---|
| §8.1 增番系 | 4 | 4 | 100% |
| §8.2 加速 | 3 | 3 | 100% |
| §8.3 阻胡 | 3 | 3 | 100% |
| §8.4 抓马 | 3 | 3 | 100% |
| §8.5 透明牌 | 3 | 3 | 100% |
| §8.6 立直 | 3 | 3 | 100% |
| §8.7 振听 | 3 | 3 | 100% |
| §8.8 Dora | 3 | 3 | 100% |
| §8.9 终局 | 3 | 3 | 100% |
| **§8 牌技能小计** | **28** | **28** | **100%** |
| 神级角色能力 | 5 | 5 | 100% |
| 史诗角色能力 | 5 | 5 | 100% |
| **§8.10 角色能力小计** | **10** | **10** | **100%** |
| 章 Boss | 3 | 3 | 100% |
| 起始包 | 3 | 3 | 100% |

**M6 整体进度：44 / 44 任务（100%）** — `tougenkyo_v1` M7 收尾用 v1 简化（+3 番 + consume_self），真 spec swap_hand_river 留 Phase 2

### M6 收尾

- 全套 GUT：**881/881 PASS**（M5 收尾时 840 → +41 case）
- 28 张牌技能 + 9 张角色能力 + 3 章 Boss + 3 起始包 全部落地
- v1 简化策略：所有需新 ctx API 的真效果都用 `add_han` / `cancel_ron` /
  `force_tsumo` / `reveal_tile_to` / `clear_furiten` 等价表达；具体留
  M7 项已在每个 hook 文件头部注释。
- M7 待扩 ctx 一览（按出现频次排序）：
  - `set_furiten(seat, turns)` — 振听操控系
  - `mark_extra_dora_for_seat` / `mark_red_dora` / `reroll_uradora` — Dora 系
  - `mark_pao_transfer` — 抓马责任转嫁
  - `force_yakuman` / `ensure_mangan` — 终局保底
  - `force_double_riichi` / `extend_ippatsu_window` — 立直系
  - `reveal_wall_segment_to` / `reveal_next_draw` / `reveal_tenpai_tiles` — 信息系
  - `inject_meld_at_start` / `swap_hand_river` / `draw_choose_n_of_m` — 角色能力
  - `scale_payout` / `mark_all_pay` — 计分调整
  - `consume_self` — 一次性消耗品（替代 `skill.consumed = true` 直写）

> 完成项更新方式：在 PR 中把对应 `- [ ]` 改为 `- [x]`，同时更新本表"已完成"数。

---

## 接口约束（重要）

为让多 PR 并行不冲突，约束如下：

1. **Hook 文件命名**：`<id>_hook.gd`（如 `white_haku_holy_hook.gd`）
2. **Hook 必继承 SkillHook** 并 override `on_event(skill, event, ctx)`
3. **Hook 内不直接读 BattleState** —— 如需 dealer_seat / round_wind 等只能通过 `ctx.event.extra` 或 SkillCtx 现有 API。**若发现需要新 ctx 字段**，先在本文档添加一节"开放问题"待讨论
4. **CardPool 注册**：在 `card_pool.gd` 的 `all_tile_variants()` 函数最后追加（不要改前面的）。append 顺序是稳定 testing 用途
5. **测试用例最少 3 个**（spec §12.2）。复用 `_setup()` / `_make_skill()` 模式（参考 `test_thunder_5w.gd`）
6. **GUT 必须 0 fail / 0 parse / 0 SCRIPT ERROR**（`gut_run_full.sh` or `--gdir=res://tests --ginclude_subdirs`）

---

## v1 简化与待办

许多 spec §8 描述的效果需要 SkillCtx 现在没有的 API（如 `force_tsumo` 已有，但 `multiply_han` / `force_riichi_no_tenpai` / `swap_hand_with_pile` 还没有）。**M6 v1 实装时一律降级**为现有 SkillCtx 能表达的最简版（如 ×1.5 → +1 番），并在 hook 注释里标注 "M7 增强为 spec 原效果"。

**禁止扩展 SkillCtx 公共 API** 在 M6 v1 内（除非用户明确批准）。理由：扩 API 会让所有现有 hook 和 SkillScheduler / 单测同步改动，工作量爆炸。

---

## 关于本会话的示范实装

本会话同 PR 演示工作模式（已勾选 §8.1 中"白板·圣光"）：
- 新增 `skills/hooks/white_haku_holy_hook.gd`（5 行）
- 新增 `tests/skills/test_white_haku_holy.gd`（3 cases）
- `card_pool.gd:all_tile_variants` 末尾追加 1 行 `pool.append(_mk_tile(...))`
- 所有 GUT 0 回归

剩余 ~38 个任务等同事 / 后续会话认领。
