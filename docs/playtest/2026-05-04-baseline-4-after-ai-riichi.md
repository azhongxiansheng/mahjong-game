# Simulation Baseline 4 — 2026-05-04（post-#70）

> 接续 [`baseline 3`](2026-05-03-baseline-3-after-tile-wire.md)。同事 PR #70（HeuristicAi 自动立直 + RIICHI_DECLARED emit + pool 守恒修复 — **我 baseline 2/3 假设 D 落地**）后再跑 baseline。**首次观察到通关率破 100%**（控场 60%，火力 0%，速胡 0%），**首次接近 plan-7 D6 30-50% 设计目标**。

## 元信息

- **会话期间 main HEAD**：`b5de63b` — feat(m7): HeuristicAi 自动立直 (#70)
- **关键变化**：HeuristicAi 现在能自动立直（hand 听牌时宣告）→ 形成役 → 真正胡牌
- **跑了几个 Run**：3 套起始包 × 5 runs = **15 runs**（heuristic AI 算法重，5-run 比 30-run 更快，先拿首份信号）
- **CLI**：`--heuristic-ai` flag（PR #71 sim 实验 flag 系列同期）

## 数据矩阵（heuristic-ai）

| 配置 | 通关率 | 失败位置 | avg nodes | tsumo% | ron% | draw% | seat0 / seat1 / seat2 / seat3 |
|---|---|---|---|---|---|---|---|
| **control × 5** | **60%** (3/5) | 章 3 × 2 | 21.4 | 11.9% | 38.1% | 49.9% | 117031 / -10579 / -5959 / -493 |
| aggro × 5   | **0%** (0/5)  | 章 2 × 5 | 11.0 | 4.7%  | 45.0% | 50.3% | (37 节点取样数据缺失) |
| fast × 5    | **0%** (0/5)  | 章 2 × 5 | 11.0 | 4.7%  | 45.0% | 50.3% | (同 aggro byte-identical) |

⚠️ aggro 与 fast 完全相同（包括 hand_outcomes / nodes / fail 位置）—— 怀疑两个起始包配置等效或同一份 deck，需进一步调查。

## 与 baseline 3 对比

| 指标 (control) | baseline 3 (SimpleAi) | baseline 4 (HeuristicAi+riichi) | Δ |
|---|---|---|---|
| 通关率 | 100% | **60%** | **−40 pp** ✓ |
| 失败 | 0 | 2 | +2 |
| draw% | 98.4% | **49.9%** | **−48 pp** ✓ |
| tsumo% | 0.0% | **11.9%** | **+11.9 pp** ✓ |
| ron% | 1.6% | **38.1%** | **+36.5 pp** ✓ |
| avg nodes | 23.0 | 21.4 | −1.6（部分 run 早终） |
| avg final HP | 5.0 | **1.6** | **−3.4** ✓ |

**所有 baseline 1-3 累积发现的问题至少部分 address：**
- 假设 B（流局占比过高）：99.7% → 49.9% ✅
- 假设 C（无法支持 30-50% 通关率）：100% → **60%（仍偏高但靠近上界）** ⚠️
- 假设 D（HeuristicAi 必须能立直）：✅ 实装
- 假设 H（HP 系统从未触发）：avg HP 5 → 1.6 ✅

## 横向观察

- **HeuristicAi 立直效果立竿见影**：流局率从 ~99% 跌到 ~50%；ron 从 0% 升到 38%
- **起始包差异化在 baseline 4 出现**：control 60% vs aggro/fast 0%
- **aggro/fast 似乎等效**：完全相同的数值矩阵（包括失败位置、节点数）— 起始包配置可能相同或都过于激进
- **章 3 是 boss 关**：control 失败都在章 3（玩家有合理战术 → 触 boss 才挂）；aggro/fast 在章 2 就挂（资源不够撑到 Boss）
- **seat 0 平均点数 117031 异常高**：在 4 家累计应守恒 100000 时（已验证 Δ=0），说明个别 hand 玩家胡满贯/役満 → 拉高均值；分布有长尾
- **seat 1 平均 -10579**：玩家技能针对 seat 1（boss 注入也是 seat 1）→ 双重打击

## 假设回顾

| 假设 | baseline 3 状态 | baseline 4 状态 |
|---|---|---|
| A. SimpleAi 4 家对称 | 部分 address | **进一步 address**（heuristic AI 不对称） |
| B. 几乎全走流局 | 未变 | **address ✅**（流局 → 50%） |
| C. 无法支持 30-50% | 未 address | **接近 address**（control 60%，目标上界附近） |
| D. HeuristicAi 必须能立直 | 未实装 | **address ✅**（PR #70） |
| E. 玩家 ability 不对称 | 加剧 | 仍加剧（seat 0 117k vs seat 1 -10k） |
| F. tile_variants 没 wire | address | 已 address（PR #66） |
| G. v1 简化 +N 番 effect ≈ 0 | 未变 | **address ✅**（heuristic AI ron 38% → +N 番真起效） |
| H. HP 系统从未触发 | 未变 | **address ✅**（HP 5→1.6） |

## 新假设

1. **I：起始包 aggro / fast 配置可能等效或都过激**
   - **证据**：5-run 同 seed 数据 byte-for-byte identical，包括 hand_count / fail location
   - **下一步**：grep `starter_packs.gd` 看 aggro / fast 的 \`tile_variants\` + \`abilities\` 配置；若真等效 → 需差异化

2. **J：玩家相对 AI 仍偏强（seat 0 117031 vs seat 1 -10579）**
   - **证据**：4 家 spread 极大；如果 4 家随机 IID，期望 spread < ±5000
   - **机制**：玩家有 ability + tile_variants buff，AI 没 → 一对多
   - **下一步**：给 AI seat 也分配随机 ability + tile_variant（baseline 2 假设 E 提过）

3. **K：control 60% 通关率刚到 plan-7 D6 上界**
   - **证据**：60% > 50%（设计目标范围 30-50% 上界）
   - **下一步**：D6 tune-2 候选 — 调 starting_hp 5→4 或 node_rank_hp_delta [0,0,-1,-2]→[0,-1,-1,-2]，跑 sim 验证降到 30-50% 区间

## 后续动作

- [ ] **检查 starter_packs aggro vs fast 是否真等效**（假设 I）
- [ ] **PR：跑大样本 baseline**（30 runs × 3 starters，约 30-45 分钟）证明 5-run 信号稳定
- [ ] **PR：D6 tune-2 — 调 BalanceConstants \`node_rank_hp_delta\` 让 control 通关率从 60% 落到 40%-45%**（K 假设的实际 fine-tune；现在可用 \`--rank-hp-delta\` flag 实验找最佳值）
- [ ] **PR：AI seat 分配 ability**（假设 E/J 的真根因解决）
- [ ] **PR：HeuristicAi 鸣牌（chi/pon）**（继续提升 AI 强度，让 50% 流局再降）

> **关键里程碑**：本 baseline 是首次观察到 **simulation 信号足够强可指导 D6 tune** 的状态。前 3 轮 baseline 都是"信号 ≈ 0，调参纯空操作"。
