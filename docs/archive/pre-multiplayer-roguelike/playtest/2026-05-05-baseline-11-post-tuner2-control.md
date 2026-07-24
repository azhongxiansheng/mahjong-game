# Simulation Baseline 11 — 2026-05-05（post tune-R2 control multi-seed 验证）

> 接续 [`baseline 10`](2026-05-04-baseline-10-post-force-yakuman.md)（pre-tune-R2，control 平均 26%）。tune-R2（PR #100）把 hanchan hp_delta [-2,-4] → [-1,-2] 软化章 3 翻倍惩罚后再跑 multi-seed baseline。**seed=1000 从 0% 救回 40%；3 seed 中位 46.7% 稳稳落 D6 30-50% 区间上段**。

## 元信息

- **会话期间 main HEAD**：`d71dcb0` — docs(plan-9): M9 收尾 (#101)
- **关键变化（vs baseline 10 pre-tune-R2）**：
  - PR #100：hanchan hp_delta `[0,0,-2,-4]` → `[0,0,-1,-2]`（east_round 同 [-1,-2] 不变，3/4 位玩家半庄惩罚减半）
- **配置**：control × 15 runs, 3 seed (1000/2000/3000), --heuristic-ai --fair-tiebreak --ai-abilities

## 数据矩阵

| seed | baseline 10 (pre tune-R2) | **baseline 11 (post tune-R2)** | Δ |
|---|---|---|---|
| 1000 | **0%** (10-run) | **40.0%** (15-run) | **+40 pp** ⬆⬆ |
| 2000 | (n/a) | **53.3%** (8/15) | — |
| 3000 | (n/a) | **46.7%** (7/15) | — |
| **中位数** | (26% avg 5-seed) | **46.7%** | **+20 pp** ⬆ |

完整 3-seed 数据：

| seed | 通关率 | 失败位置 | avg nodes | HP avg | tsumo% | ron% | seat 0 / 1 / 2 / 3 |
|---|---|---|---|---|---|---|---|
| 1000 | 40.0% (6/15) | 章 2: 5 / 章 3: 4 | 17.6 | 0.8 | 19.9% | 35.9% | 238795 / 3028 / -32158 / -109665 |
| 2000 | **53.3%** (8/15) | 章 2: 5 / 章 3: 2 | 17.8 | 1.1 | 15.9% | 43.9% | 224697 / -18289 / -34715 / -71693 |
| 3000 | 46.7% (7/15) | 章 1: 1 / 章 2: 5 / 章 3: 2 | 18.3 | 0.7 | 13.9% | 43.3% | 236265 / -901 / -18578 / -116785 |

## 关键发现

### tune-R2 救活 seed=1000 章 3 必死局面 ✅

baseline 10 报 seed=1000 control = **0%**（boss3 force_yakuman + hp_delta -4 双重打击下章 3 全军覆没）。tune-R2 把 hp_delta -4 → -2 后 seed=1000 通关率 **40%**（章 3 失败仍 4/15，但能撑过更多节点）。

| seed=1000 阶段 | 通关率 |
|---|---|
| baseline 9 (pre-#96 force_yakuman) | 20% |
| baseline 10 (post-#96 + pre tune-R2) | **0%** ⬇⬇ |
| **baseline 11 (post tune-R2)** | **40.0%** ⬆⬆ |

tune-R2 的 effect 相当显式：**让"章 3 输 1 节点 = 直接挂"变成"输 2 节点才挂"**。

### 3 seed 中位 46.7% 接近 D6 上界

| seed | 通关率 | D6 30-50% |
|---|---|---|
| 1000 | 40.0% | ✅ 中段 |
| 2000 | **53.3%** | ❌ 超 +3.3 pp |
| 3000 | 46.7% | ✅ 上段 |

3 seed 中位 46.7% — **比 baseline 9 multi-seed 中位 40% 高 +6.7 pp**。tune-R2 **整体把 control 从 D6 中段拉到上段**。seed=2000 已超 +3.3pp，需观察是否 seed-specific 偏置或常态。

### tune-R2 副作用：tsumo% 上升

| seed | baseline 9 multiseed tsumo% | baseline 11 tsumo% | Δ |
|---|---|---|---|
| 1000 | 16.8% | 19.9% | +3.1 |
| 2000 | 15.6% | 15.9% | +0.3 |
| 3000 | 14.4% | 13.9% | -0.5 |

seed=1000 tsumo% 显著上升 +3.1 pp — tune-R2 让玩家在章 3 hanchan 多撑节点 → 更多玩家自摸机会。

### seed=2000 control 53.3% 是真上界还是噪声？

baseline 7 hanchan multiseed s=2000 = 46.7%（pre-tune-R2 + 多个 PR 之前）。post-tune-R2 升到 53.3%（+6.6 pp）。tune-R2 对 seed=2000 的 push 比 seed=1000 弱 — seed=2000 章 3 失败本来就只 3 个，tune-R2 救的边际节点变少，但仍微推。

D6 30-50% 上界突破 +3.3 pp 仅 seed=2000 一个数据点，需要更多 seed 验证。**单 seed 单点不足以触发 tune-R3 决策**。

## 横向观察

### tune-R2 让 control parity 优势回升

baseline 10 时 aggro/fast 平均 30% > control 平均 26%（boss3 force_yakuman 拖累 control 章 3）。post-tune-R2 control 中位 46.7% — **预期 control 重回主流通关包**。需要 baseline 11 aggro/fast 数据验证（待做）。

### seat 0 玩家分微降

- baseline 9 multiseed s=2000 玩家分 = 233492
- **baseline 11 s=2000 玩家分 = 224697 (-3.8%)**

tune-R2 让玩家少挂 → 更长的 Run → 更多节点 → 更多对手 ron 玩家机会 → 玩家分微降。**通关率上升但玩家分下降**说明"通关率"和"玩家分"是不同维度。

### 假设 R 完全解决 ✅

baseline 10 提"假设 R: boss3 force_yakuman 让章 3 boss 节点变成高方差（0-40%）punishing"。tune-R2 把 punishment 从 -4 HP 软化到 -2 HP 后：
- seed=1000 从 0% → 40%
- 整体 multiseed 区间从 0-40% → 40-53%
- 3 seed 中位移到 D6 上段

**假设 R 完全 address**。

## 后续动作（按 ROI）

- [ ] **PR：baseline 11 aggro/fast 多 seed × 15** — 验证 3 包 parity 是否在 post-tune-R2 仍 holds（预期 aggro/fast 也在 40-53% 区间）
- [ ] **观察 seed=2000 53.3% 是否 seed-specific** — 如果 baseline 11 aggro/fast s=2000 也 50%+，tune-R2 可能微过；若只 control 高，可能偏置
- [ ] **plan-9 closure (#101) 假设演化表加 R 解决**（已隐含但 doc 可显式标）

## 关键里程碑（更新）

| 阶段 | control 通关率 | D6 30-50% |
|---|---|---|
| baseline 9 multi-seed (pre-#96, pre tune-R2) | 中位 40% | ✅ 中段 |
| baseline 10 (post-#96, pre tune-R2) | 平均 26% | ❌ -4 pp |
| **baseline 11 (post tune-R2)** | **中位 46.7%** | **✅ 上段** |

> **tune-R2 把 baseline 10 的 punishing-章 3 现象救回**。3 seed 中位接近 D6 上界，需要 aggro/fast multi-seed 数据 + 后续 seed 验证 53.3% 是否常态。

## 与 plan-9 closure (#101) 的关系

closure 报"3 包 multi-seed parity：control 38% / aggro 30% / fast 30%（D6 30-50% 区间）"。本 baseline post-tune-R2 control 中位 46.7% **比 closure 报的 38% 高 +8.7pp** — 因为 closure 用了 5 seed × 10 runs 平均（包括 force_yakuman 但用了 baseline 10 数据），而 baseline 11 是 post-tune-R2 + 3 seed × 15 runs。

修正：**post tune-R2 control 真实通关率 ~46.7%**，不是 closure 报的 38%。aggro/fast 验证将给完整 picture。
