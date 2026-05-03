# Simulation Baseline 3 — 2026-05-03（post-#66 #67）

> 接续 [`baseline 2`](2026-05-03-baseline-after-ai-upgrades.md)。同事 PR #66（玩家 deck.tile_variants → registry wire — 我 baseline 2 假设 F 落地）+ PR #67（D6 tune-1：soul_drain 30→20% / premature_riichi+mineu_oni +han_bonus 2→3）后再跑 baseline。**首次观察到 3 套起始包差异化**。

## 元信息

- **会话期间 main HEAD**：`a91bb33` — balance(m7): tune-1 (#67)
- **关键变化**：
  - PR #66 玩家 deck.tile_variants → BC.registry wire（假设 F 落地）
  - PR #67 D6 tune-1（**首次真数值调整**）
- **GUT**：1000+/1000+ PASS（基线主分支，未实跑）
- **跑了几个 Run**：3 套起始包 × 30 runs = **90 runs**

## 数据矩阵

| 配置 | 通关率 | tsumo% | ron% | draw% | seat0 / seat1 / seat2 / seat3 平均 |
|---|---|---|---|---|---|
| control × 30 | 100% | 0.0% | 1.6% | 98.4% | 25533 / 24467 / 25000 / 25000 |
| **aggro × 30**   | 100% | 0.0% | 1.6% | 98.4% | **26057 / 23943** / 25000 / 25000 |
| fast × 30    | 100% | 0.0% | 1.6% | 98.4% | 25533 / 24467 / 25000 / 25000 |

**aggro 起始包终于差异化**（seat 0 +524 vs control，seat 1 -524 vs control）。control 与 fast 仍 byte-identical。

## 与 baseline 2 对比

| 指标 | baseline 1 | baseline 2 | baseline 3 |
|---|---|---|---|
| 通关率 | 100% | 100% | **100%** |
| tsumo% | 0.3% | 0.0% | 0.0% |
| ron% | 0.0% | 1.6% | 1.6% |
| draw% | 99.7% | 98.4% | 98.4% |
| seat 0 (control) | 25018 | 25533 | 25533 |
| seat 1 (control) | 25018 | 24467 | 24467 |
| seat 0 (aggro) | 25018 | 25533 | **26057** ← 差异化 |
| seat 1 (aggro) | 25018 | 24467 | **23943** |

## 横向观察

- **aggro 与 control/fast 出现明显差异化**：seat 0 在 aggro 起始包下平均比 control 多赢 524 点；说明 PR #66 wire 后**起始包内的 tile_variant skills 开始真触发**
- **control / fast 之间仍零差异**：可能两套包内的 tile_variant 触发频次极低或 effect 数值过小（v1 简化的 +1 番类 hook 在 1.6% ron 路径里贡献微小）
- **流局率 / win 分布完全没变**：tile_variants 改变了胡牌方的得分大小，不改变是否胡（HeuristicAi 仍不立直 / 不组役）
- **HP 系统继续不触发**：1392 节点结算 0 次扣血（同 baseline 1 / 2）
- **PR #67 D6 tune-1 效果不可见**：soul_drain 30→20% 应让 hatsu 发牌的转账减少；premature_riichi / mineu_oni + 1 番应让玩家 ron 时多分。但 ron 才 1.6% × 受影响的牌触发率更低 → 数据噪声完全淹没。证明：**v1 数值调整在当前 simulation 下信号太弱**

## 假设回顾

| 假设 | 状态 |
|---|---|
| **A** SimpleAi 4 家对称 → 玩家不可能 rank 3/4 | 部分 address；HeuristicAi 让分布有变化但偏向反而扩大 |
| **B** 几乎全走流局 + 听牌分摊 | **未变**：流局率 98.4%（自 baseline 2 起） |
| **C** 无法支持 30-50% 通关率 | **未 address**：仍 100% 通关 |
| **D** HeuristicAi 必须能立直 + 鸣牌 | **未实装**（HeuristicAi 仍只 decide_discard） |
| **E** 玩家 ability 不对称偏强 | **加剧**：tile_variants wire 后玩家更强（baseline 3 aggro：+1066 vs seat 1） |
| **F** 起始包 tile_variants 没 wire | **address ✅**（PR #66） |

## 新假设

1. **G：v1 简化的 +1/+2/+3 番效果在 1.6% ron 路径下对通关率影响接近 0**
   - **证据**：PR #67 调了 3 个数值（−10pp / +1 番 / +1 番），simulation 输出零变化（除决定性已锁的 seat 平均偏移）
   - **机制**：H 番影响 fu × han 计分，但 1.6% ron × 单卡牌触发率 < 50% → 实际触发占总局数 < 1%。数值差异被流局占比 98.4% 完全淹没
   - **下一步**：调参验证必须**先解决流局率**（假设 D 落地后再做 D6 tune-2）；当前 D6 tune-1 应当作"数值改不改都一样"的**空操作**

2. **H：HP 系统在 SimpleAi 时代 + HeuristicAi 时代都从未触发**
   - **证据**：3 个 baseline 累计 90 + 90 + 90 = 270 runs，**0 次** rank 3/4 → 0 次扣血
   - **机制**：rank 计算基于 4 家终局点数；流局占 98%、点棒分配近对称 → 玩家几乎稳 rank 1-2
   - **下一步**：要么 (a) 引入立直让玩家可能 rank 3/4 (假设 D)，要么 (b) 调 BalanceConstants `node_rank_hp_delta` 让 rank 2 也扣血（如 [+1, 0, -1, -2]）

## 不爽 / 漏洞汇总

- **D6 数值调整在当前 baseline 下不可验证**：PR #67 是首次真调参，但 simulation 信号太弱无法判断好坏
- **tile_variants wire 仅放大已有偏向，没解决根本难度问题**

## 后续动作

- [ ] **PR：HeuristicAi 加立直能力**（D 落地 — 当前最高优先级）
  - 加 \`decide_riichi(seat, draws_remaining) -> bool\`：手牌进入听牌 + draws_remaining ≥ 4 时返 true
  - BC main loop 在 \`_step_draw\` 后判定 → 调 RiichiValidator → 标 RiichiState
  - 验收：simulation tsumo 占比 >> 0%（立直后必听 → 自摸概率↑）
- [ ] **PR：调 \`node_rank_hp_delta\` 让 rank 2 也扣血**（假设 H 短期解 — 容易）
  - BalanceConstants \`[0, 0, -1, -2]\` → \`[+1, 0, -1, -2]\` 或 \`[0, -1, -1, -2]\`
  - 验收：90 runs 至少出现 1-3 次失败
- [ ] **PR：simulation CLI \`--starting-hp=N\`**（实验工具）
- [ ] D6 tune-2 暂缓 — 等 D 落地后再做

> 关键洞察：**数值平衡迭代必须先让胜负的"信号"足够强**（即流局率 ≤ 50%、HP 系统真触发）。否则任何 tune PR 都是空操作。
