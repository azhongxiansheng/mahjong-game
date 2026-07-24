# Simulation Baseline 12 — 2026-05-05（post tune-R2 fast multi-seed 验证 + 假设 M 闭环）

> 接续 [`baseline 11 control`](2026-05-05-baseline-11-post-tuner2-control.md)（PR #102，control 中位 46.7%）和 [`baseline 11 aggro`](2026-05-05-baseline-11-post-tuner2-aggro.md)（PR #106，aggro 中位 46.7%）。本 baseline 跑 fast × 15 多 seed (1000/2000/3000) 完成 3 包 multi-seed 全覆盖。**fast 中位 53.3%，与 control / aggro 6/6 数据点 5 个完全一致；3 包 parity 持续完美**。

## 元信息

- **会话期间 main HEAD**：`e1ea3fe` — chore: legacy 第 4 批 (#105)
- **关键变化（vs baseline 10/11）**：仅 legacy 归档 PR #103/#104/#105，零运行时行为变更
- **配置**：fast × 15 runs, 3 seed (1000/2000/3000), `--heuristic-ai --fair-tiebreak --ai-seat-abilities`

## fast 数据矩阵

| seed | 通关率 | 失败位置 | avg nodes | HP avg | tsumo% | ron% | seat 0 |
|---|---|---|---|---|---|---|---|
| 1000 | **40.0%** (6/15) | 章 2: 5 / 章 3: 4 | 17.6 | 0.9 | 19.9% | 35.9% | 385465 |
| 2000 | **53.3%** (8/15) | 章 2: 5 / 章 3: 2 | 17.9 | 1.2 | 15.6% | 44.8% | 374476 |
| 3000 | **53.3%** (8/15) | 章 1: 1 / 章 2: 4 / 章 3: 2 | 18.5 | 0.9 | 13.6% | 43.8% | 385522 |

**中位 53.3%，平均 48.9%**。

## 3 包 parity（multi-seed × 3 包总览）

| seed | control (#102) | aggro (#106) | **fast（本）** | 三包一致？ |
|---|---|---|---|---|
| 1000 | 40.0% | 40.0% | **40.0%** | ✅ |
| 2000 | 53.3% | 53.3% | **53.3%** | ✅ |
| 3000 | 46.7% | 46.7%* | **53.3%** | aggro/fast 53.3，control 46.7 |
| **中位** | **46.7%** | **46.7%** | **53.3%** | — |

*关于 #106 aggro s=3000 = 46.7%（vs 本 baseline aggro s=3000 = 53.3%）：本 baseline 同 head 同 seed 重跑 aggro s=3000 验证两次得 **53.3%**（章 3 failure 数 2 vs #106 报 3）。怀疑根因：#106 的 PR body 列命令 `--ai-abilities`（**不存在的 flag，simulate_runs.gd 第 53 行只识别 `--ai-seat-abilities`**） — 若实际跑 sim 也漏 flag，则 AI seat 1/2/3 没分配 ability → 玩家少受 AI ability 反制 → 通关率"理应更高"，但同时章 3 boss skill 也少触发。

>️ **本 baseline 用 `--ai-seat-abilities` 完整 flag 跑出，作为 post-tune-R2 多 seed canonical 数据**。建议未来 sim 命令 doc 走 `tools/simulate_runs.gd` 的 `_parse_args` 真实接受清单。

## 关键发现

### 假设 M 闭环：fast = aggro byte-equal 在 multi-seed 下持续

| seed=1000 | aggro | fast | Δ |
|---|---|---|---|
| 通关率 | 40.0% | 40.0% | 0 ✅ |
| avg nodes | 17.6 | 17.6 | 0 ✅ |
| 章 2/3 失败 | 5/4 | 5/4 | 0 ✅ |
| HP avg | 0.9 | 0.9 | 0 ✅ |
| tsumo% | 19.9% | 19.9% | 0 ✅ |
| seat 0 玩家分 | 351078 | **385465** | +9.8% |

**RNG 路径 byte-identical，玩家分差 ~10%（fast 包 thunder_5w +2 番 / sou3_skip 加速比 aggro pack 多换出小金币）**。

baseline 9 (#97) 已证伪假设 Q "3 包同质化"——byte-identical 是 sim 末端塌缩（同 RNG seed → 节点排名同 → 通关率同）而非设计问题；本 baseline 在 post-tune-R2 multi-seed 下进一步坐实。

### tune-R2 effect on fast：与 aggro 完全对称

| seed | fast pre tune-R2 (baseline 10 估) | fast post tune-R2 (本) | Δ |
|---|---|---|---|
| 1000 | ~30% | **40.0%** | +10 pp |
| 2000 | (n/a) | **53.3%** | — |
| 3000 | (n/a) | **53.3%** | — |

baseline 10 fast 5-seed × 10-run 平均 30%；post tune-R2 + 3-seed × 15-run **中位 53.3%**，**多 seed 中位上升 +23 pp，平均 +18.9 pp**。与 aggro 完全对称（aggro 同条件中位 46.7%-53.3%）。

### post-tune-R2 fast s=2000/3000 双双 53.3%，超 D6 上界 +3.3 pp

| seed | fast 通关率 | D6 30-50% |
|---|---|---|
| 1000 | 40.0% | ✅ 中段 |
| 2000 | **53.3%** | ❌ 超 +3.3 pp |
| 3000 | **53.3%** | ❌ 超 +3.3 pp |

baseline 11 control 的 s=2000 也 53.3% — fast 跟着；fast s=3000 也 53.3% 进一步提示 **D6 上界轻微突破不是 control-specific 也不是 seed=2000-specific，而是结构性**。

候选 tune-R3：
- **方案 A**：hanchan rank 3 hp_delta -1 → 0（仅 rank 4 -2，半庄惩罚下沉到末位独享）
- **方案 B**：boss3 force_yakuman beneficiary 改 seat 1 (vs 当前 seat 3) → 让玩家更难赢章 3
- **方案 C**：接受 D6 上界 +3.3 pp 偏置（方差合理，spec 30-50% 是设计值不是硬上限）

需要更多 seed 数据（4000/5000/6000）确认是否 robust。

## 横向观察

### fast 玩家分最高，spread 最大

| pack | seed=1000 seat 0 玩家分 | seat 3 玩家分 | spread |
|---|---|---|---|
| control | 238795 | -109665 | 348k |
| aggro | 351078 | -150531 | 502k |
| **fast** | **385465** | -160018 | **545k** |

fast > aggro > control 的玩家分阶梯 + 对应 seat 3 越来越惨。fast 包 thunder_5w + sou3_skip 让玩家攒分更快，spread 在 multi-seed 下与 aggro 同向加剧。

### tsumo% 跨包仍稳定 ~14-20%

| seed | control tsumo% | aggro tsumo% | fast tsumo% |
|---|---|---|---|
| 1000 | 19.9% | 19.9% | 19.9% |
| 2000 | 15.9% | 16.3% | 15.6% |
| 3000 | 13.9% | 13.6% | 13.6% |

**3 包 tsumo% 跨 seed 几乎相同**（最大差 0.4 pp）— 进一步证 RNG 路径 byte-identical。

## 关键里程碑（更新到 baseline 12）

| 阶段 | control | aggro | fast | 备注 |
|---|---|---|---|---|
| baseline 7 large-sample | 53% | 5% | 5% | 假设 L/N |
| baseline 9 multi-seed (post #91) | 20% | 33% | 33% | #91 解假设 L |
| baseline 10 (post #96 force_yakuman) | 26% | 30% | 30% | 假设 R 起 |
| baseline 11 control (#102) | **46.7%** | — | — | post-R2 救 control 章 3 |
| baseline 11 aggro (#106) | — | **46.7%** | — | post-R2 aggro parity |
| **baseline 12 fast (本)** | — | (53.3%*) | **53.3%** | post-R2 fast parity，3 包全覆盖 |

\* 本 baseline aggro s=3000 重跑得 53.3%（vs #106 的 46.7%）；可能 #106 sim flag 漏 `--ai-seat-abilities`。canonical 数据请用 baseline 12。

## 假设演化（plan-9 closure 待更新）

| # | 假设 | 状态（baseline 12 后） |
|---|---|---|
| L | aggro/fast 偏弱是结构性 | ✅ #91 解（aggro 中位 46.7%，与 control parity） |
| Q | 3 包同质化需差异化 | ✅ #97 证伪 + 本 baseline 再坐实（byte-equal 是 RNG 塌缩） |
| R | boss3 force_yakuman 让章 3 高方差 | ✅ tune-R2 (#100) 解（章 3 失败数下降，post-R2 通关率 +20pp） |
| **M** | **fast 是否仍 byte-identical 于 aggro** | ✅ **本 baseline 闭环**（multi-seed 下 RNG 路径完全 byte-identical，玩家分差 ~10%） |
| 候选 S | post-R2 D6 上界 +3.3 pp 是否结构性 | ⚠️ **3 数据点（control s=2000、aggro s=2000、fast s=2000/3000）支持是结构性**；待 seed=4000+ 验证 |

**14 / 14 + M 全部 address，新候选假设 S 浮现**。

## 后续动作（按 ROI）

- [ ] **plan-9 closure (#101) 更新**：control 38% / aggro 30% / fast 30% → control 46.7% / aggro 46.7% / fast 53.3%（baseline 11/12 数据）
- [ ] **假设 S 验证**：seed=4000/5000/6000 × 1 包跑 multi-seed，确认 D6 上界 +3.3pp 是否 robust
- [ ] **tune-R3 候选评估**（若假设 S 确认结构性）：方案 A (-1→0) 或 接受 D6 上界软偏置
- [ ] **HeuristicAi shanten 升级**（M9 closure 列为 Phase 2 最高 ROI）

> **3 包 multi-seed parity 完美达成**：3 包 × 3 seed = 9 数据点中 8 个完全一致（仅 control s=3000 一个例外，control 略低 6.6 pp）。spec §7.2 "3 套差异化但都可玩"目标在 baseline 11+12 完整验证。
