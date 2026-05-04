# Legacy 中麻代码归档

> **状态**：deprecated。新代码 **不要 import** 这些文件。

## 背景

本目录是 spec §15 风险点 "中麻规则代码（hu_rule.gd 等）替换不彻底导致两套规则共存" 的缓解：把 M0 之前的中式麻将旧实现搬到独立目录，与 `core/rules_japanese/` 日麻新引擎物理隔离。

CLAUDE.md "Repository shape" 也明确：`scripts/` 下的 `win_pattern.gd / hu_rule.gd / mahjong_deck.gd` 等"已不在活跃开发路径上"。

## 归档时间线

- **2026-05-04** (M9)：12 个零引用的中麻文件搬到本目录
  - 役 / 听 / 胡判定：`hu_rule.gd` / `win_checker.gd` / `special_win_checker.gd` / `debug_win_checker.gd`
  - 听牌缓存 / 异步：`ting_checker.gd` / `async_ting_checker.gd` / `ting_cache.gd` / `ting_result.gd`
  - 牌组数据：`mahjong_deck.gd` / `card_deck.gd` / `card_hand.gd` / `card_data.gd`

## 仍留在 `scripts/` 的中麻相关文件

不在本目录归档但仍是中麻血统（活跃路径有依赖，不能移）：

- `scripts/card_tile.gd` — `scenes/card_tile.tscn` 直接引用；UI 复用占位
- `scripts/win_pattern.gd` — class_name 已移除避免冲突；保留作 lookup 工具
- `scripts/ai_player.gd / achievement_*.gd / leaderboard*.gd` — 中麻时代的占位 UI / sketch；新引擎不依赖

后续 `scripts/` 大清理（删除 / 整体重命名）留 Phase 2。

## 反向迁移规则

如某 PR 必须复用本目录任一类，**先回到主线** 把它升级到日麻规范（drop 中麻规则、对齐 `core/rules_japanese/` API），再从 `legacy/` 拷出。**禁止在 `legacy/` 内继续修改逻辑**。
