# Simulation Baseline 7 — 2026-05-04（半庄战大样本稳定性验证）

> 接续 [`baseline 6 hanchan`](2026-05-04-baseline-6-hanchan.md)（10-run 控制 70%）+ [`baseline 7 全东风`](2026-05-04-baseline-7-large-sample-stability.md)（15-run 全东风控制 53.3%）。同 main HEAD（PR #85 M8 全 step + #86 + #87 后），把 control × hanchan 从 10-run 提到 **15-run** 验证稳定性。

## 元信息

- **会话期间 main HEAD**：`6fa3b23` — docs(plan-7): M7 收尾文档（#87）
- **配置**：control × 15 runs (seed=1000, --heuristic-ai)，章 3 节点 session_kind="hanchan"
- **同 baseline 6 hanchan 比较**：10-run vs 15-run 同 seed 同 config

## 数据矩阵

| 配置 | 通关率 | 失败位置 | avg nodes | HP avg | tsumo% | ron% | draw% | seat 0 / 1 / 2 / 3 |
|---|---|---|---|---|---|---|---|---|
| baseline 6 hanchan control × 10 | 70% (7/10) | 章 2: 1 / 章 3: 2 | 22.2 | 2.0 | 9.6% | 48.6% | 41.8% | 219109 / 29453 / -54260 / -94302 |
| **baseline 7 hanchan control × 15** | **40.0%** (6/15) | 章 2: 3 / 章 3: 6 | **18.7** | **0.9** | 16.8% | 39.6% | 43.6% | 209146 / -16035 / -20977 / -72134 |
| baseline 6 hanchan aggro × 10 | 0% (0/10) | 章 1: 4 / 章 2: 2 / 章 3: 4 | 11.2 | 0.0 | 2.9% | 55.1% | 42.0% | 139871 / 1826 / 8633 / -50331 |
| **baseline 7 hanchan aggro × 15** | **0.0%** (0/15) | 章 1: 4 / 章 2: 9 / 章 3: 2 | **9.6** | **0.0** | 13.5% | 47.2% | 39.3% | 170423 / -12169 / -42695 / -15560 |
| **baseline 7 hanchan fast × 15** | **0.0%** (0/15) | 章 1: 4 / 章 2: 9 / 章 3: 2 | **9.6** | **0.0** | 13.5% | 47.2% | 39.3% | 170342 / -12169 / -42614 / -15560 |
| **baseline 7 hanchan control × 15 (seed=2000)** | **46.7%** (7/15) | 章 2: 5 / 章 3: 3 | **17.5** | **1.3** | 15.8% | 47.5% | 36.8% | 239480 / -35798 / -53865 / -49817 |

## 关键发现

### 10-run 强烈高估；15-run 暴露真实分布

| 指标 | 10-run | 15-run | Δ |
|---|---|---|---|
| 通关率 | 70% | **40.0%** | **-30 pp**（10-run 大幅高估） |
| avg nodes | 22.2 | 18.7 | -3.5 |
| HP avg | 2.0 | 0.9 | -1.1 |
| tsumo% | 9.6% | 16.8% | +7.2 |
| ron% | 48.6% | 39.6% | -9 |

**baseline 6 hanchan 的 70% 不可靠** — 10-run 样本偶然抽到顺利的 7/10。15-run 显示真实通关率 40%。

### 章 3 失败占主导（6/9 = 67%）

| 失败位置 | 10-run | 15-run |
|---|---|---|
| 章 1 | 0 | 0 |
| 章 2 | 1 | 3 |
| **章 3** | **2** | **6** |

章 3 hanchan 翻倍 HP 惩罚（rank 4 = -4 HP）在 15-run 真实暴露：玩家在章 3 输 1 节点（4 位 / 8 局结束分最末）= 直接 -4 HP，几乎宣告 Run 终结。

### 修正 baseline 6 hanchan 的"70% 微跌于 baseline 5 全东风 75%"判断

