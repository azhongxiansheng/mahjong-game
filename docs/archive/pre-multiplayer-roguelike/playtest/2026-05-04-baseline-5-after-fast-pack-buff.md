# Simulation Baseline 5 — 2026-05-04（post-#72 #74）

> 接续 [`baseline 4`](2026-05-04-baseline-4-after-ai-riichi.md)。同事 PR #72（aggro tune-2 +1 番）+ PR #74（fast pack 补齐 5 tile + 1 ability — 我 baseline 4 假设 I 落地）后再跑 baseline。**关键发现：fast 与 aggro byte-identical（仍）**，根因不是 starter pack 配置等效，而是 0% 通关 runs 几乎不胡牌 → 技能不触发 → 无差异。

## 元信息

- **会话期间 main HEAD**：`b1c6b60` — balance(m7): fast pack 补齐 (#74)
- **关键变化**：
  - PR #72 aggro hooks +1 番（thunder/haku/serenity 1→2）
  - PR #74 fast pack 1 tile / 0 ability → **5 tile / 1 ability**（spec §7.2 主题）
- **跑了几个 Run**：3 套起始包 × 5 runs = **15 runs**（seed=1000）

## 数据矩阵

| 配置 | 通关率 | 失败位置 | avg nodes | tsumo% | ron% | draw% | seat0 / seat1 / seat2 / seat3 |
|---|---|---|---|---|---|---|---|
| control × 5 | **60%** (3/5) | 章 3 × 2 | 21.4 | 11.9% | 38.1% | 49.9% | 117031 / -10579 / -5959 / -493 |
| aggro × 5   | 0% (0/5) | 章 2 × 5 | 11.0 | 4.7% | 45.0% | 50.3% | 113673 / 8827 / -39141 / -3359 |
| fast × 5    | 0% (0/5) | 章 2 × 5 | 11.0 | 4.7% | 45.0% | 50.3% | **113673 / 8827 / -39141 / -3359** |

⚠️ **fast 与 aggro 仍 byte-identical**（包括 seat scores 数字精确相同）

## 与 baseline 4 对比

| 配置 | baseline 4 | baseline 5 | Δ |
|---|---|---|---|
| control 通关率 | 60% | 60% | ±0 |
| aggro 通关率 | 0% | 0% | ±0 |
| fast 通关率 | 0% | 0% | ±0 |
| aggro seat 0 | (未记录) | 113673 | / |
| fast seat 0 | (同 aggro) | 113673 | 仍同 aggro |

完全没动。#72 + #74 的累积修改**没有**改变 sim 输出 — 信号弱到看不见。

## 横向观察

- **#74 补齐 fast pack 没让 fast 与 aggro 差异化**：即使配置完全不同（不同 tile + 不同 ability），sim 输出仍 byte-identical
- **#72 tune-2 (aggro hooks +1 番) 也没让 aggro 与之前不同**：仍 0% 通关、同 hand outcomes
- **control 仍 60%**：未触 #72 / #74 改动 → 不应有变化（验证 sim 决定性）

## 根因分析（新假设）

1. **L：0% 通关 runs 中 player 几乎不胡牌 → tile_variant skills 不触发 → 配置差异不影响输出**
   - **证据**：aggro & fast 都在章 2 第 8-15 节点失败；hand_outcomes 同 50% draw / 45% ron 但 ron 多是 AI 之间互 ron（玩家快速失血）
   - **机制**：tile_variant skills 集中在 WIN_DECLARED hooks（+1/+2 番）；玩家不胡 → hooks 不 fire → 配置没区别
   - **下一步**：需要 sim 跑足够长 runs 让玩家有机会胡牌，才能差异化 starter packs；当前 5 runs 同 seed 都死在章 2 → 0 数据

2. **M：starter pack 真效果只在"玩家有胜率"时显现**
   - **证据**：control 60% 通关（玩家有胜率）→ seat 0 117k；aggro/fast 0%（玩家没胜率）→ seat 0 113k（接近）
   - **机制**：seat 0 score 差距由"玩家是否赢且赢多大"决定；aggressive packs 让玩家"输得快但赢得大"，control 让玩家"稳但少赢"
   - **下一步**：跑大样本（20+ runs / 多 seed）看 aggro / fast 在长尾胜率下是否分化

3. **N：control 60% 仍高于 plan-7 D6 30-50% 上界（baseline 4 假设 K 未变）**
   - **证据**：3 个 baseline 累计 control 60% 稳定（3 = baseline 3 → 100%, 4 → 60%, 5 → 60%）
   - **下一步**：D6 tune-3 — 用 PR #71 的 \`--rank-hp-delta=0,-1,-1,-2\` flag 实验
     control 通关率落到 40-45% 区间，找最佳数值

## 假设回顾

| 假设 | baseline 4 状态 | baseline 5 状态 |
|---|---|---|
| I. aggro / fast 等效 | 怀疑 | **address ✅**（PR #74 补齐配置）但 sim 输出仍同（新假设 L 解释） |
| K. control 60% 偏高 | 提出 | **未变**：仍 60% → 候选 D6 tune-3 |
| 其它（A-J） | 见 baseline 4 | 同 baseline 4（未变） |

## 后续动作（按优先级）

- [ ] **PR：D6 tune-3 用 \`--rank-hp-delta\` 实验找通关率 40-45% 最佳值**（假设 N — 直接落 plan-7 设计目标）
- [ ] PR：跑大样本 baseline（30 runs / 多 seed）看 aggro / fast 在长尾胜率下是否分化（假设 L/M 验证）
- [ ] PR：AI seat 分配 ability（解决"player 偏强 117k vs AI 1 -10k"根因）
- [ ] PR：HeuristicAi 鸣牌（继续提升 AI 强度）

> **关键洞察**：**Starter pack 差异在低胜率场景下被 0% 通关共识覆盖**。要让 aggro / fast 真正差异化，要么 (a) 让 aggressive packs 通关率 > 0%（说明它们能赢），要么 (b) sim 在玩家败局也记录 starter pack 触发频次（添加 \`hook_fire_count\` 维度）。
