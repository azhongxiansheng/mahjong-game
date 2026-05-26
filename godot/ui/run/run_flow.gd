class_name RunFlow extends Control

# 麻将王 — 里程碑 4 第 4 步：Run 流程主控制器（plan-4 D6）
#
# 把 5 个 UI 子组件 + RunState + GameDriver 串成完整 Run：
#   1. starter_pack_picker → 选起始包 → new RunState
#   2. chapter_map_view → 玩家选下一节点
#   3a. 战斗节点 → BattleNodeRunner.run_battle_to_node_result → NodeResult
#   3b. 占位节点 → placeholder_node → "下一步"按钮 → from_placeholder
#   4. RunState.complete_node(result) → emit node_completed / run_failed / run_won
#   5. 失败 / 通关 → run_summary
#   6. "返回主菜单" → 回 starter_pack_picker

const STARTER_PACK_PICKER := preload("res://ui/run/starter_pack_picker.tscn")
const CHAPTER_MAP_VIEW := preload("res://ui/run/chapter_map_view.tscn")
const PLACEHOLDER_NODE := preload("res://ui/run/placeholder_node.tscn")
const EVENT_NODE := preload("res://ui/run/event_node.tscn")
const CAMP_NODE := preload("res://ui/run/camp_node.tscn")
const RUN_SUMMARY := preload("res://ui/run/run_summary.tscn")
const RUN_HUD := preload("res://ui/run/run_hud.tscn")
# M5 第 3 步新增：抽卡 / 商店 UI
const PACK_OPEN_VIEW := preload("res://ui/run/pack_open_view.tscn")
const SHOP_VIEW := preload("res://ui/run/shop_view.tscn")
# M5 第 4 步新增：存档恢复
const CONTINUE_PROMPT := preload("res://ui/run/continue_prompt.tscn")
# 战斗节点真实可玩：玩家 vs 3 AI
const PLAYABLE_TABLE := preload("res://ui/four_player_table/playable_table.tscn")
const REWARD_PICK_VIEW := preload("res://ui/run/reward_pick_view.tscn")
const CHARACTER_PICKER := preload("res://ui/run/character_picker.tscn")

var _run_state: RunState = null
var _hud: RunHud = null
var _current_panel: Control = null
var _last_node_ref: NodeRef = null
var _last_result: NodeResult = null
var _seed_seed: int = 0
var _pending_character_id: StringName = &""
var _pending_difficulty: int = Difficulty.Level.NORMAL
# 章节过场:_on_run_node_completed 检测 chapter 变化,弹出 ChapterIntroOverlay
# 让玩家"为剧情想通关"。第一次进 run 时 _last_chapter=0 跳过 ch1 intro。
var _last_chapter: int = 0
# Daily 模式:StarterPackPicker toggle 后置 true,_on_pack_chosen 用
# DailySeed.today_seed() 替代默认 Time.get_ticks_msec()。全服同 seed 可比成绩。
var _daily_mode: bool = false

func _ready() -> void:
	custom_minimum_size = Vector2(DT.VIEW_W, DT.VIEW_H)
	_seed_seed = Time.get_ticks_msec()
	_hud = RUN_HUD.instantiate()
	_hud.position = Vector2(0, 0)
	add_child(_hud)
	# Daily quest: 接 quest_claimed signal → 加 renown + 弹 toast。
	# Run 内完成的任务 gold 也加到 _run_state(若存在);run 外只加 renown。
	var dq = get_node_or_null("/root/DailyQuest")
	if dq and not dq.quest_claimed.is_connected(_on_daily_quest_claimed):
		dq.quest_claimed.connect(_on_daily_quest_claimed)
	# BattlePass 升级 toast — quest 完成会触发 add_xp 进而 emit level_up
	var bp = get_node_or_null("/root/BattlePass")
	if bp and not bp.level_up.is_connected(_on_bp_level_up):
		bp.level_up.connect(_on_bp_level_up)
	# 新手引导:第一次启动(SettingsManager.tutorial_seen=false)弹出 5 页教程,
	# 玩家点 Skip / 读完最后页 → 标 seen=true 持久化,以后不再弹。
	_maybe_show_tutorial()
	# M5 第 4 步：启动时检查是否有存档（user://savegame.json）
	var ss := _save_system()
	if ss and ss.has_save():
		_show_continue_prompt()
	else:
		_show_starter_picker()


