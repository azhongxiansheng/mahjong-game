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
	custom_minimum_size = Vector2(1280, 720)

func show_rewards(options: Array, battle_rank: int) -> void:
	for child in get_children():
		if child.name != "Bg":
			child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(140, 40)
	vbox.custom_minimum_size = Vector2(1000, 640)
	add_child(vbox)

	var title := Label.new()
	title.text = "战斗奖励 — 选择 1 张"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	vbox.add_child(title)

	var rank_label := Label.new()
	rank_label.text = "排名：第 %d 名" % battle_rank
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_label.add_theme_font_size_override("font_size", 20)
	rank_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	vbox.add_child(rank_label)

	vbox.add_child(HSeparator.new())

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 24)
	vbox.add_child(hbox)

	for i in range(options.size()):
		var r: GachaResult = options[i]
		var card_panel := _build_card(r, i)
		hbox.add_child(card_panel)

	vbox.add_child(HSeparator.new())

	var skip_btn := Button.new()
	skip_btn.text = "跳过（+%d 金币）" % SKIP_GOLD_REWARD
	skip_btn.custom_minimum_size = Vector2(240, 44)
	skip_btn.add_theme_font_size_override("font_size", 16)
	skip_btn.pressed.connect(func(): emit_signal("skipped"))
	var center := HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(skip_btn)
	vbox.add_child(center)

func _build_card(r: GachaResult, index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(280, 380)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.15, 0.22, 0.95)
	sb.border_color = Rarity.color(r.rarity)
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var kind_label := Label.new()
	kind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kind_label.add_theme_font_size_override("font_size", 14)
	kind_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	match r.kind:
		GachaResult.KIND_TILE:
			kind_label.text = "牌技能"
		GachaResult.KIND_ABILITY:
			kind_label.text = "角色能力"
		GachaResult.KIND_CONSUMABLE:
			kind_label.text = "战斗道具"
		GachaResult.KIND_RELIC:
			kind_label.text = "遗物（被动）"
		_:
			kind_label.text = "奖励"
	vbox.add_child(kind_label)

	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", Rarity.color(r.rarity))
	name_label.text = _get_name(r)
	vbox.add_child(name_label)

	var rarity_label := Label.new()
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_label.add_theme_font_size_override("font_size", 14)
	rarity_label.add_theme_color_override("font_color", Rarity.color(r.rarity))
	rarity_label.text = Rarity.display_name(r.rarity)
	vbox.add_child(rarity_label)

	vbox.add_child(HSeparator.new())

	var desc_label := Label.new()
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(240, 100)
	desc_label.add_theme_font_size_override("font_size", 14)
	desc_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.8))
	desc_label.text = _get_description(r)
	vbox.add_child(desc_label)

	var pick_btn := Button.new()
	pick_btn.text = "选择"
	pick_btn.custom_minimum_size = Vector2(120, 36)
	pick_btn.add_theme_font_size_override("font_size", 18)
	var captured_result: GachaResult = r
	pick_btn.pressed.connect(func(): emit_signal("reward_chosen", captured_result))
	var btn_center := HBoxContainer.new()
	btn_center.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_center.add_child(pick_btn)
	vbox.add_child(btn_center)

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