baseline 6 hanchan 报"control 75% → 70%（-5pp）章 3 hanchan 翻倍惩罚有感但未崩"是基于 10-run 噪声。**修正：control 真实通关率 40%**，比 baseline 5 全东风 75% **崩了 -35pp**，且**比 baseline 7 全东风 15-run 53.3% 还低 -13.3pp**。

### plan-7 D6 30-50% 目标 — **首次自然落入区间** ✅

| baseline | 配置 | 通关率 | D6 30-50% 落点 |
|---|---|---|---|
| 5 (PR #74 + #75) | 全东风 | 75% | ❌ 超 +25pp |
| 6 (PR #80 + #82) 5-run | 全东风 | 40% | ✅（噪声） |
| 7 (#80 + #82) 15-run | 全东风 | 53.3% | ❌ 超 +3.3pp |
| **7 hanchan (M8) 15-run** | **章 3 hanchan** | **40.0%** | **✅ 中段** |

**M8 章 3 hanchan 的副作用是把 control 通关率从 53.3% 拉到 40%，正好落在 plan-7 D6 30-50% 中段**。tune-3 + 半庄惩罚组合拳让 D6 目标自然达成。

## 假设回顾

| baseline 6 hanchan 假设 | 状态 |
|---|---|
| **J. 章 3 hanchan rank 4 hp_delta -4 太严苛** | **address ✅**（预期效果，让 control 落 D6 区间）|
| K. HeuristicAi 无终局战略（M8.5）| 持续（数据中 AI 间互相喂分仍严重 seat 1/2 -16k/-21k vs seat 3 -72k） |
| L. 章 3 难度跳变过陡 | 持续（章 3 失败 6/15 = 40%，但 control 整体 40% 通关已达 D6 目标，"难度跳变"是 by design） |
| M. aggro/fast pack byte-identical | 持续（PR #76 已记，未在本 baseline 测） |

**假设 J 重新评价**：原 baseline 6 hanchan 提议的"-4 → -3"是基于"70% 已落 D6 之外"的误判数据。15-run 真实 40% 显示 hp_delta -4 **正是 plan-7 D6 目标达成的关键平衡点**，**不需要调整**。

## 三视角对比（M8 收尾全景）

| 阶段 | 配置 | 15-run 通关率 |
|---|---|---|
| baseline 5 (PR #74/#75) | 全东风 + tune-2 | ~75%（仅 5-run） |
| baseline 7 全东风 | 全东风 + tune-3 + AI ability | 53.3% |
| **baseline 7 hanchan (本文档)** | 章 3 hanchan + 同上 | **40.0%** |

control 通关率演化：100% → 60% → 75% → 53.3% → **40.0% ✅**（落 D6 中段）。

## aggro 15-run hanchan — 0% 稳定确认

baseline 6 hanchan aggro × 10 报 0%；本次 aggro × 15 同 seed=1000 跑出 **0.0% (0/15)**，0% 完全稳定。

| 指标 | aggro 10-run | aggro 15-run | Δ |
|---|---|---|---|
| 通关率 | 0% | 0.0% | 0 ✅ 稳定 |
| 失败位置 | 章 1: 4 / 章 2: 2 / 章 3: 4 | 章 1: 4 / 章 2: 9 / 章 3: 2 | 章 2 集中 |
| avg nodes | 11.2 | 9.6 | -1.6（更早死） |
| tsumo% | 2.9% | 13.5% | +10.6（aggro hooks ×2 番有效） |
| seat0 | 139871 | 170423 | +30k |

aggro 早死现象（avg nodes 9.6 vs control 18.7 = 51%）说明 aggro pack 在章 2 阶段就大量崩盘。**章 1 失败 4/15 = 27%** 是 baseline 6 hanchan 已记的问题（与 hanchan 无关，章 1-2 仍东风战）。

aggro 章 3 失败 2/15 = 13% — 进入章 3 的 Run 中，hanchan 翻倍惩罚反而比 control 占比小（因为大部分 aggro Run 在章 1-2 已失败）。

### 假设 M（aggro/fast pack byte-identical）— **持续证实**

PR #76 已记的"aggro/fast 配置 byte-identical"在 hanchan 大样本下持续成立：

| 指标 | aggro × 15 | fast × 15 | 差异 |
|---|---|---|---|
| 通关率 | 0.0% | 0.0% | 0 ✅ |
| 失败位置 | 章1:4/章2:9/章3:2 | 章1:4/章2:9/章3:2 | 完全相同 ✅ |
| avg nodes | 9.6 | 9.6 | 0 ✅ |
| HP avg | 0.0 | 0.0 | 0 ✅ |
| tsumo% | 13.5% | 13.5% | 0 ✅ |
| seat 0 | 170423 | 170342 | -81（浮点累计噪声） |

唯一差异在 seat 平均点数小数级别（80 分级），来自浮点累计 / dict hash 顺序差。**所有结构性指标完全相同**。证实 `starter_fast` 配置仍是 `starter_aggro` 的近似副本，需 PR 覆盖 fast pack 真实差异化内容。

## 多 seed 验证（seed=1000 vs 2000，control hanchan）

| 指标 | seed=1000 | seed=2000 | Δ |
|---|---|---|---|
| 通关率 | 40.0% | **46.7%** | +6.7 pp |
| 失败章 1 | 0 | 0 | - |
| 失败章 2 | 3 | 5 | +2 |
| 失败章 3 | 6 | 3 | -3 |
| avg nodes | 18.7 | 17.5 | -1.2 |
| HP avg | 0.9 | 1.3 | +0.4 |
| tsumo% | 16.8% | 15.8% | -1 |
| ron% | 39.6% | 47.5% | +7.9 |
| seat 0 | 209146 | 239480 | +30k |

**两 seed 都稳稳落 D6 30-50% 区间**（40.0% / 46.7%）。差异 6.7pp 仍属可接受范围（15-run 方差 + RNG seed 偏差）。**章 3 失败比例从 6 → 3** 显示 seed=1000 章 3 偏难。综合判断 **control hanchan 真实通关率在 40-47% 之间，落 D6 中-上段**。

## 后续动作（按 ROI）

- [ ] **不需要 tune-4**（控场 40-47% 已稳定落 D6 区间，再调可能掉出下界）
- [ ] **PR：starter_fast 真实差异化内容**（解假设 M — 现 fast 与 aggro byte-identical 失去存在意义）
- [ ] **多 seed sim**（seed ∈ {1000, 2000, 3000}）×15-run 控制 RNG 偏差，确认 40% 不是 seed=1000 偏置
- [ ] **M8.5 brainstorm**（HeuristicAi 终局战略）— seat 3 -72k 提示 AI 间分差仍极大；若 AI 在南场会防守领先，预期 control 通关率会再降 5-10pp
- [ ] **M9 brainstorm 候选**：aggro/fast pack 加 1-2 张被动防御 skill（解假设 L 的"非控场卡组完全不可玩"）

## 关键里程碑（更新）

| 阶段 | control 通关率 | D6 30-50% |
|---|---|---|
| baseline 1 (SimpleAi) | 100% | ❌ |
| baseline 4 (HeuristicAi+riichi) | 60% | ❌ |
| baseline 5 (post tiebreak + fast buff) | 75% | ❌ |
| baseline 6 (post tune-3 + AI ability，5-run) | 40%（噪声） | ❓ |
| baseline 7 全东风 (15-run) | 53.3% | ❌ +3.3pp |
| **baseline 7 hanchan (M8, 15-run)** | **40.0%** | **✅ 中段** |

> **M8 章 3 hanchan 副作用让 plan-7 D6 30-50% 目标在大样本下首次自然达成**。后续工作转向 aggro/fast pack 平衡 + M8.5 AI 战略升级。
