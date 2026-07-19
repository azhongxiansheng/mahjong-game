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
	subtitle.text = "每个角色有独特被动与起始属性"
	DT.apply_caption_style(subtitle)
	vbox.add_child(subtitle)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", DT.GAP_LOOSE)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(hbox)

	var renown: int = _get_renown()
	var chars: Array = CharacterPool.unlocked(renown)
	var cards: Array = []
	for c in chars:
		var card := _build_char_card(c)
		hbox.add_child(card)
		cards.append(card)
	DT.stagger_in(cards, "fade_in_up", 0.28, 0.08)

	_build_difficulty_selector(vbox)

func _build_char_card(c: Character) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(260, 460)
	panel.add_theme_stylebox_override("panel", DT.make_card_stylebox(DT.BORDER_GOLD, "normal"))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", DT.GAP_TIGHT)
	panel.add_child(vbox)

	# 立绘区占主体
	var portrait_wrap := Panel.new()
	portrait_wrap.custom_minimum_size = Vector2(0, 220)
	portrait_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait_wrap.clip_contents = true
	portrait_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p_sb := StyleBoxFlat.new()
	p_sb.bg_color = Color(0.05, 0.06, 0.09, 1)
	p_sb.set_corner_radius_all(8)
	portrait_wrap.add_theme_stylebox_override("panel", p_sb)
	if c.portrait_path != "" and ResourceLoader.exists(c.portrait_path):
		var tex: Texture2D = load(c.portrait_path)
		if tex:
			var portrait := TextureRect.new()
			portrait.texture = tex
			portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
			portrait_wrap.add_child(portrait)
	vbox.add_child(portrait_wrap)

	var name_label := Label.new()
	name_label.text = c.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", DT.FONT_SUBTITLE)
	name_label.add_theme_color_override("font_color", DT.TEXT_TITLE)
	vbox.add_child(name_label)

	var desc := Label.new()
	desc.text = c.description
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(220, 56)
	desc.add_theme_font_size_override("font_size", DT.FONT_CAPTION)
	desc.add_theme_color_override("font_color", DT.TEXT_PRIMARY)
	vbox.add_child(desc)

	var stats := Label.new()
	stats.text = "HP %d    🪙 %d" % [c.starting_hp, c.starting_gold]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", DT.FONT_BODY)
	stats.add_theme_color_override("font_color", DT.TEXT_SUCCESS)
	vbox.add_child(stats)

	var pick_btn := DT.make_button("出战", DT.BtnRole.PRIMARY, Vector2(140, DT.BUTTON_H))
	var cid: StringName = c.id
	pick_btn.pressed.connect(func(): emit_signal("character_chosen", cid))
	var btn_center := HBoxContainer.new()
	btn_center.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_center.add_child(pick_btn)
	vbox.add_child(btn_center)

	return panel

func _build_difficulty_selector(parent: VBoxContainer) -> void:
	var label := Label.new()
	label.text = "难度"
	DT.apply_subtitle_style(label)
	label.add_theme_color_override("font_color", DT.TEXT_TITLE)
	parent.add_child(label)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", DT.GAP_NORMAL)
	parent.add_child(hbox)

	var _diff_buttons: Array[Button] = []
	for level in [Difficulty.Level.NORMAL, Difficulty.Level.HARD, Difficulty.Level.LUNATIC]:
		var card_text := "%s\n%s" % [Difficulty.display_name(level), Difficulty.description(level)]
		var btn := DT.make_text_card_button(hbox, card_text, Vector2(220, 88), Difficulty.color(level))
		var captured_level: int = level
		var captured_buttons: Array[Button] = _diff_buttons
		btn.pressed.connect(func():
			_selected_difficulty = captured_level
			for b in captured_buttons:
				b.modulate = Color(0.75, 0.75, 0.75, 1)
			btn.modulate = Color.WHITE
			DT.attention(btn, "pulse", 0.35)
		)
		btn.modulate = Color(0.75, 0.75, 0.75, 1) if level != _selected_difficulty else Color.WHITE
		_diff_buttons.append(btn)

func get_selected_difficulty() -> int:
	return _selected_difficulty

func _get_renown() -> int:
	var mp := get_tree().root.get_node_or_null("MetaProgress")
	if mp and mp.has_method("get_renown"):
		return mp.get_renown()
	return 999