func _maybe_show_tutorial() -> void:
	var sm = get_node_or_null("/root/SettingsManager")
	if sm == null:
		return
	if sm.tutorial_seen:
		return
	var t := TutorialOverlay.new()
	t.name = "_tutorial_overlay_root"
	get_tree().root.add_child(t)


# ESC 唤起设置 overlay,H 唤起帮助 overlay。BattleNode 在战斗内有自己的 ESC,
# 但 run 主流程(地图/商店/事件)由此处接管。overlay 自己关闭。
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k: InputEventKey = event
	if not k.pressed or k.echo:
		return
	if k.keycode == KEY_ESCAPE:
		if get_tree().root.get_node_or_null("_settings_overlay_root") != null:
			return
		var overlay := SettingsOverlay.new()
		overlay.name = "_settings_overlay_root"
		get_tree().root.add_child(overlay)
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_H:
		# 帮助 overlay 已开则不重复弹(让自己 close)
		if get_tree().root.get_node_or_null("_help_overlay_root") != null:
			return
		var help := HelpOverlay.new()
		help.name = "_help_overlay_root"
		get_tree().root.add_child(help)
		get_viewport().set_input_as_handled()

# ---- panel transitions ----

func _show_starter_picker() -> void:
	_show_character_picker()

func _show_character_picker() -> void:
	var picker: CharacterPicker = CHARACTER_PICKER.instantiate()
	_swap_panel(picker)
	picker.character_chosen.connect(_on_character_chosen)

func _on_character_chosen(char_id: StringName) -> void:
	_pending_character_id = char_id
	if _current_panel is CharacterPicker:
		_pending_difficulty = _current_panel.get_selected_difficulty()
	var pack_picker: StarterPackPicker = STARTER_PACK_PICKER.instantiate()
	_swap_panel(pack_picker)
	pack_picker.pack_chosen.connect(_on_pack_chosen)
	pack_picker.daily_mode_toggled.connect(_on_daily_mode_toggled)


# Daily quest 完成回调:加 gold(若 run 内) + renown + 弹 toast。BattlePass 也
# 在监听同 signal 累 season_xp(本文件不重复发,避免双发)。
func _on_daily_quest_claimed(_quest_id: StringName, gold: int, renown: int, _xp: int) -> void:
	if _run_state and not _run_state.finished:
		_run_state.gold += gold
		_hud.bind_run_state(_run_state)
	var mp = get_node_or_null("/root/MetaProgress")
	if mp:
		mp.renown += renown
		if mp.has_method("save_meta"):
			mp.save_meta()
	var toast = get_node_or_null("/root/SaveToast")
	if toast and toast.has_method("show_message"):
		toast.show_message("✅ 每日任务 +%d gold · +%d 声望" % [gold, renown])


# BattlePass 升级回调:弹 toast 让玩家感知"赛季在动"。reward_unlocked 由
# BattlePass UI 在主菜单 / 战令页直接消费,这里不重复处理。
func _on_bp_level_up(new_level: int) -> void:
	var toast = get_node_or_null("/root/SaveToast")
	if toast and toast.has_method("show_message"):
		toast.show_message("🎖️ 赛季等级 → Lv.%d" % new_level)


# Daily 模式 toggle 回调:仅记一个 flag,等 _on_pack_chosen 时按 flag 选 seed。
# 玩家可随时再点取消(_daily_mode 跟着切回 false),pack_chosen 之前都生效。
func _on_daily_mode_toggled(enabled: bool) -> void:
	_daily_mode = enabled

# M5 第 4 步：存档恢复入口
func _show_continue_prompt() -> void:
	var prompt: ContinuePrompt = CONTINUE_PROMPT.instantiate()
	_swap_panel(prompt)
	# 试着加载并显示摘要（即使加载失败也允许玩家点 New 清档继续）
	var ss := _save_system()
	var saved_rs = ss.load_run() if ss else null
	prompt.set_save_summary(saved_rs)
	prompt.continue_run.connect(func(): _on_continue_run(saved_rs))
	prompt.new_run.connect(_on_new_run_after_clear)

