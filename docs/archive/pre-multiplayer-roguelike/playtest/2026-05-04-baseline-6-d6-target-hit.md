# Simulation Baseline 6 — 2026-05-04（M7 D6 目标达标里程碑）

> 接续 [`baseline 5`](2026-05-04-baseline-5-after-tiebreak-and-fast-buff.md)。同事 + 我累积 PR #75 / #78 / #80 / #82 后再跑 baseline。**首次确认 plan-7 D6 设计目标 30-50% 通关率达标**（control with full feature flags：45%）。

## 元信息

- **会话期间 main HEAD**：`b964ad0` — feat(m7/sim): AI seat abilities (#82)
- **关键变化（vs baseline 5）**：
  - PR #75 rank_for_seat tiebreak_seed → **`--fair-tiebreak` flag**
  - PR #78 SimulationHarness 默认接 fair tiebreak
  - PR #80 tune-3：soul_drain 20→12% + starting_hp 5→4
  - PR #82 AI seat 1/2/3 也分配随机 ability → **`--ai-seat-abilities` flag**
- **CLI**：`--heuristic-ai --fair-tiebreak --ai-seat-abilities`（baseline-6 推荐组合）
- **跑了几个 Run**：3 套起始包 × 20 runs = **60 runs**

## 数据矩阵（heuristic-ai + fair-tiebreak + ai-seat-abilities）

| 配置 | 通关率 | HP avg | tsumo% | ron% | draw% | seat0 / seat1 / seat2 / seat3 |
|---|---|---|---|---|---|---|
| **control × 20** | **45%** ✅ | 0.9 / 4 | 12.0% | 42.5% | 45.5% | 81801 / 43222 / -20646 / -4377 |
| aggro × 20   | 0% | 0.0 | (similar) | (similar) | (similar) | 39109 / ? / ? / ? |
| fast × 20    | 0% | 0.0 | (similar) | (similar) | (similar) | 38966 / ? / ? / ? |

## 与 baseline 5 对比

| 指标 (control) | baseline 5 | baseline 6 | Δ |
|---|---|---|---|
| 通关率 | 75% | **45%** | **−30 pp** ✅ |
| HP avg | 2.5 | 0.9 | −1.6 |
| seat 1 平均 | 27097 | **43222** | **+16125** ✅ asymmetry shrink |
| seat 0 平均 | 90354 | 81801 | −8553 |

## 关键里程碑

✅ **plan-7 D6 设计目标 30-50% 通关率达标**（control 45%）
✅ **baseline-5 假设 J/M 落地**：seat 1 平均分 27k → 43k（不对称大幅缩小）
✅ **baseline-1/2/3 假设 H 落地**：HP 系统真触发（control HP 5→0.9）
✅ **plan-7 D5 alpha 反馈循环替代**：6 份 baseline 文档构成完整数据反馈轨迹

## 横向观察

- **control / aggro / fast 仍非常分化**（45% / 0% / 0%）
- **aggro / fast 0%**：进攻型 pack 在 4 家 ability 对称下完全没招架；玩家 score 39k vs control 81k 说明 control 的 soul_drain 被动收益是关键
- **章 2 仍是 aggro/fast 的"墙"**：进攻 pack 资源不足撑到章 3 boss
- **大 spread**：seat 0 81k vs seat 2 -20k；说明对手中也有运气不均（某 AI seat 拿到了 OP ability）

## 假设回顾

| 假设 | baseline 5 | baseline 6 | 说明 |
|---|---|---|---|
| A. SimpleAi 4 家对称 → 玩家不可能 rank 3/4 | 部分 | **address ✅** | tiebreak + AI abilities |
| B. 几乎全走流局 | address | address | draw 50→45% |
| C. 无法支持 30-50% | 偏高 | **address ✅** | 45% 落入区间 |
| D. HeuristicAi 必须能立直 | address | address | (PR #70) |
| E. 玩家 ability 不对称 | 加剧 | **address ✅** | (PR #82) |
| F. tile_variants 没 wire | address | address | (PR #66) |
| G. v1 +N 番效果 ≈ 0 | address | address | (PR #70) |
| H. HP 系统从未触发 | address | **address** | HP 5 → 0.9 |
| I. aggro/fast 等效 | 解除 | 解除 | (PR #74) |
| J. 玩家 ability 不对称偏强 | 加剧 | **address ✅** | (PR #82) |
| K. control 通关率偏高 | 75% | **45%** ✅ | (PR #80 tune-3) |
| L. aggro/fast 需要"防御主动收益" | 未变 | 未变 | 结构性问题，需新 skill 设计 |

baseline 1-6 累积发现的 **12 个假设中 11 个 address**。剩 L 是 game design 范畴，需要为 aggro/fast 设计"被动防御"skill（spec §13.6 留口）。

## M7 收尾状态

| plan-7 D-list | 状态 |
|---|---|
| D1 ctx 扩展批次切分 | B1/B2 ✅，B3 60%，B4 ❌ |
| D2 BalanceConstants 集中表 | ✅ |
| D3 玩家测试反馈漏斗模板 | ✅ |
| D4 SimulationHarness | ✅（含 4 个实验 flag） |
| D5 alpha 反馈循环 | ✅（6 份 baseline 文档替代） |
| D6 数值调整三步法 | ✅（tune 1-3 + fast buff + AI abilities） |

**M7 主要里程碑达成**。剩余项是单点收尾（B3/B4 ctx 完成、aggro/fast 防御 skill 设计、tougenkyo_v1 实装）。

## 不爽 / 漏洞汇总

- **aggro/fast 0%** 是结构性问题，simulation 已能稳定揭示但解需要 game design：要么加防御 skill 到 pack，要么从根本调整 pack 主题（spec §7.2 表里的预设）
- **大 score spread**（seat 2 -20k）—— 个别 AI seat 因 ability 拿不到 OP 池被持续 ron；balance 时考虑给 AI seat 也 dictionary-skill-pool

## 后续动作

- [x] **D6 目标达标**（本 baseline 文档化里程碑）
- [ ] **PR：aggro/fast pack 加 1 张防御 skill**（解假设 L）
- [ ] **PR：B3 ctx 收尾**（scale_payout / mark_pao_transfer / mark_all_pay / force_yakuman）
- [ ] **PR：tougenkyo_v1 实装**（M6 最后 1 张）
- [ ] **PR：M7 收尾文档**（plan-7 状态表更新）
