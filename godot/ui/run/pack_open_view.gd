class_name PackOpenView extends Control

# 麻将王 — 里程碑 5 第 3 步：抽卡 / 卡包打开 UI
#
# 通用占位 UI：传入 N 张 GachaResult，按 rarity 着色显示卡名 + 描述。
# 玩家点"确认"emit signal("done")，调用方负责把结果加进玩家 deck。

signal done

const RARITY_BG: Array[Color] = [
	Color(0.55, 0.55, 0.55, 1.0),  # 普通 灰(alpha 1.0,run_bg 不透出来)
	Color(0.30, 0.55, 0.85, 1.0),  # 精良 蓝
	Color(0.65, 0.30, 0.85, 1.0),  # 史诗 紫
	Color(1.00, 0.80, 0.20, 1.0),  # 神话 金
]

@onready var _title: Label = $VBox/Title
@onready var _hbox: HBoxContainer = $VBox/HBox
@onready var _confirm_btn: Button = $VBox/Confirm

var _results: Array = []  # Array[GachaResult]
var _title_text: String = "节点抽卡奖励"

func _ready() -> void:
	RunUi.attach_background(self)
	if _confirm_btn:
		_confirm_btn.pressed.connect(_on_confirm)
	_rebuild()

# ---- public setters ----

func set_results(results: Array) -> void:
	_results = results
	if is_inside_tree():
		_rebuild()

func set_title_text(s: String) -> void:
	_title_text = s
	if is_inside_tree() and _title:
		_title.text = _title_text

# ---- helpers (static) ----

# 给 GachaResult 生成卡片文本：标题 + rarity 标签 + 描述
static func format_card_text(r: GachaResult) -> String:
	if r == null:
		return "(空)"
	var lines: Array[String] = []
	if r.kind == GachaResult.KIND_TILE and r.tile_variant:
		lines.append(r.tile_variant.display_name if r.tile_variant.display_name != "" else String(r.tile_variant.id))
		lines.append("[%s]" % Rarity.display_name(r.rarity))
		if r.tile_variant.description != "":
			lines.append(r.tile_variant.description)
	elif r.kind == GachaResult.KIND_ABILITY and r.ability:
		lines.append(r.ability.display_name if r.ability.display_name != "" else String(r.ability.id))
		lines.append("[%s 角色能力]" % Rarity.display_name(r.rarity))
		if r.ability.description != "":
			lines.append(r.ability.description)
	else:
		lines.append("(空 GachaResult)")
	return "\n".join(lines)

static func bg_color_for_rarity(rarity: int) -> Color:
	if rarity < 0 or rarity >= RARITY_BG.size():
		return Color(0.3, 0.3, 0.3, 1.0)
	return RARITY_BG[rarity]

# ---- internal ----

func _rebuild() -> void:
	if _title:
		_title.text = _title_text
	if _hbox == null:
		return
	for child in _hbox.get_children():
		child.queue_free()
	for r in _results:
		var card := Panel.new()
		card.custom_minimum_size = Vector2(180, 240)
		var sb := StyleBoxFlat.new()
		# 卡底压暗,描边换成稀有度色让等级一眼可读(与 ShopView 风格一致)。
		sb.bg_color = bg_color_for_rarity(r.rarity).darkened(0.35)
		sb.border_width_top = 3
		sb.border_width_bottom = 3
		sb.border_width_left = 3
		sb.border_width_right = 3
		sb.border_color = Rarity.color(r.rarity if r else 0)
		sb.corner_radius_top_left = 4
		sb.corner_radius_top_right = 4
		sb.corner_radius_bottom_left = 4
		sb.corner_radius_bottom_right = 4
		card.add_theme_stylebox_override("panel", sb)
		var lbl := Label.new()
		lbl.text = format_card_text(r)
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.offset_left = DT.GAP_TIGHT
		lbl.offset_right = -DT.GAP_TIGHT
		lbl.offset_top = DT.GAP_TIGHT
		lbl.offset_bottom = -DT.GAP_TIGHT
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", DT.FONT_BODY)
		# 卡底变暗后字色用 TEXT_PRIMARY 保证对比度;稀有度信息靠描边色传达。
		lbl.add_theme_color_override("font_color", DT.TEXT_PRIMARY)
		card.add_child(lbl)
		_hbox.add_child(card)

func _on_confirm() -> void:
	emit_signal("done")
