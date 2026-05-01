# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Agent 工作流、编码纪律、闸门、TDD、Git/发布原则详见 [`AGENTS.md`](./AGENTS.md)。本文件只描述项目结构与技术事实；行为约束以 `AGENTS.md` 为准。**

## Repository shape (read this first — README.md is misleading)

This repo contains **two unrelated trees** that share a directory but not a build:

1. **`godot/`** — a **Godot 4.5** client written in GDScript (216 scripts). This is the actual game. Main scene: `scenes/wechat_login_final.tscn` (set in `godot/project.godot`).
2. **`main.go` + `Dockerfile` + `start.sh`** at the repo root — a **stub Go HTTP server** that only serves `/` and `/api/health` returning `{"status":"ok"}`. It exists solely to satisfy Railway's healthcheck. **There is no real backend in this repo.** The README's references to a `backend/` directory, `/auth/...` and `/game/...` endpoints, JWT, ELO, achievements, "20,000+ lines of production code," etc. do not match the code on disk — treat the README as marketing copy, not architecture documentation.

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

There is **no test runner / CI** for the GDScript code. Files named `test_*.gd` (e.g. `test_mahjong_display.gd`, `test_texture_extractor.gd`) are scene-driven manual smoke tests — open the matching `.tscn` in the editor and press F6.

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
- Texture filter is `TEXTURE_FILTER_NEAREST` for pixel-perfect rendering.

### Game-logic clusters in `godot/scripts/`
Scripts are flat (no subdirs). Group them by prefix when navigating:
- **Mahjong rules / state**: `mahjong_deck.gd`, `card_deck.gd`, `card_hand.gd`, `card_tile.gd`, `card_data.gd`, `hu_rule.gd`, `win_checker.gd`, `special_win_checker.gd`, `debug_win_checker.gd`.
- **Ting (听牌) detection**: `ting_checker.gd`, `async_ting_checker.gd`, `ting_cache.gd`, `ting_result.gd`. Async path exists because synchronous ting-checking blocks the main thread on full hands.
- **Display / UI**: `hand_display.gd`, `hand_display_manager.gd`, `game_ui.tscn`/`.gd`, `card_animator.gd`, `card_animation.gd`, `main_menu_ui.gd`, `animated_title.gd`.
- **Networking (client side, no server present)**: `network_manager.gd` (WebSocket lifecycle), `network_client.gd`, `network_message.gd`, `message_protocol.gd`, `network_debugger.gd`, `network_tester.gd`, `network_test_suite.gd`.
- **Achievements / leaderboard / AI**: `achievement_*.gd`, `leaderboard.tscn`, `ai_player.gd`. These are client-only feature sketches; without a backend they have no persistence.
- **FairyGUI reverse-engineering helpers**: `bin_analyzer.gd`, `bin_dump.gd`, `texture_extractor.gd`, plus root-level `reverse_fairygui_bin.py`, `analyze_atlas.py`, `extract_mahjong_tiles*.{py,ps1,bat}`. Used to derive tile coordinates from `mahjong.bin`.

### Scenes
Boot scene is `wechat_login_final.tscn`. After login it transitions to `main.tscn` / `main_simple_new.tscn`. `test_*.tscn` scenes are manual harnesses — don't link production code to them.

## Working in this repo

- **Don't add new top-level markdown status reports.** The repo already drowns in them; updates belong in code, commit messages, or — at most — `docs/`.
- **Don't trust the README's API surface.** If you need to know what an endpoint or feature actually does, grep the code; if the code isn't there, the feature isn't there.
- **Be wary of `.uid` files.** Every `.gd` has a sibling `.gd.uid` Godot generates; edit the `.gd`, leave the `.uid` alone, and don't delete one without the other.
- **Tile rendering is a known sore spot.** Recent commits (see `git log`) are all texture/atlas fixes. If sprites render blank, solid-colored, or misaligned, check: AtlasTexture region, WHITE modulation, NEAREST filter, and that `TextureExtractor` actually finished `_ready` before the consumer ran.
- **Networking changes can't be verified locally** without bringing up a separate WebSocket server matching `message_protocol.gd`. State this explicitly when reporting completion of network-related work.
