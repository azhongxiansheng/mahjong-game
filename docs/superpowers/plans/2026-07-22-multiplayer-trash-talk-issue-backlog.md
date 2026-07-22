# 多人麻将与“嘴强道具”Issue Backlog

> 规划入口：[Issue #212](https://github.com/jingx8885/mahjong-game/issues/212)
> Master Epic：[Issue #213](https://github.com/jingx8885/mahjong-game/issues/213)
> 创建日期：2026-07-22
> GitHub 对象：1 个规划入口 + 1 个 Master + 7 个 Epic + 39 个叶子 Issue = 48 个 Issue
> 规划状态：PR #260、E0-01 PR #261 已人工合并；#221 已关闭，#222–#224 仍是 E1 开工硬闸门
> 决策锁：入口壳 / `SessionIntent` / `GameSessionConfig` 三层分离；生产级原创大厅；1 首 Suno 大厅 BGM；全新 12 角色美术；生产注销 5 个肉鸽 Autoload

## 1. 标签与里程碑契约

每个 Issue 必须且只能拥有：

- 一个优先级：`priority: P0` 或 `priority: P1`。
- 一个类型：`type: planning`、`type: epic`、`type: docs`、`type: feature`、`type: engineering`、`type: test` 之一。
- 一个范围：`scope: planning`、`scope: e0`、`scope: e1`、`scope: e2`、`scope: e3`、`scope: e4`、`scope: e5`、`scope: e7` 之一。
- 一个里程碑：M0–M5 或 M7。
- 一个 assignee；默认当前 GitHub 登录账号 `jingx8885`。

不存在 `scope: e6`、M6、E6 Epic 或 E6 叶子 Issue。

| 里程碑 | Epic | 优先级 | 叶子数 |
|---|---:|---|---:|
| M0 产品与工程基线 | [#214 E0](https://github.com/jingx8885/mahjong-game/issues/214) | P0 | 4 |
| M1 去肉鸽与原创大厅 | [#215 E1](https://github.com/jingx8885/mahjong-game/issues/215) | P0 | 6 |
| M2 统一电脑对战 | [#216 E2](https://github.com/jingx8885/mahjong-game/issues/216) | P0 | 5 |
| M3 服务端权威与公共匹配 | [#217 E3](https://github.com/jingx8885/mahjong-game/issues/217) | P0 | 7 |
| M4 实时语音与双层 STT | [#218 E4](https://github.com/jingx8885/mahjong-game/issues/218) | P0 | 6 |
| M5 确定性垃圾话与道具 | [#219 E5](https://github.com/jingx8885/mahjong-game/issues/219) | P0 | 6 |
| M7 部署与桌面 Alpha | [#220 E7](https://github.com/jingx8885/mahjong-game/issues/220) | P1 | 5 |

## 2. 39 个叶子 Issue

### E0 产品与工程基线

| Issue | P | Type | 依赖 | 一句话验收 |
|---|---|---|---|---|
| [#221 E0-01 模式矩阵](https://github.com/jingx8885/mahjong-game/issues/221) | P0 | docs | #212 | 8 种组合、30 秒边界、非目标和无 E6 均成为唯一契约 |
| [#222 E0-02 代码/IP 盘点](https://github.com/jingx8885/mahjong-game/issues/222) | P0 | docs | #221 | Run、12 角色、道具和 IP 均标注删除/保留/原创替换 |
| [#223 E0-03 架构与协议 ADR](https://github.com/jingx8885/mahjong-game/issues/223) | P0 | engineering | #221–#222 | Control Plane/Redis/Worker/语音/STT/权威和最小协议写死 |
| [#224 E0-04 验收矩阵与 Alpha DoD](https://github.com/jingx8885/mahjong-game/issues/224) | P0 | test | #221–#223 | E1–E7 全部行为有真实测试层级和出口标准 |

### E1 去肉鸽与原创大厅

| Issue | P | Type | 依赖 | 一句话验收 |
|---|---|---|---|---|
| [#225 E1-01 生产入口切换](https://github.com/jingx8885/mahjong-game/issues/225) | P0 | feature | E0 | 启动/返回进入大厅入口壳，Run Flow 生产不可达；不拥有 Intent 或正式 Config |
| [#226 E1-02 肉鸽依赖退出生产](https://github.com/jingx8885/mahjong-game/issues/226) | P0 | engineering | #225 | 新会话无肉鸽读写；5 个指定 Autoload 从生产配置注销，脚本保留 |
| [#227 E1-03 1600×900 大厅](https://github.com/jingx8885/mahjong-game/issues/227) | P0 | feature | #225 | 生产级原创大厅的几何、视觉、角色区、动效和截图验收通过 |
| [#228 E1-04 规则抽屉](https://github.com/jingx8885/mahjong-game/issues/228) | P0 | feature | #227 | 两个入口输出东风/半庄 × 标准/欢乐的完整 `SessionIntent`；不定义正式 Config |
| [#229 E1-05 图鉴与 BGM/SFX](https://github.com/jingx8885/mahjong-game/issues/229) | P1 | feature | #227 | 图鉴过滤 Run-only；1 首 Suno 大厅 BGM 可听；BGM/SFX 可控且无语音控制 |
| [#230 E1-06 12 名原创角色](https://github.com/jingx8885/mahjong-game/issues/230) | P0 | feature | #222 | 全新 12 角色经两道确认闸门入库；12 个能力工厂映射和 portrait 序列化通过 |

### E2 统一电脑对战

| Issue | P | Type | 依赖 | 一句话验收 |
|---|---|---|---|---|
| [#231 E2-01 GameSessionConfig](https://github.com/jingx8885/mahjong-game/issues/231) | P0 | engineering | E1、#228 | 正式 Config、Intent→Config、四个稳定枚举、验证和序列化可驱动练习场 |
| [#232 E2-02 统一行动/事件接口](https://github.com/jingx8885/mahjong-game/issues/232) | P0 | engineering | #231 | 玩家/AI 操作复用真实 BattleController 并可被回放消费 |
| [#233 E2-03 东风/半庄 1+3 AI](https://github.com/jingx8885/mahjong-game/issues/233) | P0 | feature | #232 | 两种局制整场可玩、推进正确、分数守恒 |
| [#234 E2-04 模式硬隔离](https://github.com/jingx8885/mahjong-game/issues/234) | P0 | feature | #231–#232 | STANDARD 不创建角色/道具/Momentum/语音，欢乐场才启用 |
| [#235 E2-05 结算与导航](https://github.com/jingx8885/mahjong-game/issues/235) | P0 | feature | #233–#234 | 排名、重赛、返回大厅完整且不产生肉鸽奖励 |

### E3 服务端权威与公共匹配

| Issue | P | Type | 依赖 | 一句话验收 |
|---|---|---|---|---|
| [#236 E3-01 Control Plane/Redis](https://github.com/jingx8885/mahjong-game/issues/236) | P0 | engineering | E2 | 独立 Go module、真实 Redis、health/readiness；根 main.go 不变 |
| [#237 E3-02 游客与房间凭证](https://github.com/jingx8885/mahjong-game/issues/237) | P0 | feature | #236 | 过期/篡改/跨房/跨座位令牌拒绝，密钥仅来自环境 |
| [#238 E3-03 公共队列](https://github.com/jingx8885/mahjong-game/issues/238) | P0 | feature | #236–#237 | 加入/查询/取消幂等，不同局制/模式不混池 |
| [#239 E3-04 30 秒 AI 补位](https://github.com/jingx8885/mahjong-game/issues/239) | P0 | feature | #238 | 四真人立即开房，1–3 真人超时后只创建一个补位房间 |
| [#240 E3-05 Headless Worker 权威](https://github.com/jingx8885/mahjong-game/issues/240) | P0 | engineering | #232、#239 | Worker 独占牌墙/合法性/AI/技能/道具/事件，客户端只投影 |
| [#241 E3-06 快照与重连](https://github.com/jingx8885/mahjong-game/issues/241) | P1 | feature | #240 | 30 秒内恢复、超时 AI 接管、本局安全归还控制 |
| [#242 E3-07 幂等/非法行动/回放](https://github.com/jingx8885/mahjong-game/issues/242) | P1 | test | #240–#241 | 重复命令不重复应用，伪造发奖被拒，事件摘要可重放 |

### E4 实时语音与双层 STT

| Issue | P | Type | 依赖 | 一句话验收 |
|---|---|---|---|---|
| [#243 E4-01 Godot PTT/PCM](https://github.com/jingx8885/mahjong-game/issues/243) | P0 | feature | E3 | 仅 PTT 采集 PCM16/16k/mono/20ms，标准场不请求权限 |
| [#244 E4-02 四座位语音中继](https://github.com/jingx8885/mahjong-game/issues/244) | P0 | engineering | #237、#243 | 同房鉴权广播、有界背压、断开清缓冲、不落盘 |
| [#245 E4-03 whisper 模型管理](https://github.com/jingx8885/mahjong-game/issues/245) | P0 | engineering | #243 | manifest、断点续传、SHA-256、原子启用跨 macOS/Windows |
| [#246 E4-04 中英日字幕](https://github.com/jingx8885/mahjong-game/issues/246) | P0 | feature | #243、#245 | partial/final 正确替换；公共本地字幕不能发奖 |
| [#247 E4-05 faster-whisper/VAD](https://github.com/jingx8885/mahjong-game/issues/247) | P0 | engineering | #244 | 权威 final 绑定房/座位/局序，空白/失败不进入评分 |
| [#248 E4-06 new-api 回退](https://github.com/jingx8885/mahjong-game/issues/248) | P1 | engineering | #247 | 最终片段回退、超时/熔断/去重、真实接口最小请求 |

### E5 确定性垃圾话与道具

| Issue | P | Type | 依赖 | 一句话验收 |
|---|---|---|---|---|
| [#249 E5-01 多语言规则库](https://github.com/jingx8885/mahjong-game/issues/249) | P0 | docs | #230 | 12 角色/可发道具中英日规则、affinity、上下文和稳定 ID 完整 |
| [#250 E5-02 TextAnalyzer 扩展](https://github.com/jingx8885/mahjong-game/issues/250) | P0 | engineering | #249 | 标准化/关键词/模板/版本确定性，无 LLM/向量依赖 |
| [#251 E5-03 角色/道具/牌局上下文](https://github.com/jingx8885/mahjong-game/issues/251) | P0 | engineering | #250、#240 | 只使用 Worker 真实状态过滤和评分，练习/公共复用纯逻辑 |
| [#252 E5-04 Momentum/冷却/决胜](https://github.com/jingx8885/mahjong-game/issues/252) | P0 | feature | #251 | 每 utterance 至多一个奖励，重复/冷却/同分稳定 |
| [#253 E5-05 权威道具生命周期](https://github.com/jingx8885/mahjong-game/issues/253) | P0 | feature | #252 | 发放/持有/使用/效果进入统一事件流并可重放 |
| [#254 E5-06 反馈与平衡夹具](https://github.com/jingx8885/mahjong-game/issues/254) | P1 | feature | #246、#253 | 字幕/命中/到账/发动清晰，无隐藏信息泄漏，有频率基线 |

### E7 部署与桌面 Alpha

| Issue | P | Type | 依赖 | 一句话验收 |
|---|---|---|---|---|
| [#255 E7-01 服务容器拓扑](https://github.com/jingx8885/mahjong-game/issues/255) | P0 | engineering | E3–E5 | 一条命令启动 Control Plane/Redis/STT/Worker，探针全绿 |
| [#256 E7-02 Worker 生命周期](https://github.com/jingx8885/mahjong-game/issues/256) | P1 | engineering | #255 | 注册/续租/容量/原子分配/失联回收在真实 Redis 下通过 |
| [#257 E7-03 macOS Alpha 包](https://github.com/jingx8885/mahjong-game/issues/257) | P0 | engineering | #245、#255 | 干净 macOS 完成权限、模型下载、公共房整场 |
| [#258 E7-04 Windows Alpha 包](https://github.com/jingx8885/mahjong-game/issues/258) | P0 | engineering | #245、#255 | 干净 Windows 完成防火墙、模型下载、公共房整场 |
| [#259 E7-05 公网 E2E/负载/回滚](https://github.com/jingx8885/mahjong-game/issues/259) | P1 | test | #256–#258 | 四真人与 1–3 真人补位、四种玩法、负载和回滚有真实证据 |

## 3. 依赖主线

```mermaid
flowchart LR
    E0["#214 E0"] --> E1["#215 E1"] --> E2["#216 E2"] --> E3["#217 E3"] --> E4["#218 E4"] --> E5["#219 E5"] --> E7["#220 E7"]
    E2 -. "本地规则可先行" .-> E5
```

父子关系已使用 GitHub 原生 sub-issues 建立；本文件中的链接用于代码库内离线追踪，不替代 GitHub 状态。

## 4. 完成与变更规则

- 叶子 Issue 关闭前必须有合并后的 PR 和实际验证证据。
- Epic 关闭前必须确认所有原生子 Issue 关闭、Epic DoD 通过、相关文档更新。
- Master 关闭前必须通过 macOS/Windows 公网四客户端 Alpha 和“无 E6”审计。
- 若需求改变，先更新总 PRD、Epic PRD、对应 Issue 和本 backlog，再改业务代码。
- 不允许将新工作挂到 E6；需要语音安全/玩家控制时必须另行产品决策和新编号。
- Suno、Grok、image-2、nano banana 的调用只使用既有本地/new-api 配置，凭证和 staging 中间产物不入库；运行时客户端不调用生成 API。
