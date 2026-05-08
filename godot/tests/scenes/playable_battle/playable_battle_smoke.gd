extends Node2D

# F6 手测：玩家完整可玩 1 整场东风战 (4 局) vs 3 个 AI。
# 玩家 = seat 0；可点切手牌、宣告自摸/立直/荣和；每局事件以 toast 提示
# (立直 / 胡 / 流局 / 局间换庄)。

const PLAYABLE_TABLE := preload("res://ui/four_player_table/playable_table.tscn")

var _table: PlayableTable = null
var _result_label: Label = null
var _toast_label: Label = null
var _debug_log: Label = null
var _debug_lines: Array[String] = []

func _ready() -> void:
	_table = PLAYABLE_TABLE.instantiate()
	_table.position = Vector2(0, 0)
	add_child(_table)

	_result_label = Label.new()
	_result_label.text = "玩家可玩战斗 — 4 局东风战。点手牌切；事件触发时按钮自动 enable。"
	_result_label.position = Vector2(20, 4)
	_result_label.size = Vector2(1240, 24)
	_result_label.add_theme_font_size_override("font_size", 14)
	_result_label.add_theme_color_override("font_color", Color(1, 1, 0.7))
	add_child(_result_label)

	# Toast：屏幕中央上方弹关键事件（立直 / 胡 / 流局 / 局间换庄）
	_toast_label = Label.new()
	_toast_label.position = Vector2(440, 220)
	_toast_label.size = Vector2(400, 80)
	_toast_label.add_theme_font_size_override("font_size", 36)
	_toast_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.visible = false
	add_child(_toast_label)

	# Debug 日志框：左上角显示最近 10 条 _try_player_claim_async 判定 trace
	_debug_log = Label.new()
	_debug_log.position = Vector2(20, 28)
	_debug_log.size = Vector2(560, 200)
	_debug_log.add_theme_font_size_override("font_size", 11)
	_debug_log.add_theme_color_override("font_color", Color(0.7, 0.85, 0.55))
	_debug_log.text = "[claim trace 等待事件...]"
	add_child(_debug_log)

	_run_full_match()

func _append_debug_log(line: String) -> void:
	_debug_lines.append(line)
	if _debug_lines.size() > 10:
		_debug_lines.pop_front()
	if _debug_log != null:
		_debug_log.text = "\n".join(_debug_lines)

func _run_full_match() -> void:
	# 用 BattleNodeRunner.run_with_player_input_async 走完整 GameDriver 4 局循环
	# 监听 4 个 SeatPanel 的实时分数 + 事件 toast；每局结束 GameDriver.advance_or_finish
	# 自动推进 hand_index / dealer_seat / honba。
	var seed: int = 42
	# 每局开始前装个 listener 在 BC 上，按事件类型弹 toast
	# BC 在 GameDriver.start_hand() 创建，所以 listener 要在 polling 里挂
	_attach_event_listener()
	var result = await BattleNodeRunner.run_with_player_input_async(
		_table, get_tree(), seed, &"", [], {}, "east_round"
	)
	_result_label.text = "整场结束 · 最终排名 %d / 4 · 终分 %s" % [result.rank, str(result.final_scores)]
	_show_summary(result)

# 结算 overlay：4 局结束后弹一张全屏 panel 显示 4 家排名+分数。
# 点击任意位置或按任意键关闭。
func _show_summary(result) -> void:
	var overlay := Control.new()
	overlay.size = Vector2(1280, 800)
	overlay.position = Vector2.ZERO
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var bg := ColorRect.new()
	bg.size = Vector2(1280, 800)
	bg.color = Color(0, 0, 0, 0.75)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(bg)

	var panel := ColorRect.new()
	panel.position = Vector2(380, 200)
	panel.size = Vector2(520, 400)
	panel.color = Color(0.08, 0.12, 0.20, 0.98)
	overlay.add_child(panel)

	var title := Label.new()
	title.position = Vector2(0, 24)
	title.size = Vector2(520, 40)
	title.text = "对局结束"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	panel.add_child(title)

	var rank_label := Label.new()
	rank_label.position = Vector2(0, 80)
	rank_label.size = Vector2(520, 28)
	rank_label.text = "你的排名：%d / 4" % result.rank
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_label.add_theme_font_size_override("font_size", 22)
	rank_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.85))
	panel.add_child(rank_label)

	var sorted_indices := _seats_sorted_by_score(result.final_scores)
	for i in range(4):
		var seat_id: int = sorted_indices[i]
		var score: int = int(result.final_scores[seat_id])
		var name: String = "你" if seat_id == 0 else "AI %d" % seat_id
		var row := Label.new()
		row.position = Vector2(80, 130 + i * 40)
		row.size = Vector2(360, 32)
		row.text = "  第 %d 名  %s    %d" % [i + 1, name, score]
		row.add_theme_font_size_override("font_size", 20)
		var color := Color(1, 0.85, 0.4) if seat_id == 0 else Color(0.9, 0.9, 0.9)
		row.add_theme_color_override("font_color", color)
		panel.add_child(row)

	var hint := Label.new()
	hint.position = Vector2(0, 340)
	hint.size = Vector2(520, 24)
	hint.text = "(点击任意处关闭)"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.6))
	panel.add_child(hint)

	overlay.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			overlay.queue_free())

