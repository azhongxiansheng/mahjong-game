# Simulation Baseline 10 — 2026-05-05（hanchan HP 软化，3 包全部落入 D6）

> 接续 [`baseline 9`](2026-05-04-baseline-9-three-pack-parity.md)（PR #91 假设 L 解决，但 control 跌到 20%）。本 PR 软化 hanchan HP 惩罚 `[0,0,-2,-4] → [0,0,-1,-3]`，直接缓解假设 Q（hanchan rank 3-4 一发脱靶）。

## 元信息

- **会话期间 base HEAD**：M9 endgame-narrow + 3-pack-parity 合入后 main `7d949cc`
- **关键变化（vs baseline 9）**：
  - `node_rank_hp_delta_hanchan`: `[0,0,-2,-4]` → `[0,0,-1,-3]`
    - rank 3: -2 → -1（与 east_round 一致）
    - rank 4: -4 → -3（仍比 east -2 重 50%）
  - 不动 gold reward（`[60,30,10,0]` 不变）
  - 不动 east_round 配置（`[0,0,-1,-2]` 不变）
- **CLI**：`--heuristic-ai --fair-tiebreak --ai-seat-abilities`（同 baseline 9）
- **跑了几个 Run**：3 包 × 15 runs = 45 runs

## 数据矩阵（runs=15, seed=1000）

| pack | 通关率 | HP avg | 失败位置 | seat 0 (玩家) |
|---|---|---|---|---|
| **control × 15** | **33.3%** ✅ | 0.6 / 4 | 章 2: 5 / 章 3: 5 | 229831 |
| **aggro × 15** | **40.0%** ✅ | 0.9 / 4 | 章 2: 5 / 章 3: 4 | 351078 |
| **fast × 15** | **40.0%** ✅ | 0.9 / 4 | 章 2: 5 / 章 3: 4 | 385465 |

**3 包全部落入 plan-7 D6 设计目标 30-50%** ✅

## 与 baseline 9 对比

| pack | baseline 9 | **baseline 10** | Δ |
|---|---|---|---|
| control | 20.0% | **33.3%** | **+13.3 pp** ✅ |
| aggro | 33.3% | **40.0%** | +6.7 pp |
| fast | 33.3% | **40.0%** | +6.7 pp |
| 3 包平均 | 28.9% | **37.8%** | **+8.9 pp** |
| 3 包 spread | 13.3 pp | **6.7 pp** | **-6.6 pp** ✅ 更平 |

## 关键发现

### 假设 Q 解决：hanchan HP 软化让通关率重回中段
control HP avg 提升不大（0.3 → 0.6），但通关率从 20% 跃到 33%，说明软化主要救了"濒死边缘多撑 1 节点"。这正是 baseline 9 暴露的问题：hp=4 玩家在 hanchan rank 3 一次失败 -2 = hp 2，rank 4 失败 -4 = 直接归零。软化后 rank 3 -1 让玩家有"再来一次"机会。

### 3 包通关率 spread 缩小
baseline 9：control 20% / aggro 33% / fast 33%（spread 13.3 pp，control 偏低明显）
baseline 10：control 33% / aggro 40% / fast 40%（spread 6.7 pp）

3 包通关率更接近，但 aggro/fast 仍稍高于 control 6.7 pp — 提示 PR #91 给 aggro/fast 加的防御 skill (soul_drain) 略胜 control 的 native pack 配置。

### 玩家 seat 0 平均分继续放大
| pack | b9 | **b10** |
|---|---|---|
| control seat 0 | 198k | **230k** |
| aggro seat 0 | 333k | **351k** |
| fast seat 0 | 364k | **385k** |

软化让玩家"撑到章 3 底"次数变多 → 总累积分数自然上升。这不是新 asymmetry，是同一玩家活更久。

## 假设状态更新

| 假设 | b9 状态 | **b10 状态** |
|---|---|---|
| L (aggro/fast 偏弱) | 解决 (PR #91) | 解决 |
| O (AI ability 不 fire) | 证伪 | unchanged |
| P (AI 间不对称) | 大部分解 (M9 endgame) | unchanged |
| **Q (hanchan + endgame 叠加)** | **未解 (control 20%)** | **解决 ✅ (3 包 33-40%)** |

## 下一步候选

baseline 1-10 累积 12+ 假设全部 address 或定位。**M9 数值线性调优工程基本收尾**。

剩余开放议题（要做就拆下个 PR）：
1. **3 包真差异化**：当前 aggro/fast 拷 control 防御 skill 后通关率几乎重叠（40% vs 40% byte-identical）— 设计意图是"差异化但都可玩"，差异化层面缺失。需主题向重设计（aggro 真攻击 / fast 真速胡 / control 真控场）
2. **大样本验证**（30-50 runs）确认 baseline 10 稳定，非小样本噪音
3. **同事 priority**：B3/B4 ctx 升级 / 半庄玩法层真跑通

## 已知 limitation

- 15 runs 样本，标准差约 ±10pp；33% 与 40% 差距虽接近但仍在噪音内
- aggro/fast seat scores 完全 byte-identical（baseline 9 已观察）— 两包当前实际等价
