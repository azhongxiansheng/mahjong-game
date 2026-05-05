# Legacy 中麻代码归档

> **状态**：deprecated。新代码 **不要 import** 这些文件。

## 背景

本目录是 spec §15 风险点 "中麻规则代码（hu_rule.gd 等）替换不彻底导致两套规则共存" 的缓解：把 M0 之前的中式麻将旧实现搬到独立目录，与 `core/rules_japanese/` 日麻新引擎物理隔离。

CLAUDE.md "Repository shape" 也明确：`scripts/` 下的 `win_pattern.gd / hu_rule.gd / mahjong_deck.gd` 等"已不在活跃开发路径上"。

## 归档时间线

### 2026-05-04（M9 第 1 批）— 12 个中麻规则 / 牌组文件

- 役 / 听 / 胡判定：`hu_rule.gd` / `win_checker.gd` / `special_win_checker.gd` / `debug_win_checker.gd`
- 听牌缓存 / 异步：`ting_checker.gd` / `async_ting_checker.gd` / `ting_cache.gd` / `ting_result.gd`
- 牌组数据：`mahjong_deck.gd` / `card_deck.gd` / `card_hand.gd` / `card_data.gd`

### 2026-05-05（M9 第 2 批）— 50 个 multiplayer / social / 占位 UI 文件

中麻时代的"中麻+联机"草图（依赖 main.go 假后端，从未真跑通）：

- **聊天**：`chat_message / chat_system / chat_ui`
- **好友**：`friend / friend_manager / friend_notifier / friend_system / friend_ui`
- **成就**：`achievement / achievement_notifier / achievement_system / achievement_tracker / achievement_ui`
- **大厅 / 房间**：`room_manager / lobby_manager / lobby_ui / game_room / game_record / game_server`
- **网络**：`network_client / network_debugger / network_message / network_test_suite / network_tester`
- **同步**：`game_state_synchronizer / game_synchronizer / multiplayer_game_flow / player_connection_manager / player_matcher / player_stats`
- **赛季 / 战队**：`season / squad / team / team_system`
- **微信 / 通知**：`wechat_icon_downloader / wechat_icon_manager / notification / notification_center / notification_ui`
- **数据库 / 表单**：`database_manager / form_validator / login_ui / register_ui`
- **基础 UI / 工具**：`screen_base / ui_manager / ui_theme / rank_calculator / object_pool / operation_queue / performance_monitor / logger / user`

### 2026-05-05（M9 第 3 批）— 27 个零引用占位 / 测试 helper

零引用 helper / 占位 UI / M0-era 测试场景驱动文件：

- **AI / 卡片占位**：`ai_player / card_animation / card_animator / card_ui / special_card`
- **游戏状态机占位**：`game_config / game_controller / game_debug / game_flow / game_integration / game_state / game_tester / hand_display_manager`
- **UI / 网络 helper**：`animated_title / main_menu_ui / message_protocol / network_manager / config_manager / ui_diagnostics`
- **诊断 / 解密工具**：`bin_analyzer / bin_dump`（FairyGUI 资源逆向工具，已不需要）
- **M0-era 测试**：`test_achievement / test_friend / test_leaderboard / test_leaderboard_integration / unit_tests`（全是 scene-driven 手测，非 GUT；新引擎用 `tests/` 全部 GUT）
- **小尾巴**：`win_result`

### 2026-05-05（M9 第 4 批）— 8 个 .gd + 5 .tscn（首次 .tscn co-archive）

「.tscn 引用但 game flow 不可达」的 .gd 连同各自 .tscn 一起搬到 `legacy/scenes/`，
.tscn 内 ext_resource 路径同步重写到 `res://legacy/...`：

- `leaderboard_entry / leaderboard_system / leaderboard_ui` + `leaderboard.tscn`（leaderboard 功能从未接入 game flow）
- `enemy / player` + `enemy.tscn / player.tscn`（中麻 era 占位 actor）
- `test_mahjong_display / test_texture_extractor` + `test_mahjong_display.tscn / test_texture.tscn`（M0 手测 harness）
- `win_pattern.gd`（旧 LegacyWinPattern；class_name 早已移除避让 `core/rules_japanese/win_pattern.gd`，零引用）

`scripts/` 文件数 96 → 46 (#103) → 17 (#104) → **9**（减少 91%）。

## 仍留在 `scripts/` 的活跃文件（9 个 .gd）

**autoloads（project.godot 硬依赖）**：
- `game_manager.gd / texture_extractor.gd`

**主入口 / 主场景活跃路径**：
- `main.gd / wechat_login.gd / loading_screen.gd`（启动 → main.tscn）
- `main_simple.gd`（`scenes/main_simple_new.tscn` ext_resource）
- `game_ui.gd / hand_display.gd`（`scenes/game_ui.tscn`，旧中式 UI；新引擎 UI 路径在 `battle/`）
- `card_tile.gd`（`scenes/card_tile.tscn`，被 `hand_display.gd` 间接复用）

至此 `scripts/` 目录只剩活跃路径文件，spec §15 风险点完成缓解。

## 反向迁移规则

如某 PR 必须复用本目录任一类，**先回到主线** 把它升级到日麻规范（drop 中麻规则、对齐 `core/rules_japanese/` API），再从 `legacy/` 拷出。**禁止在 `legacy/` 内继续修改逻辑**。
