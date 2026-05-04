# Simulation Baseline 5 — 2026-05-04（post-#74 #75）

> 接续 [`baseline 4`](2026-05-04-baseline-4-after-ai-riichi.md)。同事 PR #74（fast pack 5 张 tile + 1 ability 补齐 — 我假设 I 落地）+ PR #75（rank_for_seat tiebreak_seed — 同事 baseline 1-4 累积发现 viewer 永远 rank 1 in tie 的根因解决）后再跑。

## 元信息

- **会话期间 main HEAD**：`6771ad0` — feat(m7/balance): tiebreak_seed (#75)
- **关键变化**：
  - PR #74 fast pack 补齐（1 → 5 tiles + 1 ability）
  - PR #75 rank_for_seat tiebreak_seed（公平同分裁决）
- **baseline-5 与 baseline-4 BC 数值不同**（baseline 4 用 default tune-1，本次用 tune-2 + tune-1 累积）
- **跑了几个 Run**：3 套起始包 × 20 runs = **60 runs**

## 数据矩阵（heuristic-ai）

| 配置 | 通关率 | HP avg | avg nodes | tsumo% | ron% | draw% | seat0 / seat1 / seat2 / seat3 |
|---|---|---|---|---|---|---|---|
| **control × 20** | **75%** (15/20) | 2.5 / 5 | 21.2 | 11.8% | 42.8% | 45.4% | 90354 / 27097 / -16373 / -1078 |
| aggro × 20   | 5% (1/20) | 0.2 | 11.3 | 10.9% | 43.3% | 45.8% | 59598 / 18811 / 14599 / 6992 |
| fast × 20    | 5% (1/20) | 0.2 | 11.3 | 9.6%  | 44.1% | 46.3% | 59551 / 18811 / 14599 / 7039 |

## 与 baseline 4 对比

| 指标 (control) | baseline 4 | baseline 5 | Δ |
|---|---|---|---|
| 通关率 | 60% | **75%** | **+15 pp** |
| HP avg | 1.6 | **2.5** | +0.9 |
| draw% | 49.9% | 45.4% | -4.5 |
| ron% | 38.1% | 42.8% | +4.7 |

⚠️ 通关率反而升了。原因：tune-2 (#72) 加 aggro 增番 + fast pack buff (#74) 改变 sim seed 流；rank 分布偏向 player 略加深。

## 横向观察

### 假设 I（aggro vs fast 等效）— **解除**
fast pack 补齐后 (#74)，aggro 与 fast 仍数据接近（59598 vs 59551 玩家平均分）但**不再 byte-identical**：
- aggro tsumo% 10.9 vs fast 9.6
- aggro ron% 43.3 vs fast 44.1
- avg seats 微差

两个 pack 现在都"以玩家自胡为主要收益路径"，玩家自胡频率相近 → 数据接近但不重合。这不算等效，是同一类设计（self-win-buff）的自然趋同。

### 假设 J（玩家 ability 不对称偏强）— **加剧**
control 玩家 90354 vs seat 1 27097 / seat 2 -16373 / seat 3 -1078。spread ≈ ±50000，远超对称期望（±5000）。
**根因**：所有 4 家共用 HeuristicAi（弃牌策略相同），但只有玩家 seat 0 装备 deck 技能 + abilities → 单方面 buff。

### 假设 K（control 仍偏高）— **更明显**
75% > plan-7 D6 设计目标上界 50%。需要：
- soul_drain 20% → 10-15%（继续降）
- 或调 starting_hp 5 → 3
- 或调 node_rank_hp_delta [0, 0, -1, -2] → [0, -1, -1, -2]（rank 2 也扣血）

### 假设 H（HP 系统从未触发）— **address ✅**
HP 系统现在真触发（control HP 5→2.5；aggro/fast HP 5→0.2）。PR #75 tiebreak_seed 是关键：之前 viewer 同分总占 rank 1 → 0 hp_delta。

### aggro / fast 仍 5% 通关
- 进攻型 skills 仅在玩家自胡时 fire
- 4-way 公平 → 玩家自胡率 ≈ 25%
- 即便每次胡 +han buff 大，HP 损失累积仍超过收益（aggro/fast HP 0.2 = 几乎全部 0 hp 失败）
- 这是**结构性**问题（offensive-only pack vs offensive-defensive pack）

## 新假设

1. **L：Aggro/fast 需要"防御主动收益"才能突破 5% 上界**
   - **证据**：seat 0 score 60k > 25k 起家但 HP 0.2 → 玩家"赢分但扣血"
   - **机制**：HP 损失基于 rank（结算时 4 家点数比较），单点 score 高但其他 3 家也分得分（控场 soul_drain 让玩家持续涉对手分；aggro/fast 没有该机制）
   - **下一步**：给 aggro/fast 加 1 张 holder_trigger 防御技能（或调整 shichu 让阈值提高）

2. **M：AI 也应分配 ability 减玩家不对称强**
   - **证据**：seat 0 90k vs seat 1 27k；3 个 AI 不对称（seat 1 还有 boss inject = 较强；seat 2/3 啥都没 = 最弱）
   - **机制**：让所有 AI 装备 1 张 ability（v1 随机选），让 4 家更对称
   - **下一步**：BattleNodeRunner 加 \`ai_seat_abilities: Dictionary\` 参数

3. **N：tune-3 候选**
   - 调 soul_drain 20% → 12% （control 75% → 50% 目标）
   - 加 starting_hp 5 → 4 （让所有 pack 难度上一档）

## 后续动作（按 ROI）

- [ ] **PR：D6 tune-3** — soul_drain 20% → 12% 让 control 落到 50%（K 假设）
- [ ] **PR：AI seat 也分配随机 ability**（J/M 假设根因）
- [ ] **PR：HeuristicAi 鸣牌（chi/pon）**（让流局率从 45% 再降，激活更多 hand）
- [ ] **PR：aggro/fast 加防御 skill**（L 假设 - 让两个 pack 上 15-25% 通关）
- [ ] **大样本 sim**（runs=100 × 多 seed）减小方差

## 关键里程碑

baseline 1-4 累积揭示的 8 个假设（A-H）已有 6 个 address；剩 J（玩家不对称）+ K（control 偏高）需要 D6 tune-3 + AI 对称化解决。**M7 平衡迭代目前可见终点：3-5 个 PR 后通关率应稳定在 30-50% 区间**。
