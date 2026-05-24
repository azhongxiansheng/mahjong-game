class_name CharacterPicker extends Control

signal character_chosen(char_id: StringName)

var _selected_difficulty: int = Difficulty.Level.NORMAL

func _ready() -> void:
	RunUi.attach_background(self)
	custom_minimum_size = Vector2(1280, 720)
	_build_ui()

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(140, 40)
	vbox.custom_minimum_size = Vector2(1000, 640)
	add_child(vbox)

	var title := Label.new()
	title.text = "选择角色"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "每个角色有独特被动能力和起始属性"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	vbox.add_child(subtitle)

	vbox.add_child(HSeparator.new())

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 24)
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
	sb.bg_color = Color(0.10, 0.13, 0.20, 0.95)
	sb.border_color = Color(0.85, 0.75, 0.3)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
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

	var name_label := Label.new()
	name_label.text = c.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 28)
	name_label.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	vbox.add_child(name_label)

	vbox.add_child(HSeparator.new())

	var desc := Label.new()
	desc.text = c.description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(240, 80)
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.85, 0.85, 0.8))
	vbox.add_child(desc)

	vbox.add_child(HSeparator.new())

	var stats := Label.new()
	stats.text = "HP: %d    金币: %d" % [c.starting_hp, c.starting_gold]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", 16)
	stats.add_theme_color_override("font_color", Color(0.6, 0.85, 0.6))
	vbox.add_child(stats)

	var pick_btn := Button.new()
	pick_btn.text = "选择 %s" % c.display_name
	pick_btn.custom_minimum_size = Vector2(160, 40)
	pick_btn.add_theme_font_size_override("font_size", 18)
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
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	parent.add_child(label)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	parent.add_child(hbox)

	var _diff_buttons: Array[Button] = []
	for level in [Difficulty.Level.NORMAL, Difficulty.Level.HARD, Difficulty.Level.LUNATIC]:
		var btn := Button.new()
		btn.text = "%s\n%s" % [Difficulty.display_name(level), Difficulty.description(level)]
		btn.custom_minimum_size = Vector2(280, 60)
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_color_override("font_color", Difficulty.color(level))
		var captured_level: int = level
		var captured_buttons: Array[Button] = _diff_buttons
		btn.pressed.connect(func():
			_selected_difficulty = captured_level
			for b in captured_buttons:
				b.flat = true
			btn.flat = false
		)
		btn.flat = (level != _selected_difficulty)
		hbox.add_child(btn)
		_diff_buttons.append(btn)

func get_selected_difficulty() -> int:
	return _selected_difficulty

func _get_renown() -> int:
	var mp := get_tree().root.get_node_or_null("MetaProgress")
	if mp and mp.has_method("get_renown"):
		return mp.get_renown()
	return 999