func _on_continue_run(saved_rs) -> void:
	if saved_rs == null:
		# 损坏存档：fallback 清档 + 新 Run
		_on_new_run_after_clear()
		return
	_run_state = saved_rs
	_run_state.node_completed.connect(_on_run_node_completed)
	_run_state.run_failed.connect(_on_run_failed)
	_run_state.run_won.connect(_on_run_won)
	_hud.bind_run_state(_run_state)
	_show_chapter_map()

func _on_new_run_after_clear() -> void:
	var ss := _save_system()
	if ss:
		ss.clear_run()
	_show_starter_picker()

func _show_chapter_map() -> void:
	var view: ChapterMapView = CHAPTER_MAP_VIEW.instantiate()
	_swap_panel(view)
	view.set_options(_run_state.next_node_options())
	# US-004：传入完整 ChapterMap 启用视觉地图渲染（fallback 文本按钮）
	if _run_state and _run_state.current_map:
		view.set_chapter_map(_run_state.current_map)
	if _last_node_ref and _last_result:
		view.set_last_result_text(
			ChapterMapView.format_last_result(_last_node_ref, _last_result)
		)
	view.node_chosen.connect(_on_node_chosen)

func _show_summary() -> void:
	var summary: RunSummary = RUN_SUMMARY.instantiate()
	_swap_panel(summary)
	summary.bind_run_state(_run_state)
	summary.back_to_menu.connect(_reset)
	summary.revive_requested.connect(_on_revive_requested)


# 玩家在 RunSummary 失败页点"花 X gold 复活": 扣 gold + hp 恢复 1 + 把
# run_state 回滚到失败前 (未 finalize), 回到当前章节地图继续选节点。
# RunSummary 已经校验过 gold >= REVIVE_GOLD_COST, 这里再 defense check 一遍。
func _on_revive_requested() -> void:
	if _run_state == null:
		return
	if _run_state.gold < RunSummary.REVIVE_GOLD_COST:
		return  # 防御:UI 不该让我们到这一步
	_run_state.gold -= RunSummary.REVIVE_GOLD_COST
	_run_state.hp = 1  # 复活给 1 HP (起死回生,不是满血,保留紧迫感)
	_run_state.finished = false
	_run_state.won = false
	# P1 fix (codex review): _on_run_failed 已经 finalize (清存档 + 加 renown +
	# 记 ended)。如果不撤销,玩家"故意失败 + 复活"可重复刷 renown/runs_completed
	# /runs_failed (每次失败都计一次)。撤销让计数恢复到 fail 之前的状态。
	# 成就解锁不撤回(达成是真发生过)。
	var mp = get_node_or_null("/root/MetaProgress")
	if mp and mp.has_method("revert_last_run"):
		mp.revert_last_run(false)
	var sm = get_node_or_null("/root/StatsManager")
	if sm and sm.has_method("revert_run_ended"):
		sm.revert_run_ended(false)
	_hud.bind_run_state(_run_state)
	_save_run_state()
	# 回到章节地图选下一节点 (失败的节点不重打,直接进下一选项)
	_show_chapter_map()

# ---- callbacks ----

func _on_pack_chosen(pack_id: StringName) -> void:
	# Daily 模式:用 DailySeed.today_seed() 让全服同 seed,玩家可比成绩。
	# 非 daily 用 Time.get_ticks_msec() 当 seed 保持每次 run 随机。
	var actual_seed: int = DailySeed.today_seed() if _daily_mode else _seed_seed
	_run_state = RunState.new(actual_seed)
	_run_state.difficulty = _pending_difficulty
	_apply_character(_pending_character_id)
	_run_state.hp += Difficulty.hp_modifier(_pending_difficulty)
	StarterPacks.apply_to(_run_state, pack_id)
	_run_state.node_completed.connect(_on_run_node_completed)
	_run_state.run_failed.connect(_on_run_failed)
	_run_state.run_won.connect(_on_run_won)
	_hud.bind_run_state(_run_state)
	# M5 第 4 步：新 Run 开始时立即存档
	_save_run_state()
	# 终身统计:run 开始计 1
	var sm = get_node_or_null("/root/StatsManager")
	if sm:
		sm.record_run_started()
		# 记 baseline snapshot 让 RunSummary 算"本 run 亮点"diff
		if sm.has_method("snapshot"):
			_run_state.stats_at_start = sm.snapshot()
	# Pro 日志:run lifecycle 摘要
	var log_node = get_node_or_null("/root/Log")
	if log_node:
		var mode_tag: String = "daily" if _daily_mode else "free"
		log_node.info("run", "started pack=%s difficulty=%d seed=%d mode=%s" % [
			str(pack_id), int(_pending_difficulty), actual_seed, mode_tag])
	# Daily run 启动 toast 让玩家明确进入 daily(避免点了 toggle 又忘了)
	if _daily_mode:
		var toast = get_node_or_null("/root/SaveToast")
		if toast and toast.has_method("show_message"):
			toast.show_message("🗓️ 今日挑战 #%s 开始" % DailySeed.today_display())
	_show_chapter_map()

