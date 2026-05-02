# 麻将王 — 日麻 + 卡牌技能 + Roguelike

> 单机日式麻将 roguelike：每张牌 / 每个角色都可以挂技能；按 StS 风格地图节点推进 Run；通关解锁更多内容。

**这不是一个联机麻将服务器。** 仓库根的 `main.go` 只是一个健康检查桩（仅 `/api/health` 返回 OK）以满足 Railway 部署需求；游戏本身是 Godot 4.5+ 单机客户端（`godot/`）。

---

## 当前状态

按 [`docs/superpowers/specs/2026-05-01-mahjong-king-design.md`](docs/superpowers/specs/2026-05-01-mahjong-king-design.md) §13 拆里程碑：

| 里程碑 | 范围 | 状态 |
|---|---|---|
| **0** | 日麻规则引擎（38 个役 / 符算 / 点数 / 振听 / Dora / 流局 / 立直） | ✅ 完成 |
| **1** | 技能框架 + 5 demo 牌技能 + 1 demo 角色能力 | ✅ 完成 |
| **2** | 单局对战 vs 1 AI（端到端 BattleController + SimpleAi） | ✅ 完成 |
| **3** | 东风战 + 4 人桌 + 牌背 + 归属可视化 | ✅ 完成 |
| **4** | Run 流程骨架（StS 地图 + 节点切换 + 营地/商店占位） | ✅ 完成 |
| **5** | 抽卡 + 卡包 + 元进度 + 存档 | ✅ 完成 |
| **6** | 30+ 牌技能 + 8-10 角色能力 + 3 章 Boss + 3 起始包 内容 | ⏳ 进行中 |
| **7** | 平衡迭代 | ⏳ 待启动 |

工作流、TDD、代码闸门、Git 约定见 [`AGENTS.md`](AGENTS.md)；项目结构与已知陷阱见 [`CLAUDE.md`](CLAUDE.md)。

---

## 仓库结构

```
godot/                          # Godot 客户端（主体）
├── core/
│   ├── tile/                   # TileId / Tile（带 owner_seat）/ Hand / Meld / Wall
│   ├── rules_japanese/         # 日麻规则：和牌识别 / 符算 / 点数 / 振听 / Dora / 流局
│   │   ├── fu/                 # 符算
│   │   ├── score/              # 点数公式
│   │   └── yaku/               # 38 个役判定 + YakuEvaluator
│   └── turn_engine/            # TurnEngine 状态机 + Validator
├── battle/                     # 一局运行时：BattleState / SkillScheduler / BattleController
├── skills/                     # SkillResource + SkillHook + SkillRegistry（含 6 demo hook）
├── meta/                       # Run 流程：RunState / ChapterMap / Gacha / SaveSystem / MetaProgress
├── ai/                         # SimpleAi（M2 最简随机弃牌）
├── ui/                         # 4 人桌 + Run 占位 UI
├── scenes/                     # 游戏场景
├── scripts/                    # 历史平铺脚本（旧中式麻将 / 登录 / 网络草稿，按里程碑迁移）
├── assets/                     # 美术资源（含 mahjong_tiles atlas）
├── tests/                      # GUT 单测（按模块分子目录）
└── addons/gut/                 # GUT 9.x 测试框架

docs/superpowers/
├── specs/                      # 设计 spec（mahjong-king-design 主 spec）
└── plans/                      # 各里程碑实现计划 / brainstorm 草案

main.go                         # Railway 健康检查桩（不是后端）
Dockerfile / start.sh           # 桩的部署脚本
AGENTS.md                       # Agent 工作流 + 编码纪律 + Git 约定
CLAUDE.md                       # 项目结构 + Godot 不变量 + 已知陷阱
```

---

## 快速开始

### 跑 Godot 客户端

```bash
# 编辑器（默认主场景：scenes/wechat_login_final.tscn）
godot -e --path godot

# 无头跑主场景
godot --path godot

# F6 跑特定测试场景（如 4 人桌 smoke）
godot --path godot tests/scenes/four_player_table_smoke.tscn
```

