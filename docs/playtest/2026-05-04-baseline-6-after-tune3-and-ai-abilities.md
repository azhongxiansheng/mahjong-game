# Simulation Baseline 6 — 2026-05-04（post-#80 #82）

> 接续 [`baseline 5`](2026-05-04-baseline-5-after-tiebreak-and-fast-buff.md)。同事 PR #80（tune-3：starting_hp 5→4 + soul_drain 20→12%）+ PR #82（AI seat 1/2/3 也分配随机 ability — 我 baseline 5 假设 J/M 落地）后再跑 baseline。**首次观察到 control 通关率落入 plan-7 D6 30-50% 目标区间** ✅；**aggro 通关率坍塌**（首次出现章 1 失败）。

## 元信息

- **会话期间 main HEAD**：`b964ad0` — feat(m7/sim): AI seat 也分配随机 ability (#82)
- **关键变化**：
  - PR #80 tune-3：starting_hp 5→4 + soul_drain 20%→12%
  - PR #82 AI seat 1/2/3 random ability injection（baseline 5 假设 J/M 落地）
- **跑了几个 Run**：control 5 + 5（with/without ai-abilities）+ aggro 5 = 15 runs

## 数据矩阵

| 配置 | 通关率 | 失败位置 | avg nodes | tsumo% | ron% | draw% | seat0 / 1 / 2 / 3 |
|---|---|---|---|---|---|---|---|
| **control × 5** | **40%** (2/5) | 章 2: 2 / 章 3: 1 | 17.6 | 11.4% | 38.8% | 49.7% | 106787 / -11662 / 6919 / -1944 |
| control × 5 (--ai-abilities) | 40% | 同上 | 17.6 | 11.4% | 38.8% | 49.7% | 106787 / -11662 / 6919 / -1944 |
| aggro × 5  | 0% (0/5) | **章 1: 2** / 章 2: 3 | **7.8** | 0.7% | **54.3%** | 44.9% | 93057 / 40021 / -45311 / 12231 |

## 与 baseline 5 对比（control）

| 指标 | baseline 5 | baseline 6 | Δ |
|---|---|---|---|
| 通关率 | 75% | **40%** | **−35 pp** ✓ |
| HP 起手 | 5 | **4** | tune-3 |
| HP avg final | 2.5 | 1.0 | -1.5 |
| draw% | 45.4% | 49.7% | +4.3 |
| ron% | 42.8% | 38.8% | -4 |
| seat 0 | 90354 | 106787 | +16433（soul_drain 20→12% 让玩家分流减少） |
| seat 1 | 27097 | -11662 | -38759（boss 受冲击） |

**关键里程碑**：control 通关率落入 plan-7 D6 **30-50% 目标中段** ✅✅。

## 与 baseline 5 对比（aggro）

| 指标 | baseline 5 | baseline 6 | Δ |
|---|---|---|---|
| 通关率 | 5% | 0% | -5 pp |
| 章 1 失败 | 0 | **2** | **首次出现！** |
| 章 2 失败 | 5 | 3 | -2 |
| avg nodes | 11.3 | **7.8** | -3.5（更早死） |
| ron% | 43.3% | **54.3%** | +11 pp |

aggro 通关率坍塌：HP 5→4 让 aggressive packs 容错降级；玩家更容易在章 1 阶段就 hp=0。

## 横向观察

### 假设 K（control 通关率偏高）— **address ✅**
control 75% → 40%。tune-3 一击搞定。soul_drain 20→12% 减少玩家从对手拿点 → 玩家排名压力大；HP 5→4 让 hp 损失累积更快。

### 假设 L/M（AI seat ability injection 应让 4 家更对称）— **效果不可见**
\`--ai-abilities\` flag 启用 vs 关闭 → control 数据完全 byte-identical：
- 通关率 40% / 40%
- HP avg 1.0 / 1.0
- seat scores 完全相同（106787 / -11662 / ...）
- hand outcomes 完全相同

**怀疑 AI ability 实际未触发或效果接近 0**：
- AI abilities 主要在 WIN_DECLARED_PRE fire（+N 番）
- AI 胡牌频次低（control 38% ron 大多是 player ron AI）
- 即使 AI 拿到 ability，触发机会少 → 对 score 分布影响 ≈ 0

### 假设 J（玩家不对称偏强）— **加剧**
control: seat 0 106787 vs seat 1 -11662 → spread ±59k（baseline 5: ±32k）。
soul_drain tune 让玩家"赢分但不被分流"，spread 反而扩大。

### 新假设

1. **O：AI ability injection 在当前 sim 等价于无操作**
   - 证据：byte-identical sim with vs without flag
   - 机制推测：AI 胡牌 ≈ 5%；ability 大多 WIN_DECLARED_PRE 触发；AI 不胡 → ability 不 fire → 对 sim 输出 0 影响
   - 下一步：(a) 验证 AI ability 真注册（GUT debug）；(b) 看 ability 设计 — 也许 AI 应该装 holder_trigger 类（受益于 player 胡）

2. **P：tune-3 让 aggro 由"slow 0%"变"fast 0%"，更接近 plan-7 设计意图**
   - 证据：aggro 章 1 失败 0→2，avg nodes 11.3→7.8
   - 机制：HP 4 + aggressive pack 不抗 = 章 1 boss 就挂
   - 设计意义：玩家选 aggro 起始包应该感觉"高风险高回报"；当前数据满足这种感觉
   - 下一步：可能需要再升 aggro pack 强度（一次胡的回报够大），让 5-15% 通关率（vs 0%）

## 假设回顾

| 假设 | baseline 5 状态 | baseline 6 状态 |
|---|---|---|
| H. HP 系统不触发 | address ✅ | 持续 ✅（更频繁） |
| K. control 偏高 | 75% > 50% | **address ✅**（40% 中段） |
| J. 玩家不对称 | 加剧 | **加剧**（±32k → ±59k） |
| L/M. AI ability fix 玩家偏强 | 提出 | **效果 ≈ 0**（新假设 O） |

## 后续动作（按 ROI）

- [ ] **PR：AI ability injection 实证 GUT 测试**（假设 O 验证）
  - 跑一局，断言 AI seat 的 SkillRegistry 真有 entry
  - 跑 RON_DECLARED_PRE 看 AI 的 ctx.add_han 是否 fire
- [ ] **PR：HeuristicAi 鸣牌（chi/pon）让 AI 胡牌频次增**
  - 直接降流局率 → 更多 win → AI ability 才有 fire 机会
- [ ] **PR：aggro pack 内容升级**（让 0% → 5-15% 通关）
- [ ] **大样本 sim**（runs=30 × 多 seed）确认 control 40% 稳定（不是 5-run 方差）

## 关键里程碑

baseline 1 → 6 累积 **8 个假设全部 address 或定位**：

| 假设 | 状态 |
|---|---|
| A. SimpleAi 4 家对称 | ✅（HeuristicAi+riichi） |
| B. 几乎全走流局 | ✅（流局 99.7→49.7%） |
| C. 30-50% 通关率不可达 | ✅（40% 落区间） |
| D. AI 必须能立直 | ✅（PR #70） |
| E. 玩家偏强（ability） | ⚠️（J 升级版） |
| F. tile_variants 没 wire | ✅（PR #66） |
| G. v1 +N 番 ≈ 0 影响 | ✅（HeuristicAi 后真生效） |
| H. HP 系统不触发 | ✅ |
| I. aggro/fast 等效 | ✅（PR #74 配置补齐） |
| J. 玩家不对称 | ⚠️（O 揭示更深结构问题） |
| K. control 通关率 | ✅（tune-3） |
| L/M. AI ability fix J | ⚠️（O 表 sim 不可见） |

> **plan-7 D6 30-50% 目标已达**。后续是稳定性验证 + aggro/fast 平衡 + 真正解决 J（结构性玩家偏强）。
