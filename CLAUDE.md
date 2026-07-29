# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **本文件只承载项目技术事实；工作流与开发规则以 [`AGENTS.md`](./AGENTS.md) 为唯一权威源。**
> 工作流规则只改 `AGENTS.md`；技术事实才改本文件。
> 优先级：**用户显式指令 > AGENTS.md > 本文件的技术事实 > 默认行为**。

## 硬约束红线（不可违反 · 完整条款见 AGENTS.md）

- **沟通**：默认中文；PR / Issue 默认中文。
- **Worktree First**：业务代码在 `git worktree` 内改，不直接在主工作区改业务代码；纯文档/agent 说明可例外。
- **分支与 PR**：默认从最新 `main` 建任务分支；验证后 commit、默认 push，按需开合并到 `main` 的中文 PR。
- **简单优先 + 外科手术式修改**：最小改动，不顺手重构无关代码。
- **计划与 UI 确认**：实现前给可执行计划；UI 分档 —— 简单 ASCII / 复杂草图+取舍（可选截图）/ 复杂流程 Mermaid。
- **验证驱动**：功能/缺陷优先 TDD + GUT；改 class/资产后必须 `godot --headless --path godot --import`；声称完成须附命令与结果。禁止 mock 顶替核心规则逻辑。
- **主路径**：`ui/lobby/lobby_shell.tscn`（生产入口）+ `ui/four_player_table/`；退役肉鸽 Run 与旧中式 `legacy/` 已物理删除；勿接 `game_ui` / 微信登录遗留为主路径。
- **牌面契约**：`mahjong_tiles_riichi` 文件名 + 272×389；WHITE modulate；赤宝 `0m/0p/0s`；滤波 LINEAR_WITH_MIPMAPS。
- **不扩张 `main.go`**；不新增根目录状态报告 markdown；不信根目录 200+ 陈旧笔记。
- **提交即推送**：本地已 commit 默认尽快 push，除非用户明确要求只留本地。
- **意外文件**：影响运行/构建的非己方变更 → 暂停询问；纯文档/元数据可忽略。
- **Codex + Grok 单 Issue 闭环**：每个 Issue 使用一个 Codex App 任务；右侧终端交互确认 Grok Plan，同一 Codex 任务独立 Review、复测、返工和交付；不另建 Review 任务。

---

## Repository shape (read this first — README.md is misleading)

This repo contains **two unrelated trees** that share a directory but not a build:

1. **`godot/`** — a Godot 4.6 client (verified on 4.6.1) written in GDScript. **Main scene: `ui/lobby/lobby_shell.tscn`** (set in `godot/project.godot`; E1-01). Tree layout:
   - `ui/lobby/` — 生产大厅入口壳；`PracticeMatchCoordinator` 消费练习 intent，`PublicMatchCoordinator` 消费公共匹配 intent 并发布无 token 的只读 UI state/view
   - `ui/four_player_table/` — 日麻 4 人桌对战 UI（`PlayableTable` / `SeatPanel` / `CardTileBack` 等）
   - `core/` — pure-logic 日麻 engine：
     - `core/tile/` — `Tile` / `TileId` / `Hand` / `DiscardRiver` / `Meld` / `MeldCollection` / `Wall`（含 dead wall API）
     - `core/rules_japanese/` — 和牌、听牌、振听、Dora、流局；`fu/` `score/` `yaku/`（约 38 役）
     - `core/turn_engine/` — `TurnEngine` + `ClaimValidator` / `RiichiValidator` / `DrawDetector`
   - `battle/` — 对战运行时：`BattleState`、`Seat`、`PlayableBattleController`、`SkillScheduler` 等
   - `items/` — 道具领域定义与运行时适配：`ItemCatalog` 是稳定 ID、类型、使用模式、触发器、发放资格与牌桌图标的唯一注册源；`ItemSkillBuilder` / `ItemEffectRunner` 负责技能构建与即时 Hook 执行
   - `skills/` — 技能框架 + hooks
   - `meta/` — 当前角色/卡牌目录、设置与战绩等持久数据
   - `tests/` — **GUT 9.x** 测试；日常快速门禁与重型协议/UI/STT 回归分开运行
   - `addons/gut/`、`addons/anima/` — 测试与动效
   - `assets/` — 牌面 `mahjong_tiles_riichi/`（38 张）、桌布、立绘等
   - `scripts/` — **legacy** 中式麻将 / 登录 / 网络草图（平铺）；**新代码不要再加进 `scripts/`**
   - `scenes/` — 遗留场景（`wechat_login_final.tscn`、`game_ui.tscn` 等，**非** main_scene）
   - `tools/asset_gen/` — 资产生成与导入管线
