extends Control

# E4-04 / #246：四席固定边缘字幕槽 + 最小奖励反馈 banner。
# 无全局 class_name；全程 MOUSE_FILTER_IGNORE；字幕不随座位旋转。
# 生产路径由内部 Timer 自驱动过期清理。

const ModelScr := preload("res://ui/four_player_table/seat_caption_model.gd")

const SLOT_W_H: float = 320.0
const SLOT_H: float = 56.0
const SLOT_W_SIDE: float = 220.0
const EXPIRY_POLL_SEC: float = 0.25

# seat → 固定屏幕矩形（不旋转）。避开四席手牌 / 操作栏 / PTT。
# seat 2 顶、seat 0 底、seat 3 左、seat 1 右。
const SLOT_RECTS := {
	0: Rect2(640.0, 610.0, SLOT_W_H, SLOT_H),
	1: Rect2(1360.0, 380.0, SLOT_W_SIDE, SLOT_H),
	2: Rect2(640.0, 72.0, SLOT_W_H, SLOT_H),
	3: Rect2(16.0, 380.0, SLOT_W_SIDE, SLOT_H),
}

# 顶部居中偏下，避开 seat2 槽 (y=72..128) 与对家手牌；也不碰操作栏/PTT。
const BANNER_RECT := Rect2(500.0, 148.0, 600.0, 28.0)

var _slots: Array = []
var _source_labels: Array = []
var _body_labels: Array = []
var _banner: Label = null
var _model = null
var _last_now_ms: int = 0
var _expiry_timer: Timer = null


func _ready() -> void:
	name = "SeatCaptionOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	custom_minimum_size = Vector2(TableLayout.TABLE_W, TableLayout.TABLE_H)
	size = Vector2(TableLayout.TABLE_W, TableLayout.TABLE_H)
	_model = ModelScr.new()
	_build_slots()
	_build_banner()
	_ensure_expiry_timer()


func _exit_tree() -> void:
	if _expiry_timer != null and is_instance_valid(_expiry_timer):
		_expiry_timer.stop()
		_expiry_timer.queue_free()
	_expiry_timer = null


func model():
	return _model


func expiry_timer() -> Timer:
	return _expiry_timer


func slot_rect(seat: int) -> Rect2:
	if not SLOT_RECTS.has(seat):
		return Rect2()
	return SLOT_RECTS[seat]


func banner_rect() -> Rect2:
	return BANNER_RECT


func slot_control(seat: int) -> Control:
	if seat < 0 or seat >= _slots.size():
		return null
	return _slots[seat]


func body_label(seat: int) -> Label:
	if seat < 0 or seat >= _body_labels.size():
		return null
	return _body_labels[seat]


func source_label_node(seat: int) -> Label:
	if seat < 0 or seat >= _source_labels.size():
		return null
	return _source_labels[seat]


func reward_banner() -> Label:
	return _banner


func apply_display(seat: int, data: Dictionary) -> void:
	if seat < 0 or seat > 3:
		return
	var slot: Control = _slots[seat]
	var src: Label = _source_labels[seat]
	var body: Label = _body_labels[seat]
	if data.is_empty():
		slot.visible = false
		src.text = ""
		body.text = ""
		return
	slot.visible = true
	# header：座位｜来源｜语言（模型提供；回退本地拼）
	var header := String(data.get("header", ""))
	if header.is_empty():
		header = ModelScr.header_text(
			int(data.get("seat", seat)),
			String(data.get("source_label", "")),
			String(data.get("lang", ""))
		)
	src.text = header
	var raw_text := String(data.get("text", ""))
	var partial: bool = bool(data.get("is_partial", false)) \
		or String(data.get("kind", "")) == "partial"
	# final/AI 属性徽标（display-only）
	var badge_suffix := ""
	var badges: Array = data.get("affinity_badges", [])
	if typeof(badges) == TYPE_ARRAY and not badges.is_empty() and not partial:
		var parts: PackedStringArray = PackedStringArray()
		for b in badges:
			var key := String(b)
			var label := String(ModelScr.AFFINITY_LABELS.get(key, key))
			parts.append("[%s]" % label)
		if parts.size() > 0:
			badge_suffix = " " + " ".join(parts)
	# partial 展示层追加省略号；不污染模型原文
	if partial:
		body.text = _partial_display_text(raw_text)
		body.modulate = Color(1, 1, 1, 0.72)
		src.modulate = Color(1, 1, 1, 0.72)
		slot.modulate = Color(1, 1, 1, 0.85)
	else:
		body.text = raw_text + badge_suffix
		body.modulate = Color(1, 1, 1, 1)
		src.modulate = Color(1, 1, 1, 1)
		slot.modulate = Color(1, 1, 1, 1)
		if bool(data.get("stt_failed", false)):
			body.modulate = Color(1.0, 0.75, 0.45, 1.0)


