# 多人麻将与“嘴强道具”Master Implementation Plan

> 规划入口：[Issue #212](https://github.com/jingx8885/mahjong-game/issues/212)
> Master Epic：[Issue #213](https://github.com/jingx8885/mahjong-game/issues/213)
> 产品契约：[`2026-07-22-multiplayer-trash-talk-prd.md`](../specs/2026-07-22-multiplayer-trash-talk-prd.md)
> Epic PRD：[`2026-07-22-multiplayer-trash-talk-epics.md`](../specs/2026-07-22-multiplayer-trash-talk-epics.md)
> Backlog：[`2026-07-22-multiplayer-trash-talk-issue-backlog.md`](./2026-07-22-multiplayer-trash-talk-issue-backlog.md)

## 1. 执行原则

1. 规划 PR 只包含本计划及配套 PRD/backlog；人工合并前不改业务代码。
2. 业务执行顺序为 `E0 → E1 → E2 → E3 → E4 → E5 → E7`；E5 的纯本地规则可在 E2 完成后先行，但 E5 完成依赖 E4。
3. 每个叶子 Issue 单独建立 `codex/<issue>-<slug>` 分支和 worktree，基于当时最新 `origin/main`。
4. 每个功能/缺陷 Issue 严格采用 Red → Green → Refactor；文档、纯发布按对应最小验证门禁。
5. 每个 PR 使用中文标题/正文，包含影响模块、验证命令和真实结果，关联 `Closes #<issue>`，指派当前维护者，等待人工合并。
6. 不直接推送 `main`，不自动合并，不把多个叶子 Issue 偷渡到同一 PR。
7. 意外代码、脚本、配置、锁文件或业务资源出现时立即停止并询问；孤立 `.uid` 等本地元数据只忽略，不提交。
8. 每个叶子 Issue 必须先运行独立 Grok Plan 会话；主 agent 审核计划、依赖、文件边界和 Red 用例后，才允许在该 Issue 的独立 worktree 启动 Grok 写权限会话。
9. Grok 实现后由主 agent 独立审阅完整 diff，并按风险亲自复跑 import、局部/全量 GUT、截图、Go/Redis/WS 或真实第三方最小请求；不得以 Grok 自述或 `--check` 结果代替验收。发现 P0/P1/P2 时，将文件、失败命令、复现证据和最小修复边界发回原 Grok 会话，修复后重新走同一验证门禁。
10. 只并行开发依赖图上互不阻塞、worktree 与主要写文件不重叠的叶子 Issue；同一 Issue/同一 worktree 同时只允许一个写入者。每个 PR 仍单独人工合并，后继 Issue 必须基于最新 `origin/main`，不得从未合并兄弟分支叠加。

## 2. 分阶段实施

### Phase 0：E0 产品与工程基线

#### E0-01 模式矩阵

- 从总 PRD 提取 8 种入口组合、启用能力、失败提示和结算出口，形成版本化模式契约。
- 将 Web/移动、排位、私人房间、肉鸽、E6 写入统一非目标，禁止后续 Issue 自行恢复。
- 验证：需求 ID 与 39 个叶子 Issue 双向链接，无未归属成功标准。

#### E0-02 代码/IP 盘点

- 用 `rg` 和资源清单定位生产 Run、Autoload、导航、存档、12 角色、能力、道具和立绘。
- 对每项标记：`remove-from-production`、`reuse`、`originalize`、`legacy-no-touch`。
- 角色盘点必须将旧 ID/显示名/能力 ID/立绘引用逐一映射到原创迁移项，但不在该 Issue 制作资产。

#### E0-03 ADR 与协议

- 先以仓库现有 `BattleController`、`NetworkedBattleController`、`LocalLoopbackServer`、`Action`、`NetworkedEvent` 为事实源。
- 固化独立 Go Control Plane、Redis 临时状态、Godot Headless Worker 权威牌局、语音/STT 服务的边界。
- 固化 HTTP、牌局 WebSocket、语音 WebSocket 包络、版本字段、稳定错误码，以及 RewardWindow 三出口、`REWARD_WINDOW_CANCELLED` 和条件式 `ITEM_GRANTED` 契约。
- 根目录 `main.go` 不扩张；新增服务必须使用独立目录和 Go module。

#### E0-04 测试矩阵

- 建立行为到测试的映射：纯逻辑 GUT、真实牌局集成、UI 几何/截图、真实 Redis/WebSocket、第三方最小请求、桌面包、最终公网四端。
- 固化协议/规则兼容：Alpha 只支持协议 v1；不兼容版本在握手阶段拒绝，不做静默降级。
- 固化完成声明：网络未完成真实公网验证时必须写“网络端到端未验证”。

**Phase 0 出口：** #221–#224 关闭；PRD、ADR、测试矩阵与代码事实一致。

### Phase 1：E1 去肉鸽与原创大厅

#### 实施顺序

1. **#225 入口壳**：先写主场景/导航 Red，再建立可启动、可返回的大厅入口壳；可用默认练习烟测证明现有桌面可挂载，但不实现抽屉、`SessionIntent` 或正式配置。
2. **#226 肉鸽依赖退出生产**：按 E0 清单解除 RunState、经济/章节 UI 与新入口耦合；后续清理已物理删除 Run UI、存档/抽卡/章节脚本及 legacy 测试。
3. **#227 生产级大厅**：按 ASCII 搭 1600×900 布局和响应式锚点；先几何测试，再完成原创背景、角色展示、入口卡片和抽屉动效，不以线框占位作为完成态。
4. **#228 规则抽屉与 `SessionIntent`**：建立选择状态并输出 UI 意图；覆盖键鼠焦点、取消和返回；禁止在本 Issue 定义正式 `GameSessionConfig`。
5. **#229 图鉴/BGM/SFX**：图鉴过滤 HP、金币、卡包、声望、战令等 Run-only 内容；补齐真实 BGM 播放链路，并通过既有 new-api Suno 模型交付 1 首可循环二次元大厅 BGM；不加入语音设置。
6. **#230 角色原创化**：先确认 12 人身份/能力/美术 brief，再确认小批量样张；两道闸门通过后批量生成全新立绘。TDD 覆盖 12 个能力工厂映射、当前后 6 注入缺口和 `portrait_path` 序列化；PNG 入库后执行 Godot import。

#### UI 验收

- 复杂 UI 实施前以已确认 ASCII 为唯一布局方向，不再另做雀魂像素复刻。
- #227/#228/#229 每个 PR 都运行相关 GUT、主路径手测；#227 和 #228 必须附 `capture_screens.gd` 的 1600×900 截图。
- 原创资源进入生产前先做文件名、尺寸、透明度、引用和版权来源审计。
- BGM/立绘生成只使用既有 new-api/Grok 本地配置；调用前按真实模型行为做最小请求，凭证不入库；`_raw_*`、`_staging*` 和失败中间产物不提交。
- 运行时客户端不调用 Suno、Grok、image-2 或 nano banana，只消费已确认并入库的最终资产。

**Phase 1 出口：** 启动即大厅；肉鸽生产入口不可达；12 角色原创化；#225–#230 关闭。

### Phase 2：E2 统一电脑对战

#### 核心实现

- **#231**：首次新增纯数据 `GameSessionConfig`，稳定枚举值与验证/序列化；拥有 `SessionIntent → GameSessionConfig` 的唯一转换，练习启动器只消费正式配置，不消费 RunState 或 UI 裸字典。
- **#232**：将玩家和 AI 的出牌、鸣牌、立直、和牌、跳过、道具命令统一为命令；将结果统一为事件，并冻结 `REWARD_WINDOW_OPENED/CLOSING/SETTLED/CANCELLED`、仅 `FULL_GRANT` 允许出现的四次 `ITEM_GRANTED` 与 `CHARACTER_ABILITY_ARMED/DISARMED` 的可回放事件 kind/schema 和合法偏序。#232 的生产适配层不得发射任何 `REWARD_WINDOW_*`、`ITEM_GRANTED` 或 `CHARACTER_ABILITY_*`，不得推进窗口 phase 或写库存/active/pending；测试只以 fixture 验证 schema、偏序和 replay 消费。全部 `REWARD_WINDOW_*` 业务发射归 #252，条件式 `ITEM_GRANTED` 与库存/武装业务事件归 #253。`ITEM_USE` 只作为命令，结果只使用 `ITEM_CONSUMED` 和/或 `ITEM_APPLIED`，不定义回声事件。优先适配现有引擎，不复制规则层。
- **#233**：用真实 `GameDriver` 参数支持东风 4 局和半庄 8 局，完成玩家 seat 0 + 3 AI 的可玩闭环。
- **#234**：在会话构造阶段决定模块依赖；STANDARD 不实例化角色/道具/RewardWindow/Momentum/语音，TRASH_TALK 才创建角色能力对象并注入其余模块；角色被动首窗默认 unarmed。
- **#235**：整场结算展示四席分数/排名；重赛创建新 session/seed；退出释放场景与音频资源。

#### TDD 门禁

1. Red：非法配置、模式隔离、东风/半庄推进、结算/导航测试先失败。
2. Green：最小接线复用现有 `BattleController`、`GameDriver`、AI。
3. Refactor：仅在测试全绿后消除新接线产生的重复。
4. 回归：相关 battle/AI/UI GUT + 全量 GUT；真实桌面主路径。

**Phase 2 出口：** 练习场 4 种组合完整可玩；#231–#235 关闭。

### Phase 3：E3 服务端权威与公共匹配

#### #236 Control Plane 骨架

- 独立 Go module 提供配置、`/healthz`、`/readyz` 和优雅关闭。
- 用本地真实 Redis 建立可复现开发拓扑；测试先启动 Redis，不用内存 map 冒充队列核心。
- 根 `main.go`、根 Dockerfile/start.sh 的健康检查职责保持不变。

#### #237 游客与房间凭证

- 游客 session token 签名包含 guest ID、显示名、到期时间。
- 房间 token 独立签发并绑定 room/seat/session/expiry，跨房、跨座位、过期和篡改必须失败。
- 密钥只读环境变量；日志不输出 token。

#### #238–#239 队列与 AI 补位

- Redis key 按 `round_kind:game_mode` 隔离；加入、查询、取消幂等。
- 用可注入时钟先写 30 秒边界 Red；四真人立即匹配，超时原子创建房间并补齐 AI。
- ticket 到房间必须一对一；并发消费者不能重复分配。

#### #240 Worker 权威

- 将现有 loopback 仲裁器演进为独立 Godot Headless Worker 入口。
- Worker 拥有 seed、牌墙、命令合法性、AI、角色/道具和事件序号；客户端只投影事件。
- `NetworkedBattleController` 从“一次性整局重放”演进为快照 + 增量事件消费，不在客户端重算隐藏信息。

#### #241–#242 重连与对抗测试

- Worker 保留 30 秒 seat lease；超时 AI 接管，玩家本局内可在安全行动边界取回。
- 快照以最后 `server_seq` 为续传边界；#241 在 E3 只实现基础包络、稳定 module key/version 与 snapshot provider 组合/恢复接口，并以测试 provider 验证透明 round-trip，不等待或猜测 E5 字段。
- 每个 `command_id` 缓存处理结果；重复提交返回原结果。
- #242 在 E3 用真实 Worker 测试非法座位、错回合、非法牌、客户端伪造服务端专属 `ITEM_GRANTED`、重复命令、事件缺口、state hash 分叉与测试 provider 快照连续性；不提前实现 RewardWindow 业务。
- #232 提供通用 replay 消费骨架；#252/#253 在 E5 提供并验证真实三出口、库存/武装 provider、冲突出口和展示零发奖回放，保留 M12 replay E2E 并证明同 seed/命令流确定性。

**Phase 3 出口：** 公共匹配可在本地真实多进程拓扑运行；#236–#242 关闭。公网未验证时仍明确标注未端到端验证。

### Phase 4：E4 实时语音与双层 STT

#### 第三方接入前置

1. 核对 Godot 4.6 的 `AudioEffectCapture`、`AudioStreamMicrophone`、`AudioStreamGenerator` 和 `WebSocketPeer` 官方接口/仓库现有用法。
2. 建立真实麦克风 loopback 最小场景，测得实际 PCM 格式、缓冲和权限行为。
3. 核对 whisper.cpp 模型发布清单、许可证和平台构建方式；用小 fixture 验证下载与 SHA-256。
4. 对配置的 new-api `/v1/audio/transcriptions` 做最小真实请求，记录认证、multipart 字段、模型名、响应和错误码。无法实测则停止 #248 业务接入并请求确认。

#### 实施顺序

- **#243**：PTT 状态机、权限、PCM16/16k/mono/20ms 分帧、播放和释放；STANDARD 无语音节点。
- **#244**：独立语音 WebSocket；房间/座位鉴权、有界队列、丢弃旧帧；不写磁盘。
- **#245**：模型 manifest、断点续传、SHA-256、临时文件与原子启用、平台可写路径。
- **#246**：partial/final 字幕按 utterance 替换、座位指示、超时布局；公共本地字幕不得进入评分。实际到账反馈只认 `ITEM_GRANTED`；`SETTLED(DISPLAY_ONLY)` 只展示“未发放”，取消只展示作废。
- **#247**：VAD 分段与 faster-whisper small；最终文本绑定 room/seat/hand_seq/utterance/window。#252/Worker 是 `grace_deadline_at` 与窗口相位的唯一权威；#247 不创建第二个权威计时器，只按 Worker 给出的边界/deadline 返回或取消 final。第 24 弃后宽限与 CLAIM 并行，荣和立即中止，迟到结果不跨窗。
- **#248**：主服务超时才回退 new-api；只发送最终片段；去重、熔断、恢复探测和密钥日志红线。

#### 真实验证

- 单机 loopback → 双客户端局域网 → 四客户端测试拓扑逐级验证。
- STT 使用真实中英日录音夹具和现场麦克风，不用 mock 顶替核心识别。
- 测量 PTT 到播放、PTT 到 partial/final 字幕延迟，并记录硬件与模型。

**Phase 4 出口：** 欢乐场实时语音/字幕与权威转写完整；标准场无语音；#243–#248 关闭；不存在任何 E6 能力。

### Phase 5：E5 确定性垃圾话与道具

#### #249 内容规则库

- 为 12 名原创角色建立五类 Momentum affinity 与中英日原创 13+ 文案。
- 为所有可发放道具建立稳定 ID、属性标签、公开上下文、优先级、具体度和多语言模式；同一玩家可跨窗口重复持有同一 item 的不同 `item_instance_id`。
- 为 AI 建立版本化角色/公开牌局情境文本模板；每 AI 席每窗至多一条，在该席本窗第一次权威弃牌后确定性选择；进入 `FULL_GRANT/DISPLAY_ONLY` 前仍未弃牌则按静默，`CANCELLED_BY_WIN` 不评分；AI 不合成语音。
- 规则 schema 固定四个 0..1000 整数分项、每 seat/window/rule 只计一次，并提供全零与有文本的黄金数值 fixture。
- schema 校验必须保证角色、道具、语言和 rule ID 无缺失/重复。

#### #250–#252 分析与决胜

- 权威开局状态提交后、第一条 `TURN_PROMPT` 前开启首窗并公开四件道具；首窗被动均为 unarmed。
- Red：中英日大小写、全半角、标点、空白、正例、反例、真人/AI/静默、满 24 + CLAIM 全过/鸣牌/荣和、中途自摸、非终场流局、终场展示、全零矩阵、同分多解和重复出口。
- 标准化后只执行关键词/模板，不调用 LLM、向量服务或随机数；`Momentum.skill_effect_multiplier()` 不进入生产路径。
- 使用权威端公开牌局事件生成上下文（练习=本地权威，公共=Worker），不接受客户端自报，不读取隐藏牌。
- #252/Worker 独占全部 `REWARD_WINDOW_OPENED/CLOSING/SETTLED/CANCELLED` 的业务发射，以及窗口 phase、三值 `window_exit`、`closing_boundary_server_seq`、`context_boundary_server_seq`、`grace_deadline_at` 与结算屏障的写入；`REWARD_WINDOW_SETTLED.outcome` 仅两值，取消事件只带 `cancel_reason=CANCELLED_BY_WIN`。其他模块不得从本地时间或 UI 推断。第 24 弃立即 CLOSING，CLAIM 与剩余宽限并行；荣和抢占 cancel；无和牌时以 CLAIM 完成序号冻结上下文。没有开放 CLAIM 的流局/终场非和牌在权威结果判定事务内直接令 `claim_is_terminal=true`，并以该判定序号冻结上下文。非终场流局走 `FULL_GRANT`；终场非和牌走 `DISPLAY_ONLY`。
- 顺序唯一，屏障为 `claim_is_terminal AND (all_eligible_utterances_are_terminal OR now >= grace_deadline_at)`：满 24 无和牌 `CLOSING → SETTLED(FULL_GRANT) → 4×ITEM_GRANTED → DISARM → next OPEN/ARM`，不发 HAND_SETTLED；非终场流局 `CLOSING → SETTLED(FULL_GRANT) → 4×ITEM_GRANTED → DISARM → HAND_SETTLED → 下一局 OPEN/ARM`；和牌 `CANCELLED → DISARM → HAND_SETTLED`；终场非和牌 `CLOSING → SETTLED(DISPLAY_ONLY) → DISARM → HAND_SETTLED → MATCH_SETTLED`。#252 发齐窗口事件但不发 `ITEM_GRANTED`；#253 在同一权威事务内唯一发出条件式 `ITEM_GRANTED` 并更新库存/pending。不存在第二种 GRANT 事件。
- 生成 4×4 定点整数矩阵，枚举 24 种双射，按总分最大、seat 0–3 的 item ID 向量字典序最小稳定决胜。
- 幂等使用 `window_id`、出口、规则/分配版本、utterance ID 与权威事件序号，不使用客户端时钟；同窗 settle 与 cancel 互斥，展示出口禁止后续 grant。

#### #253 道具权威事件

- `REWARD_WINDOW_OPENED/CLOSING/SETTLED/CANCELLED`、条件式四次 `ITEM_GRANTED`、`ITEM_CONSUMED`、`ITEM_APPLIED`、`CHARACTER_ABILITY_ARMED/DISARMED` 进入统一事件流和回放。`ITEM_USE` 仅是命令，不是事件；新增库存只认 GRANTED，移除只认指定实例 CONSUMED 或 MATCH_SETTLED，效果只认 APPLIED；`SETTLED` 不直接改库存。
- 库存只由权威端改变（练习=本地权威，公共=Worker）；STANDARD 在协议入口拒绝道具命令。
- 库存为同场多件实例集合，Alpha 不设人为容量上限；同一玩家可重复持有同 `item_id`，每次使用/消耗只作用于命令指定的 `item_instance_id`。相同 `item_id` 的持续被动实例各自注册、各自触发，并按既有 hook 顺序叠加，不得按 ID 去重。道具持续到使用/消耗或整场结束，不被新奖励替换。未来套装效果另行立项，本期不实现套装计算或 UI。
- affinity 只在实际 `ITEM_GRANTED` 时判定；武装状态拆为 `active_window_id/pending_window_id`。目标 OPEN 原子消费 pending 为 active；GRANT 可写下一窗 pending；DISARM 只清当前 active，不能清刚登记的 next pending。`DISPLAY_ONLY/CANCELLED_BY_WIN` 不登记新 pending。
- arm 只门控角色 hook 是否接收事件；不得统一清空 `SkillResource.params`，12 个技能的既有状态生命周期由 #253 逐项回归保持。
- 当前 `GAME_BEGIN` 三项 `char_washizu_passive_v1`、`char_awai_passive_v1`、`char_toki_passive_v1` 由 #253 在 `CHARACTER_ABILITY_ARMED` 上执行各自现有 hook 的等价激活效果；#230 冻结原始语义，禁止改绑到 `yamagan_v1`、`toki_foresight_v1` 等近义但身份不同的卡池能力。DISARM 只停止后续 hook 派发，ARM 时已经发生的信息揭示、清振听等一次性权威副作用不回滚。
- 复用现有道具/遗物钩子的牌局效果，移除其商店、金币、Run 获取方式，不重新实现同一效果。

#### #254 UI 与平衡

- 展示四件公开奖池、窗口进度、final 字幕、四席分配、多件库存、道具到账/使用/效果和角色被动武装；#254 的库存数字只投影 `ITEM_GRANTED/ITEM_CONSUMED/MATCH_SETTLED`，效果只投影 `ITEM_APPLIED`，不得从 `SETTLED` 或动画推断。累计实例滚动/分页且不得透露隐藏牌。
- UI 必须区分 `FULL_GRANT` 实际到账、`DISPLAY_ONLY`“仅本场统计，未发放”和 `CANCELLED_BY_WIN`“和牌优先，本窗作废”；STT 失败/超时或取消不能伪装成评分/发奖。
- 用固定中英日/AI/静默与三出口夹具记录每局窗口 outcome、库存量、同 ID 实例数、道具分布和 affinity 激活率，作为 Alpha 平衡基线。

**Phase 5 出口：** 练习与公共欢乐场确定性发奖/使用/回放通过；#249–#254 关闭。

### Phase 7：E7 部署与桌面 Alpha

#### #255–#256 服务拓扑

- 容器化 Control Plane、Redis、faster-whisper、Godot Headless Worker；一条文档化命令启动。
- health/readiness 覆盖进程与必要依赖；配置/密钥全用环境变量。
- Worker 定期注册/续租并报告容量；Redis 原子分配，失联 Worker 停止接房并回收租约。
- Alpha 只承诺单区域测试拓扑，不实现跨地域热迁移。

#### #257–#258 桌面包

- macOS/Windows 包包含必要运行依赖，不内置 multilingual small 大模型。
- 干净用户目录验证首次启动、标准场、麦克风权限、模型断点下载/校验、公共房连接和整场结算。
- macOS 不以 App Store、Windows 不以 Microsoft Store 为 Alpha 出口。

#### #259 最终验收

- 真实公网四真人完成一整场；另测 1、2、3 真人分别由 AI 补位。
- 东风/半庄、标准/欢乐至少各完成一场并保存日志/截图/版本证据。
- 记录 Control Plane、Redis、Worker、STT 的 CPU/内存、房间容量和延迟基线。
- 实际执行服务与客户端回滚。
- 审计代码、GitHub Issue/里程碑/标签：不存在 E6、举报、静音、语音控制或自动禁言实现。

**Phase 7 出口：** #255–#259 关闭，Master Epic 的全部成功标准有真实证据。

## 3. 跨模块接口冻结点

| 冻结点 | 时机 | 后续变更规则 |
|---|---|---|
| 模式枚举与 `GameSessionConfig` | E2-01 合并 | 协议值不可重命名；新增值需 PRD/协议升级 |
| HTTP/WS 包络与错误码 | E3-01/E3-02 合并 | 只做向后兼容字段增加；破坏性变化提升 protocol version |
| 权威事件与 state hash | E3-05 合并 | Worker 与客户端同时升级并有 replay fixture |
| PCM/语音帧格式 | E4-01/E4-02 合并 | 通过 voice protocol version 变更 |
| STT 结果包络与 1500ms/CLAIM 闸门 | E4-05 合并 | 同 utterance 的幂等键、PTT 结束序号、窗口归属和和牌抢占语义不可变 |
| 垃圾话规则、三出口窗口与分配算法 | E5-02/E5-04 合并 | 语音/上下文边界分离；提升 rule_version/assignment_version；旧回放引用旧 fixture |
| 重复实例库存与道具/技能事件 schema | E5-05 合并 | 不得退化为单槽或按 item_id 合并；必须保持 replay 向后兼容或迁移 fixture |

## 4. 验证命令与证据

### Godot

```bash
godot --headless --path godot --import

godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/<module> -gselect=<test_name> -gexit

godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests -ginclude_subdirs -gexit

godot --path godot -s tools/capture_screens.gd
```

### Go/服务

每个独立 Go module 运行 `go test ./...`；队列/租约测试必须连接测试 Redis；WebSocket/Worker 测试必须启动真实进程。容器阶段运行构建、health/readiness 和端到端 smoke。

### 文档/规划

```bash
git diff --check
rg -n 'E6|语音举报|自动禁言|按座位静音|全局关闭语音' \
  docs/superpowers/specs/2026-07-22-* \
  docs/superpowers/plans/2026-07-22-*
```

上述 `rg` 允许命中“明确不做/不存在”陈述，不允许出现实施 Issue、API、UI 或里程碑。

## 5. 风险与控制

| 风险 | 控制 |
|---|---|
| 肉鸽逻辑与角色能力高度耦合 | E0 先盘点；E1 只解除生产依赖，E2 再注入纯会话上下文 |
| #228 与 #231 重复定义会话配置 | E1-04 只输出 `SessionIntent`；E2-01 首次定义并冻结正式 `GameSessionConfig` 及转换 |
| 指定肉鸽 Autoload 启动时仍读盘 | E1-02 从生产配置注销 5 个 Autoload；legacy 测试显式实例化脚本 |
| 后 6 角色 hook 存在但工厂不注册 | E1-06 以 `CharacterPool` 12 个 `ability_id` 全部可 build/inject 为验收，不接受绕过工厂的测试 |
| 客户端与 Worker 各算一套导致分叉 | Worker 唯一权威；客户端只投影；state hash + replay |
| Redis 并发产生重复房间 | ticket 幂等键 + 原子匹配/租约测试 |
| PCM WebSocket 背压影响牌局 | 独立通道、有界队列、丢弃旧音频帧 |
| 本地与服务端 STT 不一致 | 公共场只采用服务端 final；本地只显示 |
| 第 24 弃同时存在 CLAIM 与 STT 宽限 | 语音边界在弃牌时冻结；CLAIM 并行且用独立上下文边界；荣和立即 cancel 并中止宽限，无和牌才在下一普通行动前 settle |
| 同窗 cancel/settle 或终场错误发奖 | 三出口状态机互斥；replay 拒绝冲突转换，`DISPLAY_ONLY/CANCELLED_BY_WIN` 强制 `grant_count=0` |
| 模型/LLM 结果不确定影响公平 | 只把文本交给确定性版本规则；模型无发奖权 |
| 4×4 最优分配存在并列或跨平台浮点差异 | 使用定点整数分数，枚举 24 种双射并按 seat/item ID 字典序决胜，记录 assignment_version |
| 多件/同种重复库存导致积压或未来套装反向侵入 Alpha | Alpha 保持独立 ItemInstance、无替换且按 instance 精确使用；统计同 ID 数量，未来套装只扫描集合，套装计算与 UI 另行立项 |
| 角色原创替换遗漏旧 IP | 12 项映射表 + 生产资源 `rg` 审计 + 资源加载测试 |
| 资产生成渠道或凭证漂移 | 调用前最小真实请求；只读既有环境配置；PR 审计无密钥；中间产物不入库 |
| 规划跨度大导致跨 Issue 偷渡 | 39 个叶子 Issue 单独 worktree/PR，父 Epic 原生层级审计 |
| 外部服务未实测 | 第三方最小真实请求闸门；无法实测就停止对应接入 |

## 6. 当前执行状态

- [x] 开启 GitHub Issues。
- [x] 创建 P0/P1、type、scope 标签和 M0–M5/M7。
- [x] 创建规划入口、Master、7 Epic、39 个叶子 Issue。
- [x] 建立 GitHub 原生 Master → Epic → 叶子层级。
- [x] 编写总 PRD、Epic PRD、master plan、issue backlog。
- [x] 规划 PR [#260](https://github.com/jingx8885/mahjong-game/pull/260) 已验证并人工合并。
- [x] E0-01 PR [#261](https://github.com/jingx8885/mahjong-game/pull/261) 已人工合并，#221 已关闭。
- [x] 用户锁定入口/Intent/Config 三层切片、生产级大厅、单曲 Suno BGM、全新角色美术和 5 个 Autoload 注销决策。
- [x] 用户锁定 RewardWindow 三出口：和牌取消、终场非和牌仅展示、非终场流局/满 24 无和牌发四件，以及同席同道具多实例。
- [ ] 本次纯文档决策修订 PR 人工合并，并同步受影响 Issue 正文。
- [ ] 完成并关闭 E0 #222–#224；在 Phase 0 出口满足前不开始 E1 业务代码。
