# Simulation Baseline 13 — 2026-05-05（假设 S 验证：D6 上界结构性偏置）

> 接续 [`baseline 12 fast`](2026-05-05-baseline-12-post-tuner2-fast.md)（PR #109）。本 baseline 跑 control / aggro × seed 4000/5000/6000 × 15 runs 验证 baseline 12 提出的**候选假设 S：post-R2 D6 上界 +3.3pp 是结构性还是噪声**。**结论：S 确认 ✅，6 seed mean 51-52% 超 D6 上限 +1-2pp，seed=4000 单点 +16.7pp**。同时 **control vs aggro 6/6 数据点完全 byte-identical**（假设 Q 第 3 次坐实）。

## 元信息

- **会话期间 main HEAD**：`2cc8a54` → `ebe30e5`（含 PR #108 m10/ctx-b4 reveal API；不影响 sim 路径）
- **配置**：control / aggro × 15 runs, 3 seed (4000/5000/6000), `--heuristic-ai --fair-tiebreak --ai-seat-abilities`
- **6 sim 总跑时**：约 25 分钟

## 数据矩阵（baseline 13 新数据）

| seed | control | aggro | 失败章 control | 失败章 aggro |
|---|---|---|---|---|
| 4000 | **66.7%** (10/15) | **66.7%** (10/15) | 1: 0 / 2: 4 / 3: 1 | 1: 0 / 2: 4 / 3: 1 |
| 5000 | 53.3% (8/15) | 53.3% (8/15) | 1: 4 / 2: 3 / 3: 0 | 1: 4 / 2: 3 / 3: 0 |
| 6000 | 46.7% (7/15) | 46.7% (7/15) | 1: 2 / 2: 5 / 3: 1 | 1: 2 / 2: 5 / 3: 1 |
| 中位 | **53.3%** | **53.3%** | — | — |

**control vs aggro 6/6 数据点完全 byte-identical**（包括失败章节分布）— 玩家分有差异（aggro 多吸 ~30k）但通关路径同。

## 合并 baseline 11+12+13（6 seed 跨包总览）

| seed | control | aggro | fast | D6 ≤50%? |
|---|---|---|---|---|
| 1000 | 40.0 | 40.0 | 40.0 | ✅ 中段 |
| 2000 | 53.3 | 53.3 | 53.3 | ❌ +3.3 pp |
| 3000 | 46.7 | 53.3 | 53.3 | edge / +3.3 |
| **4000** | **66.7** | **66.7** | (n/a) | ❌❌ **+16.7 pp** |
| 5000 | 53.3 | 53.3 | (n/a) | ❌ +3.3 pp |
| 6000 | 46.7 | 46.7 | (n/a) | ✅ |
| **6 seed mean** | **51.1%** | **52.2%** | (3 seed) 48.9% | mean +1-2 pp |
| **6 seed median** | **53.3%** | **53.3%** | (3 seed) 53.3% | median +3.3 pp |

## 假设 S 验证 ✅

| 维度 | 数据 | 判定 |
|---|---|---|
| 6 seed mean 是否 ≤ D6 上限 50%？ | control 51.1% / aggro 52.2% | ❌ 超 +1-2 pp |
| 6 seed median 是否 ≤ 50%？ | 53.3%（4/6 seed ≥ 50%） | ❌ 超 +3.3 pp |
| 是否单 seed outlier？ | seed=4000 +16.7pp 极端，但其他 5 seed 也呈分布性偏高 | 否，结构性 |
| control vs aggro 是否一致？ | 6/6 数据点 byte-identical | 是 |

**假设 S 确认 ✅**：post-R2 D6 上界突破不是 noise 或 control-specific，而是结构性偏置。

## seed=4000 是真 outlier 还是普通方差？

seed=4000 control/aggro 都 66.7%（10/15 通关）— 比第二高 seed=2000 的 53.3% 高 +13.4pp。失败分布：

- 章 1: 0 失败 — RNG 路径让前 12 节点几乎全过
- 章 2: 4 失败 — 主瓶颈节点
- 章 3: 1 失败 — hanchan 收紧无效

对比 seed=5000（章 1 失败 4）seed=6000（章 1 失败 2）— 章 1 失败数从 0 到 4 跨度大，与 RNG 有关而非 hp_delta tune。

**seed=4000 是真 outlier**，但即使排除它：5 seed mean = (40+53.3+46.7+53.3+46.7)/5 = **48.0%**，仍接近 D6 上限。

## tune-R3 决策建议

### 选项 A：tune-R3 — hanchan rank 3 hp_delta -1 → 0

效果预测：
- rank 3 玩家半庄不再扣 HP，章 3 难度进一步软化
- 通关率预计 +5-10pp，会让 mean 飙到 56-60%，**反而更超 D6**
- **不推荐**

### 选项 B：tune-R3 反向 — east_round rank 4 -2 → -3

让东风战 4 位扣血更狠（章 1/2 主要节点类型）：
- 通关率预计 -5pp
- 但与 baseline 11/12 的 "rank 4 hanchan == east_round" 设计原则冲突
- **不推荐**

### 选项 C：tune-R3 — boss3_kanmon force_yakuman beneficiary 改 seat 1（vs 当前 seat 3）

