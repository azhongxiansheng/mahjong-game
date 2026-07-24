# Simulation Baseline 9 — 2026-05-04（M9 endgame 收窄到剩 ≤ 1 局）

> 接续 [`baseline 8`](2026-05-04-baseline-8-lead-gap-threshold.md)（PR #90 lead_gap 阈值）。baseline 8 通关率 30% 仍卡在 D6 区间下沿。本 PR 收窄 endgame 触发条件：从"剩 ≤ 2 局"→ "剩 ≤ 1 局"，仅最后一局收紧立直，前一局让玩家正常立直保持攻击力。

## 元信息

- **会话期间 base HEAD**：M9 lead_gap 合入后 main
- **关键变化（vs baseline 8）**：
  - HeuristicAi `_is_endgame()` 从 hardcoded `total_hands - 2` 改为查 BalanceConstants
  - 新增 `endgame_skip_riichi_remaining_hands = 1`（默认仅最后一局 endgame）
- **CLI**：`--heuristic-ai --fair-tiebreak --ai-seat-abilities`（同 baseline 7/8）
- **跑了几个 Run**：control × 10

## 数据矩阵

| 配置 | 通关率 | HP avg | avg nodes | tsumo% | ron% | draw% | seat0 / seat1 / seat2 / seat3 |
|---|---|---|---|---|---|---|---|
| **control × 10 (baseline 9)** | 30% | 0.7 / 4 | 18.6 | 7.2% | 47.9% | 44.8% | **160688** / **76432** / -19919 / -117200 |

## 与 baseline 7/8 累积对比

| 指标 (control) | b7 (any-lead) | b8 (gap≥12k) | **b9 (last-hand only)** | 趋势 |
|---|---|---|---|---|
| 通关率 | 30% | 30% | 30% | 持平（样本噪音内） |
| HP avg | 0.7 | 0.7 | 0.7 | 持平 |
| seat 0（玩家） | 142558 | 145721 | **160688** | **+18k** ⬆ 更激进立直 |
| seat 1（领先 AI） | 111071 | 97042 | **76432** | **−35k** ⬇ asymmetry 持续缩小 |
| seat 2 | -41723 | -29335 | -19919 | +22k ⬆ |
| seat 3（垫底） | -111906 | -113428 | -117200 | -5k 微跌 |
| seat 1 - seat 2 spread | 153k | 126k | **96k** | **−57k** ✅ |
| tsumo% | 10.4 | 9.7 | 7.2 | -3.2 pp |
| ron% | 44.3 | 44.1 | 47.9 | +3.6 pp |

## 关键发现

### endgame 收窄继续缩小 AI 间不对称
seat 1 - seat 2 spread 从 baseline 7 的 153k 一路降到 baseline 9 的 96k，**减少 57k (37%)**。说明 endgame 策略生效但触发条件越收窄越好——半庄南 3 / 东风战东 3 不应跳立直，仅最后一局收紧。

### tsumo 率下降值得关注
tsumo% 从 10.4 → 7.2（降 3.2 pp），ron% 从 44.3 → 47.9（升 3.6 pp）。变化方向：玩家更激进立直 → 听牌后等 ron 多 → tsumo 机会让位。这是 endgame 收窄的副效应；非 endgame 时段所有人立直率回升。

### 通关率仍 30%（D6 区间下沿）— 假设 Q 仍未解
玩家 seat 0 平均 160k vs AI 平均 (-19k+76k-117k)/3 = -20k，差距 180k。玩家在分数上彻底碾压 AI，但章 3 hanchan 翻倍 HP 惩罚（rank 3 = -2 HP, rank 4 = -4 HP）让玩家偶尔失败一次就接近脱靶。

## 假设状态更新

| 假设 | b7 → b9 | 说明 |
|---|---|---|
| O — AI ability 不 fire | 证伪 | unchanged |
| **P — 落后方策略** | **解决（部分）** | spread 减小 37%，AI 间不对称大幅缩小 |
| **Q — hanchan + endgame 双重叠加** | **持续未解** | 通关率卡 30% 不动 |
| L — aggro/fast 需防御 | 未解 | unchanged（不在本 PR 范围） |

## 下一步候选（M9 后续）

按 ROI：
1. **减 hanchan 范围**：章 3 前 4 floor east_round / 后 4 hanchan（章 1-2 全 east，章 3 半段渐进）— 直接缓解假设 Q
2. **章 3 hanchan HP/Gold 惩罚减半**：[0,0,-2,-4] → [0,0,-1,-3]（介于 east 和 hanchan 之间）
3. **同事 priority**：假设 L（aggro/fast 防御）+ B3/B4 ctx 升级

baseline 7 → 9 累积变化已经把 AI 内卷问题大幅缓解，下一步必须直接动 hanchan 难度参数才能让通关率回到中段。

## 已知 limitation

- 10 runs 样本小，标准差 ±15pp；通关率"30% 持平 3 次"统计意义有限，但 spread 趋势单调下降 = 真信号
- aggro/fast 没测（baseline 7 已确认 0% bottom-out）