func _on_node_chosen(node_index: int) -> void:
	_run_state.choose_next_node(node_index)
	var node_ref: NodeRef = _run_state.current_node_ref()
	_last_node_ref = node_ref
	if NodeKind.is_battle(node_ref.kind):
		_run_battle_node(node_ref)
	elif node_ref.kind == NodeKind.Kind.SHOP:
		_show_shop(node_ref)
	else:
		_show_placeholder(node_ref)

func _on_run_node_completed(_opts: Array) -> void:
	_hud.bind_run_state(_run_state)
	# M5 第 4 步：节点完成后立即自动存档
	_save_run_state()
	# 速战连击 toast: streak >= 2 时玩家拿到额外 gold,用 SaveToast 通道弹提示
	# 让玩家感知"我在连胡,gold 多了"。toast 在 chapter_map 切换前显示。
	if _run_state.last_speed_streak_bonus > 0:
		var toast = get_node_or_null("/root/SaveToast")
		if toast and toast.has_method("show_message"):
			toast.show_message("🔥 速战 %d 连胡 +%d gold" % [
				_run_state.speed_streak, _run_state.last_speed_streak_bonus])
	# 章节过场:检测到 chapter 推进(打过 Boss + 还有下章) → 弹剧情 overlay。
	# _last_chapter=0 第一次跑时跳过 ch1 intro(那是 starter_pack/character
	# picker 的职责)。awaits overlay closed 后继续下个 panel。
	if _run_state.chapter > _last_chapter and _last_chapter > 0:
		await _show_chapter_intro_for(_run_state.chapter)
	_last_chapter = _run_state.chapter
	# M5 第 3 步：战斗节点结算后给 1 抽（spec §9.2 节点单抽自动）。
	if _last_node_ref and NodeKind.is_battle(_last_node_ref.kind):
		_show_node_pack_open()
	else:
		_show_chapter_map()


# 章节过场:按 new_chapter 选 ChapterIntroOverlay.Beat,弹 overlay 等关闭。
# ch2 → Beat.ENTER_CHAPTER_2;ch3 → Beat.ENTER_CHAPTER_3;无对应章默认跳过。
func _show_chapter_intro_for(new_chapter: int) -> void:
	var beat: int = -1
	match new_chapter:
		2: beat = ChapterIntroOverlay.Beat.ENTER_CHAPTER_2
		3: beat = ChapterIntroOverlay.Beat.ENTER_CHAPTER_3
	if beat < 0:
		return
	var overlay := ChapterIntroOverlay.new()
	overlay.set_beat(beat)
	get_tree().root.add_child(overlay)
	await overlay.closed

func _on_run_failed() -> void:
	_hud.bind_run_state(_run_state)
	# M5 第 4 步：Run 终态清存档（不允许"复活"重玩失败 Run）
	var ss := _save_system()
	if ss:
		ss.clear_run()
	# M5 第 3 步：跨 Run 声望累计
	var mp := get_tree().root.get_node_or_null("MetaProgress")
	if mp:
		mp.add_renown_for_run(false)
	# 终身统计 + 成就
	var sm = get_node_or_null("/root/StatsManager")
	if sm:
		sm.record_run_ended(false)
	var log_node = get_node_or_null("/root/Log")
	if log_node:
		log_node.info("run", "FAILED at chapter=%d node=%d" % [
			int(_run_state.chapter), _run_state.history.size()])
	_show_summary()

