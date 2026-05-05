# Steam 上线准备 brainstorm（2026-05-05）

> **类型**：发布平台 brainstorm doc。spec §13 实现里程碑只到 M7；M9 closure / Phase 2 brainstorm 都聚焦联机 + 平衡 + 内容生产。本文档给 **Steam 平台发布**专门 scoping，作为 v1.0 上线轨道；与 Phase 2 联机正交独立。

## TL;DR

- **决策**：买断制 $15-20，**不做真钱抽卡 / 真钱 IAP**（详见 memory `project_monetization_decision.md`）
- **理由**：Slay the Spire / Hades / Balatro 都是买断；单机 roguelike 玩家极度反感单机 IAP；F2P+真钱 gacha 需要后端 + 反作弊 + 法规合规（≥3-6 个月新工作量）；现项目无后端最适合买断
- **现有 M5 抽卡保留不动** — 已是游戏内金币模式，正确架构
- **总工程量**：~2-4 周（GodotSteam 集成 + 成就 + 云存档 + 商店页 + 上传流水线）
- **不阻塞 Phase 2 联机**：Phase 2（M11-M14）独立推进；Steam 上线可先发单机 v1.0，联机后续 patch

## 一、付费模型决策（已定）

### 排除路径

| 模型 | 排除理由 |
|---|---|
| F2P + 真钱抽卡 | 需要服务器权威化 + 反作弊 + 国区 / EU 法规合规；3-6 个月新工作量 ≈ 项目至今总和；单 / 双人 dev 不可行 |
| 买断 + 真钱抽卡（混合）| Steam 罕见；Valve 可能 review 阻拦；玩家社群差评高 |
| 永久订阅 / 战令 | 单机 roguelike 不需要持续 LiveOps；订阅模型增加退款率 |

### 选定路径：买断制 + cosmetic DLC（可选后续）

| 阶段 | 内容 | 价格 |
|---|---|---|
| **v1.0 上线** | 完整游戏（章 1-3 + Boss + 现有 44 内容 + gacha 用 in-game gold） | $15-20 |
| 6 月后（看销量）| Cosmetic DLC：牌面皮肤 / 桌布 / 头像 / 立直棒外观 | $3-5 / 包 |
| 12 月后 | Expansion DLC：新章节（章 4-5）/ 新 Boss / 新起始包 | $10-15 |

**核心原则**：DLC 不影响核心平衡，玩家不抗拒。

## 二、Steam 平台特性集成清单

按必须性 / 优先级排：

### v1.0 必须（上线前）

