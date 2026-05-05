# 麻将王 — 2026-05-05 会话总账（M9 收尾 → M12 起步）

> **类型**：单日工作总结 doc。本会话把 M9 平衡迭代正式收尾、scripts/ legacy 大清理、shanten AI building block、联机骨架 M11/M12 起步全部 ship。共 PR 数 30+（含同事并发），main HEAD 从 d71dcb0（M9 closure 起点）走到 4bd3a35+（M12/p1 协议数据）。

## TL;DR

| 维度 | 起点 (HEAD d71dcb0) | 终点 (HEAD 4bd3a35+) | 变化 |
|---|---|---|---|
| GUT 测试数 | 1123 | **1208** | **+85**（+7.6%） |
| `scripts/` 文件数 | 17 (post #103) | **9** | **-47%**（-91% from 96 起） |
| 假设清单 | 14/14 主线 | **15/15 + S 候选确认** | +M / +S |
| 多 seed parity | control 单 pack (#102) | **3 包 × 6 seed = 18 数据点** | 全覆盖 |
| 联机骨架 | spec §4.3 仅约定 | **M11 接口抽象 + M12 协议** | 4 PR 起步 |
| AI 决策 | M7 retention | **+ shanten opt-in** | building block |

## 一、M9 平衡迭代正式收尾

### 假设演化（全部 address）

| # | 假设 | 状态 | 关键 PR |
|---|---|---|---|
| L | aggro/fast 偏弱是结构性 | ✅ #91 解 | (PR #91) |
| Q | 3 包同质化需差异化机制 | ✅ #97/#109/#113 **3 次证伪** | — |
| R | boss3 force_yakuman 让章 3 高方差 | ✅ tune-R2 (#100) 解 | #100 |
| **M** | **fast 是否仍 byte-identical 于 aggro** | ✅ **#109 闭环** | #109 |
| **S** | **post-R2 D6 上界 +3.3pp 是结构性** | ✅ **#113 验证**（mean +1-2pp） | #113 |

**判定**：15/15 主假设全部 address；建议**不触发 tune-R3**（spec §14 alpha 反馈原则）。

### 多 seed 数据矩阵（6 seed × 3 包）

| seed | control | aggro | fast |
|---|---|---|---|
| 1000 | 40.0 | 40.0 | 40.0 |
| 2000 | 53.3 | 53.3 | 53.3 |
| 3000 | 46.7 | 53.3 | 53.3 |
| **4000** | **66.7** | **66.7** | n/a |
| 5000 | 53.3 | 53.3 | n/a |
| 6000 | 46.7 | 46.7 | n/a |
| **mean** | **51.1%** | **52.2%** | 48.9% |

**control vs aggro 6/6 数据点 byte-identical**（包括失败章节分布）— soul_drain 通用基底完全可行；spec §7.2 "差异化但都可玩"通过非通关率维度（玩家分 / spread）实现。

## 二、scripts/ legacy 大清理（spec §15 风险点闭环）

### 4 批清理时间线

| 批 | PR | 内容 | scripts/ 剩余 |
|---|---|---|---|
| 第 1 批（前会话） | #95 | 12 个中麻规则 / 牌组文件 | 84 |
| 第 2 批 | #103 | 50 个 multiplayer / social / 占位 UI | 46 |
| 第 3 批 | #104 | 27 个零引用占位 / 测试 helper | 17 |
| 第 4 批 | #105 | 8 .gd + 5 .tscn co-archive | **9** |

**总计**：96 → 9（**-91%**）。剩余 9 个全是活跃路径（autoloads / 主入口 / 主场景 / hand_display 间接复用）。

spec §15 风险点 "中麻规则代码（hu_rule.gd 等）替换不彻底导致两套规则共存" **正式闭环**。

## 三、M10 Path A：HeuristicAi shanten 升级

| PR | 内容 | 测 |
|---|---|---|
| #115 | ShantenCalculator（standard / chiitoi / kokushi） | +15 |
| #117 | HeuristicAi 接入 shanten（opt-in via `--shanten-ai`） | +6 |
| #119 | Memoization 优化（1 run 180s → 134s ~25%速） | — |

**关键发现**：
- ✅ 算法正确（21 测覆盖 standard / chiitoi / kokushi / 副露折抵 / 一致性）
- ⚠️ 单 run sim 信号示**shanten AI 太强**（玩家分 +75%，估计破 D6 80%+）
- ✅ 决策：保留作 building block（默认 `use_shanten_aware_discard = false`），等真玩家 alpha 反馈再决定
- 📋 baseline 14 sim 验证留作"假设 S 等同 alpha 反馈"决策依据，不立即触发

**M9 closure (#101)** 已通过 #110 更新：38/30/30 → 46.7/46.7/53.3 实测中位。

## 四、M11 Path C：BattleController 接口抽象

| PR | 内容 | 测 |
|---|---|---|
| #118 | Phase 2 联机骨架 brainstorm（M11/M12/M13/M14 4 阶段拆解） | — |
| #121 | IBattleController 接口抽象（BattleController extends IBattleController） | +5 |
| #123 | caller 类型签名 7 处迁移到 IBattleController | — |
| #124 | M11 进度更新 + p3 文件改名推迟到 M12 解释 | — |

**实质**：spec §4.3 "BattleController 抽象成接口"约束**已完成**。M12 NetworkedBattleController 引入时只需 extends IBattleController 即可 plug-in，无需改 GameDriver / RunFlow / tests。

**未做**（M11/p3 文件改名 BattleController → LocalBattleController）：14 文件 + ~30+ 静态调用点 mass-rename，纯 cosmetic；推迟到 M12 引入 NetworkedBattleController 时与改名一起做更对称。

## 五、M12 Path C 起步：联机协议数据类型

| PR | 内容 | 测 |
|---|---|---|
| #127 | `protocol/action.gd` (Action) + `protocol/networked_event.gd` (NetworkedEvent) | +21 |

**Action**（client → server）：
- Kind enum 10 项（DRAW/DISCARD/RIICHI/PASS_CLAIM/CHI/PON/KAN/RON/TSUMO + UNKNOWN）
- 静态构造 helpers + 序列化（与 BattleEvent 风格对齐）

**NetworkedEvent**（server → all clients）：
- 包装 BattleEvent + server_seq 单调递增 + causing_action_id + server_ts_ms（M14 反作弊 / 录像用）

**留 M12/p2+**：LocalLoopbackServer 仲裁逻辑、NetworkedBattleController client 半边、真 WebSocket 传输（M13）、鉴权 / 反作弊（M14）。

## 六、同事并发 PR（重要里程碑参与）

| PR | 内容 |
|---|---|
| #106 | baseline 11 aggro multi-seed（与 #102/#109 三联） |
| #107 | WaitCalculator.is_tenpai 早退辅助（M10 building block） |
| #108 | M10 ctx B4：信息系 reveal API + 5 hooks 升级真效果 |
| #111 | M10/net foundation：BattleEvent/TileInstance 序列化 + smoke test |
| #112 | sim CLI parse_args 静态化 + 未知 flag 警告（#109 的 follow-up） |
| #120 | Steam 上线准备 brainstorm |

## 七、main HEAD 当前状态

- **Commit**：`4bd3a35` (post-#127)
- **GUT**：1208/1208 PASS
- **目录结构**新增：
  - `core/rules_japanese/shanten_calculator.gd`
  - `battle/i_battle_controller.gd`
  - `protocol/action.gd` / `protocol/networked_event.gd`
  - `tests/protocol/`
- **目录结构清理**：
  - `legacy/` 89 .gd + 5 .tscn（全 4 批归档完成）
  - `scripts/` 9 .gd（仅活跃路径）

## 八、Phase 2 路线图（M11+）

```
✅ M11/p1 IBattleController 接口   (#121)
✅ M11/p2 caller 类型迁移          (#123)
⏳ M11/p3 文件改名 LocalBattleController (推迟到 M12 起步时)
✅ M12/p1 protocol.Action / NetworkedEvent (#127)
🔵 M12/p2 LocalLoopbackServer 仲裁器骨架
🔵 M12/p3 NetworkedBattleController client 半边
🔵 M12/p4 server-side BattleState 镜像 + TurnEngine 调度
🔵 M12/p5 4-client local loopback 集成测
🔵 M13/p1 真 WebSocket server（决策 Go vs Godot Server Build）
🔵 M14/p1 反作弊 / RNG seed / 重放检测
```

## 九、留 Phase 2 / 真玩家 alpha 决策的项

1. **shanten AI 是否破 D6**：等 alpha 反馈再 multi-run 验证（#119 后留可选）
2. **tune-R3 是否触发**：建议不触发；alpha 反馈精调（章 1 -2→-3 + 章 3 调回 -2）
3. **教程 / 新手引导**（spec §15）：未做；可与联机一起做，可单独
4. **半庄"南入"实装**（`enable_south_exit_top30k` flag 已留位）
5. **server 选型**（M13）：Go（重写 SkillScheduler）vs Godot Server Build（复用）

## 十、本日收尾要点

- M9 平衡迭代正式收尾（15/15 + S 候选 address；建议不 tune-R3）
- scripts/ 96 → 9（spec §15 风险点闭环 -91%）
- M10 Path A shanten AI 作 building block ship（默认 off）
- M11 接口抽象本质完成（M12 NetworkedBattleController 已可 plug-in）
- M12/p1 协议数据类型 ship（Action + NetworkedEvent + 21 测）
- GUT +85（1123 → 1208）
- 8 个我的 PR + 6 个同事 PR = 14 个 main 推进
