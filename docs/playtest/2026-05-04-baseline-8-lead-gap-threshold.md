# Simulation Baseline 8 — 2026-05-04（M9 假设 P：endgame skip riichi 加 lead gap 阈值）

> 接续 [`baseline 7`](2026-05-04-baseline-7-endgame-ai.md)（M8.5 落地，PR #89）。baseline 7 观察 endgame "任何领先即跳" 让 AI 间 spread 翻倍（seat 1 平均 43k → 111k）。M9 假设 P 改进：仅当**显著领先**（≥ 12000 = 半庄子家满贯）才跳过立直。

## 元信息

- **会话期间 base HEAD**：M8.5 合入后 main `0963df2`
- **关键变化（vs baseline 7）**：
  - HeuristicAi `_should_skip_riichi` 加 `_lead_over_second(seat) >= endgame_skip_riichi_lead_gap` 检查
  - BalanceConstants 加 `endgame_skip_riichi_lead_gap = 12000`
- **CLI**：`--heuristic-ai --fair-tiebreak --ai-seat-abilities`（同 baseline 7）
- **跑了几个 Run**：control × 10

## 数据矩阵

| 配置 | 通关率 | HP avg | avg nodes | tsumo% | ron% | draw% | seat0 / seat1 / seat2 / seat3 |
|---|---|---|---|---|---|---|---|
| **control × 10 (baseline 8)** | **30%** | 0.7 / 4 | 17.9 | 9.7% | 44.1% | 46.2% | 145721 / **97042** / -29335 / -113428 |

## 与 baseline 7 对比（control，主验证目标）

| 指标 (control) | baseline 7 | baseline 8 | Δ |
|---|---|---|---|
| 通关率 | 30% | 30% | 持平（样本噪音内） |
| HP avg | 0.7 | 0.7 | 持平 |
| avg nodes | 16.8 | 17.9 | +1.1 |
| seat 1 平均 | **111071** | **97042** | **−14029** ✅ spread 缩小 |
| seat 2 平均 | -41723 | -29335 | +12388 ✅ |
| seat 3 平均 | -111906 | -113428 | -1522 |

## 关键发现

### 假设 P **部分成立** — AI 间 spread 缩小但通关率未升
- ✅ seat 1 vs seat 2 spread 从 152k → 126k（缩小 17%）
- ✅ seat 1 不再无脑保护点数（领先 < 12000 时正常立直）
- ❌ 玩家 control 通关率仍 30%（D6 区间下沿）

含义：spread 是 AI 间内卷问题，控通关率主要受**玩家 vs AI** 差距驱动。玩家 145k vs AI 平均 (-29k+97k+...)/3 = -15k，差距 160k。

### 假设 Q（hanchan + endgame 双重叠加把通关率推到下沿）依然成立
要让 control 重回 30-50% 中段，候选：
1. 减 hanchan 范围（章 3 半段 east_round / 半段 hanchan）
2. 玩家也用 endgame 策略 — 但 sim 中已经是（HeuristicAi 共享）；问题是玩家更常领先 → endgame 不立 → 通关率反降
3. 缩小 endgame 触发条件 — 改"剩 ≤ 1 局"（仅最后一局收紧）

## 下一步候选

按 M9 priority：
1. 测 `endgame_skip_riichi_lead_gap = 6000`（更激进阈值，让更多 endgame 立直发生）
2. 测 endgame 触发条件改"剩 ≤ 1"（半庄南 4 / 东风战东 4 only）
3. 解 假设 L（aggro/fast 防御技能）— 同事 Phase 2 priority
4. 解 假设 O 真根因（ability ctx mutation）— 同事 B3/B4 ctx 升级

## 已知 limitation

- 10 runs 样本小（标准差 ≈ ±15pp）；通关率 "30% 持平" 可能掩盖 ±5pp 差异
- 仅 control 跑了；aggro/fast 没测（baseline 7 显示它们是 0% bottom-out，阈值化不会改变）
- baseline 8 数据建议 M9 复跑 30+ runs 稳定
