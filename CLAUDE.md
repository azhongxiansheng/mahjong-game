# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Agent 工作流、编码纪律、闸门、TDD、Git/发布原则详见 [`AGENTS.md`](./AGENTS.md)。本文件只描述项目结构与技术事实；行为约束以 `AGENTS.md` 为准。**

## Repository shape (read this first — README.md is misleading)

This repo contains **two unrelated trees** that share a directory but not a build:

1. **`godot/`** — a Godot 4.5 client (verified on 4.6.1) written in GDScript. Main scene: `scenes/wechat_login_final.tscn` (set in `godot/project.godot`). Tree layout:
   - `scripts/` (~110 .gd files) — legacy 中式麻将 implementation, login flow, networking sketch, UI helpers. **Flat, no subdirs.** Some files (e.g. `win_pattern.gd`, `hu_rule.gd`, `mahjong_deck.gd`) are no longer in the active development path; the new 日式麻将 engine lives under `core/` and `battle/`.
   - `core/` — pure-logic 日麻 engine, organized by concern:
     - `core/tile/` — `Tile` / `TileId` / `Hand` / `Meld` / `Wall` (含 dead wall API)
     - `core/rules_japanese/` — `WinPattern.detect`, `StandardDecomposer`, `ChiitoiDetector`, `KokushiDetector`, `WaitCalculator`, `FuritenChecker`, `DoraIndicator`, `ExhaustiveDraw`, `AbortiveDraw`, plus subpackages `fu/` (符算)、`score/` (基本点+点数公式)、`yaku/` (38 个役判定 + `YakuEvaluator`)
     - `core/turn_engine/` — `TurnEngine` 状态机 + `ClaimValidator` / `RiichiValidator` / `DrawDetector`
   - `battle/` — 一局对战的运行时数据与调度器：`BattleState`、`Seat`、`BattlePhase`、`RiichiState`、`FuritenState`、`DoraIndicators`、`TileInstance`、`SkillCtx`、`SkillScheduler`、`BattleEvent`
   - `skills/` — 技能框架：`SkillResource`、`SkillRegistry`、`SkillHook` 接口；`skills/hooks/` 含 6 个 demo hook
   - `tests/` — GUT 单元测试，按模块分子目录（`tests/core/`、`tests/core/yaku/`、`tests/battle/`、`tests/skills/`、`tests/scenes/skills/` F6 手测场景、`tests/_fixtures/`）。当前 ~94 个测试文件，全部走 GUT
   - `addons/gut/` — GUT 9.x 测试框架（已通过 `[editor_plugins]` 启用）
   - `assets/` — 美术资源（含 `mahjong_tiles/` 三张图集 PNG）
   - `scenes/` — 游戏场景（`wechat_login_final.tscn` 主入口、`main_simple_new.tscn`、`game_ui.tscn` 等）
2. **`main.go` + `Dockerfile` + `start.sh`** at the repo root — a **stub Go HTTP server** that only serves `/` and `/api/health` returning `{"status":"ok"}`. It exists solely to satisfy Railway's healthcheck. **There is no real backend in this repo.** The README's references to a `backend/` directory, `/auth/...` and `/game/...` endpoints, JWT, ELO, achievements, "20,000+ lines of production code," etc. do not match the code on disk — treat the README as marketing copy, not architecture documentation.

设计文档与里程碑 plan 在 **`docs/superpowers/{specs,plans}/`** —— 例如 `specs/2026-05-01-mahjong-king-design.md` 是当前总体设计，`plans/2026-05-01-{rule-engine-foundation,yaku-detection,fu-and-score,furiten-dora-draw,turn-engine,skill-framework}.md` 是里程碑 0a-0e + 里程碑 1 的 implementation plans（追溯文档）。新增计划应放此目录，**不要**新增根目录 markdown。

The Godot client's `network_manager.gd` connects to `ws://localhost:8080` over WebSocket and expects a server that does not exist in this repo. Networking-related work in the client cannot be end-to-end tested against this tree alone.

The 200+ root-level markdown files (`PHASE*.md`, `RAILWAY_*.md`, `*_FINAL_*.md`, `项目*.md`, etc.) are historical status/progress notes, mostly in Chinese, often contradictory, and **not authoritative**. Read code before trusting any doc here.

## Common commands

### Godot client
```bash
# Open editor (run from repo root or godot/)
godot -e --path godot

# Run the project headlessly (main scene = wechat_login_final.tscn)
godot --path godot

# Run a specific scene (e.g. the texture-extractor smoke test)
godot --path godot scenes/test_texture.tscn
```

### GDScript 单元测试（GUT）

新引擎与技能框架的代码用 **GUT 9.x**（`godot/addons/gut/`）跑 headless 单测，无 CI 但本地验证完整：

