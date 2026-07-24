# Simulation Baseline 7 — 2026-05-04（大样本稳定性验证）

> 接续 [`baseline 6`](2026-05-04-baseline-6-after-tune3-and-ai-abilities.md)。同 main HEAD（PR #80 + #82 后），把 control 从 5-run 提到 **15-run** 看稳定性 + 变量是否回归到 plan-7 D6 30-50% 设计目标。

## 元信息

- **会话期间 main HEAD**：`b964ad0` — feat(m7/sim): AI seat 也分配随机 ability (#82)
- **配置**：control × 15 runs (seed=1000, --heuristic-ai, no --ai-abilities)
- **同 baseline 6 比较**：5-run vs 15-run 同 seed 同 config

## 数据矩阵

| 配置 | 通关率 | 失败位置 | avg nodes | HP avg | tsumo% | ron% | draw% | seat 0 / 1 / 2 / 3 |
|---|---|---|---|---|---|---|---|---|
| baseline 6 control × 5 | 40% (2/5) | 章 2: 2 / 章 3: 1 | 17.6 | 1.0 | 11.4% | 38.8% | 49.7% | 106787 / -11662 / 6919 / -1944 |
| **baseline 7 control × 15** | **53.3%** (8/15) | 章 2: 3 / 章 3: 4 | **19.5** | **1.3** | 16.5% | 38.9% | 44.6% | 106037 / -26 / 2703 / -8714 |

## 关键发现

### 5-run 方差大；15-run 更接近真实分布

| 指标 | 5-run | 15-run | Δ |
|---|---|---|---|
| 通关率 | 40% | **53.3%** | **+13.3 pp**（5-run 偏低） |
| avg nodes | 17.6 | 19.5 | +1.9 |
| tsumo% | 11.4% | 16.5% | +5.1 |
| draw% | 49.7% | 44.6% | -5.1 |

**5-run 的 40% 不可靠** — 偶然 2 个失败造成数值偏低。15-run 显示真实通关率约 53%。

### 53.3% 仍略超 plan-7 D6 30-50% 上界

baseline 6 PR #83 标"control 40% 落入 D6 目标"是基于 5-run 噪声数据。**15-run 显示 control 通关率仍偏高 3.3 pp**。

### 失败分布更分散

5-run: 章 2 (2) + 章 3 (1) = 3 fails
15-run: 章 2 (3) + 章 3 (4) = 7 fails

章 3 失败在 15-run 占主导（4/7 = 57%），说明玩家在 control 起始包下能撑到 Boss 关，但 Boss 关不太能 carry 过去。这是健康的设计意图（Boss 应有一定挑战）。

### tsumo 占比 11.4% → 16.5%

更长的 sim 暴露 player + tile_variants buff 让玩家自摸更频繁。这是好事（更激动人心 / 有意义的 win condition）。

## 对 baseline 6 的修正

baseline 6 报"40% 落入 plan-7 D6 30-50% 目标"过于乐观。修正：**control 真实通关率约 53.3%**，仍**略超**目标 3.3 pp。tune-3 (PR #80) 让 control 从 75% 降到 53%，幅度 -22 pp 进入区间附近，是显著进步，但精确落在 30-50% 区间需要再降 ~5 pp。

## 后续动作（按 ROI）

- [ ] **PR：D6 tune-4**：进一步小幅 nerf
  - 候选 1：soul_drain 12% → 8%（继续减玩家分流）
  - 候选 2：starting_hp 4 → 3（更紧的 hp）
  - 候选 3：thunder_5w 番 2→1（弱化玩家"信号牌"）
  - 用 `--rank-hp-delta` flag 各跑 15-run 选最佳
- [ ] **PR：跑 aggro/fast 的 15-run baseline** 验证 0% 失败稳定性
- [ ] **多 seed sim**（seed ∈ {1000, 2000, 3000}）×15-run 控制 RNG 偏差

## 关键里程碑（更新）

| 阶段 | control 通关率 |
|---|---|
| baseline 1 (SimpleAi) | 100% |
| baseline 4 (HeuristicAi+riichi) | 60% |
| baseline 5 (post tiebreak + fast buff) | 75% |
| baseline 6 (post tune-3 + AI ability，5-run) | 40%（噪声） |
| **baseline 7 (post tune-3，15-run)** | **53.3%**（信号） |

> **plan-7 D6 30-50% 目标接近达成**（53.3% 略超 3.3 pp）；tune-4 可微调让 control 完全落区间内。
