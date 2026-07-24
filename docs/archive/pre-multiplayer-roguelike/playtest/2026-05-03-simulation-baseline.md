# Simulation Baseline — 2026-05-03

> **类型**：自动化 simulation 输出（plan-7 D4 工具首份产出）。非人类 alpha session。结构沿用 `_template.md` 的"假设"段，但不填"主观难度/乐趣"等需要人来打分的字段。

## 元信息

- **测试类型**：headless simulation（`tools/simulate_runs.gd`）
- **会话期间 main HEAD**：`b86b737` — feat(m7): 玩家 ability 接入 BattleController.registry (#56)
- **关键 plumbing 状态**：
  - PR #52 han_deltas → ScoreCalc ✅
  - PR #54 HAITEI / HOUTEI 事件 emit + game_ctx 标志 ✅
  - PR #56 玩家 ability wire ✅
- **GUT**：929/929 PASS（基线）
- **跑了几个 Run**：4 组 × 30 runs = **120 runs**

## 会话概要

跑 4 组对照 simulation：3 套起始包（control / aggro / fast）× pick=first；外加 1 组 control × pick=random。**4 组结果完全一致**：通关率 100%、avg nodes 23、final HP 5/5、章 1/2/3 失败 0。强信号：**当前对战配置下玩家几乎不可能输**。

---

## 数据矩阵

| 配置 | 通关率 | avg nodes/Run | min/max nodes | avg final HP | 章 1/2/3 失败 |
|---|---|---|---|---|---|
| control × first | 100% (30/30) | 23.0 | 23 / 23 | 5.0 | 0 / 0 / 0 |
| aggro × first   | 100% (30/30) | 23.0 | 23 / 23 | 5.0 | 0 / 0 / 0 |
| fast × first    | 100% (30/30) | 23.0 | 23 / 23 | 5.0 | 0 / 0 / 0 |
| control × random| 100% (30/30) | 23.0 | 23 / 23 | 5.0 | 0 / 0 / 0 |

> 4 组**完全相同**。3 套起始包对结果零差异；节点选择策略（first vs random）对结果零差异。

## 横向观察

- **节点数 23 是上限触顶**：每章 ~7 节点 × 3 章 ≈ 21-23，min=max=avg=23 表示**每个 Run 都跑到 Boss 终局**（不存在中途失败导致的早终）
- **HP 完全不损耗**：120 Runs × 平均节点 23 = 2760 节点结算，**全部** rank 1 或 rank 2（hp_delta=0），没有一次 rank 3/4
- **起始包零差异**：4 组（含 3 套起始包 + 1 组节点选择策略变化）输出 byte-for-byte 一致
- **节点选择策略零差异**：control×first 与 control×random 同 seed 同结果（决定性 RNG 让"挑哪个节点"在 outcome 维度无意义；可能是流局比例过高导致路径不影响最终排名）

## 提取的"假设"

1. **假设 A：SimpleAi 4 家对称对战 → 玩家几乎不可能 rank 3/4**
   - **证据**：120 Runs × 23 nodes = 2760 节点结算，rank 3/4 出现次数 = 0
   - **机制推断**：BC 用单个 SimpleAi 实例服务全部 4 座位（`ai = SimpleAi.new(seed + 1)`），SimpleAi 仅"随机弃手牌一张"，4 家行为完全对称；玩家因起始包 ability hook（如 seabed_hunter / 其他 M6 角色能力）有微小优势 → 系统性偏向 rank 1-2
   - **下一步**：
     - 对比"玩家无 ability"vs"玩家有 ability"通关率差异 — 验证是否纯 ability 优势导致
     - 长期解：替换 BC 中 AI 为更强 AI（至少会立直 / 鸣牌 / 选择性弃牌），让 4 家不对称地竞争

2. **假设 B：当前 simulation 几乎所有节点结算走"流局 + 听牌均匀分摊"路径**
   - **证据**：4 组无差异 + 节点数 max=23 说明连庄罕见（庄家自摸 / 听牌流局连庄会让节点数 < 22）
   - **机制推断**：SimpleAi 不立直、不鸣牌、不主动宣告 → 满 70 张摸完很难凑成 14 张和牌型；多数局以 EXHAUSTIVE_DRAW 结束；流局点棒在 4 家间按听牌人数分摊，若 0-1-2-3 听牌人各占 25% 则期望 hp_delta ≈ 0
   - **下一步**：在 simulation 输出加 `hand_outcomes` 分布（tsumo / ron / exhaustive_draw 各占比），验证此假设

3. **假设 C：当前 baseline 完全无法支持"通关率 30-50%"的 plan-7 D6 设计目标**
   - **证据**：100% 通关率 × 0 hp 损耗，与 30-50% 目标差异 ≥ 50 个百分点
   - **机制推断**：plan-7 D6 假设玩家 vs 真人 / 强 AI；当前 SimpleAi 比"真人随机点击"还要差（不会立直 = 永远凑不到役 = 0 番不能胡）
   - **下一步**：
     - 短期：BalanceConstants 调 `starting_hp` 5 → 1（强制强约束），看是否破 100%
     - 真解：M7 后续阶段引入"中级 AI"（会立直 + 鸣牌）作为 simulation 对手（plan-7 D4 已注 v1 用 SimpleAi，beta 阶段补中级）

## 不爽 / 漏洞汇总

- **simulation 决定性过强**：3 套起始包 × pick 策略 × random 都同结果。这本身**不是 bug**（同 seed 应同结果），但暗示了"hp_delta 链路在当前配置下没接通有效信号"
- **观测维度太粗**：当前 stats 只有 completed/failed/avg_nodes/avg_hp。无法分辨"流局占比 / tsumo 占比 / ron 占比 / 各家平均得分 / 起始包 ability 触发次数"等关键诊断维度

## 后续动作

- [ ] 起 PR：在 SimulationHarness 加 hand_outcome 统计（tsumo/ron/exhaustive_draw）+ avg_score_per_seat[4] + ability_fire_count
- [ ] 起 PR：跑"hp=1 starter=control"对照实验，验证 hp 调低能否让 100% 跌破
- [ ] 中期：引入"中级 AI"（参看 spec §13.2 / §13.6 内容生产里"AI 行为升级"），让 simulation 有真竞争信号
- [ ] M7 D6 调参 PR 必须 cite 本文 + 后续观测维度扩展产物
