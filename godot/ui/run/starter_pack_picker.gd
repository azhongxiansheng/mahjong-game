class_name StarterPackPicker extends Control

# 麻将王 — 里程碑 4 第 3 步：起始包 3 选 1 UI（plan-4 D7）
#
# 3 张卡片：火力 / 速胡 / 控场。v1 仅"控场型" Button 可点（available=true），
# 其余 2 张 disabled 灰显，按钮文字含"（M6 实装）"提示。
# 玩家点击可选卡片 → emit signal("pack_chosen", pack_id)。

signal pack_chosen(pack_id: StringName)

@onready var _hbox: HBoxContainer = $VBox/HBox

var _packs: Array = []  # Array[Dictionary]，从 StarterPacks.all() 拿

const LOGO_PATH := "res://assets/feifan_logo_transparent.png"

func _ready() -> void:
	RunUi.attach_background(self)
	_attach_logo()
	_packs = StarterPacks.all()
	_rebuild()

# 顶部插品牌 logo,放在 Title 上方。资产缺失时跳过。
func _attach_logo() -> void:
	if not ResourceLoader.exists(LOGO_PATH):
		return
	var vbox := $VBox as VBoxContainer
	if vbox == null:
		return
	var logo := TextureRect.new()
	logo.texture = load(LOGO_PATH)
	logo.custom_minimum_size = Vector2(192, 192)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(logo)
	vbox.move_child(logo, 0)

# ---- helpers (static) ----

# starter pack id → 打法字头(守/攻/速),让玩家一眼看出三张卡的取向。
# 控场=守(防御/封印/抓马)、火力=攻(增番/铁壁)、速胡=速(立直/加速)。
static func archetype_glyph(pack_id) -> String:
	match StringName(pack_id):
		&"starter_control": return "守"
		&"starter_aggro":   return "攻"
		&"starter_fast":    return "速"
	return ""


# 打法色(用在 pack 卡描边):蓝守/红攻/金速,与 Rarity 色板独立避免歧义。
static func archetype_color(pack_id) -> Color:
	match StringName(pack_id):
		&"starter_control": return Color(0.30, 0.55, 0.85)  # 蓝 守
		&"starter_aggro":   return Color(0.85, 0.25, 0.25)  # 红 攻
		&"starter_fast":    return Color(1.0,  0.80, 0.25)  # 金 速
	return Color(0.5, 0.5, 0.5)


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
	for pack in _packs:
		# DT.make_text_card_button 统一处理 Button+Label autowrap 防撑爆。
		var btn := DT.make_text_card_button(
				_hbox,
				format_card_text(pack),
				Vector2(DT.CARD_W, DT.CARD_H),
				archetype_color(pack.get("id", &"")))
		btn.disabled = not pack.get("available", false)
		var pack_id_capture: StringName = pack.id
		btn.pressed.connect(func(): emit_signal("pack_chosen", pack_id_capture))
