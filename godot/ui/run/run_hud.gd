class_name RunHud extends Control

# US-008：Run HUD 顶栏排版升级
#
# 之前纯三段文字，本 PR 改成视觉化 HUD：
#   左：章节/层徽章
#   中：HP bar（颜色按 % 渐变：绿 > 50% / 黄 > 25% / 红 ≤ 25%）+ HP 数字
#   右：金币 + Deck 大小

@onready var _label_chapter: Label = $HBox/Chapter
@onready var _label_hp: Label = $HBox/HpBox/HpLabel
@onready var _hp_bar: ProgressBar = $HBox/HpBox/HpBar
@onready var _label_gold: Label = $HBox/Gold
@onready var _label_deck: Label = $HBox/Deck

const ICON_HP_PATH := "res://assets/run_icons/icon_hp.png"
const ICON_GOLD_PATH := "res://assets/run_icons/icon_gold.png"

# HUD 末尾的能力芯片容器(程序化追加,.tscn 里没有):
# 每个能力一颗小 Panel,稀有度色描边 + 短名 Label + 悬停 tooltip 显示全名+描述。
var _abilities_box: HBoxContainer = null

func _ready() -> void:
	_attach_hud_icons()
	_attach_abilities_box()
	_refresh_default()


func _attach_abilities_box() -> void:
	var hbox := $HBox as HBoxContainer
	if hbox == null:
		return
	_abilities_box = HBoxContainer.new()
	_abilities_box.name = "Abilities"
	_abilities_box.add_theme_constant_override("separation", 6)
	hbox.add_child(_abilities_box)

# HP / 金币 emoji 之前用 ♥ 🪙 字符做图标，本 PR 接入真正的 run_icons 贴图：
# 在 .tscn 既有节点旁插一个 TextureRect 当图标，格式化文本仅留数字部分。
# 资产缺失时静默跳过（label 仍渲染纯数字，不崩）。
func _attach_hud_icons() -> void:
	var hp_box := $HBox/HpBox as HBoxContainer
	if hp_box and ResourceLoader.exists(ICON_HP_PATH):
		var hp_icon := TextureRect.new()
		hp_icon.texture = load(ICON_HP_PATH)
		hp_icon.custom_minimum_size = Vector2(28, 28)
		hp_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hp_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hp_box.add_child(hp_icon)
		hp_box.move_child(hp_icon, 0)
	var hbox := $HBox as HBoxContainer
	if hbox and ResourceLoader.exists(ICON_GOLD_PATH) and _label_gold:
		var gold_icon := TextureRect.new()
		gold_icon.texture = load(ICON_GOLD_PATH)
		gold_icon.custom_minimum_size = Vector2(28, 28)
		gold_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gold_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hbox.add_child(gold_icon)
		hbox.move_child(gold_icon, _label_gold.get_index())

# ---- public setters ----

func bind_run_state(rs: RunState) -> void:
	if _label_chapter == null:
		return
	var floor_str := "?"
	var node_ref: NodeRef = rs.current_node_ref()
	if node_ref:
		floor_str = String.num(node_ref.floor_index + 1)
	_label_chapter.text = format_chapter_text(rs.chapter, floor_str)
	_set_hp(rs.hp, rs.max_hp)
	_label_gold.text = format_gold_text(rs.gold)
	_label_deck.text = format_deck_text(_deck_size(rs))
	_rebuild_abilities(rs)

# ---- helpers (static, 测试可用) ----

static func format_chapter_text(chapter: int, floor_str: String) -> String:
	return "章 %d · 层 %s" % [chapter, floor_str]

static func format_hp_text(hp: int, max_hp: int) -> String:
	return "%d / %d" % [hp, max_hp]

static func format_gold_text(gold: int) -> String:
	return "%d" % gold

static func format_deck_text(size: int) -> String:
	return "卡组 %d" % size

# HP bar 颜色按剩余比例：> 50% 绿，> 25% 黄，否则红
static func hp_bar_color(hp: int, max_hp: int) -> Color:
	if max_hp <= 0:
		return Color(0.6, 0.6, 0.6)
	var ratio: float = float(hp) / float(max_hp)
	if ratio > 0.5:
		return Color(0.30, 0.75, 0.35)  # 绿
	if ratio > 0.25:
		return Color(0.90, 0.70, 0.20)  # 黄
	return Color(0.85, 0.25, 0.25)      # 红

static func _deck_size(rs: RunState) -> int:
	if rs == null or rs.player_deck == null:
		return 0
	return rs.player_deck.tile_variant_count() + rs.player_deck.abilities.size()

# ---- internal ----

func _set_hp(hp: int, max_hp: int) -> void:
	_label_hp.text = format_hp_text(hp, max_hp)
	if _hp_bar:
		_hp_bar.max_value = max(1, max_hp)
		_hp_bar.value = clamp(hp, 0, max_hp)
		# fill 颜色（StyleBoxFlat）
		var sb := StyleBoxFlat.new()
		sb.bg_color = hp_bar_color(hp, max_hp)
		sb.corner_radius_top_left = 4
		sb.corner_radius_top_right = 4
		sb.corner_radius_bottom_left = 4
		sb.corner_radius_bottom_right = 4
		_hp_bar.add_theme_stylebox_override("fill", sb)

func _refresh_default() -> void:
	if _label_chapter == null:
		return
	_label_chapter.text = format_chapter_text(1, "?")
	var hp_init: int = int(BalanceConstants.lookup(&"starting_hp"))
	_set_hp(hp_init, hp_init)
	_label_gold.text = format_gold_text(0)
	_label_deck.text = format_deck_text(0)
	if _abilities_box:
		for child in _abilities_box.get_children():
			child.queue_free()


# 重建能力芯片：每个能力 Panel + 短名 Label + 稀有度色描边 + tooltip(全名+描述)。
func _rebuild_abilities(rs: RunState) -> void:
	if _abilities_box == null:
		return
	for child in _abilities_box.get_children():
		child.queue_free()
	if rs == null or rs.player_deck == null:
		return
	for a in rs.player_deck.abilities:
		_abilities_box.add_child(_make_ability_chip(a))


static func _make_ability_chip(a) -> Control:
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(64, 30)
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	# 稀有度色描边覆盖主题 Panel StyleBox
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.10, 0.13, 1.0)
	sb.border_color = Rarity.color(int(a.rarity) if a else 0)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	chip.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = _ability_short_name(a)
	lbl.size = Vector2(64, 30)
	lbl.position = Vector2(0, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.93, 0.85))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(lbl)
	chip.tooltip_text = _ability_tooltip(a)
	return chip


# 取能力 display_name 前 2-3 字作短名;无 display_name 则取 id 前 2 字。
static func _ability_short_name(a) -> String:
	if a == null:
		return "?"
	var s: String = String(a.display_name) if a.display_name != "" else String(a.id)
	if s.length() <= 4:
		return s
	return s.substr(0, 3)


static func _ability_tooltip(a) -> String:
	if a == null:
		return ""
	var lines: Array[String] = []
	var name: String = a.display_name if a.display_name != "" else String(a.id)
	lines.append("【%s · %s】" % [name, Rarity.display_name(int(a.rarity))])
	if a.description != "":
		lines.append(a.description)
	return "\n".join(lines)
