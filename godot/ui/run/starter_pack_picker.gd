class_name StarterPackPicker extends Control

# 起始包 3 选 1：大字头圆章 + 短描述卡，对标雀魂/尖塔「选风格」页。

signal pack_chosen(pack_id: StringName)
signal daily_mode_toggled(enabled: bool)

@onready var _hbox: HBoxContainer = $VBox/HBox

var _packs: Array = []  # Array[Dictionary]
var _daily_mode: bool = false
var _daily_btn: Button = null

const LOGO_PATH := "res://assets/feifan_logo_transparent.png"

func _ready() -> void:
	RunUi.attach_background(self)
	_attach_logo()
	_attach_daily_toggle()
	_packs = StarterPacks.all()
	_rebuild()


func _attach_daily_toggle() -> void:
	var vbox := $VBox as VBoxContainer
	if vbox == null:
		return
	_daily_btn = Button.new()
	_daily_btn.text = "🗓️ 今日挑战 #%s" % DailySeed.today_display()
	_daily_btn.custom_minimum_size = Vector2(360, 36)
	_daily_btn.flat = true
	_daily_btn.add_theme_font_size_override("font_size", DT.FONT_CAPTION)
	_daily_btn.add_theme_color_override("font_color", DT.TEXT_MUTED)
	_daily_btn.toggle_mode = true
	_daily_btn.toggled.connect(_on_daily_toggled)
	vbox.add_child(_daily_btn)
	vbox.move_child(_daily_btn, 3)


func _on_daily_toggled(enabled: bool) -> void:
	_daily_mode = enabled
	if _daily_btn:
		if enabled:
			_daily_btn.text = "✅ 今日挑战 #%s (全服同 seed)" % DailySeed.today_display()
			_daily_btn.add_theme_color_override("font_color", DT.TEXT_TITLE)
		else:
			_daily_btn.text = "🗓️ 今日挑战 #%s" % DailySeed.today_display()
			_daily_btn.add_theme_color_override("font_color", DT.TEXT_MUTED)
	emit_signal("daily_mode_toggled", enabled)

func _attach_logo() -> void:
	if not ResourceLoader.exists(LOGO_PATH):
		return
	var vbox := $VBox as VBoxContainer
	if vbox == null:
		return
	var logo := TextureRect.new()
	logo.texture = load(LOGO_PATH)
	logo.custom_minimum_size = Vector2(140, 140)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(logo)
	vbox.move_child(logo, 0)

# ---- helpers (static) ----

static func archetype_glyph(pack_id) -> String:
	match StringName(pack_id):
		&"starter_control": return "守"
		&"starter_aggro":   return "攻"
		&"starter_fast":    return "速"
	return ""


static func archetype_color(pack_id) -> Color:
	match StringName(pack_id):
		&"starter_control": return Color(0.30, 0.55, 0.85)
		&"starter_aggro":   return Color(0.85, 0.25, 0.25)
		&"starter_fast":    return Color(1.0,  0.80, 0.25)
	return Color(0.5, 0.5, 0.5)


# 测试仍断言此格式（含【守】字头）
static func format_card_text(pack: Dictionary) -> String:
	var lines: Array[String] = []
	var glyph := archetype_glyph(pack.get("id", &""))
	if glyph != "":
		lines.append("【%s】 %s" % [glyph, pack.display_name])
	else:
		lines.append(pack.display_name)
	lines.append("")
	if not pack.get("available", false):
		lines.append("（敬请期待）")
		lines.append("")
	lines.append(pack.description)
	return "\n".join(lines)


# ---- internal ----

func _rebuild() -> void:
	if _hbox == null:
		return
	for child in _hbox.get_children():
		child.queue_free()
	var cards: Array = []
	for pack in _packs:
		var card := _build_pack_card(pack)
		_hbox.add_child(card)
		cards.append(card)
	DT.stagger_in(cards, "fade_in_up", 0.28, 0.08)


func _build_pack_card(pack: Dictionary) -> PanelContainer:
	var accent: Color = archetype_color(pack.get("id", &""))
	var available: bool = bool(pack.get("available", false))
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(DT.CARD_W + 20, DT.CARD_H + 40)
	var border := accent if available else DT.TEXT_MUTED
	panel.add_theme_stylebox_override("panel", DT.make_card_stylebox(border, "normal"))
	if not available:
		panel.modulate = Color(0.7, 0.7, 0.7, 0.9)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", DT.GAP_TIGHT)
	panel.add_child(vbox)

	var glyph := archetype_glyph(pack.get("id", &""))
	if glyph != "":
		vbox.add_child(RunUi.make_glyph_badge(glyph, accent, 96))

	var name_lbl := Label.new()
	name_lbl.text = String(pack.get("display_name", ""))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", DT.FONT_SUBTITLE)
	name_lbl.add_theme_color_override("font_color", accent if available else DT.TEXT_MUTED)
	vbox.add_child(name_lbl)

	var desc := Label.new()
	if available:
		desc.text = String(pack.get("description", ""))
	else:
		desc.text = "（敬请期待）\n\n" + String(pack.get("description", ""))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc.add_theme_font_size_override("font_size", DT.FONT_CAPTION)
	desc.add_theme_color_override("font_color", DT.TEXT_PRIMARY)
	desc.custom_minimum_size = Vector2(0, 80)
	vbox.add_child(desc)

	var pick := DT.make_button(
		"选择" if available else "未开放",
		DT.BtnRole.PRIMARY if available else DT.BtnRole.SECONDARY,
		Vector2(140, DT.BUTTON_H))
	pick.disabled = not available
	if available:
		var pack_id_capture: StringName = pack.id
		pick.pressed.connect(func(): emit_signal("pack_chosen", pack_id_capture))
	var center := HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(pick)
	vbox.add_child(center)
	return panel
