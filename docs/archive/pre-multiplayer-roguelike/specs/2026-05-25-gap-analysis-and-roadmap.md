# 麻将王 — 差距分析 & 开发路线图

- 作者：jingx8885
- 日期：2026-05-25
- 状态：active
- 依据：设计规范 `2026-05-01-mahjong-king-design.md` + 代码实际状态

## 1. 里程碑完成度总览

| # | 范围 | 状态 | 关键发现 |
|---|------|------|---------|
| 0 | 日麻规则引擎全栈 | **COMPLETE** | 44 役文件，符算/点数/振听/Dora 全路径，85 核心测试 |
| 1 | 技能框架 + demo | **COMPLETE** | 59 个 hook，28+ 技能 + 15 角色能力，完整事件总线 + 调度器 |
| 2 | 单局对战 vs AI | **COMPLETE** | BattleController 端到端，TurnEngine 集成，RON 自动判定 |
| 3 | 东风战 + 4 人桌 | **COMPLETE** | GameDriver 编排，4 人 UI，owner_seat 可视化，38 张牌 sprite |
| 4 | Run 流程骨架 | **COMPLETE** | RunState / ChapterMap / NodeKind 全类型，13 个 Run UI 场景 |
| 5 | 抽卡 + 存档 + 元进度 | **COMPLETE** | Gacha 三渠道，SaveSystem JSON 持久化，MetaProgress 声望 |
| 6 | 30+ 技能 + Boss + Pack | **ADVANCED** | 28 技能 + 15 能力已编码，3 Pack，3 Boss；.tres 外部化 pending |
| 7 | 平衡迭代 | **IN PROGRESS** | BalanceConstants 完整，14+ baseline run，HeuristicAi 调优中 |

## 2. 关键差距分析（按影响力排序）

### GAP-1: 鸣牌窗口不完整（影响力：**致命**）

**现状：**
- TurnEngine 有完整的 `apply_chi/pon/minkan/ankan/added_kan` 方法
- ClaimValidator 有完整的 `can_chi/pon/minkan/can_added_kan/can_ron/can_tsumo` 检查
- PlayableBattleController 已为 **玩家 seat 0** 实现了 chi/pon/minkan 弹窗
- BattleController sync 路径 CLAIM 阶段直接 `advance_to_next_seat()`

**缺失项：**

| 子项 | 描述 | 难度 |
|------|------|------|
| **AI 鸣牌决策** | AI 从不 chi/pon/kan；需要在 HeuristicAi 中加入鸣牌判断 | 中 |
| **玩家自家杠** | 玩家摸牌后无法宣告暗杠/加杠 | 低 |
| **AI 自家杠** | AI 摸牌后不检查暗杠/加杠 | 低 |
| **鸣牌优先级** | 多家想鸣同张时的优先级裁定（ron > pon/kan > chi）| 中 |
| **抢杠（chankan）** | 加杠时其他家的荣和机会 | 中 |
| **喰い替え禁止** | 鸣牌后禁止立即弃出相同牌或构成顺子的边缘牌 | 低 |
| **吃的 companion 选择** | 玩家吃时自动选第一组，应让玩家选 | 低 |

**影响：** 没有完整鸣牌 = 所有人都是门清打法 → 日麻的攻防核心缺失。

### GAP-2: AI 质量不足（影响力：**高**）

**现状：**
- SimpleAi: 随机弃牌
- HeuristicAi: 孤立度判断 + 向听感知 + 终局策略

**缺失项：**
- 安全牌判断（筋牌/壁牌推理）
- 防御切换（对手立直时切换到防守模式）
- 鸣牌决策（何时 pon/chi，何时跳过）
- 读对手听牌（分析弃牌河推测危险度）

### GAP-3: 语音/AI 交互系统（影响力：**差异化创新**）

**现状：** 完全未实现。

**愿景：** 玩家说话/念台词 → AI 识别 → 判定契合度/气势 → 影响技能效果/运势。

**需要设计的子系统：**
- 语音采集 + STT（Whisper）
- 文本分析 + 属性提取（LLM）
- 气势/运势数据模型
- 与 SkillScheduler 的集成
- 文字输入替代方案
- AI 对手的语音反应

**状态：** 需要单独的设计 spec，属于全新 feature，不在原始 M0-M7 范围内。

### GAP-4: 节点时长过长（影响力：**中**）

**现状：** 20-30 分钟/节点 × 36-45 节点 = 一次 Run 需 8-12 小时。

**可选方案：**
- 减少每章节点数（当前 12-15 → 改为 6-8）
- 加入"速战模式"（2 局制东风战）
- 优化 AI 思考延迟和动画速度

### GAP-5: 缺少主动技能使用（影响力：**中**）

**现状：** 所有技能被动触发，玩家在对局中没有"主动发动技能"的时刻。

**建议：** 消耗品/角色能力加入主动触发 UI（每局可主动发动 1-2 次）。

## 3. 本 session 开发范围

**聚焦 GAP-1: 鸣牌窗口完善。** 理由：
1. 影响力最高（"致命"级别）
2. 基础设施已完备（TurnEngine + ClaimValidator 全就绪）
3. 是 PlayableBattleController 已有代码的自然延伸
4. 不涉及新的外部依赖

### 实现优先级

1. **P0 — 玩家自家杠**（ankan/added_kan）：摸牌后检测 + UI 弹按钮
2. **P0 — AI 鸣牌决策**：HeuristicAi 加入 pon/chi/ankan/added_kan 判断
3. **P0 — 鸣牌优先级裁定**：统一的 claim resolution 流程
4. **P1 — 抢杠（chankan）**：加杠时 ron 检查
5. **P1 — 喰い替え禁止**：鸣牌后弃牌限制
6. **P2 — 吃 companion 玩家选择**：多组合时弹选择 UI

### 后续 session 计划

- **GAP-3 语音系统**：写设计 spec（下一个 session）
- **GAP-2 AI 防御**：在鸣牌完成后迭代
- **GAP-4/5**：平衡调优阶段处理

## 4. 技术约束

- TDD 强制：先写测试，再写实现（feedback_tdd_and_third_party）
- Worktree 隔离：独立分支开发（feedback_git_worktree_push）
- 不破坏现有 94 个测试
- 不改 TurnEngine/ClaimValidator 的现有 API（只加新调用点）
- SkillScheduler 事件链路必须完整（鸣牌事件 emit TILE_CLAIMED / MELD_FORMED）