```bash
# 首次/拉新分支后必须先重建 class cache
godot --headless --path godot --import

# 跑全套（~94 个测试文件，应当 0 fail / 0 parse error）
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
    -gdir=res://tests -ginclude_subdirs -gexit

# 只跑某个文件
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
    -gdir=res://tests/battle -gselect=test_skill_scheduler -gexit
```

`godot/scripts/test_*.gd`（少数旧文件如 `test_mahjong_display.gd`、`test_texture_extractor.gd`）是**早期遗留的 scene 驱动手测**，不走 GUT；`godot/tests/scenes/skills/skill_*_test.tscn` 是**里程碑 1 的 F6 手测场景**，在编辑器中按 F6 跑。生产代码新增测试一律放 `godot/tests/<module>/test_*.gd` 用 GUT 写。

### Stub Go server
```bash
go run main.go            # listens on $PORT (default 8080)
go build -o app main.go   # build binary
docker build -t mahjong . # uses Dockerfile (golang:1.20)
```
`go test ./...` will report "no test files" — there are none.

### 资产生成 (gpt-image-2)

通过 OpenAI 兼容 API 调用 `gpt-image-2` 生成游戏资产(Akagi/斗牌传说风),管线在 **`godot/tools/asset_gen/`**。

**凭证 / 网关**
- 从 `~/.zshrc` 读 `OPENAI_BASE_URL` + `OPENAI_API_KEY`(脚本 `gen_client._gateways()` 自动取两组配置 fallback)。**凭证不入仓库**。
- 两个 gateway 都提供 `gpt-image-2`,但 `size` 参数会被偶尔忽略(请求 `1536x1024` 实际返回 `1024x768`)。脚本对此有 retry 兜底。

**工具**
| 脚本 | 作用 |
|------|-----|
| `tile_specs.py` | Akagi 风格 prompt 前后缀 + 38 张牌(34 标准 + 0m/0p/0s 赤宝 + back)逐张 prompt builder |
| `gen_client.py` | `POST /v1/images/generations` 调用 gpt-image-2,b64_json 解码,3 重试 × 2 gateway fallback |
| `postprocess.py` | Pillow 裁透明边 + 缩放到 `TILE_SIZE` 272×389;`slice_row(png, expected)` 按列 alpha>60 切水平整排,粘连时返回不足张数触发上游重试 |
| `generate_tiles.py` | **逐张生成**(单牌精度最稳,style 略漂),`--workers N` 并行;失败可 `--only 8s,1z` 重做 |
| `generate_sheets.py` | **按花色整排生成 + alpha 间隙切片**(同花色内 style 最一致);每 sheet 最多 4 次 retry 直到切到 expected;honor 牌总粘连切不开 → 现状用逐张 fallback |
| `generate_misc.py` | 桌面背景 / run 背景 / 节点图标 / HUD 图标 / logo 等非牌资产,并行 |
| `import_fluffystuff.py` | **当前牌面来源**:FluffyStuff/riichi-mahjong-tiles (CC0) 的 600×800 PNG 合成 Front+牌面 → 272×389;不走 AI 生成,无 style 漂移 |

**约定路径**
- 麻将牌:`godot/assets/mahjong_tiles_riichi/{1m..9m,1p..9p,1s..9s,1z..7z,0m,0p,0s,back}.png` —— 文件名严格不变(`TextureExtractor` 按名加载),统一 272×389 透明。
- 节点 / HUD 图标:`godot/assets/run_icons/{node_normal,node_elite,node_camp,node_shop,node_event,node_boss,icon_hp,icon_gold}.png` 透明 128–256 px。
- 背景:`godot/assets/{run_bg,mahjong_table_bg}.png` 不透明 1536×1024。
- Logo:`godot/assets/feifan_logo_transparent.png` 透明 512×512。

**工作流**
```bash
# 1) smoke test 锁风格(4 张)
python3 godot/tools/asset_gen/generate_tiles.py --smoke

# 2a) 按花色整排(推荐;同花色内 style 一致)
python3 godot/tools/asset_gen/generate_sheets.py --all
# 切到 _staging_sheets/,人工 QA 后 cp 到 godot/assets/mahjong_tiles_riichi/

# 2b) 逐张兜底(整排切不开 / 单牌坏)
python3 godot/tools/asset_gen/generate_tiles.py --only 8s,1z --out _staging

# 3) 其余资产
python3 godot/tools/asset_gen/generate_misc.py --all

# 4) 必须刷缓存,否则下次启动报 "Unable to open file ctex"
godot --headless --path godot --import
```

**输入产物(.gitignore)**:`_raw_*/`、`_staging*/`、`_samples/`、`__pycache__/`。**只入库**:`*.py` 脚本和最终 PNG。

