class_name HandStartSplash extends Control

# 一局对战开始前的 splash overlay:大字显示 "第 N 局 · 东 M" + 庄家信息,
# fade-in 0.2s → 停留 0.7s → fade-out 0.4s 自动消失,共 ~1.3s。
# PlayableTable.play_hand_async 实例化此节点,await 完成才继续。
#
# 商业级 game-feel:让玩家在每局开始前有"这是第几局,我是不是庄"的明确感知,
# 避免一直闷头打牌不知道战况进度。

signal finished


# 制作 splash overlay。
# title: "第 1 局 · 东 1"
# subtitle: "你 是庄家" / "AI 2 是庄家"
static func make(title: String, subtitle: String) -> HandStartSplash:
	var s := HandStartSplash.new()
	s._title = title
	s._subtitle = subtitle
	return s


var _title: String = ""
var _subtitle: String = ""
var _title_label: Label = null
var _subtitle_label: Label = null


func _init() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不挡其它输入
	z_index = 150


func _ready() -> void:
	# 半透明背景(让 splash 文字更醒目,但仍能看见牌桌)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 标题:大金字
	_title_label = Label.new()
	_title_label.text = _title
	_title_label.add_theme_font_size_override("font_size", 78)
	_title_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	_title_label.add_theme_constant_override("shadow_offset_x", 3)
	_title_label.add_theme_constant_override("shadow_offset_y", 3)
	_title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.anchor_left = 0.0
	_title_label.anchor_top = 0.5
	_title_label.anchor_right = 1.0
	_title_label.anchor_bottom = 0.5
	_title_label.offset_top = -80
	_title_label.offset_bottom = 0
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_label)

	# 副标题:小白字
	_subtitle_label = Label.new()
	_subtitle_label.text = _subtitle
	_subtitle_label.add_theme_font_size_override("font_size", 28)
	_subtitle_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.78))
	_subtitle_label.add_theme_constant_override("shadow_offset_x", 2)
	_subtitle_label.add_theme_constant_override("shadow_offset_y", 2)
	_subtitle_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.92))
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.anchor_left = 0.0
	_subtitle_label.anchor_top = 0.5
	_subtitle_label.anchor_right = 1.0
	_subtitle_label.anchor_bottom = 0.5
	_subtitle_label.offset_top = 10
	_subtitle_label.offset_bottom = 60
	_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_subtitle_label)

	# fade-in → 停留 → fade-out → finished → queue_free
	modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.2)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.7)
	tween.tween_property(self, "modulate:a", 0.0, 0.4)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		finished.emit()
		queue_free())


# 静态格式化:hand_number 1-8 (东 1..东 4 + 南 1..南 4)
# 返回 ("第 N 局 · 东 M", "你/AI N 是庄家")
static func format_title(hand_number: int, round_wind: int, dealer_seat: int, honba: int) -> Dictionary:
	var wind_str: String = "东"
	if round_wind == TileId.S_WIND:
		wind_str = "南"
	elif round_wind == TileId.W_WIND:
		wind_str = "西"
	elif round_wind == TileId.N:
		wind_str = "北"
	var hand_local: int = hand_number
	if hand_local > 4:
		hand_local = hand_local - 4
	var title: String = "%s %d 局" % [wind_str, hand_local]
	if honba > 0:
		title += " · %d 本场" % honba
	var dealer_name: String = "你" if dealer_seat == 0 else "AI %d" % dealer_seat
	var subtitle: String = "%s 是庄家" % dealer_name
	return {"title": title, "subtitle": subtitle}