2. **`main.go` + `Dockerfile` + `start.sh`** at the repo root — a **stub Go HTTP server** that only serves `/` and `/api/health` returning `{"status":"ok"}`. It exists solely to satisfy Railway's healthcheck. **There is no real backend in this repo.** The README's references to a `backend/` directory, JWT, ELO, etc. do not match the code on disk — treat the README as marketing copy, not architecture documentation.
3. **`services/`** — 独立后端服务（非根 Go 桩）：
   - `services/control-plane/` — 匹配控制面（Go）；#255/#256 E7 测试拓扑见 `docker-compose.e7.yml`（Redis + CP + STT + 双 Headless Worker 注册/租约；宿主端口默认 `127.0.0.1`）
   - `services/stt/` — #247 公共场 faster-whisper STT（Python 3.11；内部 WebSocket；模型默认 multilingual `small` + CPU int8 + Silero VAD）。Worker 经 `SttBridge` / `STT_SERVICE_URL` 接线；容器镜像 `Dockerfile`，模型走外部缓存卷、不入镜像。详见 `services/stt/README.md`。**不**扩张根 `main.go` / 根 Dockerfile 业务职责。**网络端到端未验证。**

设计文档与里程碑 plan 在 **`docs/superpowers/{specs,plans}/`**。新增计划放此目录，**不要**新增根目录 markdown。

Networking: 本仓已有 `services/control-plane/` 与 Godot Headless Worker 的本地真实 HTTP/WS 路径；公共客户端默认 CP 为 `http://127.0.0.1:8081`，可用 `CONTROL_PLANE_URL` 覆盖。仓库仍不提供公网部署端点，网络改动须声明未完成公网四客户端端到端验证。

The 200+ root-level markdown files (`PHASE*.md`, `RAILWAY_*.md`, `*_FINAL_*.md`, etc.) are historical and **not authoritative**. Read code before trusting them.

## Common commands

### Godot client
```bash
godot -e --path godot
# main scene = ui/lobby/lobby_shell.tscn
godot --path godot
godot --path godot -s tools/capture_screens.gd   # /tmp/shot_*.png
```

### GDScript 单元测试（GUT）

```bash
scripts/godot_bootstrap.sh  # 新 worktree 首测；两轮 import，仅第二轮作为门禁

scripts/test_run_core.sh  # 日常：core/battle/skills/ai/meta/health
scripts/test_run_slow.sh  # 显式：integration/protocol/server/session/UI/STT 等

godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
    -gdir=res://tests/battle -gselect=test_skill_scheduler -gexit
```

生产代码新增测试一律放 `godot/tests/<module>/test_*.gd`。遗留 `godot/scripts/test_*.gd` 为 scene 手测，不走 GUT。

### Stub Go server
```bash
go run main.go            # $PORT default 8080
go build -o app main.go
docker build -t mahjong .
```
`go test ./...` reports "no test files" unless you add some.

### STT 服务（#247/#248，`services/stt`）
```bash
cd services/stt
python3.11 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python -m stt_service   # ws://127.0.0.1:9100；可用 STT_DEVICE / STT_COMPUTE_TYPE / STT_MODEL_CACHE
# Worker: STT_SERVICE_URL=ws://127.0.0.1:9100 ... headless_worker_main.gd --stt-url=...
pytest -q tests          # 含真实中英日 fixture + VAD + #248 fallback（见 fixtures/SOURCES.md）
```
原始 PCM 仅有界内存；**不**写磁盘。公共网络四客户端链路未端到端验证。

### E7 容器测试拓扑（#255/#256）
```bash
# 本机主命令可用独立 docker-compose；Compose V2 插件则改 docker compose
# 成功退出即 CP+Redis+STT+双 Worker healthy
cd services/control-plane
docker-compose -f docker-compose.e7.yml --env-file .env.example up -d --build --wait --wait-timeout 900
# 契约 / 真实健康 smoke（仓库根；smoke 复用同一 --wait 语义）
scripts/e7_255_topology_contract_test.sh
scripts/e7_255_topology_smoke.sh
# #256 Worker 注册/租约/容量/失联回收
scripts/e7_256_worker_lifecycle_contract_test.sh
scripts/e7_256_worker_lifecycle_smoke.sh
# 清理（-v 删除 STT 模型缓存卷）
docker-compose -f docker-compose.e7.yml --env-file .env.example down -v --remove-orphans
```
端口：Redis `6379`、CP `8081`、Worker A `9000`/`9001`、Worker B `9002`/`9003`、STT `9100`（均默认 `127.0.0.1`）。Worker 经 `WORKER_REGISTRATION_TOKEN` 向 CP 注册；匹配按租约/容量选择。**网络端到端未验证。**