# 4 家按 score 降序排列，返回 seat_id 数组
static func _seats_sorted_by_score(scores: Array) -> Array:
	var arr: Array = []
	for i in range(scores.size()):
		arr.append([int(scores[i]), i])
	arr.sort_custom(func(a, b): return a[0] > b[0])
	var result: Array = []
	for pair in arr:
		result.append(pair[1])
	return result

# 监听 PlayableTable 内 BC 的 events 数组；每帧 diff，遇到关键事件弹 toast。
var _last_event_idx: int = 0
var _listener_active: bool = false
func _attach_event_listener() -> void:
	_listener_active = true
	_event_listener_loop()

func _event_listener_loop() -> void:
	while _listener_active:
		await get_tree().process_frame
		if _table == null or _table._bc == null:
			continue
		var events: Array = _table._bc.events
		while _last_event_idx < events.size():
			_handle_event(events[_last_event_idx])
			_last_event_idx += 1
		# BC 切换（新局）后 events 数组重新开始；用长度 reset 检测
		if events.size() < _last_event_idx:
			_last_event_idx = 0

func _handle_event(ev: BattleEvent) -> void:
	match ev.type:
		&"PLAYER_CLAIM_PROBE":
			# debug：每次 AI 切牌后玩家鸣牌判定 trace
			var c_chi: bool = bool(ev.extra.get("can_chi", false))
			var c_pon: bool = bool(ev.extra.get("can_pon", false))
			var c_kan: bool = bool(ev.extra.get("can_minkan", false))
			var pc: int = int(ev.extra.get("player_count", 0))
			var tid: int = int(ev.extra.get("tile_id", -1))
			var ds: int = int(ev.extra.get("discarder_seat", -1))
			_append_debug_log("AI%d 切 %s | 你 ×%d | chi=%s pon=%s kan=%s" % [
				ds, CardTileBack.tile_short_name(tid), pc,
				"✓" if c_chi else "x", "✓" if c_pon else "x", "✓" if c_kan else "x"])
			if c_chi or c_pon or c_kan:
				_show_toast("可鸣牌！选择按钮", 1.0)
		&"RIICHI_DECLARED":
			_show_toast("立直！seat %d" % ev.actor_seat, 1.5)
		&"WIN_DECLARED":
			var ti: TileInstance = ev.tile_instance
			var name := "胡牌"
			if ti != null and ti.tile != null:
				name = "胡牌 · seat %d 自摸/荣 · %s" % [ev.actor_seat, CardTileBack.tile_short_name(ti.tile.id)]
			else:
				name = "胡牌 · seat %d" % ev.actor_seat
			_show_toast(name, 2.5)
		&"TSUMO_DECLARED":
			_show_toast("自摸！seat %d" % ev.actor_seat, 1.5)
		&"RON_DECLARED":
			_show_toast("荣和！seat %d" % ev.actor_seat, 1.5)
		&"EXHAUSTIVE_DRAW":
			_show_toast("流局", 1.5)
		&"GAME_BEGIN":
			_show_toast("开局！", 1.0)

func _show_toast(text: String, duration: float) -> void:
	if _toast_label == null:
		return
	_toast_label.text = text
	_toast_label.visible = true
	_toast_label.modulate = Color(1, 0.9, 0.4, 1.0)
	# 用 timer 让 toast duration 后自动隐藏
	var timer := get_tree().create_timer(duration)
	await timer.timeout
	if _toast_label != null:
		_toast_label.visible = false
