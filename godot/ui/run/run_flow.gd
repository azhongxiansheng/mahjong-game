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

func _ready() -> void:
	custom_minimum_size = Vector2(1280, 720)
	_seed_seed = Time.get_ticks_msec()
	_hud = RUN_HUD.instantiate()
	_hud.position = Vector2(0, 0)
	add_child(_hud)
	# M5 第 4 步：启动时检查是否有存档（user://savegame.json）
	var ss := _save_system()
	if ss and ss.has_save():
		_show_continue_prompt()
	else:
		_show_starter_picker()

# ---- panel transitions ----

func _show_starter_picker() -> void:
	_show_character_picker()

func _show_character_picker() -> void:
	var picker: CharacterPicker = CHARACTER_PICKER.instantiate()
	_swap_panel(picker)
	picker.character_chosen.connect(_on_character_chosen)

func _on_character_chosen(char_id: StringName) -> void:
	_pending_character_id = char_id
	var pack_picker: StarterPackPicker = STARTER_PACK_PICKER.instantiate()
	_swap_panel(pack_picker)
	pack_picker.pack_chosen.connect(_on_pack_chosen)

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

# ---- callbacks ----

func _on_pack_chosen(pack_id: StringName) -> void:
	_run_state = RunState.new(_seed_seed)
	_apply_character(_pending_character_id)
	StarterPacks.apply_to(_run_state, pack_id)
	_run_state.node_completed.connect(_on_run_node_completed)
	_run_state.run_failed.connect(_on_run_failed)
	_run_state.run_won.connect(_on_run_won)
	_hud.bind_run_state(_run_state)
	# M5 第 4 步：新 Run 开始时立即存档
	_save_run_state()
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
	# M5 第 3 步：战斗节点结算后给 1 抽（spec §9.2 节点单抽自动）。
	if _last_node_ref and NodeKind.is_battle(_last_node_ref.kind):
		_show_node_pack_open()
	else:
		_show_chapter_map()

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
	_show_summary()

func _on_run_won() -> void:
	_hud.bind_run_state(_run_state)
	var ss := _save_system()
	if ss:
		ss.clear_run()
	var mp := get_tree().root.get_node_or_null("MetaProgress")
	if mp:
		mp.add_renown_for_run(true)
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
	await _show_battle_prep(table, boss_id, player_ability_ids, player_tile_variants, player_consumable_ids)
	var session_kind: String = "east_round"
	var result: NodeResult = await BattleNodeRunner.run_with_player_input_async(
		table, get_tree(), node_seed, boss_id, player_ability_ids,
		player_tile_variants, session_kind, 0, player_consumable_ids, player_relic_ids
	)
	if not is_instance_valid(table) or not table.is_inside_tree():
		return
	_last_result = result
	_run_state.complete_node(result)

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
	new_panel.position = Vector2(0, 50)  # HUD 占了 0..40
	add_child(new_panel)
	_current_panel = new_panel

func _make_loading_label(text: String) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(800, 600)
	var lbl := Label.new()
	lbl.text = text
	lbl.size = Vector2(800, 600)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 24)
	c.add_child(lbl)
	return c

static func _loading_text_for_battle(node_ref: NodeRef) -> String:
	var label := node_ref.display_name() if node_ref else "战斗"
	return "%s 进行中…\n（v1 v1 同步跑完整场东风战，无 4 人桌动画；M5/M6 视觉化）" % label

func _show_battle_prep(table: Control, boss_id: StringName, ability_ids: Array, tile_variants: Dictionary, consumable_ids: Array) -> void:
	var overlay := Control.new()
	overlay.size = Vector2(1280, 800)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	table.add_child(overlay)
	var bg := ColorRect.new()
	bg.size = Vector2(1280, 800)
	bg.color = Color(0, 0, 0, 0.85)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(bg)
	var panel := VBoxContainer.new()
	panel.position = Vector2(340, 120)
	panel.custom_minimum_size = Vector2(600, 500)
	overlay.add_child(panel)
	var title := Label.new()
	title.text = "战斗准备" if boss_id == &"" else "BOSS 战"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	panel.add_child(title)
	panel.add_child(HSeparator.new())
	if not ability_ids.is_empty():
		var ab_label := Label.new()
		ab_label.text = "角色能力："
		ab_label.add_theme_font_size_override("font_size", 20)
		ab_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
		panel.add_child(ab_label)
		for aid in ability_ids:
			var card: AbilityCard = _find_ability_card(aid)
			var l := Label.new()
			l.text = "  • %s" % (card.display_name if card else String(aid))
			l.add_theme_font_size_override("font_size", 16)
			l.add_theme_color_override("font_color", Color(0.95, 0.95, 0.85))
			panel.add_child(l)
	if tile_variants.size() > 0:
		var tv_label := Label.new()
		tv_label.text = "牌技能：%d 张" % tile_variants.size()
		tv_label.add_theme_font_size_override("font_size", 20)
		tv_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
		panel.add_child(tv_label)
	if not consumable_ids.is_empty():
		var c_label := Label.new()
		c_label.text = "战斗道具："
		c_label.add_theme_font_size_override("font_size", 20)
		c_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))
		panel.add_child(c_label)
		for cid in consumable_ids:
			var item: ConsumableItem = _find_consumable(cid)
			var l := Label.new()
			l.text = "  • %s" % (item.display_name if item else String(cid))
			l.add_theme_font_size_override("font_size", 16)
			l.add_theme_color_override("font_color", Color(0.95, 0.95, 0.85))
			panel.add_child(l)
	panel.add_child(HSeparator.new())
	var btn := Button.new()
	btn.text = "开战！"
	btn.custom_minimum_size = Vector2(200, 44)
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