### E7 macOS Alpha 包（#257）
```bash
# 契约（预设 / ad-hoc / 麦克风说明 / 路径隔离）
scripts/e7_257_macos_export_contract_test.sh
# 安装 Godot 4.6.1 export template（如缺）并导出 → /tmp/mahjong-e7-257-*
scripts/e7_257_macos_package.sh
# 干净目录 smoke：Info.plist / ad-hoc codesign / 包内无 ggml 大模型
scripts/e7_257_macos_package_smoke.sh
# 真实 ggml-small（487601967 字节）下载 + SHA-256（隔离 /tmp，不写真实 Application Support）
scripts/e7_257_whisper_model_download_smoke.sh
```
- 预设名 `macOS Alpha`；bundle id `com.lovteam.MahjongGame`；**仅 ad-hoc**（禁止 Developer ID / 公证）。
- Gatekeeper：未公证应用可能被拦截，见 `docs/superpowers/specs/2026-07-26-e7-03-macos-alpha-packaging.md`。
- Godot 4.6 macOS `user://`：`~/Library/Application Support/Godot/app_userdata/MahjongGame`（smoke 监控此路径，非旧 `Application Support/MahjongGame`）。
- 模型 smoke：必须用导出 `MahjongGame.app` 在空 root 上 `ensure_ready()` 拉生产清单（487601967 字节）；禁止编辑器冒充与 curl 预置成品。macOS 可用 `/usr/bin/curl` 经可 kill 子进程（`OS.create_process`，非阻塞轮询）仅解析 HF CDN URL（不下载 body）；cancel/release/销毁立即 kill，主线程不等待。
- 欢乐场内联权限说明 + 模型进度采样；标准场零麦克风/零下载。**网络端到端未验证**；真实麦克风授权需可见人工操作。不含 App Store / Windows #258 / 四端 #259。

#248 new-api 备份（可选）：专用 `STT_NEW_API_ENDPOINT` / `STT_NEW_API_MODEL` / `STT_NEW_API_TOKEN` /
`STT_NEW_API_TIMEOUT_MS` + 主逻辑 `STT_PRIMARY_TIMEOUT_MS`。缺配置则备份禁用，主服务仍运行。
仅 final 在主异常/逻辑超时后回退；partial 与正常空白终态不回退。熔断与 PONG 健康摘要不含 token。
**勿**静默复用资产生成 `OPENAI_*`。真实供应商 smoke ≠ 公网/四客户端 e2e。

### Windows Alpha 包（#258 / E7-04）

- 预设：`godot/export_presets.cfg` → **Windows Desktop** / **x86_64** / **`codesign/enable=false`** / **`export_filter=exclude` + denylist**（排除 tests/gut/legacy/`main.tscn`；不用 scenes-only，因 preload 依赖登记不全）
- 打包：`scripts/package_windows_alpha.sh` → 日志扫描 SCRIPT/Parse 错误 + `Storing File` 清单 → `dist/windows-alpha/MahjongGame-windows-x86_64-alpha.zip`
- 契约：`scripts/windows_alpha_contract_test.sh`
- **真机规范入口**：`scripts/windows_clean_smoke.ps1`（PowerShell；证据不足非 0）。`scripts/windows_clean_smoke.sh` 仅非 Windows NOT_RUN / 转发
- 规格：`docs/superpowers/specs/2026-07-26-windows-alpha-packaging.md`
- 模型仍走 **`user://models/whisper/<version>`**（#245），**不**随包内置（生产 small ≈ 487601967 字节）
- 首次说明：仅 **Windows 运行时**；`platform/platform_first_use_notices.gd`（无 class_name，preload）+ Settings 键 `windows_first_*_notice_acked`
- **网络端到端未验证**；真实 Windows clean smoke / 麦克风 / 公网整场待真机

### 资产生成

管线在 **`godot/tools/asset_gen/`**。当前牌面主力来源：**FluffyStuff CC0**（`import_fluffystuff.py` → 272×389）；gpt-image-2 管线仍可用作风格实验。

