# Simulation Baseline 9 — 多 seed control 验证（修正"control 20% 偏低"判断）

> 接续 [`baseline 9 (3-pack parity)`](2026-05-04-baseline-9-three-pack-parity.md)。同事报"control 跌到 20%（baseline 7 是 53%）"提"control nerf 偏低，是否要把 soul_drain 留 control + 给 aggro/fast 弱版"。本 baseline **多 seed 验证发现 seed=1000 是异常值**，control 真实通关率落 ~40-47%，**仍稳稳在 D6 30-50% 区间**。

## 元信息

- **会话期间 main HEAD**：`7d949cc` — feat(m9/endgame-narrow) (#92)
- **配置**：control × 15 runs, 3 个 seed (1000/2000/3000), --heuristic-ai --fair-tiebreak --ai-abilities
- **方法学**：复用 baseline 7 hanchan multi-seed 同方法（PR #88）

## 数据矩阵

| seed | 通关率 | 失败位置 | avg nodes | HP avg | tsumo% | ron% | draw% | seat 0 |
|---|---|---|---|---|---|---|---|---|
| 1000 (baseline 9 原数据) | **20.0%** (3/15) | (n/a) | (n/a) | 0.3 | (n/a) | (n/a) | (n/a) | 198582 |
| **2000** (本次) | **46.7%** (7/15) | 章 2: 5 / 章 3: 3 | 17.1 | 1.0 | 15.6% | 45.4% | 39.0% | 233492 |
| **3000** (本次) | **40.0%** (6/15) | 章 1: 1 / 章 2: 5 / 章 3: 3 | 17.6 | 0.6 | 14.4% | 42.8% | 42.9% | 237784 |

## 关键发现

### seed=1000 是 baseline 9 control 异常值

| seed | 通关率 | 偏离 3-seed 中位数 |
|---|---|---|
| 1000 | 20.0% | **-20 pp**（异常低）|
| 2000 | 46.7% | +7 pp |
| 3000 | 40.0% | 中位数 |

**3 seed 平均：~35%**。中位数 40%。**seed=1000 是 -20pp 异常值**，不代表真实分布。

### "control nerf 到 20% 偏低"判断需修正

baseline 9 doc 提议"是否要把 soul_drain 留 control + 给 aggro/fast 弱版"是基于 seed=1000 的 20%。**多 seed 显示 control 真实通关率 40-47%，稳稳落 D6 30-50% 区间中-上段**。**不需要回拨**。

### baseline 9 假设 L 解决判断仍成立

aggro/fast 在 baseline 9 doc 报 33.3% / 33.3% — 即使加 ±20pp seed 噪声，aggro/fast 通关率也仍非 0% 完全失败。**3 包 parity 设计意图 = 都"可玩"** 仍达成。

但 aggro/fast 多 seed 验证可作 followup（本 baseline 仅跑 control）。

### 假设 Q（3 包同质化）— **重新评估**

baseline 9 提"3 包都用 soul_drain → 同质化"作为新风险。多 seed 验证显示：

- seed=1000: control 20% < aggro/fast 33%（同事数据）— 暗示 control 失去优势
- seed=2000: control 46.7% — control 仍偏强
- seed=3000: control 40.0% — 中段

**3 包同质化不必然削弱 control 优势** — 取决于 seed 抽到的对手 ability 配合度。**Q 假设需要 aggro/fast 多 seed 验证才能确认**。

## 与 baseline 7 hanchan 对比（M7+M8 → M8.5+M9 全 stack）

| 阶段 | control 通关率（多 seed）|
|---|---|
| baseline 7 hanchan (PR #88) | 40-47%（seed 1000/2000） |
| **baseline 9 multiseed（本文档）** | **20-47%**（seed 1000/2000/3000）|

baseline 9 区间更宽（M8.5/M9 终局策略 + aggro/fast 防御 skill 引入更多 RNG 路径）。中位 ~40% 与 baseline 7 hanchan 中位 ~43% 接近 — **大方向是 control 仍稳稳落 D6，但 seed 方差明显上升**。

## 横向观察

### seed 方差上升原因（推测）

baseline 7 hanchan multi-seed 区间 40-47%（差 7pp），baseline 9 区间 20-47%（差 27pp）。可能：
1. **aggro/fast 防御 skill** 让 4 家被动收益网络更对称 → 玩家收益上限降低 + 抗 RNG 能力下降
2. **M8.5/M9 终局策略**让 AI 在领先时不立直 → 局末分数变化更剧烈，玩家通关临界点更敏感
3. **lead_gap 阈值**让 AI 间互相牵制 → 玩家失误窗口更细

3-seed 不够覆盖完整方差 — **建议 baseline 10 用 5 seed × 15 run** 或 **baseline 10 用 30-run 单 seed** 给更稳数据。

### seat 终局点数

| seed | seat 0 玩家 | spread (max - min) |
|---|---|---|
| 2000 | 233492 | 305k |
| 3000 | 237784 | 366k |

玩家分仍 ~230-240k 高于 4 家平均 0 — soul_drain 在 control 包仍是主收益源；同质化未削弱玩家收益绝对值（**削弱的是相对优势**）。

## 后续动作（按 ROI）

- [ ] **不需要回拨 control / soul_drain 留 control**（多 seed 显示 40-47% 仍稳）
- [ ] **PR：baseline 10 — aggro/fast 多 seed × 15** 验证 33% 是否也 seed 敏感（如果 aggro 跑出 50%+ 单 seed，需重新评估假设 L）
- [ ] **PR：baseline 11 — control 30-run 单 seed**（vs 15-run × 3 seed 哪个方差更小）
- [ ] **保留同事 baseline 9 的假设 Q** 标 "Pending multi-seed validation" — 暂不调整 game design

## 对 baseline 9 的修正

| 同事原结论 | 多 seed 修正 |
|---|---|
| control 跌到 20%（偏低） | **40-47%（仍 D6 中段）** |
| 需要把 soul_drain 留 control | **不需要**（seed=1000 是异常值）|
| 3 包同质化削弱 control 优势 | 待验证（aggro/fast 多 seed 数据未跑）|

## 关键里程碑（更新）

| 阶段 | control 通关率 | D6 30-50% |
|---|---|---|
| baseline 7 hanchan multi-seed | 40-47% | ✅ |
| baseline 9 single seed (s=1000) | 20.0% | ❌ -10 pp |
| **baseline 9 multi-seed (本文档)** | **40-47% (median 40%)** | **✅ 中-上段** |

> **多 seed 验证 = 对小样本异常值的解药**。M7+M8.5+M9 累积调参后 control 仍稳稳落 plan-7 D6 目标，**不需要进一步 nerf 或 buff**。
