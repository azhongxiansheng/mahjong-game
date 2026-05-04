# Simulation Baseline 9 — 2026-05-04（3 包 parity 首次达成）

> 接续 [`baseline 8`](2026-05-04-baseline-8-lead-gap-threshold.md)。PR #91（aggro/fast 加被动防御 skill）后再跑 baseline。**首次确认 3 套起始包通关率落入相近区间**（20-33%），spec §7.2 "3 套差异化但都可玩" 设计意图首次实现。

## 元信息

- **会话期间 main HEAD**：`1a0257b` — balance(m8): aggro/fast pack 加被动防御 skill (#91)
- **关键变化（vs baseline 8）**：
  - PR #91：aggro pack HATSU 上 green_hatsu_serenity → soul_drain_hatsu_v1；新加 W9 iron_wall + CHUN seal_chun
  - PR #91：fast pack 加 HATSU soul_drain + W9 iron_wall + CHUN seal_chun
  - 已包含 baseline 7-8 累计的 PR #89 (M8.5 终局策略) + #90 (M9 lead_gap)
- **配置**：runs=15, seed=1000, --heuristic-ai --fair-tiebreak --ai-seat-abilities

## 数据矩阵（15-run, seed=1000）

| 配置 | 通关率 | HP avg | tsumo% | ron% | draw% | seat 0 / 1 / 2 / 3 |
|---|---|---|---|---|---|---|
| **control × 15** | **20.0%** (3/15) | 0.3 / 4 | (n/a) | (n/a) | (n/a) | 198582 / ? / ? / ? |
| aggro × 15 | **33.3%** (5/15) | 0.7 / 4 | 21.3% | 32.2% | 46.5% | 333606 / -32646 / -101954 / ? |
| fast × 15 | **33.3%** (5/15) | 0.7 / 4 | 21.3% | 32.2% | 46.5% | 364240 / -38838 / -117654 / -107748 |

## 与 baseline 7（control 53.3%, aggro/fast 5%）对比

| pack | baseline 7 | baseline 9 | Δ |
|---|---|---|---|
| control | 53.3% | **20.0%** | **−33.3 pp** |
| aggro | 5% | **33.3%** | **+28.3 pp** ✅ |
| fast | 5% | **33.3%** | **+28.3 pp** ✅ |

## 关键发现

### 假设 L 完全证伪 / 解决

baseline 1-6 累积猜想 **"aggro/fast 偏弱是结构性 game design 问题"**：当时认为需要重设计 spec §7.2 主题分布。本 baseline 证实：**只需把 control 的核心被动 skill（soul_drain）拷给 aggro/fast，3 包就能 parity**。

3 套 pack 现在落入 20-33% 相近区间 — 没有任何一包 0% 或 100%。这是 spec §7.2 "3 套差异化但都可玩" 的设计意图首次落实。

### control 反而被 nerf 到 20%

预期外的副作用：control 跌到 20%（baseline 7 是 53%）。

机制：
1. aggro/fast 现在也有 soul_drain，会**反向吸取 control 的胡分**
2. control 失去"唯一被动收益持有者"的不对称优势
3. 加上 M8.5/M9 终局策略（领先时不立直）让 AI seats 互相牵制更多

3 包 parity = 玩家相对优势削弱 — control 不再是"唯一稳赢"包。

### 假设 Q（新）：3 包同质化（皆有 soul_drain）需要差异化机制

3 包都有 soul_drain → 同质化的同时削弱了"3 套差异化"卖点。**spec §7.2** 主题（火力 / 速胡 / 控场）现在主要靠 _其它_ skill 区分；soul_drain 成了通用基底。

可能修复：
- 设计 mirror skills：`north_drain_v1` / `man_drain_v1` 等不同 TileId 的 12% 退分变种
- 或差异化分配：control 留 soul_drain；aggro/fast 用 _弱版_ 退分（5-8%）+ 各自主题强化
- 或重设计 pack 主题让"被动收益"也有差异（如：aggro = 玩家胡时给对手 -5% 上限；fast = 立直棒返还）

## 横向观察

- **AI 间 spread 极大**：fast 的 seat 2 / 3 都 ≈ -110k（被 4 家 ron 拖死）
- **player 平均分离 200k-360k**：高于 baseline 8（control 219k），3 包都靠 soul_drain 拉高分；但通关率反而被 lead_gap 阈值约束
- **HP 都接近 0**：3 包 HP avg 都在 0.3-0.7（baseline 7 control 1.3）— 玩家更接近"濒死通关"

## M7-M9 演化曲线（control / aggro / fast）

| baseline | control | aggro | fast | 备注 |
|---|---|---|---|---|
| 0（M7 起点） | 100% | 100% | 100% | 守恒 bug，无信号 |
| 1 (#62 sim 工具) | 100% | 100% | 100% | 同上 |
| 4 (#70 AI 立直) | 75% | 5% | 5% | 数值首次破墙 |
| 5 (#74 fast 补齐) | 75% | 5% | 5% | parity 假象 |
| 6 hanchan (#85) | 70% | 0% | 0% | 章 3 翻倍惩罚显现 |
| 7 large-sample | 53.3% | 5% | 5% | 真实分布 |
| 8 (#90 lead_gap) | (无大变化) | (n/a) | (n/a) | AI spread 收紧 |
| **9 (#91 防御 skill)** | **20%** | **33%** | **33%** | **3 包 parity 首次达成** |

## 后续动作

- [x] **假设 L 解决**（3 包 parity）
- [ ] **假设 Q 显现**：3 包同质化，需要差异化机制
- [ ] control nerf 到 20% 偏低 — 是否要把 soul_drain 留 control + 给 aggro/fast 弱版
- [ ] 多 seed 验证 baseline 9（仅 seed=1000，可能种子敏感）
- [ ] 后续 ctx API（B3/B4）解锁更多 hook spec 原效果
