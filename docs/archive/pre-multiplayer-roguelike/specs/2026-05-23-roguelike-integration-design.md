# 麻将王 — 肉鸽道具/角色技能集成到日麻战斗

> **状态**：实施中（2026-05-23）

## 问题

所有肉鸽组件均已实装但从未用户可见：

- 40+ SkillHook（牌技能 28 + 角色能力 14）已有 GUT 测试覆盖
- CardPool / StarterPacks / Deck / TileVariant / AbilityCard 数据层完整
- BattleNodeRunner 注入链（player abilities + tile variants + boss abilities + AI abilities）已接通
- RunFlow + ChapterMap + Shop + Event + Camp 完整 UI

**断裂点**：`loading_screen.gd` 跳转 `main_simple_new.tscn`（遗留中式麻将静态展示），从不加载 `run_flow.tscn`。玩家看到的是 13 张静态牌。

## 设计

### 第 1 层：接通入口（Gate Opener）

`loading_screen.gd` 改为跳转 `run_flow.tscn`（RunFlow 已自带 starter pack → chapter map → battle 全循环）。

不新建主菜单场景——RunFlow._ready 已有存档检测 + starter pack picker + "返回主菜单"循环。待后续里程碑做精装主菜单时再抽离。

### 第 2 层：全链路 TDD 验证

用真实对象（非 mock）写 GUT 测试验证：

1. **StarterPack → Deck → Registry 注入**：选 control pack → player_deck 含 5 tile variants + 1 ability → BattleNodeRunner inject 后 registry.get_all_entries().size() > 0
2. **玩家技能真实触发**：seeded BC + thunder_5w_v1 注入 → run_to_end → WIN_DECLARED_PRE 时 ctx.han_deltas 包含 +1
3. **Boss 能力触发**：boss1_iron_curtain → RON_DECLARED 时 cancel_ron 生效
4. **AI 对手能力**：inject_random_ai_seat_abilities → AI seat 的 skill 也 fire

### 第 3 层：战斗内技能反馈 UI

PlayableTable 的 event polling toast 增加 SKILL_TRIGGERED 事件类型的格式化（技能名 + 效果摘要 + 受益人/受害人）。

## 范围

**In-scope**：入口接通 + TDD 全链路 + toast 增强
**Out-of-scope**：stub hook 升级为真实效果（后续任务）、主菜单美化、新 hook 创作

## 文件变更清单

| 文件 | 变更 |
|------|------|
| `scripts/loading_screen.gd` | 跳转改为 `res://ui/run/run_flow.tscn` |
| `tests/battle/test_roguelike_integration.gd` | 新增：全链路 TDD |
| `tests/battle/test_skill_trigger_e2e.gd` | 新增：玩家/Boss/AI 技能触发 e2e |
| `ui/four_player_table/playable_table.gd` | toast 增加 SKILL_TRIGGERED |
| `battle/battle_controller.gd` | _emit SKILL_TRIGGERED 事件（新事件类型） |
