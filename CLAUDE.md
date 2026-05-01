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

## Godot architecture

### Autoloads (singletons)
Defined in `godot/project.godot` `[autoload]`:
- **`GameManager`** (`scripts/game_manager.gd`) — holds user session (`user_data`, `is_logged_in`). Set after WeChat-style login.
- **`TextureExtractor`** (`scripts/texture_extractor.gd`) — runs at `_ready` of every scene. Loads the three FairyGUI atlas PNGs (`assets/mahjong_tiles/mahjong_atlas0{,_1,_2}.png`) and slices 34 mahjong tiles (`w1`-`w9`, `t1`-`t9`, `s1`-`s9`, plus `E S W N Z F B`) at **80×120 px** with **0 padding** using `AtlasTexture`. Tile size and atlas layout are reverse-engineered from the original 贵州弈乐麻将 FairyGUI bundle (see `mahjong.bin` and `extract_tiles.py` in that folder); changing `TILE_WIDTH`/`TILE_HEIGHT` will misalign every tile.

Tile-rendering invariants worth knowing:
- AtlasTexture is preferred over manual `get_region` (see commit `364db08`).
- Sprites must be modulated `WHITE` — anything else (including default theme tints) makes tiles render as solid color (commit `6090d26`).
- Texture filter is `TEXTURE_FILTER_NEAREST` for pixel-perfect rendering. **Set via project setting** `rendering/textures/canvas_textures/default_texture_filter=1` in `project.godot` —— `AtlasTexture` 自身没有 `filter_mode` 属性（旧代码曾误用，已修，参见 `texture_extractor.gd` 头部常量注释）。

### 日麻引擎与技能框架（active development）

新代码的组织（按里程碑 0a-0e + 1）：

- **`core/tile/`** — `TileId` 枚举（含字牌、E_WIND/S_WIND/...）、`Tile`（带 `owner_seat` 字段）、`Hand`、`Meld`（CHI/PON/MINKAN/ANKAN/ADDED_KAN）、`Wall`（含 dead wall API：`reserve_dead_wall(14)` / `take_rinshan()` / `peek_dora_indicator(n)` / `peek_uradora_indicator(n)`）。
- **`core/rules_japanese/`** — 和牌识别（`WinPattern.detect`）、分解（`StandardDecomposer`）、`ChiitoiDetector` / `KokushiDetector` / `WaitCalculator` / `FuritenChecker` / `DoraIndicator` / `ExhaustiveDraw` / `AbortiveDraw`；含子包：
  - `fu/` — 符算（`MeldFu` / `PairFu` / `WaitFu` / `FuCalculator`）
  - `score/` — 点数（`ScoreFormula` / `PayoutCalculator`）
  - `yaku/` — 38 个役判定（`yaku/pattern/` 形式役、`yaku/yakuman/` 役満、`yaku/state/` 状态役），`YakuEvaluator` 入口、`YakuEntries` 互斥规则
  - 顶层有 `ScoreCalc`（结算入口）、`WinContext` aka `ScoreContext`（结算上下文）、`YakuList`（dict 累计简版）
- **`core/turn_engine/`** — `TurnEngine` 状态机（draw / discard / advance / declare_riichi / apply_chi/pon/minkan/ankan/added_kan/ron/tsumo）、`ClaimValidator` 鸣牌合法性、`RiichiValidator` 立直触发、`DrawDetector` 流局触发。
- **`battle/`** — 运行时数据：`BattleState`（seats / wall / phase / dora_indicators / current_seat / honba / riichi_sticks）、`Seat`（hand / melds / points / riichi / furiten / discards）、`SkillScheduler` 调度器（owner/holder 分组 + rarity 排序 + 链路深度防护）、`BattleEvent`、`SkillCtx`、`TileInstance`。
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