**视觉核对**:`godot --path godot -s tools/capture_screens.gd` 渲染主要场景到 `/tmp/shot_*.png`(macOS CLI 启动的 Godot 窗口会被 compositor 截屏过滤,这条工具直接走视口 `get_texture().get_image().save_png()` 规避此问题)。

## Godot architecture

### Autoloads (singletons)
Defined in `godot/project.godot` `[autoload]`:
- **`GameManager`** (`scripts/game_manager.gd`) — holds user session (`user_data`, `is_logged_in`). Set after WeChat-style login.
- **`TextureExtractor`** (`scripts/texture_extractor.gd`, v2) — runs at `_ready` of every scene. **不再走 FairyGUI atlas 切片**;改为按 riichi 标准命名(`1m..9m / 1p..9p / 1s..9s / 1z..7z / 0m / 0p / 0s / back`)直接 `load("res://assets/mahjong_tiles_riichi/<key>.png")`,共 **38 张 272×389 透明 PNG**,目前来自 [FluffyStuff/riichi-mahjong-tiles](https://github.com/FluffyStuff/riichi-mahjong-tiles)(CC0 公有领域),用 `tools/asset_gen/import_fluffystuff.py` 合成牌底+牌面并缩放(早前的 gpt-image-2 Akagi 风格生成管线仍在 `tools/asset_gen/`,见上节"资产生成 (gpt-image-2)")。`get_tile_texture(key)` 是渲染层(`CardTileBack` / `SeatPanel` / `DiscardRiver` / `MeldArea`)的入口,缺图 fall-back 到 `null` 让调用方走 Label。
- **`SaveSystem`** (`meta/save_system.gd`) — autoload,`save_run(rs)` / `load_run()` / `clear_run()` 走 `user://savegame.json`。
- **`MetaProgress`** (`meta/meta_progress.gd`) — autoload,跨 Run 声望累计 + 战绩。

Tile-rendering invariants worth knowing:
- `assets/mahjong_tiles_riichi/<key>.png` **文件名严格不变** —— TextureExtractor 按名加载;重生成资产时 `--out` 到 staging 目录人工 QA 后再 `cp` 覆盖,不要换文件名。
- 资产改完必须 `godot --headless --path godot --import` 刷 `.godot/imported/*.ctex`,否则启动报"Unable to open file ctex"一连串错。
- Sprites must be modulated `WHITE` — anything else (including default theme tints) makes tiles render as solid color (commit `6090d26`).
- Texture filter is `TEXTURE_FILTER_NEAREST` for pixel-perfect rendering. **Set via project setting** `rendering/textures/canvas_textures/default_texture_filter=1` in `project.godot`。

### 日麻引擎与技能框架（active development）

新代码的组织（按里程碑 0a-0e + 1）：

- **`core/tile/`** — `TileId` 枚举（含字牌、E_WIND/S_WIND/...）、`Tile`（带 `owner_seat` 字段）、`Hand`、`Meld`（CHI/PON/MINKAN/ANKAN/ADDED_KAN）、`Wall`（含 dead wall API：`reserve_dead_wall(14)` / `take_rinshan()` / `peek_dora_indicator(n)` / `peek_uradora_indicator(n)`）。
- **`core/rules_japanese/`** — 和牌识别（`WinPattern.detect`）、分解（`StandardDecomposer`）、`ChiitoiDetector` / `KokushiDetector` / `WaitCalculator` / `FuritenChecker` / `DoraIndicator` / `ExhaustiveDraw` / `AbortiveDraw`；含子包：
  - `fu/` — 符算（`MeldFu` / `PairFu` / `WaitFu` / `FuCalculator`）
  - `score/` — 点数（`ScoreFormula` / `PayoutCalculator`）
  - `yaku/` — 38 个役判定（`yaku/pattern/` 形式役、`yaku/yakuman/` 役満、`yaku/state/` 状态役），`YakuEvaluator` 入口、`YakuEntries` 互斥规则
  - 顶层有 `ScoreCalc`（结算入口）、`WinContext` aka `ScoreContext`（结算上下文）、`YakuList`（dict 累计简版）
- **`core/turn_engine/`** — `TurnEngine` 状态机（draw / discard / advance / declare_riichi / apply_chi/pon/minkan/ankan/added_kan/ron/tsumo）、`ClaimValidator` 鸣牌合法性、`RiichiValidator` 立直触发、`DrawDetector` 流局触发。
- **`battle/`** — 运行时数据：`BattleState`（seats / wall / phase / dora_indicators / current_seat / honba / riichi_sticks）、`Seat`（hand / melds / points / riichi / furiten / discards）、`SkillScheduler` 调度器（owner/holder 分组 + rarity 排序 + 链路深度防护）、`BattleEvent`、`SkillCtx`、`TileInstance`。玩家输入通过 `PlayerDecisionPort` 接入；`PlayableBattleController` 不依赖具体 UI 控件。
- **`skills/`** — `SkillResource` / `SkillRegistry` / `SkillHook` 接口；`skills/hooks/` 含 6 个 demo（`thunder_5w` 增番、`seal_chun` 阻胡、`soul_drain_hatsu` 抓马、`xray_1w` 透明牌、`unfuriten_5p` 解振听、`seabed_hunter` 角色能力）。

里程碑进度详见 `docs/superpowers/plans/`：0a-0e（规则引擎全栈）+ 里程碑 1（技能框架）已完成；里程碑 2（单局对战 vs 1 AI）进行中。

### Class_name 注意事项（GUT 集成的硬约束）

GDScript 全局 `class_name` 在仓库内**不可重复**——重复会让其中一个被 hide，引用方拿到错版本，整条编译链断裂导致 GUT 测试 Parse error 雪崩（参见 PR #11 修复的 `WinPattern` / `WinContext` / `YakuList` 三处冲突）。新增 `class_name` 前先 `grep -rn 'class_name <Name>' godot/` 全局排重。

### Game-logic clusters in `godot/scripts/`（legacy）

`scripts/` 是**旧中式麻将实现**，平铺无子目录。新代码不要再加进 `scripts/`，按上述子树规划；`scripts/` 内的旧文件除非影响新引擎工作（如 `class_name` 冲突），否则**不要顺手重构**。

旧代码大致分组：
- **Mahjong rules / state（旧中式）**: `mahjong_deck.gd`, `card_deck.gd`, `card_hand.gd`, `card_tile.gd`, `card_data.gd`, `hu_rule.gd`, `win_checker.gd`, `special_win_checker.gd`, `debug_win_checker.gd`. 与 `core/` 下的日麻代码并存但接口完全不同。
- **Ting (听牌) detection（旧）**: `ting_checker.gd`, `async_ting_checker.gd`, `ting_cache.gd`, `ting_result.gd`. 日麻听牌走 `core/rules_japanese/wait_calculator.gd`。
- **Display / UI**: `hand_display.gd`, `hand_display_manager.gd`, `game_ui.tscn`/`.gd`, `card_animator.gd`, `card_animation.gd`, `main_menu_ui.gd`, `animated_title.gd`.
- **Networking (client side, no server present)**: `network_manager.gd` (WebSocket lifecycle), `network_client.gd`, `network_message.gd`, `message_protocol.gd`, `network_debugger.gd`, `network_tester.gd`, `network_test_suite.gd`.
- **Achievements / leaderboard / AI**: `achievement_*.gd`, `leaderboard.tscn`, `ai_player.gd`. Client-only sketches without persistence.
- **FairyGUI reverse-engineering helpers**: `bin_analyzer.gd`, `bin_dump.gd`, `texture_extractor.gd` (autoload), plus root-level `reverse_fairygui_bin.py`, `analyze_atlas.py`, `extract_mahjong_tiles*.{py,ps1,bat}`.

### Scenes
Boot scene is `wechat_login_final.tscn`. After login it transitions to `main.tscn` / `main_simple_new.tscn`. `test_*.tscn` scenes 是手测 harness —— 别把生产代码连到它们。`godot/tests/scenes/skills/*.tscn` 是技能框架的 F6 手测场景（每张技能/能力一个 .tscn）。

## Working in this repo

- **Don't add new top-level markdown status reports.** The repo already drowns in them; updates belong in code, commit messages, or — at most — `docs/`.
- **Don't trust the README's API surface.** If you need to know what an endpoint or feature actually does, grep the code; if the code isn't there, the feature isn't there.
- **Be wary of `.uid` files.** Every `.gd` has a sibling `.gd.uid` Godot generates; edit the `.gd`, leave the `.uid` alone, and don't delete one without the other.
- **Tile rendering is a known sore spot.** Recent commits (see `git log`) are all texture/atlas fixes. If sprites render blank, solid-colored, or misaligned, check: AtlasTexture region, WHITE modulation, NEAREST filter (project setting), and that `TextureExtractor` actually finished `_ready` before the consumer ran.
- **Networking changes can't be verified locally** without bringing up a separate WebSocket server matching `message_protocol.gd`. State this explicitly when reporting completion of network-related work.
- **GUT 跑测前必须 `--import` 一次** to refresh class cache，否则 `class_name` 改动后 Godot 仍按旧 cache 解析，会出现 "Identifier X not declared" / "Static function not found" 之类的 Parse error。
- **`class_name` 全局重复会让一边被 hide。** 新增 `class_name` 前 `grep -rn 'class_name <Name>' godot/`；命名冲突时优先重命名引用方少的一侧，避免破坏多文件依赖链。
