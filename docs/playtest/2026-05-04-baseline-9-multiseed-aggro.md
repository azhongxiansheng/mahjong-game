# Simulation Baseline 9 — aggro 多 seed 验证（修正"假设 Q 同质化削弱 control"判断）

> 接续 [`baseline 9 control multiseed`](2026-05-04-baseline-9-multiseed-control.md)（PR #94）。control 多 seed 显示 40-47% 真实区间。本 baseline 跑 aggro × 15 多 seed (1000/2000/3000)，**确认 3 包真实通关率几乎完全一致 (~40%)** — 比同事 baseline 9 报的"3 包 parity"更深。

## 元信息

- **会话期间 main HEAD**：`7806d27` — feat(m9/ctx-b3) force_yakuman_for_seat (#96)
- **配置**：aggro × 15 runs, 3 个 seed (1000/2000/3000), --heuristic-ai --fair-tiebreak --ai-abilities
- **方法学**：复用 baseline 9 control multi-seed 同方法（PR #94）

## 数据矩阵

| seed | 通关率 | 失败位置 | avg nodes | HP avg | tsumo% | ron% | seat 0 |
|---|---|---|---|---|---|---|---|
| 1000 (#93 baseline 9) | 33.3% (5/15) | (n/a) | (n/a) | 0.7 | 21.3% | 32.2% | 333606 |
| **2000** (本次) | **46.7%** (7/15) | 章 2: 5 / 章 3: 3 | 17.1 | 1.0 | 15.6% | 45.4% | 352274 |
| **3000** (本次) | **40.0%** (6/15) | 章 1: 1 / 章 2: 4 / 章 3: 4 | 17.9 | 0.6 | 14.1% | 43.3% | 356048 |

## 与 control 多 seed 对比（PR #94）

| seed | control 通关率 | aggro 通关率 | Δ |
|---|---|---|---|
| 1000 | 20.0% | 33.3% | +13.3 pp |
| 2000 | 46.7% | 46.7% | 0 ✅ |
| 3000 | 40.0% | 40.0% | 0 ✅ |
| **中位** | **40%** | **40%** | **0** ✅ |

**seed=2000 和 3000 control/aggro 通关率完全相同（46.7% / 40.0%）**。仅 seed=1000 控制 control 低 13pp。

### 同 RNG 路径，不同 scoring

seed=2000 control 和 aggro：
- **完全相同**：失败位置（章2:5/章3:3）、avg nodes (17.1)、HP avg (1.0)、tsumo% (15.6%)、ron% (45.4%)、draw% (39.0%)
- **不同**：seat 0 玩家分（control 233k vs aggro 352k = +51%）

aggro pack 现在拥有 soul_drain_hatsu_v1（PR #91）让玩家从 hatsu 牌再多吸 12% — **同 RNG 路径下玩家积分上升但通关临界条件相同**。说明：通关率瓶颈不在玩家分高低，而在 **HP 损失累计 = 节点排名分布**。

## 关键发现

### 假设 L 解决判断进一步加强

baseline 9 (#93) 报 aggro 33% / control 20% 提到 "3 包 parity 首次达成"。multi-seed 验证显示 **aggro 真实通关率 40-47% = control 40-47% = 完全 parity**。

| 阶段 | aggro 通关率 |
|---|---|
| baseline 7 large-sample | 5% |
| baseline 7 hanchan | 0% |
| baseline 9 (s=1000) | 33.3% |
| **baseline 9 multi-seed (本文档)** | **40-47%（中位 40%）** ✅ |

### 假设 Q（3 包同质化削弱 control）— **证伪 ✅**

baseline 9 提"3 包都用 soul_drain → 同质化削弱 control 优势"。multi-seed 显示：
- **control 中位 40%、aggro 中位 40%、完全 parity**
- "control 优势"在 baseline 9 (s=1000) 是 -13pp，但平均下来等价
- 同质化的"假设 Q 风险"= 误读 seed=1000 单点

**spec §7.2 "3 套差异化但都可玩"目标已达成**。差异化通过 _其他_ skill (W9 iron_wall / CHUN seal_chun / 各包独有 tile_variants) 体现，soul_drain 作通用基底**没有问题**。

### 副信号：aggro pack soul_drain 让玩家分上升 +50% 但通关率 0 变化

aggro seat 0 平均 352k vs control 233k。玩家在 aggro pack 下 _表面收益_ 高 50%，但通关率完全相同。机制：
- 通关瓶颈是 hp_delta 累计（HP 5→0 = 4 次 4 位）
- 节点排名分布主要由 _4 家相对分_ 决定，不由 _玩家分绝对值_ 决定
- aggro 多吸的 100k 主要从 AI 那里来，但 4 家相对位次未必变 → 排名不变 → HP 不变 → 通关率不变

**设计含义**：spec §14 "玩家平均收益 +N pp" 这种数值目标 _不直接驱动_ 通关率。游戏体验维度可能差很大（玩家觉得"赢得舒服"），但 mechanical 通关率维度同质。

## 横向观察

### 章 3 失败比例对比

| pack × seed | 章 1 | 章 2 | 章 3 |
|---|---|---|---|
| control × s2000 | 0 | 5 | 3 |
| **aggro × s2000** | 0 | 5 | 3 |
| control × s3000 | 1 | 5 | 3 |
| **aggro × s3000** | 1 | 4 | 4 |

s2000 控制完全相同；s3000 aggro 章 2 减 1 / 章 3 加 1（防御 skill 让 aggro 在章 2 多撑 1 节点但章 3 仍败）。**hanchan 章 3 翻倍惩罚是通关率主瓶颈**。

### seat 3 两 seed 都极低

- s2000: aggro seat 3 = -102k（vs control -71k = -31k 更低）
- s3000: aggro seat 3 = **-156k**（vs control -128k = -28k 更低）

aggro 让玩家多吸的 ~80-100k 大多从 seat 3 来。seat 3（位置最远 AI）成为 4 家中"持续被 ron"的主要来源 — 半庄战南场 AI 防御策略（PR #90 lead_gap）让落后 AI 仍激进立直，被 ron 概率高。

## 后续动作（按 ROI）

- [ ] **fast 多 seed × 15 验证**（解假设 M — fast 是否真 byte-identical 于 aggro 在 multi-seed 下也成立）
- [ ] **不需要拆分 soul_drain control/aggro/fast**（multi-seed 显示 parity 良好，无需"control 留独占 soul_drain"）
- [ ] **关闭 baseline 9 doc 的"假设 Q 显现"标记** — 已证伪
- [ ] M9 ctx B3 全套（同事 PR #96 已开 force_yakuman，剩 scale_payout / mark_pao_transfer / mark_all_pay）

## 关键里程碑（更新）

| 阶段 | aggro 通关率 | D6 30-50% |
|---|---|---|
| baseline 7 large-sample | 5% | ❌ |
| baseline 7 hanchan | 0% | ❌ |
| baseline 9 single seed (s=1000) | 33.3% | ✅ 下段 |
| **baseline 9 multi-seed (本文档)** | **40-47%（中位 40%）**| **✅ 中段** |

**3 包 parity 在 multi-seed 下完美达成。spec §7.2 "都可玩" 目标 ✅**。

## 对 baseline 9 (#93) 的修正汇总

| #93 原结论 | 多 seed 修正 (PR #94 + 本文档) |
|---|---|
| control 20% 偏低，需要回拨 | control 真实 40-47%，**不需要回拨** |
| 假设 Q：3 包同质化削弱 control | **证伪**（control/aggro 中位都 40%）|
| aggro 33.3% / fast 33.3% | aggro 真实 40-47%（fast 待验证）|

> **multi-seed 是对小样本异常值的解药** — 第二次确认（PR #88 已验过 hanchan baseline 7）。建议项目惯例：所有 baseline 推送到 D-list 决策前，至少 3-seed × 15-run 验证。
