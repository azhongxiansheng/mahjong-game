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

## 仍留在 `scripts/` 的非活跃文件

未归档但仍非活跃路径（有 .tscn 引用 或 间接依赖未拆）：

- `scripts/card_tile.gd` — `scenes/card_tile.tscn` ext_resource
- `scripts/win_pattern.gd` — class_name 已移除避免冲突；lookup 工具
- `scripts/leaderboard_*.gd` — `scenes/leaderboard.tscn` 直接引用
- `scripts/ai_player.gd / enemy.gd / player.gd` — 中麻 era 占位
- `scripts/main.gd / main_simple.gd / wechat_login.gd / loading_screen.gd / hand_display.gd / game_ui.gd` — 主入口 / 渲染（活跃路径，不动）
- `scripts/game_manager.gd / texture_extractor.gd` — 仍在 autoloads（activeloads，必须留）
- `scripts/animated_title / bin_*` 等少量纯 helper

后续 `scripts/` 第 3 批清理（拆 .tscn 依赖 / leaderboard_* / ai_player）留 Phase 2。

## 反向迁移规则

如某 PR 必须复用本目录任一类，**先回到主线** 把它升级到日麻规范（drop 中麻规则、对齐 `core/rules_japanese/` API），再从 `legacy/` 拷出。**禁止在 `legacy/` 内继续修改逻辑**。