| 特性 | Godot 集成 | 工作量 |
|---|---|---|
| **Steamworks SDK** | [GodotSteam 插件](https://github.com/CoaguCo-Industries/GodotSteam)（git submodule + AppID 配置） | 2-3 天接入 + 调试 |
| **Steam Achievements** | `Steam.set_achievement(name)`；现游戏天然有 章节通关 / Boss 击杀 / 全包通关 / 全 yaku 收集等钩子 | 1-2 天列表设计 + 接入 |
| **Steam Cloud 存档** | `Steam.file_write(path)` / `file_read`；M5 SaveSystem 改写到 Steam 路径 | 1 天 |
| **Steamworks 账户 + AppID** | $100 注册 + 法人 / 个人税表（有审核期）| ~1 周 wait |
| **商店页** | 截图 / GIF / trailer / 中英 description | 1 周（美术 + 文案）|
| **Build 上传流水线** | steamcmd + depot 配置 + branch（default / beta） | 1-2 天 |

### v1.0 推荐（上线前 / 上线后第 1 个 patch）

| 特性 | 工作量 |
|---|---|
| **Steam Trading Cards** | 玩家收集 → 兑换徽章；增加 community 留存 — 需 Valve 审核启用 |
| **Steam 表情包 / 头像 / 个人资料背景** | 同上，套餐式申请 |
| **Steam Workshop** | 玩家 mod 起始包 / 自定义 Boss — Phase 3 考虑（现 v1 不开）|
| **Steam Input** | 手柄支持（Steam Deck verified target）|

### Phase 2 联机后期（M14 完成）

| 特性 | 依赖 |
|---|---|
| **Steam P2P / Steam Networking** | 同事 M11-M14 网络骨架完成后接入 |
| **Steam 排行榜** | Run 用时 / 通关章节统计 |
| **Steam 创意工坊** | 玩家上传起始包 / Boss / skill |

## 三、Steam Deck 兼容性

Roguelike 在 Steam Deck 表现优秀（Slay the Spire / Balatro 都是 Verified）。

**对项目的要求**：
- 控制器映射（现 UI 全鼠标点击 — 需要 D-pad / button 替代）
- 1280×800 分辨率适配（现游戏窗口可缩放但 UI layout 需测）
- 性能：60 FPS @ 4W TDP（GUT sim 一局 ~100ms 远低于实时阈值）

**目标**：申请 Steam Deck **Verified** 评级（vs Playable / Unsupported）— 增加 Deck 用户曝光。

## 四、上线时间表（粗算）

```
Week 0     Phase 2 联机 PR (#111/#114/#116) 持续 → 不阻塞 Steam
Week 1     Steamworks 注册 + AppID 申请（异步等审核）
Week 1-2   GodotSteam 接入 + 成就钩子接 + 云存档迁移
Week 3     商店页素材准备（截图 / GIF / trailer 60s）
Week 4     Build 上传 + steamcmd 流水线 + 内测 review
Week 5     Steam Deck 兼容性测试 + 提交 Valve verified 申请
Week 6     v1.0 上线（公开 release，无内测期）
```

**关键依赖**：Steamworks 账户审核（~1 周）+ 商店页 Valve review（~5 天）+ Steam Deck Verified review（~2 周，可上线后申请）。

**最早上线**：~6 周后；**保守估**：8-10 周（含 NDA / 美术 / trailer 制作时长）。

## 五、上线前 D-list

| 项 | 状态 | 责任 |
|---|---|---|
| D1 决定付费模型 | ✅（买断 $15-20） | 用户已批 2026-05-05 |
| D2 GodotSteam 集成 | ⬜ | 工程 |
| D3 Steamworks 注册 + AppID | ⬜（用户操作）| 用户 |
| D4 成就列表设计（30-40 个）| ⬜ | 工程 + 用户 |
| D5 Steam Cloud 存档迁移 | ⬜ | 工程 |
| D6 商店页素材 | ⬜ | 美术 + 用户 |
| D7 Build 上传流水线 | ⬜ | 工程 |
| D8 Steam Deck 控制器映射 | ⬜ | 工程 |
| D9 中英 localization | ⬜（已部分 hardcoded 中文 / spec 英）| 工程 |
| D10 法务 / EULA / 隐私 | ⬜ | 用户（Valve 模板可用）|

## 六、关键开放问题

1. **目标市场**：国际 Steam（Valve global）、Steam 国区（需版号），还是双线？版号申请是 3-6 个月独立流程（不是 Steam 控）
2. **localization**：v1 中文 + 英文，or 中文 only（影响 trailer 文案）
3. **Trailer**：用户自制，还是外包？（外包 60s trailer ~$500-2000）
4. **Early Access vs 直发 v1.0**：Early Access 允许"未完成"上线 + 持续更新；v1.0 直发要求"完整可玩"
5. **价格**：$15 / $18 / $20 — 看竞品定位（Slay the Spire $25，Balatro $15，Hades $25）
6. **联机模式**是否 v1.0 必备？— 答：**不是**（Phase 2 后续 patch 加，单机 v1.0 已完整）

## 七、风险与缓解

| 风险 | 缓解 |
|---|---|
| Valve review 拒绝（如内容不完整 / 含 IAP / 截图涉政）| 上线前 1 月先送 build 给 Valve 内测 review |
| Steam Deck Verified 审核慢 | 上线初先发 Playable 评级（自动），上线后再申请 Verified |
| 国区版号无 → 国区 Steam 上不了 | 主战场国际 Steam；国区 Steam 待版号下来后上 |
| 销量 < 预期 → cosmetic DLC ROI 不够 | 上线后看 6 个月数据再决定 DLC 投入 |
| 玩家差评 "缺联机" | 商店页明确写"联机后续 patch 免费加" — 类似 Hades 早期做法 |

## 八、与 Phase 2 联机的关系

Phase 2 联机（M11-M14）和 Steam 上线**完全正交**：
- Steam v1.0 = 单机买断
- Phase 2 联机 = v1.x patch 免费加（玩家二次激活）

不需要等 Phase 2 完成才上 Steam — 反而**先上 v1.0 拿到玩家反馈再决定联机的具体形态**（PvP？协作？观战？）才更稳。

## 九、后续动作

按 ROI 排：

1. **用户**：决定上述 6 个开放问题（特别是 1 / 2 / 4 / 5 — 影响时间表 + 工程方向）
2. **工程**：GodotSteam 插件接入 spike（半天评估接口完整性 / Godot 4.5 兼容性）
3. **工程**：成就列表 brainstorm（基于现有 BattleEvent / NodeResult 钩子）
4. **用户**：Steamworks 账户注册（异步等审核）
5. **用户 + 工程**：商店页素材准备（同步进行）
6. **后续 plan doc**：每个 D-item 出独立 plan（如 `2026-XX-XX-godot-steam-integration.md`）

## 十、不在本 brainstorm 范围

- 真钱抽卡 / IAP（已决策排除）
- 国区版号申请流程（独立法务事务）
- 后端服务器架构（买断模式不需要）
- 联机 P2P / 服务器架构（Phase 2 独立 brainstorm 已存在）
- 移动端 / 主机移植（v2.0 后另议）
