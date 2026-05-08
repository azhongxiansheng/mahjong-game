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

func _ready() -> void:
	_refresh_default()

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

# ---- helpers (static, 测试可用) ----

static func format_chapter_text(chapter: int, floor_str: String) -> String:
	return "📍 章 %d · 层 %s" % [chapter, floor_str]

static func format_hp_text(hp: int, max_hp: int) -> String:
	return "♥ %d / %d" % [hp, max_hp]

static func format_gold_text(gold: int) -> String:
	return "🪙 %d" % gold

static func format_deck_text(size: int) -> String:
	return "🃏 卡组 %d" % size

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