static func _partial_display_text(raw: String) -> String:
	if raw.ends_with("…") or raw.ends_with("..."):
		return raw
	return raw + "…"


func ingest_caption(input: Dictionary) -> Dictionary:
	if _model == null:
		_model = ModelScr.new()
	var res: Dictionary = _model.ingest(input)
	if not bool(res.get("ok", false)):
		return res
	# 刷新时钟：有合成 now_ms 则用其；否则墙钟（生产）
	var now_ms: int
	if input.has("now_ms") and typeof(input.get("now_ms")) == TYPE_INT:
		now_ms = int(input["now_ms"])
	else:
		now_ms = Time.get_ticks_msec()
	_last_now_ms = now_ms
	_model.tick(now_ms)
	_refresh_all()
	_ensure_expiry_timer()
	return res


## 公开 character_id 补全徽标；不改 TTL、不重复 partial 动画。
func ingest_caption_enrichment(input: Dictionary) -> Dictionary:
	if _model == null:
		_model = ModelScr.new()
	# 优先 enrichment 路径
	if input.has("character_id") and input.has("utterance_id") and input.has("seat"):
		var en: Dictionary = _model.enrich_character(
			int(input["seat"]),
			String(input["utterance_id"]),
			String(input["character_id"])
		)
		if bool(en.get("ok", false)):
			_refresh_all()
			return en
	# 回落普通 ingest（含 stt_failed 首条）
	return ingest_caption(input)


func tick_display(now_ms: int) -> void:
	if _model == null:
		return
	_last_now_ms = now_ms
	_model.tick(now_ms)
	_refresh_all()


## 测试/内部：触发与 Timer 相同的过期刷新路径。
func force_expiry_tick_for_test(now_ms: int = -1) -> void:
	if now_ms < 0:
		now_ms = Time.get_ticks_msec()
	tick_display(now_ms)


func set_reward_banner_text(msg: String) -> void:
	if _banner == null:
		return
	_banner.text = msg
	_banner.visible = not msg.is_empty()


func clear_reward_banner() -> void:
	set_reward_banner_text("")


func reward_feedback_text() -> String:
	if _banner == null:
		return ""
	return _banner.text


func _on_caption_expiry_timeout() -> void:
	tick_display(Time.get_ticks_msec())


func _ensure_expiry_timer() -> void:
	if _expiry_timer != null and is_instance_valid(_expiry_timer):
		if _expiry_timer.is_stopped():
			_expiry_timer.start()
		return
	_expiry_timer = Timer.new()
	_expiry_timer.name = "CaptionExpiryTimer"
	_expiry_timer.wait_time = EXPIRY_POLL_SEC
	_expiry_timer.one_shot = false
	_expiry_timer.autostart = true
	_expiry_timer.timeout.connect(_on_caption_expiry_timeout)
	add_child(_expiry_timer)
	_expiry_timer.start()


func _refresh_all() -> void:
	for seat in range(4):
		var d: Dictionary = _model.display_for_seat(seat)
		if d.is_empty() or not _model.has_visible_for_seat(seat, _last_now_ms):
			apply_display(seat, {})
		else:
			apply_display(seat, d)


func _build_slots() -> void:
	_slots.clear()
	_source_labels.clear()
	_body_labels.clear()
	for seat in range(4):
		var r: Rect2 = SLOT_RECTS[seat]
		var panel := PanelContainer.new()
		panel.name = "CaptionSlot%d" % seat
		panel.position = r.position
		panel.size = r.size
		panel.custom_minimum_size = r.size
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.rotation_degrees = 0.0
		panel.visible = false

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.05, 0.08, 0.12, 0.78)
		style.set_corner_radius_all(6)
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		panel.add_theme_stylebox_override("panel", style)

		var vbox := VBoxContainer.new()
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_theme_constant_override("separation", 2)
		panel.add_child(vbox)

		var src := Label.new()
		src.name = "SourceLabel"
		src.mouse_filter = Control.MOUSE_FILTER_IGNORE
		src.add_theme_font_size_override("font_size", 11)
		src.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0, 0.95))
		src.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		vbox.add_child(src)

		var body := Label.new()
		body.name = "BodyLabel"
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_theme_font_size_override("font_size", 14)
		body.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.max_lines_visible = 2
		body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.custom_minimum_size = Vector2(r.size.x - 16.0, 0)
		vbox.add_child(body)

		add_child(panel)
		_slots.append(panel)
		_source_labels.append(src)
		_body_labels.append(body)


func _build_banner() -> void:
	_banner = Label.new()
	_banner.name = "RewardFeedbackBanner"
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.position = BANNER_RECT.position
	_banner.size = BANNER_RECT.size
	_banner.add_theme_font_size_override("font_size", 16)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1.0))
	_banner.visible = false
	add_child(_banner)
