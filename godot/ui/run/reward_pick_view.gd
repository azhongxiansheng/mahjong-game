class_name RewardPickView extends Control

# 麻将王 — 战斗后 3 选 1 奖励（核心肉鸽循环）
#
# 战斗节点结束后弹出 3 张奖励卡，玩家选 1 张加入 deck/consumables。
# 也可跳过（获得少量金币作为补偿）。

signal reward_chosen(result: GachaResult)
signal skipped

const SKIP_GOLD_REWARD: int = 30

func _ready() -> void:
	RunUi.attach_background(self)
	set_anchors_preset(Control.PRESET_FULL_RECT)

func show_rewards(options: Array, battle_rank: int) -> void:
	for child in get_children():
		if child.name != "RunBgArt":
			child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = DT.PANEL_PAD
	vbox.offset_right = -DT.PANEL_PAD
	vbox.offset_top = DT.PANEL_PAD
	vbox.offset_bottom = -DT.PANEL_PAD
	vbox.add_theme_constant_override("separation", DT.GAP_NORMAL)
	add_child(vbox)

	var title := Label.new()
	title.text = "战斗奖励 — 选择 1 张"
	DT.apply_title_style(title)
	vbox.add_child(title)

	var rank_label := Label.new()
	rank_label.text = "排名：第 %d 名" % battle_rank
	DT.apply_body_style(rank_label)
	rank_label.add_theme_color_override("font_color", DT.TEXT_MUTED)
	vbox.add_child(rank_label)

	vbox.add_child(HSeparator.new())

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", DT.GAP_LOOSE)
	vbox.add_child(hbox)

	var cards: Array = []
	for i in range(options.size()):
		var r: GachaResult = options[i]
		var card_panel := _build_card(r, i)
		hbox.add_child(card_panel)
		cards.append(card_panel)
	# 3 张奖励卡错峰翻入 — 肉鸽循环最高频的"开奖"时刻
	DT.stagger_in(cards, "fade_in_up", 0.3, 0.09)

	vbox.add_child(HSeparator.new())

	var skip_btn := DT.make_button("跳过（+%d 金币）" % SKIP_GOLD_REWARD,
		DT.BtnRole.SECONDARY, Vector2(240, DT.BUTTON_H))
	skip_btn.pressed.connect(func(): emit_signal("skipped"))
	var center := HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(skip_btn)
	vbox.add_child(center)

func _build_card(r: GachaResult, index: int) -> PanelContainer:
	var kind_text := "奖励"
	match r.kind:
		GachaResult.KIND_TILE:
			kind_text = "牌技能"
		GachaResult.KIND_ABILITY:
			kind_text = "角色能力"
		GachaResult.KIND_CONSUMABLE:
			kind_text = "战斗道具"
		GachaResult.KIND_RELIC:
			kind_text = "遗物"
	var panel := RunUi.make_item_card_shell(
		Vector2(260, 400),
		Rarity.color(r.rarity),
		RunUi.resolve_gacha_icon_path(r),
		_get_name(r),
		"%s · %s" % [kind_text, Rarity.display_name(r.rarity)],
		_get_description(r),
		100,
	)
	var vbox: VBoxContainer = panel.get_child(0) as VBoxContainer
	var pick_btn := DT.make_button("选择", DT.BtnRole.PRIMARY, Vector2(140, DT.BUTTON_H))
	var captured_result: GachaResult = r
	pick_btn.pressed.connect(func(): emit_signal("reward_chosen", captured_result))
	var btn_center := HBoxContainer.new()
	btn_center.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_center.add_child(pick_btn)
	if vbox:
		vbox.add_child(btn_center)
	else:
		panel.add_child(btn_center)
	return panel

static func _get_name(r: GachaResult) -> String:
	if r.kind == GachaResult.KIND_TILE and r.tile_variant:
		return r.tile_variant.display_name if r.tile_variant.display_name != "" else String(r.tile_variant.id)
	if r.kind == GachaResult.KIND_ABILITY and r.ability:
		return r.ability.display_name if r.ability.display_name != "" else String(r.ability.id)
	if r.kind == GachaResult.KIND_CONSUMABLE and r.consumable:
		return r.consumable.display_name if r.consumable.display_name != "" else String(r.consumable.id)
	if r.kind == GachaResult.KIND_RELIC and r.relic:
		return r.relic.display_name if r.relic.display_name != "" else String(r.relic.id)
	return "???"

static func _get_description(r: GachaResult) -> String:
	if r.kind == GachaResult.KIND_TILE and r.tile_variant:
		return r.tile_variant.description
	if r.kind == GachaResult.KIND_ABILITY and r.ability:
		return r.ability.description
	if r.kind == GachaResult.KIND_CONSUMABLE and r.consumable:
		return r.consumable.description
	if r.kind == GachaResult.KIND_RELIC and r.relic:
		return r.relic.description
	return ""
