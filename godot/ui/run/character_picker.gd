class_name CharacterPicker extends Control

signal character_chosen(char_id: StringName)

var _selected_difficulty: int = Difficulty.Level.NORMAL

func _ready() -> void:
	RunUi.attach_background(self)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = DT.PANEL_PAD
	vbox.offset_right = -DT.PANEL_PAD
	vbox.offset_top = DT.PANEL_PAD
	vbox.offset_bottom = -DT.PANEL_PAD
	vbox.add_theme_constant_override("separation", DT.GAP_NORMAL)
	add_child(vbox)

	var title := Label.new()
	title.text = "选择角色"
	DT.apply_title_style(title)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "每个角色有独特被动能力和起始属性"
	DT.apply_caption_style(subtitle)
	vbox.add_child(subtitle)

	vbox.add_child(HSeparator.new())

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", DT.GAP_LOOSE)
	vbox.add_child(hbox)

	var renown: int = _get_renown()
	var chars: Array = CharacterPool.unlocked(renown)

	for c in chars:
		var card := _build_char_card(c)
		hbox.add_child(card)

	vbox.add_child(HSeparator.new())
	_build_difficulty_selector(vbox)

func _build_char_card(c: Character) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(280, 420)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(DT.BG_BASE.r + 0.06, DT.BG_BASE.g + 0.07, DT.BG_BASE.b + 0.12, 0.95)
	sb.border_color = DT.TEXT_TITLE
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = DT.GAP_NORMAL
	sb.content_margin_right = DT.GAP_NORMAL
	sb.content_margin_top = DT.GAP_NORMAL
	sb.content_margin_bottom = DT.GAP_NORMAL
	panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", DT.GAP_TIGHT)
	panel.add_child(vbox)

	if c.portrait_path != "":
		var tex: Texture2D = load(c.portrait_path)
		if tex:
			var portrait := TextureRect.new()
			portrait.texture = tex
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.custom_minimum_size = Vector2(200, 150)
			portrait.expand_mode = TextureRect.EXPAND_FIT_HEIGHT
			vbox.add_child(portrait)

	var name_label := Label.new()
	name_label.text = c.display_name
	DT.apply_subtitle_style(name_label)
	name_label.add_theme_color_override("font_color", DT.TEXT_TITLE)
	vbox.add_child(name_label)

	vbox.add_child(HSeparator.new())

	var desc := Label.new()
	desc.text = c.description
	DT.apply_caption_style(desc)
	desc.custom_minimum_size = Vector2(240, 80)
	vbox.add_child(desc)

	vbox.add_child(HSeparator.new())

	var stats := Label.new()
	stats.text = "HP: %d    金币: %d" % [c.starting_hp, c.starting_gold]
	DT.apply_body_style(stats)
	stats.add_theme_color_override("font_color", DT.TEXT_SUCCESS)
	vbox.add_child(stats)

	var pick_btn := Button.new()
	pick_btn.text = "选择 %s" % c.display_name
	pick_btn.custom_minimum_size = Vector2(160, DT.BUTTON_H)
	pick_btn.add_theme_font_size_override("font_size", DT.FONT_BODY)
	var cid: StringName = c.id
	pick_btn.pressed.connect(func(): emit_signal("character_chosen", cid))
	var btn_center := HBoxContainer.new()
	btn_center.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_center.add_child(pick_btn)
	vbox.add_child(btn_center)

	return panel

func _build_difficulty_selector(parent: VBoxContainer) -> void:
	var label := Label.new()
	label.text = "难度选择"
	DT.apply_subtitle_style(label)
	label.add_theme_color_override("font_color", DT.TEXT_TITLE)
	parent.add_child(label)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", DT.GAP_NORMAL)
	parent.add_child(hbox)

	# Button text 多行会被单行宽度撑爆 minimum_size (commit bcbcc63 的教训)。
	# 用 DT.make_text_card_button 统一规避:Button(text="") + 内嵌 Label autowrap。
	var _diff_buttons: Array[Button] = []
	for level in [Difficulty.Level.NORMAL, Difficulty.Level.HARD, Difficulty.Level.LUNATIC]:
		var card_text := "%s\n\n%s" % [Difficulty.display_name(level), Difficulty.description(level)]
		var btn := DT.make_text_card_button(hbox, card_text, Vector2(240, 120), Difficulty.color(level))
		var captured_level: int = level
		var captured_buttons: Array[Button] = _diff_buttons
		btn.pressed.connect(func():
			_selected_difficulty = captured_level
			for b in captured_buttons:
				b.flat = true
			btn.flat = false
		)
		btn.flat = (level != _selected_difficulty)
		_diff_buttons.append(btn)

func get_selected_difficulty() -> int:
	return _selected_difficulty

func _get_renown() -> int:
	var mp := get_tree().root.get_node_or_null("MetaProgress")
	if mp and mp.has_method("get_renown"):
		return mp.get_renown()
	return 999