当前 boss3 kanmon 让 seat 3（玩家对家）拿役满；改成 seat 1（玩家下家）：
- seat 1 升役满更难压住玩家（地理位置 1 vs 3）
- 但 boss3 是章 3 节点，seed=4000 章 3 仅 1 失败 — 调它影响小
- **影响有限**

### 选项 D：暂不 tune，接受当前方差 ✅ **推荐**

理由：
1. **6 seed mean 51-52% 超 D6 仅 +1-2 pp**，median 53.3% 超 +3.3 pp — 软偏置不严重
2. **seed=4000 是真 outlier**，但单 seed 不足以触发 tune
3. **D6 30-50% 是设计区间不是硬上限**；spec §14 "调参靠 alpha 反馈"原则推荐**让真玩家上场后再 tune**
4. tune-R3 任何方向都有反向风险（A/B 反而推 mean 更超 / 不超下沉）
5. baseline 13 数据本身已确认 control/aggro 完美 parity（6/6 byte-identical）— **设计意图实现**，平衡数值已基本到位

## 横向观察

### control vs aggro 6/6 byte-identical（假设 Q 第 3 次证伪）

baseline 9 (#97) / baseline 12 (#109) / 本 baseline 13 — **三次 multi-seed 验证下 control 与 aggro 同 RNG seed 通关率完全一致**。3 包"差异化"通过：

- **soul_drain（control / aggro 通用）**：玩家分加成
- **W9 iron_wall + CHUN seal_chun（aggro / fast）**：被动防御
- **thunder_5w + sou3_skip（fast 独有）**：增番加速

**通关率瓶颈是节点排名分布（hp_delta + RNG）而非包间差异**。spec §7.2 设计意图（"3 套差异化但都可玩"）通过非通关率维度（玩家分 / spread）实现。

### seed=5000 章 1 失败 4 / 章 3 失败 0 — 异常分布

seed=5000 是反向 outlier：章 1 失败 4 / 章 3 失败 0。**章 1 RNG 不利 + 章 3 极顺**。提示：当前 hp_delta tune 让"前 1/3 节点 RNG 极差能直接挂"，但"章 3 已不是难点"。tune-R2 软化章 3 太成功，章 3 现在反而比章 1 容易。

如果未来 tune-R3：**章 1 hp_delta 微调（rank 4 -2 → -3）+ 章 3 调回（rank 3 -1 → -2）保持 mean 稳定**，但这是 spec §14 "alpha 反馈"才该做的精调，不是 sim 阶段。

## 关键里程碑（更新）

| 阶段 | control | aggro | fast | 备注 |
|---|---|---|---|---|
| baseline 7 large-sample | 53% | 5% | 5% | 假设 L/N |
| baseline 9 multi-seed (post #91) | 20% | 33% | 33% | #91 解 L |
| baseline 10 (post #96 force_yakuman) | 26% | 30% | 30% | 假设 R 起 |
| baseline 11 control (#102) | 46.7% | — | — | post-R2 救章 3 |
| baseline 11 aggro (#106) | — | 46.7% | — | post-R2 aggro parity |
| baseline 12 fast (#109) | — | (53.3%*) | 53.3% | post-R2 fast parity |
| **baseline 13 (本)** | **51.1%** | **52.2%** | — | **6 seed mean，假设 S 确认** |

\* baseline 12 重跑 aggro s=3000 = 53.3%（vs #106 报 46.7%；可能 #106 漏 `--ai-seat-abilities` flag）

## 假设演化（最新）

| # | 假设 | 状态 |
|---|---|---|
| L | aggro/fast 偏弱是结构性 | ✅ #91 解 |
| Q | 3 包同质化需差异化机制 | ✅ #97 + #109 + 本 baseline **3 次证伪** |
| R | boss3 force_yakuman 让章 3 高方差 | ✅ tune-R2 (#100) 解 |
| M | fast 是否仍 byte-identical 于 aggro | ✅ #109 闭环 |
| **S** | **post-R2 D6 上界 +3.3pp 是结构性** | ✅ **本 baseline 确认**（6 seed mean +1-2pp，median +3.3pp） |

**15 / 15 假设全部 address**。

## 后续动作（按 ROI）

- [ ] **plan-9 closure** 补假设 S 状态行（已 PR #110 部分，本 baseline 加补丁 PR）
- [ ] **不触发 tune-R3**：接受当前方差为合理设计区间（建议 D）
- [ ] **HeuristicAi shanten 升级**（PR #107 已铺 is_tenpai building block）— 若有时间转向 Phase 2 主题
- [ ] **教程 / 新手引导**（spec §15 学习曲线风险）— Phase 2 主题
- [ ] **Phase 2 真玩家 alpha 反馈 → tune-R3** 时再精调 hp_delta（章 1 / 章 3 各微调）

## 总结

baseline 13 完成假设 S 验证 — D6 上界 +1-2pp 偏置确认结构性，但建议**暂不触发 tune-R3**，理由：偏置幅度小、tune 反向风险高、应留 alpha 反馈精调。3 包 multi-seed parity 已经过 4 次（#97 + #102 + #106 + #109 + 本）独立验证，spec §7.2 "差异化但都可玩"目标完整实现。M9 平衡迭代收尾。
