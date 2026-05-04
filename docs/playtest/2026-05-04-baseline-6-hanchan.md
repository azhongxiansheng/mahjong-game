# Simulation Baseline 6 — 2026-05-04（M8 半庄战首跑）

> 接续 [`baseline 5`](2026-05-04-baseline-5-after-tiebreak-and-fast-buff.md)。M8 落地：章 3 全节点 session_kind="hanchan"（8 局），HP/Gold 排名表翻倍 ([0,0,-2,-4] / [60,30,10,0]）。章 1-2 维持东风战（学习曲线 spec §15）。
>
> **首要观察**：章 3 hanchan 翻倍惩罚把 aggro/fast 的"5% 通关"压到 0%，control 从 75% 微跌到 70%。endgame 难度缺口对玩家"非控场"卡组致命；M9 平衡迭代候选。

## 元信息

- **会话期间 main HEAD**：`f21f358` — feat(m8/step7): CenterInfoPanel 风圈显示扩展到南场
- **关键变化**（M8 step 1-7 累积）：
  - BalanceConstants 加 `_hanchan` 后缀字段（hands_per_node 8 / hp_delta [0,0,-2,-4] / gold [60,30,10,0]）
  - GameDriver 接 total_hands + hands_per_round；半庄战 hand_index>=4 时 round_wind 切到南
  - NodeRef.session_kind 字段；ChapterConfig 章 1/2 east_round / 章 3 hanchan
  - SAVE_VERSION 1→2 + v1 migration
  - SimulationHarness 透传 NodeRef.session_kind 到 BattleNodeRunner
- **跑了几个 Run**：3 套起始包 × 10 runs = **30 runs**（hanchan 单跑约 2x 时长，10 runs 已能稳定差距）
- **配置**：seed=42 起，--heuristic-ai

## 数据矩阵（heuristic-ai）

| 配置 | 通关率 | HP avg | avg nodes | tsumo% | ron% | draw% | seat0 / seat1 / seat2 / seat3（节点终局平均点数）|
|---|---|---|---|---|---|---|---|
| **control × 10** | **70%** (7/10) | 2.0 / 5 | 22.2 | 9.6% | 48.6% | 41.8% | 219109 / 29453 / -54260 / -94302 |
| aggro × 10 | **0%** (0/10) | 0.0 | 11.2 | 2.9% | 55.1% | 42.0% | 139871 / 1826 / 8633 / -50331 |
| fast × 10 | **0%** (0/10) | 0.0 | 11.2 | 2.9% | 55.1% | 42.0% | 139779 / 1826 / 8633 / -50239 |

## 与 baseline 5 对比（control，唯一通关有效配置）

| 指标 (control) | baseline 5（全东风） | baseline 6（章 3 hanchan） | Δ |
|---|---|---|---|
| 通关率 | 75% | **70%** | **-5 pp** |
| HP avg | 2.5 | 2.0 | -0.5 |
| ron% | 42.8% | **48.6%** | +5.8 pp |
| draw% | 45.4% | **41.8%** | -3.6 pp |
| avg nodes/Run | 21.2 | 22.2 | +1 |

观察：
1. **章 3 翻倍惩罚有感但未崩** — control 从 75% → 70%，HP 终值小幅下滑。8 局给 ron 更多机会（+5.8 pp）。
2. **aggro/fast 完全无法过章 3** — baseline 5 都是 5%，baseline 6 同步降到 0%。失败 chapter 分布：4/2/4（章 1/2/3 失败数）— 章 3 失败 4 个 Run 而 baseline 5 仅 1-2 个。
3. **节点终局点数放大 ~2x** — control seat0 219109（vs baseline 5 90354）。半庄翻倍直接把 score variance 放大。

## 失败章节分布

| 起始包 | 章 1 | 章 2 | 章 3 |
|---|---|---|---|
| control | 0 | 1 | 2 |
| aggro | 4 | 2 | 4 |
| fast | 4 | 2 | 4 |

aggro/fast 章 1 就崩（4/10 Run 章 1 死）— 这部分跟 hanchan 无关（章 1-2 仍东风战），是 baseline 5 已知问题（aggro pack 配置仍 byte-identical 于 fast，PR #76 已记）。章 3 失败拉到同水平（4 个 Run）说明 hanchan 翻倍 HP 惩罚对玩家"输 1 节点"=直接 -4 HP 致命。

## 横向观察

### 假设 J（hanchan 翻倍 HP 过严苛）— **新假设**
章 3 hanchan rank 4 = -4 HP（玩家最大 5 HP 的 80%）。一节点失败几乎宣告 Run 终结。
- 候选调整：rank 4 hp_delta -4 → -3（hanchan）
- 验证方式：`--rank-hp-delta=0,0,-2,-3`（M8.5 sim 时按 session_kind 分流后再加 flag）
- 风险：单节点容错变高 → 通关率反弹太多

### 假设 K（HeuristicAi 无终局战略）— **复述**
plan.md Step 9 已识别：HeuristicAi 是单局 evaluator，半庄南场（hand 5-8）应有"防守领先 / 拼搏垫底"策略。当前观察：
- ron% 升至 48.6% 提示 AI 在 8 局里"接近听牌就立直"频率不变 → 立直棒消耗增加
- 玩家 vs AI 分差极大（seat0 219109 vs seat3 -94302）— AI 间互相喂分仍严重
拆 M8.5 处理。

### 假设 L（章 3 难度跳变过陡）
章 1-2 east_round + 章 3 hanchan 是断崖式切换。玩家从 4 局 → 8 局 + HP 翻倍惩罚同时发生。
- 候选调整：渐进 — 章 2 加 1-2 个 hanchan 节点过渡，或章 3 前半 east_round / 后半 hanchan
- 验证：M9 spec 决定（Phase 2 范围扩展讨论）

## 提取的"假设"清单（M8.5 / M9 候选）

按 plan-7 D6 三步法可验证：

1. **假设 J**：章 3 hanchan rank 4 hp_delta = -4 太严苛，应 -3
2. **假设 K**：HeuristicAi 加南场战略后 control 通关率应 +5-10 pp（见 plan Step 9 拆 M8.5）
3. **假设 L**：章 3 全 hanchan 切换太陡，应章 2 末尾过渡或章 3 前半东风
4. **假设 M**：aggro/fast pack 配置 byte-identical（baseline 5 PR #76 记），应先解开再观察 hanchan 影响

## 已知 limitation

- **HeuristicAi 单局 evaluator** — 8 局后半 AI 不会"防守领先"或"拼搏垫底"。本 baseline 数据反映的是"AI 在每一局都行为一致"的退化版半庄战。M8.5 升级后预计：
  - 玩家 vs AI 差距缩窄（AI 1 位时降低立直频率）
  - control 通关率可能 +5-10 pp（领先 AI 偷塔机会更难）
- **半庄战 simulation 仅章 3 触发** — 全 hanchan 配置（含章 1-2）需新加 sim flag `--all-hanchan`，本 baseline 暂未测

## 下一步

- M8 step 8 收尾 → 提交 PR
- M8.5 brainstorm：HeuristicAi 终局策略
- M9 brainstorm：candidate 假设 J/L 数值精调 vs 教程引导 / 联机 / 移动端