func _on_run_won() -> void:
	_hud.bind_run_state(_run_state)
	var ss := _save_system()
	if ss:
		ss.clear_run()
	var mp := get_tree().root.get_node_or_null("MetaProgress")
	if mp:
		mp.add_renown_for_run(true)
	var sm = get_node_or_null("/root/StatsManager")
	if sm:
		sm.record_run_ended(true)
	var log_node = get_node_or_null("/root/Log")
	if log_node:
		log_node.info("run", "WON chapter=%d nodes=%d" % [
			int(_run_state.chapter), _run_state.history.size()])
	# 通关过场:RunSummary 之前播 WIN 剧情(3 句台词 ~8s),给玩家一段情绪
	# 高峰再看战绩。失败不播过场(避免冲淡失败感)。
	var overlay := ChapterIntroOverlay.new()
	overlay.set_beat(ChapterIntroOverlay.Beat.WIN)
	get_tree().root.add_child(overlay)
	await overlay.closed
	_show_summary()

# ---- node execution ----

# 战斗节点：玩家完整可玩。每局用 PlayableTable + PlayableBattleController；
# 跑完 4 局东风战（或半庄）后算 NodeResult。
func _run_battle_node(node_ref: NodeRef) -> void:
	var table: PlayableTable = PLAYABLE_TABLE.instantiate()
	_swap_panel(table)
	var node_seed: int = _run_state.run_seed * 100 + node_ref.index
	var boss_id: StringName = &""
	if node_ref.kind == NodeKind.Kind.BOSS:
		boss_id = ChapterConfig.get_boss_id(_run_state.chapter)
	var player_ability_ids: Array = _player_ability_ids()
	var player_tile_variants: Dictionary = _player_tile_variants()
	var player_consumable_ids: Array = _player_consumable_ids()
	var player_relic_ids: Array = _player_relic_ids()
	await _show_battle_prep(table, boss_id, player_ability_ids, player_tile_variants, player_consumable_ids, node_ref)
	# session_kind 从 node_ref 读 (同事 commit 813814e 修复的 silent bug):
	# 之前硬编码 east_round 让 GAP-4 speed mode 在 ChapterConfig/Generator/
	# BalanceConstants 全改完后仍无生效,玩家实际仍跑 4 局/节点。
	var session_kind: String = node_ref.session_kind
	# AI 难度按 chapter / difficulty / 节点类型决定:
	#  - 章 1 第一个 NORMAL 节点 + 难度 NORMAL → SimpleAi (新手第 1 局保护)
	#  - 其余 → HeuristicAi (有挑战感,之前硬编 SimpleAi 让所有玩家都太弱)
	# 之前 run_with_player_input_async 内部硬编 use_heuristic_ai=false,老手
	# 体验不到挑战。现在由 RunFlow 决策:让新手温暖入门,老手有压力。
	var use_heuristic: bool = _should_use_heuristic_ai(node_ref)
	var result: NodeResult = await BattleNodeRunner.run_with_player_input_async(
		table, get_tree(), node_seed, boss_id, player_ability_ids,
		player_tile_variants, session_kind, 0, player_consumable_ids,
		player_relic_ids, use_heuristic
	)
	if not is_instance_valid(table) or not table.is_inside_tree():
		return
	_last_result = result
	_run_state.complete_node(result)

# 节点 → AI 难度决策。新手保护规则:
#  - Difficulty.NORMAL + chapter 1 + 玩家访问节点数 <= 1 + NodeKind.NORMAL
#    → 用 SimpleAi (随机弃牌,几乎不胡)
#  - 其余情况 → HeuristicAi
# Boss / Elite / 章 2+ / 难度 HARD+ / 第 2+ 节点都吃 HeuristicAi。让"第 1 局"
# 是温暖的体验:玩家先熟悉规则 + UI + 自己的 deck,再面对真正会胡的对手。
# 战斗 prep 预告字串。读节点 session_kind + 难度策略,告诉玩家"几局 / AI 多硬"。
# 例: "速战 · 2 局 · 普通 AI (新手保护)" / "东风战 · 4 局 · 强 AI" / "半庄战 · 8 局 · 强 AI"
func _format_battle_preview(node_ref: NodeRef) -> String:
	var sk: String = node_ref.session_kind
	var hands: int = BalanceConstants.get_hands_per_node(sk)
	var session_name: String = ""
	match sk:
		"speed": session_name = "速战"
		"east_round": session_name = "东风战"
		"hanchan": session_name = "半庄战"
		_: session_name = sk
	var ai_label: String = "强 AI" if _should_use_heuristic_ai(node_ref) else "普通 AI（新手保护）"
	# 时长粗估:speed/east_round 一局 ~2 分钟,hanchan 一局 ~3 分钟
	var per_hand_min: int = 3 if sk == "hanchan" else 2
	var est_min: int = hands * per_hand_min
	return "%s · %d 局 · 约 %d 分钟 · %s" % [session_name, hands, est_min, ai_label]


