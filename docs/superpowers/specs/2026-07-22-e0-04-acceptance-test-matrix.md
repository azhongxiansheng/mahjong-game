# E0-04 验收测试矩阵

> **Issue：** [#224](https://github.com/jingx8885/mahjong-game/issues/224)（E0-04）
> **父 Epic：** [#214](https://github.com/jingx8885/mahjong-game/issues/214) / 总 PRD：[`2026-07-22-multiplayer-trash-talk-prd.md`](./2026-07-22-multiplayer-trash-talk-prd.md)
> **Epic 分解：** [`2026-07-22-multiplayer-trash-talk-epics.md`](./2026-07-22-multiplayer-trash-talk-epics.md)
> **范围：** E1–E5、E7 全部 **35** 个叶子 Issue（`#225`–`#259`）
> **硬约束：** **不存在 E6**（无 `scope:e6`、无举报/静音/语音控制/自动禁言占位）；核心规则、AI、语音、STT、发奖 **不得用 mock 顶替**；公共网络链路在四客户端公网证据前必须标注 **「网络端到端未验证」**。

本文是桌面 Alpha 与各叶子 Issue 的**唯一验收矩阵**。实现 Issue 关闭时，必须能在本矩阵中找到对应行，并附上所要求层级的真实证据。本文件只描述门禁与证据契约，不实现业务代码。

---

## 1. 证据层级与环境阻断

验收证据按层级递进。**上级未通过时，下级不得宣称「已完成」**。每一叶子行的「最低证据层」是关闭该 Issue 的硬门槛；更高层可在后续 Epic 复用同一行追加证据。

| 层级 | 代号 | 环境与工具（仅写仓库/工作流**真实已有或本矩阵明确要求后续交付**的能力） | 阻断规则 |
|---|---|---|---|
| L0 | `IMPORT` | **独立**运行 `godot --headless --path godot --import`（**不得**带 `\|\| true`；退出码必须为 0） | 改 PNG / 新 `class_name` / 影响资源缓存后**必跑且必须成功**；失败则阻断全部 Godot 层。**`scripts/test_run_core.sh` 不能替代 L0**：该脚本在 import 后使用 `\|\| true`，仅为 best-effort，不构成 L0 证据 |
| L1 | `GUT_LOCAL` | `godot --headless --path godot -d -s addons/gut/gut_cmdln.gd -gdir=res://tests/<module> -gselect=<name> -gexit` | 功能/缺陷 Red→Green 的最小证据；0 fail / 0 parse error |
| L2 | `GUT_CORE_CI` | `.github/workflows/core-tests.yml` → `scripts/test_run_core.sh`：内部会 best-effort import（`\|\| true`）后跑 GUT 目录 `res://tests/core,battle,skills,integration`；CI 固定 `GODOT_VERSION=4.5-stable` | 触及 core/battle/skills/integration 的 PR 必须绿；Epic 结束前不得靠「只跑局部」放行。**L2 绿 ≠ L0 已证明**；涉及资源/`class_name` 时仍须单独提交 L0 成功日志 |
| L3 | `GUT_FULL` | 全量：`godot --headless --path godot -d -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`（约 250+ 脚本 / 1800+ 用例） | 跨模块回归、Autoload/主场景契约变更后的阻断层 |
| L4 | `UI_SHOT` | 非 headless：`godot --path godot -s tools/capture_screens.gd`；`CAPTURE_SIZE = Vector2i(1600, 900)`；**当前**可出 Run 场景与牌桌/battle_live 等 `/tmp/shot_*.png`。**当前尚无生产大厅截图** | UI 几何与主路径观感；**禁止用 headless 冒充截图**。大厅证据仅在 #227/#228 **扩展** `capture_screens.gd` 并实际产出后才可引用，不得把未来能力写成当前事实 |
| L5a | `SVC_LOCAL` | 真实 **Control Plane + Redis + Headless Worker**（及 E4 后 **STT**）；健康检查 / readiness；**不扩张根 `main.go` 业务职责** | 无真实进程/容器 smoke 不得关闭 E3/E7 服务叶子 |
| L5b | `VOICE_STT` | **证据族**（非整族一次齐套才可关闭叶子）：真实麦克风 PTT、双客户端语音环回、本地 whisper.cpp、服务端 faster-whisper（主）、new-api 回退（备）；固定 PCM16 LE / 16 kHz / mono / 20 ms | 各 E4 叶子**只须**其负责组件的真实证据（见 §1.3）；**禁止**因整族未齐而反向阻塞上游叶子（例如 #243 不得依赖尚未实现的 #247/#248）。核心链路仍**不得 mock** |
| L5c | `PUBLIC_E2E` | 公网至少两个明确场景（见 #259）：**(A) 4 真人完整整场**；**(B) 1–3 真人 + AI 补位完整整场**；东风/半庄、标准/欢乐至少各一场 | **桌面 Alpha 最终阻断**；此前相关 PR 必须写「网络端到端未验证」 |
| L5d | `DESKTOP_PKG` | 干净 macOS / Windows 用户目录：安装包、权限、防火墙提示、whisper 模型按需下载 + SHA-256、整场连接 | 对应 #257/#258；与 L5c 共同构成 Alpha DoD |

### 1.0 L0 与 L2 的 import 关系（强制）

```bash
# L0 唯一合法证据：独立命令，要求 exit 0
godot --headless --path godot --import
# 禁止把下列脚本内的 import 当作 L0：
# scripts/test_run_core.sh 中有：godot ... --import || true
```

- **L0**：资源导入/class 缓存的**成功**门禁；失败即红，不得忽略退出码。
- **L2**：`scripts/test_run_core.sh` 为 CI/core 回归入口；其中 import 带 `|| true` 仅为减轻良性告警对 GUT 的误杀，**明确是 best-effort**。
- 关闭触及 PNG / 新 `class_name` / 资源缓存的 Issue 时：PR 须同时附 **L0 成功**与（若适用）L2/L3 结果；**不可**只写「跑过 test_run_core」。

### 1.1 通用声明模板（网络）

凡触及匹配、Worker、语音中继、公网连接且**尚未**取得 L5c 证据的 PR / Issue 关闭说明，必须包含：

```text
网络端到端未验证
```

取得 L5c 后，可改为引用 #259 证据包路径与日期。

### 1.2 核心不 mock 规则

| 领域 | 允许 | 禁止 |
|---|---|---|
| 日麻规则 / 符算 / 和牌 / 听牌 / TurnEngine | 真实 `core/` + GUT | mock 替代判定结果 |
| AI 行动 | 真实合法行动入口 | 脚本直接改牌墙/分数冒充 AI |
| RewardWindow / 矩阵 / 分配 | 真实权威状态机 + fixture 输入 | mock `ITEM_GRANTED` 或客户端自报奖励 ID |
| STT | 真实主备链路或受控真实超时/熔断 | 用假文本直接写入窗口累计冒充转写完成 |
| 网络/Redis | 真实 Redis / 真实 WS / 真实 Worker | 用内存假服务顶替幂等/租约/快照 round-trip 的「完成」宣称 |
| 外部副作用隔离 | 第三方 HTTP 可在**已声明**的契约测试中用最小真实请求；失败则停止接入 | 用 mock 宣称 new-api / 麦克风权限「已完成」 |

Fixture **可以**提供确定的权威事件流、文本序列、时钟与 seed；fixture **不是**对核心逻辑的 mock。

### 1.3 L5b 证据族与叶子责任（禁止反向依赖）

L5b 是**真实语音/STT 证据族**的总称，不是「必须一次凑齐全部组件才能关闭任一 E4 叶子」。

| 叶子 | 关闭时须具备的真实组件证据 | 明确不依赖 |
|---|---|---|
| #243 | 本机麦克风权限、PTT 按下/松开采集、PCM16 帧元数据、STANDARD 不申请麦 | **不**依赖 #247/#248 服务端 STT 已实现 |
| #244 | 双客户端真实语音环回、令牌校验、有界丢帧、与牌局命令通道隔离 | 可将帧**送往** STT 接口挂点，但**不**要求主备 STT 已产 final |
| #245 | whisper.cpp 清单/断点下载/SHA-256/原子启用的真实文件系统行为 | 不依赖公网四端；不依赖 #247 服务 |
| #246 | 中英日字幕展示与替换；可用本地或注入的**真实转写结果形状**做 UI，公共场本地文本不进权威窗 | 完整主备 STT 权威性归 #247/#248 |
| #247 | 真实 faster-whisper（+VAD）权威 final、边界/`grace_deadline_at` 遵守 | 依赖 #244 中继与 #252 边界权威，**不**被 #243 单独关闭阻塞 |
| #248 | 真实超时/失败触发 new-api 回退、熔断与同 utterance 去重 | 依赖 #247 主路径；**不**成为 #243 的关闭前置 |

跨叶子联调（双端 + 主备 STT 全链路）在相关叶子均就绪后追加，但**不得**把下游未交付写成上游关闭门槛。核心采集、中继、转写、回退逻辑全程**禁止 mock 顶替**。

---

## 2. 版本兼容策略

所有跨会话、跨客户端、跨 Worker 的载荷必须显式版本化。不兼容升级只能通过**新版本号 + 拒绝未知必需版本**完成，禁止静默改语义。

| 版本字段 | 拥有方（首次定义/变更） | 兼容规则 | 测试证据 |
|---|---|---|---|
| `protocol_version` | E3 协议 ADR（#223）/ #240–#242 事件与快照包络 | 整数；客户端/Worker 对未知主版本拒绝连接或拒绝应用快照 | 未知版本原子失败（#241/#242） |
| `ROOM_SNAPSHOT` 序号字段（#223 ADR 冻结名） | #241 应用/续传；#242 连续性对抗 | 载荷使用 **`payload.snapshot_server_seq`**（已应用序号上限）与 **`payload.next_server_seq`**（续传起点）。客户端应用快照后：视 `snapshot_server_seq` 为已包含的权威上限，**仅从 `next_server_seq` 起**消费增量事件。**禁止**使用未冻结别名 `last_server_seq` 作为协议字段 | **字段名契约测试**（见下表 SNAP-*）；序号缺口/重复检出（#241/#242） |
| `rule_version` | #249–#251 规则库与评分；#231 `GameSessionConfig.rule_version` | 字符串稳定 ID；变更必须同时更新黄金矩阵 fixture；旧回放绑定旧 `rule_version` 字节级可重放 | 全零/有文本黄金 fixture；同输入字节级一致（#250/#251） |
| `assignment_version` | #252 4×4 双射与字典序决胜 | 与 `rule_version` 解耦；只影响分配算法记录，不改评分分项语义 | 同分多解字典序最小向量；24 种双射最大化总分 |
| 模块 `schema_version`（snapshot provider） | #241 包络；#252 窗口 DTO；#253 库存/武装 DTO | 每个 `module_key` 恰好一个 provider；未知**必需**版本 → 稳定错误且**不部分应用**快照 | 测试 provider + E5 provider round-trip；STANDARD 不注册欢乐模块 key |
| `GameSessionConfig` / Intent 枚举值 | #228 Intent；#231 Config | 稳定枚举名与协议值；非法组合不得进入牌桌 | 8 种入口组合转换测试 |
| 音频帧契约 | #243/#244 | PCM16 LE / 16 kHz / mono / 20 ms **固定**；不版本漂移，若变更视为新协议并升 `protocol_version` | 双客户端环回帧校验 |
| Godot / CI | `.github/workflows/core-tests.yml` | CI：`GODOT_VERSION=4.5-stable`；本地开发可验证 4.6.x，但合并门禁以 CI 与全量 GUT 为准 | CI 绿 + 全量 GUT |

#### 快照序号字段契约测试（#241/#242 必覆盖）

| ID | 断言 |
|---|---|
| SNAP-01 | `ROOM_SNAPSHOT` JSON/DTO **必须**暴露 `payload.snapshot_server_seq` 与 `payload.next_server_seq`（路径以 #223 ADR 为准）；反序列化不得静默改名 |
| SNAP-02 | **精确不变量（强制，非可选）：** 顶层 `envelope.server_seq == payload.snapshot_server_seq`；且 `payload.next_server_seq == payload.snapshot_server_seq + 1`。应用快照后客户端已应用上限 = `payload.snapshot_server_seq`；下一条合法增量事件的 `server_seq` **必须等于** `payload.next_server_seq`。违反任一等式 → 契约测试失败 |
| SNAP-03 | `server_seq < next_server_seq` 的增量视为重复/过期并拒绝或幂等忽略；`server_seq > next_server_seq` 视为缺口并失败 |
| SNAP-04 | 契约测试**负向**：载荷若只提供 `last_server_seq` 而无冻结字段名 → 解析失败或稳定错误（防止文档/实现漂移回旧别名） |
| SNAP-05 | 测试 provider serialize → snapshot → restore → 增量 round-trip：**往返后** `envelope.server_seq`、`payload.snapshot_server_seq`、`payload.next_server_seq` 均不变，且仍满足 SNAP-02 两式；STANDARD 快照不注册欢乐模块 key |

**升级流程（强制）：**

1. 先改 fixture / 契约测试（Red），再改实现（Green）。
2. 旧 `rule_version` + 旧事件流必须仍能回放；新版本用新 fixture 锁死。
3. 快照：旧客户端遇到新必需 `schema_version` → 拒绝；服务端不得用默认值「猜」业务字段；序号续传只认 `snapshot_server_seq` / `next_server_seq`。
4. 禁止在 STANDARD 路径注册 TRASH_TALK 模块 key 以「兼容」为名泄漏状态。

---

## 3. 仓库真实验证能力基线（写矩阵时不得虚构命令）

### 3.1 现有可执行入口

```bash
# L0 资源/class 缓存 —— 必须独立运行且 exit 0（L0 证据）
godot --headless --path godot --import
# 注意：不可用 scripts/test_run_core.sh 代替；该脚本内 import 为「|| true」best-effort

# L1 局部 GUT
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/<module> -gselect=<test_name> -gexit

# L2 CI 同源（core/battle/skills/integration）—— 不构成 L0
scripts/test_run_core.sh
# 或：GODOT=/path/to/godot scripts/test_run_core.sh
# 脚本事实：先执行 godot --import || true，再跑 GUT；import 非零不会阻断脚本

# L3 全量 GUT
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests -ginclude_subdirs -gexit

# L4 1600×900 截图（禁止 --headless）
godot --path godot -s tools/capture_screens.gd
# 当前真实输出示例（Run/牌桌，非生产大厅）：
#   /tmp/shot_four_player_table.png、/tmp/shot_battle_live.png、
#   /tmp/shot_chapter_map.png 等 run 场景标签
# 生产大厅 / 规则抽屉截图：当前工具尚无对应条目，见 §3.3
```

### 3.2 CI 事实

- 工作流：`.github/workflows/core-tests.yml`（`pull_request` + `push` to `main`）。
- Job：下载 Godot **4.5-stable** headless → `scripts/test_run_core.sh`。
- 该脚本**不会**因 import 非零而失败；因此 **CI 绿不能当作 L0 import 成功证据**。
- **当前 CI 不覆盖**：强制成功的独立 import 门禁、UI 截图、Control Plane、Redis、Worker、麦克风、公网 E2E、桌面打包。这些必须在对应叶子用 L0 / L4 / L5* 证据关闭，不得假装「CI 绿 = Alpha 完成」。

### 3.3 截图工具事实（`godot/tools/capture_screens.gd`）

- 固定 `CAPTURE_SIZE = Vector2i(1600, 900)`。
- **当前事实：** SHOTS 仅含既有 **Run** 多场景与 `four_player_table`，以及脚本内 `PlayableTable` + 真实 `BattleController` 的 live/end/moment 路径。**当前尚无生产大厅截图**，也没有规则抽屉展开态条目。
- **后续（非当前能力）：** #227 / #228 在实现 PR 中扩展 `capture_screens.gd` 的生产大厅 / 抽屉标签并实际跑出 `/tmp/shot_*.png` 后，才可作为对应叶子的 L4 大厅证据。在扩展完成前，#227/#228 不得引用「现有 capture 已含大厅」；可用几何 GUT + 手测，但 L4 大厅项保持未满足直至工具扩展并出图。
- 矩阵与 PR 描述**禁止**把「将要扩展的 capture」写成「仓库已能截大厅」。

### 3.4 根 `main.go`

仅 Railway 健康检查桩。E3 Control Plane 必须**独立 Go module/目录**，验收时核对根桩行为不变（#236）。

---

## 4. 事件所有权与 FULL_GRANT 顺序

### 4.1 所有权（禁止跨 Issue 偷跑）

| 事件 / 状态 | 唯一定义/fixture 方 | 唯一业务发射方 | 禁止 |
|---|---|---|---|
| 行动/事件包络、schema、合法偏序 | **#232**（fixture + replay 骨架） | 牌局基础事件：E2/E3 Worker；E5 类事件见下行 | #232 生产路径发射 `REWARD_WINDOW_*` / `ITEM_GRANTED` / `CHARACTER_ABILITY_*` |
| `REWARD_WINDOW_OPENED/CLOSING/SETTLED/CANCELLED`、phase、`window_exit`、双边界、`grace_deadline_at`、结算屏障 | schema 由 #232 fixture 冻结 | **#252 / Worker 独占** | #253 发射任何 `REWARD_WINDOW_*`；#247 自建第二套 deadline |
| `ITEM_GRANTED`、库存、`ITEM_CONSUMED`/`ITEM_APPLIED`、`CHARACTER_ABILITY_ARMED/DISARMED`、active/pending | schema 由 #232 fixture 冻结 | **#253 独占**（在同一权威事务内消费 `SETTLED(FULL_GRANT)`） | 独立 `GRANT` 事件；客户端提交 `ITEM_GRANTED`；UI 从 `SETTLED` 推断库存 |
| `ITEM_USE` | 命令集合（#232/#253） | 无结果回声；接受后只出 `ITEM_CONSUMED` 和/或 `ITEM_APPLIED`，拒绝为稳定 `ERROR` | 事件流出现 `ITEM_USE` 回声 |
| 字幕/本地 STT 展示 | #246 | 仅展示；公共场本地文本**不得**进权威窗口累计 | 本地字幕触发发奖 |
| 权威 final 转写 | #247（主）、#248（备） | 按 #252 的 `closing_boundary_server_seq` / `grace_deadline_at` 截止 | STT 服务创建第二个权威计时器 |

### 4.2 结算屏障（唯一写法）

```text
claim_is_terminal AND (all_eligible_utterances_are_terminal OR now >= grace_deadline_at)
```

- `claim_is_terminal == true` **仅当**：
  - 全部 CLAIM 资格动作已终态，且非和牌鸣牌已应用；**或**
  - 无开放 CLAIM，且权威结果已在同一事务内确定为流局 / 终场非和牌。
- 和牌 cancel **立即**中止屏障与 1500ms 宽限，不得等待 deadline。
- 下一状态推进（摸牌、岭上补牌、出牌提示、道具/技能牌局事件）**不得越过**屏障。

### 4.3 FULL_GRANT 与相关出口顺序（权威回放必须字节级一致）

**不存在独立 `GRANT` 事件。** FULL_GRANT 统一为：

```text
REWARD_WINDOW_SETTLED(outcome=FULL_GRANT) → 4× ITEM_GRANTED(seat 0..3)
```

| 场景 | 权威顺序（摘要） | HAND_SETTLED？ |
|---|---|---|
| 满 24 弃且无和牌（同局继续） | `discard → CLOSING(+closing_boundary) → 屏障 → SETTLED(FULL_GRANT) → 4×ITEM_GRANTED → DISARM(active) → 可 OPEN next / ARM → 下一普通行动` | **无** |
| 非终场流局（可未满 24） | 先权威结果 → `CLOSING`（写双边界+唯一 deadline）→ 屏障 → `SETTLED(FULL_GRANT) → 4×ITEM_GRANTED → DISARM → HAND_SETTLED → 下一局 OPEN/ARM` | **有**（在 grant/disarm 之后） |
| 任意和牌（含第 24 弃荣和、中途自摸） | `CANCELLED(CANCELLED_BY_WIN) → DISARM → HAND_SETTLED`（终场和牌再 `MATCH_SETTLED`）；**不叠 DISPLAY_ONLY**；pending 断言为空；不评分不分配不发奖 | 有 |
| 终场非和牌展示 | `CLOSING → 屏障 → SETTLED(DISPLAY_ONLY, grant_count=0) → DISARM → HAND_SETTLED → MATCH_SETTLED`；**零** `ITEM_GRANTED` | 有 |
| FULL_GRANT 后武装登记 | 先登记 **next pending**（仅 `affinity_match=true` 的 `ITEM_GRANTED`），再 `DISARM` **current active**；pending **不得**被 disarm 误清 | — |
| 整场清空 | `MATCH_SETTLED` 清空库存 / active / pending；UI 只投影事件，不从 SETTLED 改数字 | — |

出口优先级：`CANCELLED_BY_WIN > DISPLAY_ONLY > FULL_GRANT`。
`window_exit` 三值：`FULL_GRANT | DISPLAY_ONLY | CANCELLED_BY_WIN`（OPEN/CLOSING 时为 `null`）。
`SETTLED.outcome` 仅两值：`FULL_GRANT | DISPLAY_ONLY`。
`CANCELLED.cancel_reason` 固定 `CANCELLED_BY_WIN`，**不含** outcome/矩阵。
settle 与 cancel **互斥**；取消后禁止 settle；展示后禁止 grant。

### 4.4 双边界与唯一 deadline

| 字段 | 含义 | 写入方 |
|---|---|---|
| `closing_boundary_server_seq` | 第 24 弃（或 scoring close 的关闭点）语音截止边界；只收 `PTT_END.server_seq <= closing_boundary` 的 final | #252 |
| `context_boundary_server_seq` | 评分上下文边界：CLAIM 全过/非和牌鸣牌应用序号，或流局/终场结果判定序号 | #252 |
| `grace_deadline_at` | 与 CLOSING **同一事务**写入的唯一 1500ms 宽限截止；#247 不得另建时钟权威 | #252 |

凡 scoring close（满 24 / 非终场流局 / 终场非和牌）均有**双边界 + 唯一 deadline**。荣和抢占：立即 cancel，迟到 final **不进当前窗也不漂移到下一窗**。

---

## 5. RewardWindow / 库存 / 武装 — 强制夹具总表

下列夹具是 #224 正文对 E5（及 #232 schema）的硬覆盖清单。实现分布在 #232（仅 schema/偏序 fixture）、#249–#254；矩阵关闭 #252/#253 时必须逐项打勾并附固定 seed 回放摘要。

### 5.1 窗口与 CLAIM

| ID | 夹具 | 期望 |
|---|---|---|
| RW-00 | 权威开局后、首条 `TURN_PROMPT` 前开窗 | 权威开局状态提交后、**第一条** `TURN_PROMPT` **之前**必须发出 `REWARD_WINDOW_OPENED`；按 `seed` / `hand_seq` / `window_index` / `rule_version` **确定性**公开**恰好 4** 个**互不重复**的 `item_id`；相同输入下奖池顺序**字节级一致**；若出现重复 `item_id` 或非 4 件 → **测试必须失败** |
| RW-01 | 满 24 + CLAIM 全过 | CLOSING → 屏障 → FULL_GRANT → 4×ITEM_GRANTED；无 HAND_SETTLED |
| RW-02 | 满 24 + 非和牌鸣牌应用 | context_boundary = 鸣牌应用序号；其后 FULL_GRANT |
| RW-03 | 满 24 + 荣和 | 立即 CANCELLED_BY_WIN；中止宽限；不评分不分配；再 HAND_SETTLED |
| RW-04 | 中途自摸（未满 24） | OPEN→CANCELLED；无矩阵；库存不变；pending 空 |
| RW-05 | 未满 24 非终场流局 | 先 CLOSING 再 FULL_GRANT；有 HAND_SETTLED；库存/pending 可入下一局 |
| RW-06 | 终场非和牌 | DISPLAY_ONLY；grant_count=0；零 ITEM_GRANTED；后 MATCH_SETTLED 清空 |
| RW-07 | 终场和牌 | CANCELLED → DISARM → HAND_SETTLED → MATCH_SETTLED 清库存；**不叠** DISPLAY_ONLY |
| RW-08 | 第 24 弃必先 CLOSING+boundary | CLAIM 与 1500ms 并行；汇合后才 settle；荣和抢占 cancel |
| RW-09 | `PTT_END` 边界与伪造负向 | 权威侧：仅 `PTT_END` 事件自身的权威 `server_seq`（由 Worker 分配）参与 `<= closing_boundary` 入窗判定；`>` 丢弃；取消后迟到 final 不跨窗。**负向：** 客户端 `PTT_END` 若携带 `server_seq` 或 `server_seq_ref` 字段 → 稳定 **`FORGERY_REJECTED`**（ERR 控制响应）；**整条请求不归一化、不参与窗口边界**，不写入 utterance 累计 |
| RW-10 | 双边界分离 | closing 只管语音；context 只管评分上下文；不得混用 |
| RW-11 | 唯一 `grace_deadline_at` | 与 CLOSING 同事务；STT 只遵守不另建 |
| RW-12 | 结算屏障公式 | 见 §4.2；和牌立即中止 |
| RW-13 | settle/cancel 冲突 | 已 cancel 再 settle → 拒绝；已 settle 再 cancel → 拒绝 |
| RW-14 | 合法 phase | 仅 `OPEN→CLOSING→SETTLED|CANCELLED` 或 `OPEN→CANCELLED` |
| RW-15 | Alpha 只有和牌可 cancel | 流局/满 24 无和不得 CANCELLED |

### 5.2 评分与分配

| ID | 夹具 | 期望 |
|---|---|---|
| SC-01 | 0..1000 四分项 | `persona + item_tag + public_context + expression`，各项 `[0,1000]`，总分 `[0,4000]` |
| SC-02 | 黄金矩阵（有文本） | 固定 rule_version 下字节级矩阵 |
| SC-03 | 全零矩阵 | 仍产生稳定展示/分配（scoring 出口）；取消出口无矩阵 |
| SC-04 | 静默席 | expression=0，仍占矩阵一行并参与分配 |
| SC-05 | AI 模板 | 每席每窗至多 1 条；首次权威弃牌后按 seed 序列选择；未弃则静默；不生成语音 |
| SC-06 | 同分多解 | 24 种双射先最大化总分，并列取 seat0–3 的 `item_id` 向量字典序最小 |
| SC-07 | 字节级回放 | 同 seed + 事件流 + 文本序列 + rule/assignment version → 出口/矩阵/分配/grant_count 字节一致 |
| SC-08 | 重复 utterance / close | 幂等；不冲突出口、不重复分配 |

### 5.3 库存与武装

| ID | 夹具 | 期望 |
|---|---|---|
| INV-01 | 同玩家同 `item_id` 两个 `item_instance_id` | 独立持有，不合并 |
| INV-02 | 持续被动逐实例注册/触发/叠加 | 按既有 hook 顺序；不替换 |
| INV-03 | 分别 ITEM_USE → CONSUMED/APPLIED | 只作用于指定 instance；无 ITEM_USE 回声 |
| INV-04 | ROOM_SNAPSHOT 恢复多实例 + active/pending | 增量不复活取消窗、不重复发奖 |
| INV-05 | MATCH_SETTLED 整场清空 | 库存/active/pending 全清 |
| INV-06 | UI 真相源 | 增=GRANTED，删=CONSUMED/MATCH_SETTLED，效果=APPLIED；**不从 SETTLED 推断库存** |
| ARM-01 | 首窗 unarmed | 能力对象可创建但被动默认 unarmed |
| ARM-02 | 仅 GRANTED 且 affinity_match 登记 next pending | false / DISPLAY_ONLY / CANCELLED 不登记 |
| ARM-03 | OPEN 消费 pending→active，再常规事件；SETTLED/CANCELLED 后 DISARM active | 顺序可回放 |
| ARM-04 | FULL_GRANT：先登记 next pending 再 DISARM current | pending 不被误清 |
| ARM-05 | 非终场和牌取消 | pending 空；旧库存保留；下一局首窗 unarmed |
| ARM-06 | GAME_BEGIN-only 三项 | `char_washizu_passive_v1` / `char_awai_passive_v1` / `char_toki_passive_v1`：ARM 执行等价激活；DISARM 只停后续 hook，**不回滚**已揭示/清振听 |
| ARM-07 | `SkillResource.params` | arm/disarm **不统一清空或改写**；12 技能语义逐项回归 |

### 5.4 STANDARD 四零（#234 主责，E3/E4/E5 回归）

| 零项 | 断言 |
|---|---|
| 零 RewardWindow | 不创建窗口状态机；无 `REWARD_WINDOW_*` |
| 零库存 | 不创建 ItemInstance 集合；拒绝一切道具命令 |
| 零角色能力武装 | 不创建/不注入可武装被动生产路径；无 `CHARACTER_ABILITY_*` |
| 零语音节点 | 不请求麦克风、不创建采集/PTT/STT 链路 |

---

## 6. 叶子矩阵（35）

图例：

- **最低层**：关闭 Issue 的阻断证据层（可多项）。
- **验证命令/方式**：优先引用 §3 真实入口；尚未落地的服务拓扑在对应 E7 叶子交付后引用其文档化命令。
- **网络声明**：`Y` = 关闭前 PR 必须含「网络端到端未验证」（直至 L5c）；`—` = 纯本地/文档。

### 6.1 E1 去肉鸽与原创大厅（#225–#230，6）

| Issue | 标题摘要 | 关键验收点 | 最低层 | 验证命令/方式 | 阻断依赖 | 网络 |
|---|---|---|---|---|---|---|
| #225 E1-01 | 生产入口换大厅壳 | `main_scene`→大厅壳；冷启动/返回/恢复不进 `run_flow`；无 SessionIntent/Config | L1+L3+手测 | 导航 GUT Red→Green；启动主场景手测；`grep main_scene godot/project.godot` | E0 #221–#224 已关闭 | — |
| #226 E1-02 | 注销 5 Autoload | 生产不注册 SaveSystem/MetaProgress/BattlePass/DailyQuest/SaveToast；无继续 Run 等入口；旧存档仍进大厅 | L1+L3 | 生产无肉鸽依赖 GUT；带 `user://savegame.json` 启动手测 | #225；盘点 #222 | — |
| #227 E1-03 | 1600×900 生产大厅 | ASCII IA 一致；几何 GUT；生产观感非线框；挂点稳定；锚点不重叠 | L0+L1+L4（大厅 L4 须先扩展工具） | UI 几何 GUT；**独立** `godot … --import` 成功（非 test_run_core）；**实现时扩展** `capture_screens.gd` 后才出生产大厅 1600×900 图——**当前工具无大厅条目，不得伪称已有** | #225 | — |
| #228 E1-04 | 练习/匹配+规则抽屉 | 两入口同一抽屉；`SessionIntent` 仅 room/round/mode(+可选角色)；8 组合稳定；无 seed/session/凭证 | L1+L4（抽屉 L4 同须扩展） | Intent 组合 GUT；抽屉展开态截图仅在 capture 扩展并出图后计 L4；扩展前几何 GUT+手测不可冒充「已有大厅 capture」 | #227；输出归 #231 消费 | — |
| #229 E1-05 | 图鉴+BGM/SFX | 过滤 Run-only；**1 首二次元风格、可循环大厅 BGM**（经仓库**既有 new-api 配置下的 Suno** 模型生成并入库）；音量持久化；设置无 E6 语音项；运行时只播入库资产、不调生成 API | L1+手测可听 | 图鉴过滤/BGM GUT；桌面听感手测；生成前最小真实 new-api/Suno 请求确认模型；PR 无密钥、raw/staging 不入库 | #227 | — |
| #230 E1-06 | 12 原创角色 | 闸门 A/B；旧 IP 退出生产；12 `ability_id` 工厂可构建；`portrait_path` 往返；GAME_BEGIN 三项 ID 锁 | L0+L1+L3 | 能力/序列化/资源 GUT；旧 IP 负向审计；import | #222；展示消费者 #227/#229 | — |

### 6.2 E2 统一电脑对战（#231–#235，5）

| Issue | 标题摘要 | 关键验收点 | 最低层 | 验证命令/方式 | 阻断依赖 | 网络 |
|---|---|---|---|---|---|---|
| #231 E2-01 | GameSessionConfig | 稳定枚举；Intent→Config 唯一转换；练习 `[HUMAN,AI,AI,AI]`；to/from_dict；8 组合 | L1+L2 | Config/转换 GUT；非法 Intent 稳定错误 | #228 | — |
| #232 E2-02 | 统一行动/事件 | 既有操作走统一接口；AI 同入口；**仅 fixture** 冻 REWARD/ITEM/ABILITY schema 与偏序；生产不发射 E5 业务事件 | L1+L2 | 接口 GUT + E5 schema fixture/replay（无业务副作用） | #231 | — |
| #233 E2-03 | 东风/半庄 1+3 AI | 局数/场风/庄/本场/立直棒；玩家全操作；分数守恒 | L1+L2+手测 | 固定 seed 整场 GUT；桌面主路径 | #231/#232 | — |
| #234 E2-04 | 标准/欢乐硬隔离 | **四零**见 §5.4；TRASH_TALK 首窗 unarmed；运行中不可切模式；同日麻基础规则 | L1+L2+L3 | 构造期隔离 GUT；伪造欢乐事件负向测试 | #231–#233；角色 #230 | — |
| #235 E2-05 | 结算与导航 | 分数排名；再来一局新 session/seed；回大厅释放资源；无 Run 奖励 | L1+L4+手测 | 结算 GUT；截图/手测返回路径 | #233 | — |

### 6.3 E3 服务端权威与公共匹配（#236–#242，7）

| Issue | 标题摘要 | 关键验收点 | 最低层 | 验证命令/方式 | 阻断依赖 | 网络 |
|---|---|---|---|---|---|---|
| #236 E3-01 | CP + Redis 拓扑 | 独立 Go module；health/readiness；一条命令起 Redis；**根 main.go 不变** | L5a | 真实进程/容器 smoke；HTTP health | E2 可玩闭环 | Y |
| #237 E3-02 | 游客与房间凭证 | guest 会话；令牌绑 room/seat/session/过期；篡改/跨房拒绝；密钥环境变量 | L5a | 真实 CP API 测试 | #236 | Y |
| #238 E3-03 | 公共队列 API | 加入/查询/取消；同规则幂等 ticket；不同 round/mode 不混池 | L5a | 真实 Redis 队列测试 | #237 | Y |
| #239 E3-04 | 30s AI 补位 | 4 真人立即开房；1–3 人满 30s 补 AI；ticket 单房间 | L5a | 可控时钟 + 真实 Redis 并发 | #238 | Y |
| #240 E3-05 | Headless Worker 权威 | 客户端只发命令；牌墙/RNG/AI 仅 Worker；驱动既有 NetworkedBattleController | L5a+L2 相关 | Worker 集成 + 规则 GUT 同源逻辑 | #236/#239 | Y |
| #241 E3-06 | 快照/重连/AI 接管 | 30s 重连；超时 AI 合法行；`ROOM_SNAPSHOT` 使用 ADR 冻结字段 **`snapshot_server_seq`（已应用上限）+ `next_server_seq`（续传）**；modules 包络；测试 provider round-trip；STANDARD 不注册欢乐 provider；**SNAP-01..05 字段名契约** | L5a | 真实断线重连；provider 单测 + 序号字段契约 GUT | #240 | Y |
| #242 E3-07 | 幂等/非法/回放 | **CID-01..03**（含首次**处理**/拒绝也缓存）；**ERR-01** 错误通道；越权/伪造（含客户端 `ITEM_GRANTED` 等）→ 控制 ERROR；state hash；`next_server_seq` 增量连续性；同 seed 摘要；M12 replay；SNAP-02/05 + SNAP-04 | L5a+L2 | 对抗测试 + replay E2E + CID + ERR-01 + SNAP-02..05；断言 CONFLICT/FORGERY 无 `server_seq`/`state_hash`、不进业务回放 | #240/#241 | Y |

**command_id 指纹冲突（#242 强制，稳定夹具 CID-*）：**

| ID | 断言 |
|---|---|
| CID-01 | **首次处理**命令时（**含首次拒绝**）即绑定/缓存指纹 = `session_id` + `room_id` + `seat` + `kind` + **规范化 payload**，并缓存**该次原处理结果**（成功结果或原拒绝 ERROR）；**`client_seq` 不参与**指纹 |
| CID-02 | 同 `command_id` + **同指纹**：返回**首次处理**缓存的原结果（含原拒绝）；**不**发新业务事件、**不**分配新 `server_seq`、状态不变 |
| CID-03 | 同 `command_id` + **不同指纹**：以 **ERROR 控制响应**返回稳定码 **`COMMAND_ID_CONFLICT`**；响应**无** `server_seq`、**无** `state_hash`；**不**进入权威业务回放日志；**不**改状态、**不**分配新 `server_seq`、**不**覆盖首次处理结果；**禁止** `COMMAND_DUPLICATE` 或同义别名 |

**错误通道契约（#242 强制，稳定夹具 ERR-*；HTTP/WS 复用）：**

| ID | 断言 |
|---|---|
| ERR-01 | **所有权威业务 `ServerEvent` 必有 `server_seq`**。**`ERROR` 是控制响应**：不属于业务 `EventKind`、**不进**权威业务回放日志、**不含** `server_seq` / `state_hash`。HTTP 与 WS **复用**同一逻辑 `code` / `message`（及稳定错误码枚举） |

**E3 范围边界：** #241 只冻包络与测试 provider；#242 只做通用幂等/指纹冲突/错误通道/伪造拒绝/包络连续性。三出口、库存、武装的**真实 Worker 回放**归 #252/#253。

### 6.4 E4 实时语音与双层 STT（#243–#248，6）

| Issue | 标题摘要 | 关键验收点 | 最低层 | 验证命令/方式 | 阻断依赖 | 网络 |
|---|---|---|---|---|---|---|
| #243 E4-01 | PTT/PCM 采集播放 | 仅按下采集；20ms 帧元数据；松开/离房释放；STANDARD 不申请麦；客户端 `PTT_END` **不得**携带 `server_seq`/`server_seq_ref` | L1+L5b（**仅采集组件**） | 单元 + 真实麦克风手测；**关闭不依赖 #247/#248**（§1.3） | #234 隔离 | Y |
| #244 E4-02 | 四座位语音中继 | 令牌校验；只广播他席+可送 STT 挂点；有界丢帧；断线清缓冲；牌局命令通道隔离；客户端带 `server_seq`/`server_seq_ref` 的 `PTT_END` → **`FORGERY_REJECTED`**（RW-09 负向，ERR-01） | L5b（**双端环回**） | 双客户端真实环回；伪造 `PTT_END` 负向（整条不归一化、不参与窗口边界） | #243/#240 | Y |
| #245 E4-03 | whisper.cpp 模型管理 | 清单含版本/URL/大小/SHA-256；断点续传；失败不破主游戏；mac/Win 同逻辑 | L5b（**本地模型生命周期**）+L5d 逻辑 | 下载/校验集成；干净目录 smoke | #243 | —/Y |
| #246 E4-04 | 中英日字幕 | 临→终替换；超时消失不挡操作；公共场本地字幕不进权威窗/不触发 GRANTED；AI 模板不伪装麦 | L1+L4+L5b（**字幕展示**） | UI GUT + 双端字幕手测 | #244 | Y |
| #247 E4-05 | faster-whisper 权威 | utterance 稳定 ID；绑 room/seat/hand/window/权威 ptt `server_seq`；遵守 #252 双边界与唯一 deadline；和牌中止宽限；不持久化；**拒绝**已 `FORGERY_REJECTED` 的客户端伪序号 utterance（RW-09） | L5b（**主 STT**） | 真实 faster-whisper + RW-09..12（含伪造负向）；核心不 mock | #244；边界权威 #252 | Y |
| #248 E4-06 | new-api 回退 | 仅最终片段；密钥不落日志；熔断快失败；同 utterance 主备最多计分一次 | L5b（**备 STT**） | 真实超时触发回退的最小请求 + 熔断测试；核心不 mock | #247 | Y |

### 6.5 E5 确定性垃圾话与道具（#249–#254，6）

| Issue | 标题摘要 | 关键验收点 | 最低层 | 验证命令/方式 | 阻断依赖 | 网络 |
|---|---|---|---|---|---|---|
| #249 E5-01 | 规则库 13+ | 12 角色五类 affinity；道具稳定 id/标签/rule_id；四分项 schema；全零+有文本 fixture；AI 模板确定性；无 E6 动作 | L1+L2 | 规则库 GUT；IP 负向；fixture 字节锁 | #230；本地规则可在 E2 后开工 | — |
| #250 E5-02 | TextAnalyzer | 标准化；关键词/模板；1000 基点整数；rule 每窗每席最多一次；无 item_id/发奖；字节级一致 | L1+L2 | Analyzer GUT；重复 final 幂等 | #249 | — |
| #251 E5-03 | 上下文评分 | 公开上下文事件集；绑 context_boundary；CANCELLED 不评分；静默行；练习=Worker 同纯逻辑；黄金矩阵 | L1+L2 | 评分 GUT SC-01..07 | #250 | — |
| #252 E5-04 | 六巡窗+分配 | **RW-00**（开局后、首 `TURN_PROMPT` 前 `REWARD_WINDOW_OPENED`；`seed/hand_seq/window_index/rule_version` 确定性公开恰好 4 个互不重复 `item_id`，同输入奖池顺序字节级一致，重复 `item_id` 失败）+ §5.1 其余 RW-01..15；§5.2 SC-*；独占 REWARD_WINDOW_*；不发 ITEM_GRANTED；双边界+屏障+三出口 | L1+L2+L3；公共场加 L5a 回放 | 固定 seed 窗口 GUT（含 RW-00 奖池字节锁）；与 #232 fixture 偏序一致 | #232 schema；公共接线 #240 | Y（公共） |
| #253 E5-05 | 库存/武装/回放 | §5.3 INV/ARM；FULL_GRANT 顺序 §4.3；ITEM_USE 命令语义；snapshot provider；STANDARD 拒绝道具 | L1+L2+L3+L5a 回放 | 双实例/arm/disarm/不回滚 GUT；Worker 同事件流回放 | #252；DTO 包络 #241 | Y（公共） |
| #254 E5-06 | 反馈 UI+夹具 | 奖池/24 进度/三出口文案；多实例可操作；滚动分页无容量上限；1600×900；基线指标 | L1+L4+手测 | 几何 GUT；`capture_screens`；欢乐场手测 | #252/#253；字幕镜像 #246 | Y |

### 6.6 E7 部署与桌面 Alpha（#255–#259，5）

| Issue | 标题摘要 | 关键验收点 | 最低层 | 验证命令/方式 | 阻断依赖 | 网络 |
|---|---|---|---|---|---|---|
| #255 E7-01 | 容器测试拓扑 | 一条文档化命令起 CP+Redis+STT+Worker；health/readiness/端口；密钥环境变量；不扩根 main.go | L5a | 容器构建 + 四服务健康 | E3/E4 服务存在 | Y |
| #256 E7-02 | Worker 租约/容量 | 续租；原子分配不超卖；失联停新房；可重注册 | L5a | 真实 Redis 故障/多 Worker | #255/#240 | Y |
| #257 E7-03 | macOS 包 | 依赖齐全不内置大模型；首次欢乐权限+下载进度；标准场无麦也可玩；公网整场 | L5d+L5c | 干净 macOS 用户目录 smoke | #245/#255 | Y→L5c |
| #258 E7-04 | Windows 包 | 同上；防火墙提示；断点下载+SHA-256；公网整场 | L5d+L5c | 干净 Windows smoke | #245/#255 | Y→L5c |
| #259 E7-05 | 公网四端+Alpha 清单 | **场景 A：4 真人完整整场**；**场景 B：1–3 真人 + 服务端 AI 补位完整整场**（两场景均须独立证据）；东风/半庄、标准/欢乐至少各一场；STT 延迟/Worker 容量/资源基线；回滚步骤；**无 E6 审计**；汇总全部 Epic DoD | L5c+L5d | 场景 A/B 分列证据包；负载 smoke；§8 清单全绿 | E1–E5、#255–#258 | L5c 完成后可去掉「未验证」 |

---

## 7. 叶子覆盖校验（闭合性）

| Epic | 叶子号 | 个数 |
|---|---|---|
| E1 | #225 #226 #227 #228 #229 #230 | 6 |
| E2 | #231 #232 #233 #234 #235 | 5 |
| E3 | #236 #237 #238 #239 #240 #241 #242 | 7 |
| E4 | #243 #244 #245 #246 #247 #248 | 6 |
| E5 | #249 #250 #251 #252 #253 #254 | 6 |
| E7 | #255 #256 #257 #258 #259 | 5 |
| **合计** | **#225–#259 连续** | **35** |
| **E6** | **无行、无占位、无同义模块** | **0** |

校验命令（文档维护用）：

```bash
# 矩阵中出现的叶子 Issue 号应恰为 225..259
rg -o '#[0-9]+' docs/superpowers/specs/2026-07-22-e0-04-acceptance-test-matrix.md \
  | tr -d '#' | sort -n | uniq | awk '$1>=225 && $1<=259'
# 期望：225 到 259 共 35 行；且全文无「E6」业务模块验收行（仅允许「无 E6」禁令表述）
```

---

## 8. 桌面 Alpha Definition of Done

以下全部满足才可宣称 **桌面 Alpha 完成**（对应 PRD §7.2 + #259）：

1. **大厅无肉鸽：** #225/#226/#235 证据齐；启动/对局/结算/重赛/返回不读 Run 状态。
2. **8 模式组合：** #228+#231；练习与公共均可达东风/半庄 × 标准/欢乐。
3. **匹配可靠：** #238/#239；1–4 真人只进一房；30s AI 补位。
4. **STANDARD 四零：** #234 及 E4/E5 负向回归。
5. **欢乐场奖励闭环：** #249–#254；§5 夹具全绿；多实例库存与 arm/disarm/不回滚。
6. **权威可回放：** 同 seed+命令流+rule/assignment version → 牌局与发奖摘要一致（#242/#252/#253）；快照续传认 `snapshot_server_seq` / `next_server_seq`。
7. **12 原创角色：** #230；无旧 IP；能力映射回归。
8. **无 E6：** 仓库与 GitHub 审计 `S-NO-E6-01`（#259）：无 M6、`scope:e6`、举报/静音/语音总开关/自动禁言实现或占位 API。
9. **双端包：** #257/#258 干净环境安装 + 模型按需下载 + 可连同一公网房整场。
10. **四端公网证据（#259 L5c，两场景均须）：** **(A) 4 真人完整整场**；**(B) 1–3 真人 + AI 补位完整整场**；另含东风/半庄、标准/欢乐覆盖，以及 STT 延迟、Worker 容量、资源基线与回滚记录。
11. **验证门禁：** 相关变更按 §1：L0 独立成功 import；L1–L3 GUT；UI L4（大厅截图仅扩展后）；服务 L5a；语音/STT 按 §1.3 分量证据；最终 L5c/L5d。
12. **网络措辞：** 在第 10 条达成前，所有公共网络相关 PR 保留「网络端到端未验证」。

### 8.1 成功指标 ↔ 证据归属（与 PRD 对齐）

| 指标 | 最终证据层 | 负责叶子 |
|---|---|---|
| S-MODE-01 | L1 | #228 #231 |
| S-PRACTICE-01 | L2+手测 | #233 #235 |
| S-MATCH-01 | L5a | #238 #239 |
| S-AUTH-01 | L5a+L2 | #240 #242 |
| S-ISOLATION-01 | L1+L3 | #234 |
| S-REWARD-01 | L2+L3+（公共）L5a 回放 | #249–#253 |
| S-ORIGINAL-01 | L0+L1+L3 | #230 |
| S-NO-ROGUE-01 | L1+L3 | #225 #226 #235 |
| S-DESKTOP-01 | L5c+L5d | #257 #258 #259 |
| S-NO-E6-01 | 审计 | #259 |

---

## 9. 跨切面检查清单（每个业务 PR）

- [ ] 关联叶子 Issue；中文 PR；worktree/任务分支。
- [ ] Red → Green → Refactor（功能/缺陷）；结果附命令摘要。
- [ ] 触及资源/`class_name` → **独立**运行 `godot --headless --path godot --import` 且 **exit 0**（L0）；**不得**用 `scripts/test_run_core.sh`（内部 `import \|\| true`）冒充 L0。
- [ ] 触及 core/battle/skills/integration → `scripts/test_run_core.sh` 或等价 GUT 绿（L2，与 L0 分离记录）。
- [ ] UI → 1600×900 几何 GUT；若声称 L4 截图，路径须对应当前 `capture_screens.gd` **真实已有**标签（Run/牌桌等）。生产大厅/抽屉截图仅在 #227/#228 扩展工具并出图后可引用。
- [ ] 网络相关 → 正文含「网络端到端未验证」或 L5c 场景 A/B 证据链接。
- [ ] 语音/STT → 只声称本叶子负责组件的真实证据（§1.3）；不反向依赖未交付下游；核心不 mock。
- [ ] 快照/重连 → 使用 `snapshot_server_seq` / `next_server_seq`；强制 `envelope.server_seq == payload.snapshot_server_seq` 且 `next_server_seq == snapshot_server_seq + 1`（SNAP-02/05）；不用 `last_server_seq` 别名。
- [ ] 命令幂等（#242）→ 指纹在**首次处理**（含首次拒绝）时绑定；同指纹回放原结果；冲突以无 `server_seq`/`state_hash`、不进业务回放的 ERROR 返回 `COMMAND_ID_CONFLICT`；禁 `COMMAND_DUPLICATE`。
- [ ] 错误通道（ERR-01）→ 业务 `ServerEvent` 必有 `server_seq`；`ERROR` 为控制响应、非业务 EventKind、不进回放、无 `server_seq`/`state_hash`；HTTP/WS 复用 `code`/`message`。
- [ ] 语音伪造（RW-09）→ 客户端 `PTT_END` 携带 `server_seq`/`server_seq_ref` → `FORGERY_REJECTED`；整条不归一化、不参与窗口边界。
- [ ] 无 E6 引入；STANDARD 路径无欢乐模块泄漏。
- [ ] 事件发射符合 §4 所有权；FULL_GRANT 顺序无第二 GRANT 事件。
- [ ] 不扩张根 `main.go`；不把生产主路径接回 `ui/run/run_flow.tscn`。
- [ ] 核心逻辑无 mock 顶替。

---

## 10. 文档维护

- 需求变更：先改 PRD / Epic / Issue，再改**本矩阵**，最后改代码。
- 本文件路径固定：`docs/superpowers/specs/2026-07-22-e0-04-acceptance-test-matrix.md`（E0-04 唯一矩阵文件）。
- 禁止新增根目录进度报告 markdown；验证摘要写入 PR / Issue 评论。

---

## 11. 修订记录

| 日期 | 说明 |
|---|---|
| 2026-07-22 | 初版：覆盖 #225–#259 共 35 叶；证据层级；版本策略；RewardWindow/库存/武装夹具；事件所有权与 FULL_GRANT 顺序；STANDARD 四零；真实 CI/脚本/capture 能力；网络未验证声明；macOS/Windows Alpha DoD；明确无 E6。 |
| 2026-07-22 | P2 修订：快照字段改为 `snapshot_server_seq`/`next_server_seq` + SNAP 契约；L4/§3.3 澄清当前无生产大厅截图；L0 独立成功 import 与 L2 `\|\| true` 分离；L5b 证据族与叶子分量责任（#243 不反向依赖 #247/#248）；#259 场景 A/B；#229 二次元/Suno/new-api 措辞。 |
| 2026-07-22 | P2：§5.1 新增 **RW-00**（权威开局后、首条 `TURN_PROMPT` 前 `REWARD_WINDOW_OPENED`；确定性 4 件互不重复奖池、字节级顺序、重复 `item_id` 失败）；#252 叶子行显式引用。 |
| 2026-07-22 | P2（ADR）：SNAP-02 冻结 `envelope.server_seq == payload.snapshot_server_seq` 且 `next_server_seq == snapshot_server_seq + 1`；SNAP-05 round-trip 覆盖该关系；#242 补 command_id 指纹 CID-01..03（`COMMAND_ID_CONFLICT`，禁 `COMMAND_DUPLICATE`）。 |
| 2026-07-22 | P2（ADR）：CID-01「首次处理」（含拒绝）绑定指纹与原结果；CID-03 CONFLICT 为无 seq/hash、不进回放的 ERROR；新增 ERR-01 错误通道；RW-09/#244/#247 客户端 `PTT_END` 伪序号 → `FORGERY_REJECTED`。 |
