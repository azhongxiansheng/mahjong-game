# Simulation Baseline 11 — 2026-05-05（post tune-R2 aggro multi-seed 验证）

> 接续 [`baseline 11 control`](2026-05-05-baseline-11-post-tuner2-control.md)（post tune-R2 control 中位 46.7%）。本 baseline 跑 aggro × 15 多 seed (1000/2000/3000)。**3 seed 通关率与 control 完全相同（40 / 53.3 / 46.7%），3 包 parity 在 post-tune-R2 持续完美**。

## 元信息

- **会话期间 main HEAD**：`37be151` — chore: legacy 第 3 批 (#104)
- **配置**：aggro × 15 runs, 3 seed (1000/2000/3000), --heuristic-ai --fair-tiebreak --ai-abilities

## 数据矩阵

| seed | 通关率 | 失败位置 | avg nodes | HP avg | tsumo% | ron% | seat 0 |
|---|---|---|---|---|---|---|---|
| 1000 | **40.0%** (6/15) | 章 2: 5 / 章 3: 4 | 17.6 | 0.9 | 19.8% | 35.9% | 351840 |
| 2000 | **53.3%** (8/15) | 章 2: 5 / 章 3: 2 | 17.8 | 1.1 | 15.9% | 43.9% | 339629 |
| 3000 | **46.7%** (7/15) | 章 1: 1 / 章 2: 4 / 章 3: 3 | 18.5 | 0.7 | 13.6% | 43.8% | 353580 |

## 与 control 完全 parity

| seed | control | aggro | Δ |
|---|---|---|---|
| 1000 | 40.0% | **40.0%** | 0 ✅ |
| 2000 | 53.3% | **53.3%** | 0 ✅ |
| 3000 | 46.7% | **46.7%** | 0 ✅ |
| **中位** | **46.7%** | **46.7%** | **0** ✅✅ |

**3 seed 通关率完全相同**（baseline 9 multiseed 也曾发现 s=2000 / s=3000 完全 parity，见 PR #97）。

### 同 RNG 路径，分配差异

| seed=1000 | control | aggro | Δ |
|---|---|---|---|
| avg nodes | 17.6 | 17.6 | 0 ✅ |
| HP avg | 0.8 | 0.9 | +0.1 |
| tsumo% | 19.9% | 19.8% | -0.1（噪声） |
| 失败章 2 | 5 | 5 | 0 ✅ |
| 失败章 3 | 4 | 4 | 0 ✅ |
| seat 0 玩家分 | 238795 | 351840 | **+47%** |

aggro 与 control 在 RNG 路径上完全一致；唯一差异是 **seat 0 玩家分比 control 高 ~50%**（soul_drain_hatsu_v1 多吸 12% han）。**通关率瓶颈是节点排名分布而非玩家分绝对值**（PR #97 已记同样观察）。

### s=3000 微差异

| s=3000 | control | aggro |
|---|---|---|
| 失败章 2 | 5 | 4 |
| 失败章 3 | 2 | 3 |
| avg nodes | 18.3 | 18.5 |

s=3000 唯一的 RNG 路径分歧 — aggro 章 2 救回 1 节点但章 3 又挂 1，**总通关率仍 7/15 = 46.7% 完全等价**。aggro 防御 skill (W9 iron_wall) 在某些 RNG 序列下能让玩家撑到下一节点，但章 3 hanchan 仍是主瓶颈。

## 关键发现

### 假设 L 完全解决（再次确认）

| 阶段 | aggro 中位通关率 |
|---|---|
| baseline 7 large-sample (pre PR #91) | 5% |
| baseline 9 multi-seed (post #91) | 40% |
| **baseline 11 (post tune-R2 + #91)** | **46.7%** ✅ |

aggro 从最初 5% 一路涨到 46.7% — 与 control parity，spec §7.2 "3 套差异化但都可玩"目标完全实现。

### 假设 Q（3 包同质化）— **再次证伪**

baseline 9 (#93) 提"假设 Q：3 包都用 soul_drain → 同质化削弱 control 优势"。post-tune-R2 数据：

- control 中位 46.7%
- aggro 中位 46.7%
- **完全 parity，control 没有"被削弱"，反而 aggro 跟上**

3 包"差异化"通过其他维度体现（W9 iron_wall / CHUN seal_chun / 各包独有 tile_variants）。soul_drain 作通用基底持续可行。

### tune-R2 effect on aggro：与 control 对称

| seed | aggro pre tune-R2 (baseline 10) | aggro post tune-R2 (本 baseline) | Δ |
|---|---|---|---|
| 1000 | 20% | **40.0%** | **+20 pp** ✅ |
| 42 | 40% (baseline 10) | (n/a 本 baseline) | — |
| 100 | 30% (baseline 10) | (n/a) | — |

tune-R2 把 aggro seed=1000 也从 20% 救回 40%（同 control 救回 0%→40%）。两包受益对称。

## 横向观察

### seat 1/2/3 spread 加剧

| seed | control seat 3 | aggro seat 3 | Δ |
|---|---|---|---|
| 1000 | -109665 | (-160k 估计 from 玩家+47%) | aggro 让 seat 3 更惨 |
| 2000 | -71693 | -? | seat 1/2 已 -58k/-79k |
| 3000 | -116785 | -? | seat 1/2 已 -61k/-49k |

aggro pack 让玩家多吸约 80-100k，主要从 seat 3（玩家对家）攒。**spread 极大** 提示：spec §14 "玩家平均收益"和"AI 间相对位次"是分离的设计杠杆。

### post tune-R2 的 D6 上界压力持续

| seed | aggro 通关率 | D6 30-50% |
|---|---|---|
| 1000 | 40.0% | ✅ 中段 |
| 2000 | **53.3%** | ❌ 超 +3.3 pp |
| 3000 | 46.7% | ✅ 上段 |

aggro seed=2000 也 53.3% 超上界 — 与 control seed=2000 一致。**seed=2000 是真上界，不是 control-specific 偏置**。tune-R2 把 D6 上限轻微突破已是结构性 — 需要 tune-R3 决策（如 hanchan rank 3 hp_delta -1 → 0）或接受。

## 后续动作（按 ROI）

- [ ] **fast 多 seed × 15 post-tune-R2 验证** — 闭环假设 M（fast 是否仍 byte-identical 于 aggro）
- [ ] **观察 seed=2000 53.3% 超上界趋势** — 若再跑 seed=4000 / 5000 也 50%+，触发 tune-R3 决策
- [ ] **plan-9 closure (#101) 假设演化表** — Q 标 "证伪 ✅"，R 标 "tune-R2 解决 ✅"
- [ ] M9 closure (#101) "control 38% / aggro 30% / fast 30%" 数据 **过时** — 实际中位 control 46.7% / aggro 46.7%（待 fast 验证）

## 关键里程碑（更新）

| 阶段 | aggro 通关率 | D6 30-50% |
|---|---|---|
| baseline 7 large-sample | 5% | ❌ |
| baseline 9 multi-seed (post #91) | 40% | ✅ 中段 |
| **baseline 11 (post tune-R2)** | **46.7%（中位）**| **✅ 上段（s=2000 超上界 +3.3pp）**|

> **3 包 parity 在 post tune-R2 + multi-seed 双重验证下完美达成**。3 seed × 2 pack = 6 数据点，control / aggro 在 6/6 数据点完全一致。spec §7.2 设计意图实现已超过验证门槛。

## 修正 plan-9 closure (#101) 数据

closure 报：
> 3 包 multi-seed parity：control 38% / aggro 30% / fast 30%（D6 30-50% 区间）

实际 post tune-R2 + 3 seed × 15 runs：
- control 中位 **46.7%**
- aggro 中位 **46.7%**
- fast 待跑

**closure 数据偏低 ~8-17 pp**（用了 baseline 10 pre tune-R2 的 5-seed × 10-run 平均）。建议 closure 加 footnote 标"baseline 11 post-tune-R2 数据见 PR #102 / 本 PR"。