func _should_use_heuristic_ai(node_ref: NodeRef) -> bool:
	if _run_state == null:
		return true
	# 难度高:全程 HeuristicAi
	if _run_state.difficulty > Difficulty.Level.NORMAL:
		return true
	# 章 2+: 全程 HeuristicAi
	if _run_state.chapter > 1:
		return true
	# Boss / Elite 节点:始终 HeuristicAi (这是"考核",不能放水)
	if node_ref.kind == NodeKind.Kind.BOSS or node_ref.kind == NodeKind.Kind.ELITE:
		return true
	# 已访问节点 >= 2:玩家熟悉了,上 HeuristicAi
	if _run_state.history.size() >= 2:
		return true
	# 剩下的:章 1 + Normal 难度 + 普通节点 + 前 2 个 → SimpleAi 保护
	return false


func _player_ability_ids() -> Array:
	var ids: Array = []
	if _run_state == null:
		return ids
	if _run_state.selected_character_id != &"":
		var ch: Character = CharacterPool.find(_run_state.selected_character_id)
		if ch and ch.ability_id != &"":
			ids.append(ch.ability_id)
	if _run_state.player_deck == null:
		return ids
	for a in _run_state.player_deck.abilities:
		if a != null:
			ids.append(a.id)
	return ids

func _player_tile_variants() -> Dictionary:
	if _run_state == null or _run_state.player_deck == null:
		return {}
	return _run_state.player_deck.tile_variants

func _player_relic_ids() -> Array:
	if _run_state == null:
		return []
	return _run_state.relic_ids()

func _player_consumable_ids() -> Array:
	var ids: Array = []
	if _run_state == null:
		return ids
	for c in _run_state.consumables:
		if c is ConsumableItem and c.is_battle():
			ids.append(c.id)
	return ids

func _show_placeholder(node_ref: NodeRef) -> void:
	# US-007：EVENT 节点用真实 UI（硬编码事件 + 选项 + 副作用）。
	if node_ref.kind == NodeKind.Kind.EVENT:
		_show_event(node_ref)
		return
	# US-005：CAMP 节点用真实 UI（恢复 HP）。其他类型仍用通用占位。
	if node_ref.kind == NodeKind.Kind.CAMP:
		_show_camp(node_ref)
		return
	var p: PlaceholderNode = PLACEHOLDER_NODE.instantiate()
	_swap_panel(p)
	p.set_node_kind(node_ref.kind)
	p.done.connect(func():
		_last_result = BattleNodeRunner.placeholder_result()
		_run_state.complete_node(_last_result)
	)

func _show_event(node_ref: NodeRef) -> void:
	var ev: EventNode = EVENT_NODE.instantiate()
	_swap_panel(ev)
	ev.bind_run_state(_run_state)
	# 用 run_seed * 7 + node.index 决定本节点抽哪个事件，保证存档恢复可复现
	var ev_seed: int = _run_state.run_seed * 7 + node_ref.index
	ev.set_event_seed(ev_seed)
	ev.done.connect(func():
		_last_result = BattleNodeRunner.placeholder_result()
		_run_state.complete_node(_last_result)
	)

func _show_camp(_node_ref: NodeRef) -> void:
	var camp: CampNode = CAMP_NODE.instantiate()
	_swap_panel(camp)
	camp.bind_run_state(_run_state)
	camp.done.connect(func():
		_last_result = BattleNodeRunner.placeholder_result()
		_run_state.complete_node(_last_result)
	)