需要 [Godot 4.5+](https://godotengine.org/)（已在 4.6.1 验证）。

### 跑 Go 健康检查桩（部署用）

```bash
go run main.go               # 监听 $PORT，默认 8080
curl http://localhost:8080/api/health    # → {"status":"ok"}
```

或 Docker：

```bash
docker build -t mahjong .
docker run -p 8080:8080 mahjong
```

---

## 测试

### Godot — GUT 单测

```bash
# 拉新分支后必须先重建 class cache
godot --headless --path godot --import

# 跑全套
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
    -gdir=res://tests -ginclude_subdirs -gexit

# 只跑某个目录
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
    -gdir=res://tests/battle -gexit
```

测试覆盖日麻规则引擎、技能框架、Battle / Run / Meta 各层，按模块分在 `godot/tests/` 子目录。

`godot/scripts/test_*.gd` 是早期遗留 scene-driven 手测；`godot/tests/scenes/skills/skill_*_test.tscn` 是技能框架 F6 手测场景（编辑器按 F6 跑）。新写测试一律放 `godot/tests/<module>/test_*.gd` 走 GUT。

### Go — 无测试

```bash
go test ./...    # → "no test files"
```

桩没有业务逻辑，没必要写测试。

---

## 关键设计

- **owner_seat 归属可视化**：每张 `TileInstance` 记 `owner_seat`（0-3）；牌背贴图按 owner 着色，即使被鸣到别人副露区也保持原牌背。技能触发时区分 owner（持有人）与 holder（当前位置）。
- **事件总线 + SkillScheduler**：所有局内副作用都通过 `BattleEventBus` 发出 + `SkillScheduler` 处理；不写绕过总线直改 `BattleState` 的代码。这是 Phase 2 联机扩展的硬约束。
- **分层状态对象**：`BattleState`（一局快照）→ `GameState`（一场东风战 4 局序列）→ `RunState`（一 Run 跨章节）→ `MetaProgress`（跨 Run 声望解锁）。每层独立可测、可序列化。
- **抽卡决定性**：`RandomNumberGenerator.state` 持久化进 `current_run.json`，中途退出再进 RNG 状态严格一致 → 防读档刷抽卡。
- **Class_name 全局唯一**：GDScript `class_name` 重复会让其中一个被 hide，编译链断裂导致 GUT Parse error 雪崩。新增 `class_name` 前先 `grep -rn 'class_name <Name>' godot/`。
- **牌渲染不变量**：80×120 / 0 padding / `AtlasTexture` / WHITE 调制 / NEAREST 过滤（通过 `project.godot` 的 `default_texture_filter=1` 设置）。详见 CLAUDE.md。

---

## 文档索引

| 文档 | 用途 |
|---|---|
| [`AGENTS.md`](AGENTS.md) | Agent 工作流、编码纪律、TDD、闸门、Git/发布原则 |
| [`CLAUDE.md`](CLAUDE.md) | 项目结构、Godot 不变量、已知陷阱、GUT 命令 |
| [`docs/superpowers/specs/2026-05-01-mahjong-king-design.md`](docs/superpowers/specs/2026-05-01-mahjong-king-design.md) | 主 spec：架构、数据类型、事件、技能方向库、里程碑 |
| `docs/superpowers/plans/` | 各里程碑实现计划 / brainstorm 草案 |

---

## 不实装 / 路线图外

以下功能在历史 README 中出现过但**当前不在 spec 范围**：

- 联机对战 / 服务器权威（spec §4.3 标记 Phase 2）
- 排行榜 / ELO / 赛季 / 战队 / 好友 / 私聊 / 黑名单 / 通知系统
- 微信登录（`scenes/wechat_login_final.tscn` 仅作启动占位）
- 付费抽卡（spec §9.4 明确不引入付费）

如需翻历史信息查 `git log`；不要信根目录散落的旧 `PHASE*.md` / `RAILWAY_*.md` / `项目*.md` 状态报告（详见 CLAUDE.md "Don't trust the README's API surface"）。

---

## 许可证

MIT。
