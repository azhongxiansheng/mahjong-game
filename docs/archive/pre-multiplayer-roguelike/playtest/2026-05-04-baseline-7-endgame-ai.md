# Simulation Baseline 7 — 2026-05-04（M8.5 endgame AI 首跑）

> 接续 [`baseline 6`](2026-05-04-baseline-6-d6-target-hit.md)（同事 PR #84）+ M8 半庄战合入（PR #85）。M8.5 引入 HeuristicAi 终局策略：endgame（剩 ≤ 2 局）+ 自家排名第 1 → 跳过立直。本 baseline 用 PR #85 合入后的 main + M8.5 endgame 策略首跑。
>
> **首要观察**：control 通关率 45% → 30%。endgame 策略对玩家（通常领先）影响最大；hanchan章 3 翻倍惩罚叠加，玩家更难维持 HP。

## 元信息

- **会话期间 main HEAD**：`40103e5` — feat(m8.5): HeuristicAi 终局策略
- **关键变化（vs baseline 6）**：
  - PR #85 (M8) — 章 3 全 hanchan（8 局节点，HP/Gold 翻倍）
  - M8.5 — HeuristicAi `set_strategic_context` + endgame 跳过立直
- **CLI**：`--heuristic-ai --fair-tiebreak --ai-seat-abilities`（baseline 6 同款 + M8 + M8.5 累积）
- **跑了几个 Run**：3 套起始包 × 10 runs = **30 runs**

## 数据矩阵

| 配置 | 通关率 | HP avg | avg nodes | tsumo% | ron% | draw% | seat0 / seat1 / seat2 / seat3 |
|---|---|---|---|---|---|---|---|
| **control × 10** | **30%** | 0.7 / 4 | 16.8 | 10.4% | 44.3% | 45.3% | 142558 / 111071 / -41723 / -111906 |
| aggro × 10 | 0% | 0.0 | 8.4 | 9.1% | 48.6% | 42.3% | 89895 / 88888 / -17392 / -61391 |
| fast × 10 | 0% | 0.0 | (相同模式) | 8.7% | 45.6% | 45.6% | 88171 / 80471 / -17535 / -51107 |

## 与 baseline 6 对比

| 指标 (control) | baseline 6 | baseline 7 | Δ |
|---|---|---|---|
| 通关率 | 45% | **30%** | **−15 pp** |
| HP avg | 0.9 | 0.7 | −0.2 |
| avg nodes | (n/a) | 16.8 | — |
| seat 1 平均 | 43222 | **111071** | **+67849** ⚠️ |
| seat 0 平均 | 81801 | 142558 | +60757 |

⚠️ **AI 不对称反弹严重** — seat 1 vs seat 2/3 spread 大幅扩大（43k → 111k；-21k → -42k）。原因分析：endgame 策略让所有 HeuristicAi 实例（包括 AI seats）在领先时都不立直，但 seat 1 早盘领先后 endgame 不立直 → 保住领先 → 强者越强；seat 2/3 落后时仍立直 → 浪费立直棒 → 进一步落后。

## 关键发现

### 假设 O **证伪**（PR e8022f7 commit）
M8.5 启动前先做 fire-count 测试：seat 2 单场胡率 0.56 远高于 4 家均分 0.25。AI ability fire **不缺机会**。byte-identical 现象的真根因不在 fire 频次。**M9 应聚焦 ability hook 内部 ctx mutation 是否真改 state**。

### M8.5 endgame 策略生效但效应不均
端到端测试（test_heuristic_ai_endgame.gd）证 32 场对比 with_strategy 立直次数 < without_strategy 显著。但应用到完整 sim：
- ✅ 玩家立直率确实下降 → 通关率从 45% → 30%（**走出 D6 目标 30-50% 区间下沿**）
- ⚠️ AI 间不对称扩大 — 领先 AI 不立 → 强者越强；落后 AI 仍立 → 棒丢更快
- 🔍 修复方向（M9）：让落后方（rank 4）也调整策略 — 加大立直频率（"垫底拼搏"），不只是领先方收紧

### hanchan 章 3 没让 0% 起始包改善
aggro / fast 仍 0% 通关。失败章节分布：
- aggro: 章 1 = 5 / 章 2 = 4 / 章 3 = 1（章 1 就死，hanchan 之前）
- fast: 同型

这跟 baseline 6 一致 — 假设 L（aggro/fast 需要防御技能）仍未解。

## 假设回顾

| 假设 | baseline 6 | baseline 7 | 说明 |
|---|---|---|---|
| O（AI ability 不 fire） | 提出 | **证伪** | fire 频次充足（实测 56%）；真根因在 ctx mutation |
| J（AI 不对称） | 缩小（27k → 43k） | **反弹** | endgame 策略对 AI 间也不对称（领先 AI 越强） |
| L（aggro/fast 需防御） | 持续未解 | 持续未解 | 0% 通关率不变 |
| **新假设 P** | — | 提出 | endgame 策略应反向 — 落后方加大立直频率（"垫底拼搏"），不只领先方收紧 |
| **新假设 Q** | — | 提出 | hanchan章 3 + endgame 策略叠加把 control 推到下沿；要么解 P/L，要么减 hanchan 范围（章 3 半段） |

## 后续动作（按 ROI）

1. **PR：HeuristicAi 落后方策略**（解假设 P；实测 with_strategy_4th 立直频率 > default）
2. **PR：ability hook ctx mutation 实证**（解假设 O 真根因）
3. **PR：aggro/fast pack 防御技能补齐**（解假设 L）
4. **章 3 hanchan 减半**（前 4 floor east_round / 后 4 hanchan，缓解假设 Q）

## 已知 limitation

- M8.5 endgame 策略只覆盖 decide_riichi；defensive decide_discard（领先时避危险牌）未实现，留 M9
- "胡率"测试只在单 BattleController（dealer=0）观察；多 dealer 旋转 + GameDriver 跨局未跑 fire rate 测试
- baseline 7 sample 30 runs，建议 M9 复跑 60 runs 稳定数据

## 下一步

- 本 PR：M8.5 endgame strategy 落地 + 假设 O 证伪
- M9 brainstorm：候选解 P / L / hanchan 半段 / ability ctx mutation 实证