# M5 第 3 步：战斗节点结算后弹 1 张抽卡奖励
func _show_node_pack_open() -> void:
	var view: RewardPickView = REWARD_PICK_VIEW.instantiate()
	_swap_panel(view)
	var draw_seed: int = _run_state.run_seed * 1000 + (_last_node_ref.index if _last_node_ref else 0)
	var options: Array = Gacha.draw_reward_options(_run_state.pity_state, draw_seed)
	var rank: int = _last_result.rank if _last_result else 1
	view.show_rewards(options, rank)
	view.reward_chosen.connect(func(result: GachaResult):
		_run_state.pity_state.record_draw(result.rarity)
		_apply_gacha_to_deck(result)
		_hud.bind_run_state(_run_state)
		_save_run_state()
		_show_chapter_map()
	)
	view.skipped.connect(func():
		_run_state.gold += RewardPickView.SKIP_GOLD_REWARD
		_hud.bind_run_state(_run_state)
		_save_run_state()
		_show_chapter_map()
	)

# M5 第 3 步：商店节点
func _show_shop(node_ref: NodeRef) -> void:
	var view: ShopView = SHOP_VIEW.instantiate()
	_swap_panel(view)
	var shop_seed: int = _run_state.run_seed * 1000 + node_ref.index + 7  # 偏移 7 避免与 pack 抽卡重复
	view.set_seed_and_gold(shop_seed, _run_state.gold)
	view.item_bought.connect(func(slot_index: int, result: GachaResult):
		_run_state.gold -= ShopView.price_for(result)
		_apply_gacha_to_deck(result)
		view.update_gold(_run_state.gold)
		_hud.bind_run_state(_run_state)
	)
	view.done.connect(func():
		_last_result = BattleNodeRunner.placeholder_result()
		_run_state.complete_node(_last_result)
	)

# 把 GachaResult 加进玩家 deck
func _apply_gacha_to_deck(result: GachaResult) -> void:
	if result == null or _run_state == null:
		return
	if result.kind == GachaResult.KIND_TILE and result.tile_variant:
		if _run_state.player_deck:
			_run_state.player_deck.add_tile_variant(result.tile_variant)
	elif result.kind == GachaResult.KIND_ABILITY and result.ability:
		if _run_state.player_deck:
			_run_state.player_deck.add_ability(result.ability)
	elif result.kind == GachaResult.KIND_CONSUMABLE and result.consumable:
		_run_state.add_consumable(result.consumable)
	elif result.kind == GachaResult.KIND_RELIC and result.relic:
		_run_state.add_relic(result.relic)

# ---- helpers ----

func _swap_panel(new_panel: Control) -> void:
	if _current_panel:
		_current_panel.queue_free()
	# PlayableTable 内部用绝对坐标硬编 1280×800 (FourPlayerTable 720 + ActionPanel
	# 80),不能跟 anchor 一起拉伸,否则 ActionPanel 落屏外或 SeatPanel 错位。
	# 用 scale 整体缩放到可用 height,顶部留 HUD_H 给 HUD,水平居中。
	# 其它面板 (starter picker / chapter map / shop ...) 走原 anchor 撑满路径。
	if new_panel is PlayableTable:
		new_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		new_panel.size = Vector2(DT.VIEW_W, DT.VIEW_H)
		var avail_h: float = float(DT.VIEW_H - DT.HUD_H)
		var scale_factor: float = avail_h / float(DT.VIEW_H)
		new_panel.scale = Vector2(scale_factor, scale_factor)
		new_panel.position = Vector2(
			(DT.VIEW_W - DT.VIEW_W * scale_factor) / 2.0,
			DT.HUD_H)
	else:
		new_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		new_panel.offset_top = DT.HUD_H
		new_panel.offset_left = 0
		new_panel.offset_right = 0
		new_panel.offset_bottom = 0
	add_child(new_panel)
	_current_panel = new_panel

func _make_loading_label(text: String) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var lbl := Label.new()
	lbl.text = text
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", DT.FONT_SUBTITLE)
	lbl.add_theme_color_override("font_color", DT.TEXT_MUTED)
	c.add_child(lbl)
	return c

static func _loading_text_for_battle(node_ref: NodeRef) -> String:
	var label := node_ref.display_name() if node_ref else "战斗"
	return "%s 进行中…\n（v1 v1 同步跑完整场东风战，无 4 人桌动画；M5/M6 视觉化）" % label

