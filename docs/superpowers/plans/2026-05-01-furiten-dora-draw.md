# 麻将王 — 里程碑 0d：振听 / Dora / 流局 / 立直状态 实现计划

> **Goal:** 完成日麻规则引擎的剩余纯算法层 —— 振听、听牌张、Dora 张数、立直/振听状态对象、流局（牌墙耗尽 + 5 种途中流局）。**不含**状态机、事件总线、鸣牌触发条件 —— 这些留给下一个 plan（turn_engine）与里程碑 1（技能框架）。

**Spec 锚点**：`docs/superpowers/specs/2026-05-01-mahjong-king-design.md`
- §3.2 日麻术语（振听 / 流局 / 5 种途中流局定义）
- §5 数据类型（RiichiState / FuritenState / DoraIndicators）
- §13 里程碑 0

## 范围

In-scope:
- `WaitCalculator` 听牌张计算（枚举 34 张 + 复用 `WinPattern.detect`）
- `FuritenChecker` 振听判定（待牌张 ∩ 自家弃牌河 ≠ ∅）
- `DoraIndicator` Dora 张数统计（复用 `TileId.next_for_dora` + 含赤 dora）
- `RiichiState` 立直状态对象（declared / turn / ippatsu_window / double_riichi / stick_paid）
- `FuritenState` 振听状态对象（permanent / temporary / waits）
- `DoraIndicators` 容器（visible / hidden_uradora）
- `ExhaustiveDraw` 牌墙耗尽流局：不听罚符分配 + 庄家连庄判定
- `AbortiveDraw` 5 种途中流局判定（纯函数）

Out-of-scope:
- BattleState 全量
- `core/turn_engine/`（摸/弃/鸣牌状态机）
- BattleEventBus / SkillScheduler
- 鸣牌（chi/pon/kan）的触发条件
- 立直宣言流程（属于状态机，本计划只提供 RiichiState 数据 + 简单转换）

## 关键假设

1. `WaitCalculator` 复用 `WinPattern.detect` 暴力枚举 34 张，性能可接受（手牌 13 张 × 34 候选 × decompose 微秒级，远低于 1ms）
2. 振听 = 永久振听 ∪ 暂时振听 ∪ 立直振听；checker 只返 bool，状态字段维护交给调用方
3. Dora 不构成役（spec §3.2），张数纯加；赤 dora 各 5 数牌每色 1 张（plan 0c YakuList 的 dora_count 字段已统一）
4. 不听罚符（罚符 3000）分配：所有不听家共出 3000 / 不听家数；分给听牌家 3000 / 听牌家数；都是听 / 都不听则 0
5. 5 种途中流局判定函数都是**纯**的，输入完整快照（不依赖外部状态）
6. 缩进：TAB（与 0a/0c 一致）

## 文件清单

新增源 7 + 测试 7：

| 路径 | 用途 |
|------|------|
| `godot/core/rules_japanese/wait_calculator.gd` | 听牌张枚举 |
| `godot/core/rules_japanese/furiten_checker.gd` | 振听判定 |
| `godot/core/rules_japanese/dora_indicator.gd` | Dora 张数统计 + indicator → dora |
| `godot/core/rules_japanese/exhaustive_draw.gd` | 牌墙耗尽流局：罚符 + 连庄 |
| `godot/core/rules_japanese/abortive_draw.gd` | 5 种途中流局判定 |
| `godot/battle/riichi_state.gd` | 立直状态对象 |
| `godot/battle/furiten_state.gd` | 振听状态对象 |
| `godot/battle/dora_indicators.gd` | Dora 指示牌容器 |

> **`battle/` 子目录**新增：本计划首次创建 `godot/battle/`（spec §4.1 已规划），仅放纯数据对象。状态机/控制器留给下一计划。

不动的：
- 0a/0c 已交付的源/测试
- `godot/scripts/*.gd` 旧脚本

## Task 拆分（TDD）

每 task 严格 Red → Green → commit。

1. `WaitCalculator` — 枚举 34，调用 `WinPattern.detect`
2. `FuritenChecker` — waits ∩ discard_pile ≠ ∅
3. `RiichiState` 数据对象
4. `FuritenState` 数据对象（含 update_from_discard helper）
5. `DoraIndicator` — 单 indicator → dora；多 indicator + 手牌 → dora 数
6. `DoraIndicators` 容器（visible / hidden_uradora）
7. `ExhaustiveDraw` — 罚符分配 + 庄家连庄判定
8. `AbortiveDraw` — 5 种途中流局判定纯函数
9. 收尾 + 完成记录 + push

## 验证

- `scripts/test_run_core.sh` 累计测试 ≥ 230（0c 末 164 + 0d 新增 ~70），0 失败
- 0a/0c 现有代码 0 修改

## 风险

| 风险 | 缓解 |
|------|------|
| `WinPattern.detect` 输入约束（hand.size + 3*melds.size + 1 == 14）→ WaitCalculator 调用时手是 13 张，需"虚拟摸"再 detect | WaitCalculator 内部对每个候选 winning_tile 构造调用，正确传 hand=13 + winning_tile（detect 已含 winning_tile 加进去再 decompose） |
| 振听 3 类（永久/暂时/立直）状态字段易乱 | FuritenState 字段命名严格按 spec §5；checker 只看一个 bool 输出；状态切换在调用方 |
| 5 种途中流局触发顺序与裁定 | v1 仅做"判定函数"返 bool；触发时机/优先级留给状态机 |

## 后续

完成后：
1. 进入下一计划（turn_engine + BattleState 状态机）
2. 之后里程碑 1（技能框架 + 事件总线 + SkillScheduler + 5 demo 技能）

---

## 完成记录

- **完成日期**：2026-05-01
- **累计测试数**：236（GUT，Scripts 28 / Asserts 613，全部 PASS）
- **本计划新增**：72 测试（236 - 0c 末 164）
- **commit 数**：8（每 task 1 个）+ 1 docs
- **分支**：`feat/plan-0d-furiten-dora-draw`

### 提交清单（按时间倒序）

| SHA | 主题 |
|-----|------|
| `bafde6f` | AbortiveDraw 5 种途中流局判定（Task 8） |
| `fc69cdc` | ExhaustiveDraw 罚符 + 庄连庄（Task 7） |
| `2798582` | DoraIndicators 容器（Task 6） |
| `fa95001` | DoraIndicator 指示牌→dora + 张数（Task 5） |
| `3ee8e5e` | FuritenState 振听状态对象（Task 4） |
| `2b7885a` | RiichiState 立直状态对象（Task 3） |
| `c074152` | FuritenChecker 振听判定（Task 2） |
| `9ca6786` | WaitCalculator 听牌张枚举（Task 1） |
| `ad7d460` | docs: plan 0d 实现计划（base） |

### 已确认事实

- 0a/0c 已交付的源/测试 一字未动
- 5 个新源到 `godot/core/rules_japanese/`（wait_calculator / furiten_checker / dora_indicator / exhaustive_draw / abortive_draw）
- 3 个新源到首次创建的 `godot/battle/`（riichi_state / furiten_state / dora_indicators）
- 8 个新测试全部 `godot/tests/core/`
- 累计 236 个测试，0 失败

