# Simulation Baseline 10 — 2026-05-04（post-force_yakuman 多 seed 验证）

> 接续 [`baseline 9 multi-seed`](2026-05-04-baseline-9-multiseed-control.md)（修正 control 20% 偏低是 seed 偏置）。PR #95（legacy 归档）+ #96（force_yakuman + boss3 升级）后再跑 multi-seed baseline。**boss3_kanmon 真升役满后章 3 杀伤显著提高**。

## 元信息

- **会话期间 main HEAD**：`7806d27` — feat(m9/ctx-b3): force_yakuman_for_seat + boss3_kanmon 升级 (#96)
- **关键变化（vs baseline 9）**：
  - PR #95：12 个零引用中麻代码搬到 godot/legacy/（不影响逻辑）
  - PR #96：boss3_kanmon v1 \`add_han(+3)\` 桩 → v2 \`force_yakuman_for_seat\`
- **CLI**：`--heuristic-ai --fair-tiebreak --ai-seat-abilities`（同 baseline 7-9）
- **runs / seed**：每 pack 跨 5 seed × 10 runs（control）+ 3 seed × 10 runs（aggro/fast）= 110 runs 总

## 数据矩阵 — control multi-seed

| seed | baseline 9 (pre-#96) | **baseline 10 (post-#96)** | Δ |
|---|---|---|---|
| 42 | (n/a) | **30%** | — |
| 100 | (n/a) | **30%** | — |
| 1000 | 20% | **0%** | **−20 pp** ⬇⬇ boss3 真役满拉低章 3 通关 |
| 5000 | (n/a) | **30%** | — |
| 9999 | (n/a) | **40%** | — |

**control 平均 26%**（5 seed），相比 baseline 9 multi-seed 的 ~33% 略降。boss3 force_yakuman 把 seed=1000 的章 3 大概率失败放大到 100% 失败。

## 数据矩阵 — aggro / fast multi-seed

| seed | aggro | fast |
|---|---|---|
| 42 | 40% | 40% |
| 100 | 30% | 30% |
| 1000 | 20% | 20% |

**aggro/fast 平均 30%**。aggro/fast 间 byte-for-byte 接近一致（同样的 seat 0 score，差仅 ~100 点）—— PR #91 后 fast pack 的 8 张 tiles 与 aggro 6 张差异在数据上不可见（待差异化机制再分化）。

## 核心发现

### 假设 R（新）：boss3 force_yakuman 让章 3 boss 节点变成"高方差"事件

- 之前 boss3 +3 番桩：章 3 boss 是大威胁但可承受（+3 番 ≈ 满贯）
- 现在 boss3 真役满：章 3 boss 命中 → ron 玩家 32000-48000 点
- 半庄战章 3 hanchan 翻倍惩罚（rank 3 = -2 HP）让一次大铳直接挂掉

设计意图是这样的（"章 3 是高难度"），但通关率方差 0-40% 表明 v1 数值偏 punishing。

### M9 调参方向候选

| 假设 | 验证策略 | 优先级 |
|---|---|---|
| **R-1** boss3 force 仅 HAITEI（保留）但 HOUTEI 降回 +3 番 | 让 boss3 终局 ron 不一定役满 | 中 |
| **R-2** chapter 3 hanchan rank 3/4 降到 [-1, -2]（同 east_round） | 半庄惩罚翻倍是 punisher 之一 | 高 |
| **R-3** 给玩家 1 张"防役满"消耗品 skill | 终局 boss-kill 后悔药 | 低（content production） |

### 平均通关率落入 D6 区间下沿

| pack | 平均通关率（multi-seed） | D6 目标 |
|---|---|---|
| control | 26% | 30-50% |
| aggro | 30% | 30-50% ✅ |
| fast | 30% | 30-50% ✅ |

aggro/fast 进入 D6 下沿；control 受 boss3 拖累略低于。3 包 parity 大致维持。

## 后续动作

- [x] **多 seed 验证 baseline 9 趋势** ✅
- [ ] **R-1 / R-2 调参**（让 control 回到 30-50%）
- [ ] **B3 ctx 剩余 API**：scale_payout / mark_pao_transfer / mark_all_pay
- [ ] **3 包差异化机制**（假设 Q）