- 凭证：环境变量 / `~/.zshrc`（`OPENAI_BASE_URL` + `OPENAI_API_KEY`），**不入仓库**。
- 约定：`godot/assets/mahjong_tiles_riichi/{1m..9m,1p..9p,1s..9s,1z..7z,0m,0p,0s,back}.png`
- 工作流：smoke → staging QA → `cp` → **`godot --headless --path godot --import`**
- 中间产物 `_raw_*` / `_staging*` / `_samples` 已 gitignore，**不入库**

## Godot architecture

### Autoloads（见 `project.godot`）
生产仅注册 `DT`、`GameManager`、`TextureExtractor`、`AudioManager`、`SettingsManager`、`DebugOverlay`、`StatsManager`、`Log`、`ANIMA`。
退役的肉鸽 Run、旧中式客户端及其存档/抽卡/章节脚本已经物理删除，不再提供显式加载兼容。

**`TextureExtractor`**：按名加载 `res://assets/mahjong_tiles_riichi/<key>.png`（38 张），`get_tile_texture(key)` 供牌桌渲染。

### Tile-rendering invariants
- 文件名严格不变；源尺寸 **272×389**
- face 用 **WHITE** modulate（dim 用遮罩，勿用非白 RGB modulate 整牌）
- 赤宝：`is_red_dora` → atlas key **`0m` / `0p` / `0s`**
- 滤波：`rendering/textures/canvas_textures/default_texture_filter=3`（**LINEAR_WITH_MIPMAPS**）
- 改 PNG 后必须 `--import`，否则 ctex 失效界面全黑
- Viewport 设计基准 **1600×900**；`PlayableTable` 默认走 **2D 伪 3D**，
  `MahjongTable3D` 仅保留为显式实验 opt-in

### 日麻引擎与技能（active）
见 `core/`、`battle/`、`skills/`。玩家输入：`PlayerDecisionPort` + `TableDecisionAdapter` + `PlayerActionPanel`。
里程碑与差距：`docs/superpowers/specs/`（含牌桌 overhaul、gap analysis 等）。

### 道具领域（active）
`items/item_catalog.gd` 统一登记当前 10 个战斗消耗品与 12 个遗物；`CardPool`、`ConsumableFactory`、`RelicFactory`、`ItemInventoryModule`、`ItemAuthority` 和牌桌 UI 只消费该目录，不再维护各自的具体 ID 白名单。`seat_swap_v1` / `tsubame_v1` 保留为已知但不可发放、不可使用；协议 DTO、`ItemInstance` 状态与 `ITEM_*` 事件仍由 `session/` 权威链维护。

### 麻将牌领域模型

- `Tile` 是一张物理牌：`id` / `is_red_dora` / `owner_seat` / `instance_id` 均只读；`TileId` 承担 34 种牌的纯规则映射。
- `Seat` 是席位聚合根，持有 `Hand`、`DiscardRiver`、`MeldCollection`；业务代码只通过集合 API 读写，`tiles()` / `all()` 返回副本。
- `DiscardRiver` 原子维护弃牌顺序和立直弃牌索引；被鸣牌必须使用 `claim_last()`。
- `MeldCollection` 按 `local_index * 4 + seat_id` 分配 `meld_id`，负责副露结构、实体与 PON → ADDED_KAN 升级校验；行动合法性仍由 `ClaimValidator` / `TurnEngine` 负责。
- `Wall` 封装 136 张权威牌、摸牌游标、王牌区和岭上游标；`DoraIndicators` 仅以 `reveal_pair()` 成对推进表/里指示牌。
- 技能锚点类型为 `TileSkillAnchor`，指向真实物理 `Tile`；其六键序列化结构保持协议兼容。
- 权威快照恢复先完整验证，再通过 staging 一次提交；wire schema、公开快照字段与隐私边界不随内部领域对象变化。

### Class_name
全局 `class_name` **不可重复**。新增前 `grep -rn 'class_name <Name>' godot/`。

### Legacy
`scripts/` 中式实现、`scenes/game_ui`、微信登录场景等**不要接生产主路径**；除非 `class_name` 冲突，不要顺手重构 legacy。

## Working in this repo

- 不要新增根目录状态报告 markdown。
- 不要相信 README 的 API 宣传。
- 每个 `.gd` 旁有 Godot 生成的 `.gd.uid`：改 `.gd` 时保留配对，勿单独乱删。
- 网络改动完成时声明「未端到端验证」。
- GUT 前 `--import`；插件默认只保留 GUT + Anima，新插件先评估 ROI。
