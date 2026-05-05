# Simulation Baseline 14 — 2026-05-05（shanten AI 破 D6 上界确认）

> 接续 [`baseline 13`](2026-05-05-baseline-13-hypothesis-s.md)（假设 S 验证）。本 baseline 跑 control × seed 1000/2000/3000 × 5 runs，开 `--shanten-ai` flag（PR #117 引入）验证 shanten AI 是否结构性破 D6 30-50% 上界。**结论：是 ✅**。建议 shanten AI 保留作 building block（默认 off），不进入 sim default 路径；等真玩家 alpha 反馈再决定是否打开。

## 元信息

- **会话期间 main HEAD**：`f14d625` — feat(server/m12): LocalLoopbackServer 骨架 (#129)
- **配置**：control × 5 runs, 3 seed (1000/2000/3000), `--heuristic-ai --shanten-ai --fair-tiebreak --ai-seat-abilities`
- **3 sim 总跑时**：~33 分钟（每 run ~134s post-memo #119）

## 数据矩阵

| seed | baseline 11 (no shanten) | **baseline 14 (shanten)** | Δ | D6 上界（50%） |
|---|---|---|---|---|
| 1000 | 40.0% (6/15) | **80.0%** (4/5) | **+40.0 pp** | ❌ 超 +30 pp |
| 2000 | 53.3% (8/15) | **80.0%** (4/5) | +26.7 pp | ❌ 超 +30 pp |
| 3000 | 46.7% (7/15) | 40.0% (2/5) | -6.7 pp | ✅ |
| **mean** | **46.7%** | **66.7%** | **+20.0 pp** | ❌ **超 +16.7 pp** |

完整 5-run 数据：

| seed | 通关率 | 失败章节 | avg nodes | HP avg | tsumo% | ron% | seat 0 玩家分 |
|---|---|---|---|---|---|---|---|
| 1000 | 80% (4/5) | 章 1: 0 / 章 2: 0 / 章 3: 1 | 22.0 | 1.6 | 18.2% | 48.3% | 227663 |
| 2000 | 80% (4/5) | 章 1: 0 / 章 2: 1 / 章 3: 0 | 20.8 | 1.8 | 22.5% | 49.5% | 275592 |
| 3000 | 40% (2/5) | 章 1: 0 / 章 2: 3 / 章 3: 0 | 17.2 | 1.2 | 16.4% | 57.3% | 364917 |

## 关键发现

### shanten AI 结构性破 D6 ✅

3 seed 中 2 个（s=1000、s=2000）通关率 ≥80% — D6 上界 +30 pp 大幅突破。这与 single-run sim 信号（PR #119 描述："1 run 100% 通关 / 玩家分 454k"）一致 — shanten AI 让 4 家整体决策效率拉齐，但**玩家技能（soul_drain 12%）单边偏置仍存在**，于是变成"全员高效率 + 玩家技能加成"叠加 → 通关率结构性上升 ~20 pp。

### seed=3000 反向异常（-6.7 pp）

seed=3000 通关率反降 — 章 2 失败 3 次（是 baseline 11 章 2 失败 5/15 = 33% 的接近翻倍：3/5 = 60%）。**shanten AI 让 AI seat 也更高效率 → 章 2 boss 难度反弹**。但样本只 5，不能确定 robust。

### tsumo% / ron% 跨 seed 跳变大

| seed | tsumo% | ron% |
|---|---|---|
| 1000 | 18.2% | 48.3% |
| 2000 | 22.5% | 49.5% |
| 3000 | 16.4% | **57.3%** |

vs baseline 11 control（tsumo ~14-20%，ron ~36-44%）：shanten AI 让 ron% 升 ~10 pp（更多玩家荣胡机会被 AI 也用上）；tsumo% 大致持平。

## 决策：保留作 building block，sim default 不开

| 选项 | 评估 |
|---|---|
| A: shanten AI 默认 on | ❌ 结构性破 D6；sim 失去信号 |
| B: 保留 opt-in，sim default off | ✅ **推荐** — shanten AI 留作 future "真 player UI 等价对手"；sim 用 retention 保持 D6 平衡基线 |
| C: 卸载 shanten AI 代码 | ❌ 浪费 #115/#117/#119 工作；building block 在真玩家 alpha 时仍有用 |

**已实现状态符合 B**：`use_shanten_aware_discard` 默认 `false`；`--shanten-ai` CLI 是显式 opt-in；不影响现有 baseline 11/12/13 跑法。本 baseline 14 仅作"shanten 是否破 D6"的明确证据归档，不改任何代码。

## 与之前推断对照

PR #119 描述："single-run sim 信号示 shanten AI 太强（玩家分 +75%，估计破 D6 80%+）"

| 维度 | 推断 (#119) | baseline 14 实测 |
|---|---|---|
| 通关率峰值 | 估计 80%+ | 80% (s=1000/2000) ✅ |
| 玩家分倍率 | +75% (single run 454k) | s=1000 +20% / s=2000 +25% / s=3000 +52% |

通关率推断准确；玩家分倍率比 single run 估计低（multi-run 平均回归现实）— 但仍显著。

## shanten AI 的"真用途"

baseline 14 不是 shanten AI 的失败 — 是它的 **scope 错位**。shanten AI **建模的是"真玩家级别决策水平"**，把它放进 4 家全 AI 的 sim 让数据偏置；但放进**真玩家 vs 3 AI** 的 alpha 测试时，它精确表达"AI 对手智能水平 = 玩家可比"。

| 用例 | shanten AI 适用？ |
|---|---|
| 平衡 sim（4 家 AI） | ❌ 让 AI 也"真玩家级"破坏 baseline 信号 |
| 真玩家 alpha（1 玩家 + 3 AI） | ✅ 让 AI 对手智能匹配玩家，提供合理对抗 |
| 单测 / 对战示例 | ✅ 验证 SkillScheduler / 役判定在高质量决策下的正确性 |
| Boss 章节调难（章 3 等） | ✅ Boss 用 shanten AI 让 boss "更聪明"匹配玩家进度 |

**M9 closure 列假设 G' "AI shanten 升级让 sim 更接近真实玩家"** — baseline 14 证伪此假设的"sim"部分，但确认"真玩家"部分。building block 在 Phase 2 真玩家场景下仍有价值。

## 后续动作

- [x] 本 baseline doc 记录结构性破 D6 + 决策 B（保留 opt-in）
- [ ] M9 closure (#101 / #110) 加 footnote 记录 shanten AI 不进 sim default
- [ ] Phase 2 alpha 阶段：考虑给 boss seat 1（章 3 boss）启 shanten AI 让 boss 更聪明
- [ ] 不触发 baseline 15 / tune-R3 — sim 平衡基线已收尾（M9 假设清单 15/15 + S address；shanten 不进 default）

## 总结

baseline 14 完成 shanten AI 在 sim 路径的最终评估 — **结构性破 D6 +20pp mean**。决策保留 building block，默认 off；让 #115/#117/#119 工作以"真玩家 alpha 等价对手"形式留存。M9 平衡迭代正式收尾，sim 阶段 baseline 数据信号锁定到 baseline 11/12/13（multi-seed mean 46.7-53.3%）。

下一步主线：M12 联机骨架（已 #127 + #129 + IBattleController #121/#123）继续 p3 / p4，或转向 spec §15 教程 / 新手引导（Phase 2 主题）。
