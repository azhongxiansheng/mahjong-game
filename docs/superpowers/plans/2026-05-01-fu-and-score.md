# 麻将王 — 里程碑 0c：日麻符算 + 点数公式 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development 或 superpowers:executing-plans。

**Goal:** 在 0a 引擎地基之上，实现日麻符算（fu）、点数公式（base + 满贯档 + 役满钳制）、支付分配（自摸/荣胡 × 庄/闲 + 本场 + 立直棒 + 包牌 stub），并提供顶层 `ScoreCalc.calculate()` 入口。与同事并行的 plan 0b（30+ 役判定）模块独立、数据契约共享，0b 完工后由本计划负责开串接 PR。

**Architecture:** 在 `godot/core/rules_japanese/{fu,score}/` 下新增纯 GDScript 模块，复用 0a 的 `StandardDecomposer` / `WinPattern` / `Meld` / `TileId`，全部走 GUT TDD（Red → Green → Refactor）。

**Tech Stack:**
- Godot 4.5+（验证机 4.6.1.stable.official）
- GDScript 2.0
- GUT 9.4.0
- 命令行：`scripts/test_run_core.sh`

**Spec 锚点:** `docs/superpowers/specs/2026-05-01-mahjong-king-design.md` §5 ScoreCalc/YakuList、§14 役満倍数上限。

---

## 范围与非目标

**In-scope:**
- `WinContext` 胡牌瞬时上下文
- `YakuList` 役清单数据契约（与 0b 共享）
- `MeldFu` 面子符 / `PairFu` 雀头符 / `WaitFu` 待牌符
- `FuCalculator` 综合符算（含七対子 25、平和 20/30、副底 20、自摸 +2、门清荣胡 +10）
- `ScoreFormula` 基本点 + 满贯档 + 役满倍数（spec §14 上限 2）
- `PayoutCalculator` 支付分配（自摸/荣胡 × 庄/闲 + 本场 + 包牌 v1 stub）
- `ScoreCalc` 顶层入口

**Out-of-scope:**
- 役判定（属 plan 0b）
- 振听 / Dora / 立直状态 / 流局判定（属 plan 0d）
- BattleState / 事件总线 / 状态机（属 plan 0d 与里程碑 1）
- 包牌完整规则（v1 stub，复杂规则留 0d）

## 关键假设

1. **`YakuList` 契约由本计划锚定**（依据 spec §5）。0b 偏离时由本计划串接 PR 适配。
2. **包牌 v1 stub**：自摸 → pao_seat 出全；荣胡 → pao_seat 与 loser 各半。
3. **连风牌雀头**：取 +2（与天凤一致）。
4. **不实施切上満貫**：30 符 4 番 = 1920 按 1920 算。
5. **多分解选 fu 最高**（TODO: 0b 串接后改 (han, fu) 字典序最大）。
6. **缩进**：`.gd` 用 TAB（与 0a 一致）。

## 文件清单

新增 9 源 + 9 测试：

| 路径 | 用途 |
|------|------|
| `godot/core/rules_japanese/win_context.gd` | 胡牌上下文 |
| `godot/core/rules_japanese/yaku_list.gd` | 役清单契约 |
| `godot/core/rules_japanese/fu/meld_fu.gd` | 面子符 |
| `godot/core/rules_japanese/fu/pair_fu.gd` | 雀头符 |
| `godot/core/rules_japanese/fu/wait_fu.gd` | 待牌符 |
| `godot/core/rules_japanese/fu/fu_calculator.gd` | 综合符算 |
| `godot/core/rules_japanese/score/score_formula.gd` | 基本点 + 满贯档 |
| `godot/core/rules_japanese/score/payout_calculator.gd` | 支付分配 |
| `godot/core/rules_japanese/score_calc.gd` | 顶层入口 |
| `godot/tests/core/test_*.gd` | 对应 9 个测试文件 |

不动 0a 的 9 个源 + 9 测试，不动 `godot/scripts/*.gd` 旧脚本。

---

## 完成记录

- **完成日期**：2026-05-01
- **累计测试数**：164（GUT，Scripts 19 / Asserts 489，全部 PASS）
- **commit 数**：9（每 task 1 个）
- **执行方式**：直接在 worktree 内 TDD 推进
- **最终 HEAD**：`2ae75c1`

### 提交清单（按时间倒序）

| SHA | 主题 |
|-----|------|
| `2ae75c1` | ScoreCalc 顶层入口 + 日麻 golden cases（Task 9） |
| `63983a6` | PayoutCalculator 支付分配 — 自摸/荣胡 × 庄/闲 + 本场 + 包牌 stub（Task 8） |
| `078c460` | ScoreFormula 基本点 + 满贯档 + 役满倍数（Task 7） |
| `ed1cb6f` | FuCalculator 综合符算入口（Task 6） |
| `21131bc` | WaitFu 待牌符 — 边/嵌/单骑 +2 / 双面/双碰 0（Task 5） |
| `4a47b66` | PairFu 雀头符 — 役牌+2 / 其余 0（Task 4） |
| `a1563ff` | MeldFu 面子符 — 顺/刻/杠 × 中张/幺九 × 明/暗（Task 3） |
| `a0556a0` | YakuList 役清单数据契约 + stub（Task 2） |
| `90b58ef` | WinContext 胡牌瞬时上下文（Task 1） |

### 已确认事实

- 0a 的 9 个源文件 + 9 个测试 一字未动
- 9 个新源文件全部落 `godot/core/rules_japanese/{fu,score,}/`
- 9 个新测试文件全部落 `godot/tests/core/`
- 累计 164 个测试，0 失败
- 含日麻标准点数表 golden case：30符1番闲自摸 1100 / 50符4番闲荣胡满贯 8000 / 庄国士役满 48000
- 全部 commit 待 push 到 `feat/plan-0c-fu-and-score`

### 后续

1. 等同事 plan 0b PR 合并到 main
2. 由本计划开串接 PR：把 stub `YakuList` 替换为 0b 真实输出，跑全套 + golden case 验证
3. 进入 plan 0d（振听 / Dora / 立直 / 流局 / 状态机）
