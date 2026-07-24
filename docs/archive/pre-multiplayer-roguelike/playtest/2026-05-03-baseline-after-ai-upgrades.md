# Simulation Baseline 2 — 2026-05-03（post-#63 #64）

> 接续 [`2026-05-03-simulation-baseline.md`](2026-05-03-simulation-baseline.md)。在同事推完 PR #63（主循环 RON 自动检测 + atama-hane + 自动 HOUTEI）+ PR #64（HeuristicAi 启发式弃牌 + GameDriver 计分守恒 fix）后再跑 baseline，验证之前提的假设 A/B/C 是否被前述 plumbing 改动 address。

## 元信息

- **测试类型**：headless simulation（`tools/simulate_runs.gd`）
- **会话期间 main HEAD**：`62b62ce` — feat(m7): HeuristicAi (#64)
- **关键变化（vs baseline 1）**：
  - PR #63 主循环 RON 自动检测 + atama-hane 顺序
  - PR #64 HeuristicAi（启发式弃牌；不再纯随机）+ GameDriver 计分守恒 bug fix
- **GUT**：977/977 PASS（基线主分支）
- **跑了几个 Run**：3 套起始包 × 30 runs = **90 runs**

## 数据矩阵（post）

| 配置 | 通关率 | avg nodes | tsumo% | ron% | draw% | seat0 / seat1 / seat2 / seat3 平均 |
|---|---|---|---|---|---|---|
| control × 30 | 100% | 23.0 | 0.0% | 1.6% | 98.4% | 25533 / 24467 / 25000 / 25000 |
| aggro × 30   | 100% | 23.0 | 0.0% | 1.6% | 98.4% | 25533 / 24467 / 25000 / 25000 |
| fast × 30    | 100% | 23.0 | 0.0% | 1.6% | 98.4% | 25533 / 24467 / 25000 / 25000 |

3 组**完全一致**（同 baseline 1 的零差异现象）。

## 与 baseline 1 对比

| 指标 | baseline 1（pre） | baseline 2（post） | Δ |
|---|---|---|---|
| 通关率 | 100% | 100% | **±0** |
| HP 损耗 | 0 | 0 | ±0 |
| tsumo 占比 | 0.3% | 0.0% | **−0.3 pp** |
| ron 占比 | 0.0% | 1.6% | **+1.6 pp**（auto RON 起作用了） |
| exhaustive_draw 占比 | 99.7% | 98.4% | −1.3 pp |
| seat 0 平均点数 | 25018 | 25533 | **+515**（赢 ron 多） |
| seat 1 平均点数 | 25018 | 24467 | **−551**（被 ron 多） |
| seat 2 / 3 | 25006 / 25006 | 25000 / 25000 | ±6 |

## 横向观察

- **AI 升级显著改变分布**：HeuristicAi 比 SimpleAi 弃牌"更紧"，反而**自摸下降到 0%**（不主动追役 / 凑型）；但 auto RON 检测让"对手手中正好听的牌被弃出"路径生效 → ron 占比从 0% 升到 1.6%
- **不对称偏向放大**：玩家 seat 0 vs AI seat 1 点差从 ±12 扩到 ±1066，**玩家越来越强**（heuristic AI 反而更容易出 ron 牌给玩家胡）
- **seat 2 / 3 仍稳定 25000**：3 个 AI 之间互相不 ron（对称，互相不偏向）；只有"玩家有 ability + AI 没"形成的不对称导致 seat 0 vs 1 双向偏移
- **流局率仍 98.4%**：baseline 1 假设 B "几乎全走流局路径"在 AI 升级后依然成立 — heuristic AI 仍不立直，不组役 → 0 番不能胡
- **HP 系统完全不触发**：1392 节点结算（464 节点 × 3 套 starter）**全部** rank 1-2，没一次 rank 3/4

## 假设回顾

| baseline 1 假设 | 状态 |
|---|---|
| **A** SimpleAi 4 家对称 → 玩家几乎不可能 rank 3/4 | **部分 address**：HeuristicAi 让分布有变化，但偏向反而扩大；玩家 seat 0 因 ability + AI 不立直组合**更强** |
| **B** 几乎全走流局 + 听牌分摊 | **基本未变**：流局率 98.4%（vs 99.7%）；HeuristicAi 启发式仍**不立直、不鸣牌、不组役** |
| **C** 当前 baseline 无法支持 30-50% 通关率 | **未 address**：仍 100% 通关；HeuristicAi 没让玩家变弱反而变强 |

## 新假设

1. **D：HeuristicAi 必须能立直 + 鸣牌才会让玩家有挑战**
   - **证据**：流局率 98.4% → AI 几乎从不组成役 → 0 番无法胡 → 玩家不可能 rank 4
   - **机制**：日麻规则严格"无役不能胡"；不立直 + 不鸣牌 = 永远凑不到 1 番
   - **下一步**：HeuristicAi 加 RiichiValidator 调用 + 立直检测 → 能立直时立直 → 1 番立直 → 真竞争

2. **E：玩家 ability wire 让玩家不对称偏强**
   - **证据**：seat 0 +533 vs seat 1 -533，seat 2/3 不变；唯一不对称就是 player ability
   - **机制**：起始包 ability 在 BC.registry 注入到玩家 seat 0；3 个 AI 都没 ability
   - **下一步**：给 AI seat 也分配 ability（v1 简单：随机抽 1 张普通 ability 给每 AI；M7 后期 AI 主题化）

3. **F：3 套起始包对结果零差异（baseline 1 假设延续）**
   - **证据**：control / aggro / fast 三组 byte-for-byte identical
   - **机制推断**：起始包仅 1-2 个 ability，且 ability 触发条件几乎不命中（流局占 98%）；起始包内的 tile_variants 还没 wire 到 BC.registry（只有 abilities 走 #56 path）
   - **下一步**：grep `BattleNodeRunner / BC` 确认 tile_variants 是否真触发；若没 wire → 加 PR
     wire tile_variants（类似 #56 但针对 deck.tile_variants）

## 不爽 / 漏洞汇总

- **simulation 仍输出极度集中**（98.4% 流局），数据信噪比差
- **HP 系统在 baseline 没起任何作用**：1392 节点结算 0 次扣血 → hp_delta 链路虽然实现但实际未触发
- **仍无 AI 主题 / 难度差异化**：所有 AI 都是同一个 HeuristicAi 实例

## 后续动作

- [ ] PR：HeuristicAi 加立直 / 鸣牌能力（假设 D）→ 拆 2 个 PR：先立直，再鸣牌
- [ ] PR：起始包 deck.tile_variants 也 wire 到 BC.registry（假设 F + 类比 #56）
- [ ] PR：simulation CLI 支持 \`--starting-hp=N\` 临时覆盖 BalanceConstants（baseline 1 假设 C 实验用）
- [ ] 对照实验跑：HeuristicAi vs HeuristicAi 立直版 → 流局率 / 通关率变化
- [ ] M7 D6 调参 PR 必须 cite 本文 + baseline 1 累计观察