func _show_battle_prep(table: Control, boss_id: StringName, ability_ids: Array, tile_variants: Dictionary, consumable_ids: Array, node_ref: NodeRef = null) -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	table.add_child(overlay)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(DT.BG_BASE.r, DT.BG_BASE.g, DT.BG_BASE.b, DT.MODAL_BG_DIM)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(bg)
	var panel := VBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(600, 500)
	panel.offset_left = -300
	panel.offset_top = -250
	panel.offset_right = 300
	panel.offset_bottom = 250
	panel.add_theme_constant_override("separation", DT.GAP_NORMAL)
	overlay.add_child(panel)
	var title := Label.new()
	title.text = "战斗准备" if boss_id == &"" else "BOSS 战"
	DT.apply_title_style(title)
	panel.add_child(title)
	# 预告:本节点局数 + AI 难度,让玩家心理预期清晰("速战 2 局 vs Heuristic AI"
	# 比"开始战斗"更让人知道自己面对什么)。boss_id 不空时已有 "BOSS 战"标题
	# 传递主题色,不再重复 AI 信息。
	if node_ref != null:
		var preview := Label.new()
		preview.text = _format_battle_preview(node_ref)
		DT.apply_body_style(preview)
		preview.add_theme_color_override("font_color", DT.TEXT_MUTED)
		panel.add_child(preview)
	panel.add_child(HSeparator.new())
	if not ability_ids.is_empty():
		var ab_label := Label.new()
		ab_label.text = "角色能力"
		DT.apply_subtitle_style(ab_label)
		ab_label.add_theme_color_override("font_color", DT.TEXT_TITLE)
		panel.add_child(ab_label)
		for aid in ability_ids:
			var card: AbilityCard = _find_ability_card(aid)
			var l := Label.new()
			l.text = "  • %s" % (card.display_name if card else String(aid))
			DT.apply_body_style(l)
			panel.add_child(l)
	if tile_variants.size() > 0:
		var tv_label := Label.new()
		tv_label.text = "牌技能：%d 张" % tile_variants.size()
		DT.apply_subtitle_style(tv_label)
		tv_label.add_theme_color_override("font_color", DT.TEXT_TITLE)
		panel.add_child(tv_label)
	if not consumable_ids.is_empty():
		var c_label := Label.new()
		c_label.text = "战斗道具"
		DT.apply_subtitle_style(c_label)
		c_label.add_theme_color_override("font_color", DT.TEXT_TITLE)
		panel.add_child(c_label)
		for cid in consumable_ids:
			var item: ConsumableItem = _find_consumable(cid)
			var l := Label.new()
			l.text = "  • %s" % (item.display_name if item else String(cid))
			DT.apply_body_style(l)
			panel.add_child(l)
	panel.add_child(HSeparator.new())
	var btn := Button.new()
	btn.text = "开战！"
	btn.custom_minimum_size = Vector2(200, DT.BUTTON_H)
	btn.pressed.connect(func(): overlay.queue_free())
	panel.add_child(btn)
	while is_instance_valid(overlay):
		await get_tree().process_frame

func _find_ability_card(aid: StringName) -> AbilityCard:
	for a in CardPool.all_abilities():
		if a.id == aid:
			return a
	return null

func _apply_character(char_id: StringName) -> void:
	if _run_state == null or char_id == &"":
		return
	var ch: Character = CharacterPool.find(char_id)
	if ch == null:
		return
	_run_state.selected_character_id = char_id
	_run_state.hp = ch.starting_hp
	_run_state.max_hp = ch.starting_hp + 2
	_run_state.gold = ch.starting_gold

func _find_consumable(cid: StringName) -> ConsumableItem:
	for c in CardPool.all_consumables():
		if c.id == cid:
			return c
	return null

func _reset() -> void:
	_run_state = null
	_last_node_ref = null
	_last_result = null
	# Run 间种子不同
	_seed_seed += 1
	# P2 fix (codex review): _daily_mode 是 toggle 状态,不在 _reset 时清零会
	# 让上次 daily run 默默继承到下次 run (玩家以为开 free run 却跑了 daily
	# 同 seed)。下次进 starter picker 默认从"非 daily"开始,要 daily 主动 toggle。
	_daily_mode = false
	# _last_chapter 类似:残留会让回到主菜单后再开新 run 误判 chapter intro。
	_last_chapter = 0
	_hud._refresh_default()
	_show_starter_picker()

# M5 第 4 步：SaveSystem autoload 访问 helper
func _save_system() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("SaveSystem")

func _save_run_state() -> void:
	if _run_state == null:
		return
	var ss := _save_system()
	if ss:
		ss.save_run(_run_state)
