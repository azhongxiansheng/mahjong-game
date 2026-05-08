class_name PlayableTable extends Control

# 麻将王 — 战斗节点真实可玩 顶层容器。
#
# 组合 FourPlayerTable + PlayerActionPanel + PlayableBattleController，
# 跑一局完整东风局玩家可玩对战。
#
# 1280×800：上方 720 给 four_player_table（含旋转的 4 个 SeatPanel），
# 下方 80 给 player_action_panel。

const FOUR_PLAYER_TABLE := preload("res://ui/four_player_table/four_player_table.tscn")
const PLAYER_ACTION_PANEL := preload("res://ui/four_player_table/player_action_panel.tscn")

const TABLE_HEIGHT: float = 720.0
const ACTION_PANEL_HEIGHT: float = 80.0

var _table: FourPlayerTable = null
var _action_panel: PlayerActionPanel = null
var _bc: PlayableBattleController = null

var _seat_panel_player: SeatPanel = null

# 屏幕左上 debug log：显示最近 10 条 PLAYER_CLAIM_PROBE，方便调试
# "为啥碰/吃/杠按钮没出来"。RunFlow + Smoke 都用同一份。
var _debug_log: Label = null
var _debug_lines: Array[String] = []

func _ready() -> void:
	custom_minimum_size = Vector2(1280, TABLE_HEIGHT + ACTION_PANEL_HEIGHT)
	_build_layout()
	_build_debug_log()

func _build_debug_log() -> void:
	_debug_log = Label.new()
	_debug_log.position = Vector2(20, 28)
	_debug_log.size = Vector2(560, 200)
	_debug_log.add_theme_font_size_override("font_size", 11)
	_debug_log.add_theme_color_override("font_color", Color(0.7, 0.85, 0.55))
	_debug_log.text = "[claim trace 等待 AI 切牌...]"
	add_child(_debug_log)

func _append_debug_log(line: String) -> void:
	_debug_lines.append(line)
	if _debug_lines.size() > 10:
		_debug_lines.pop_front()
	if _debug_log != null:
		_debug_log.text = "\n".join(_debug_lines)

func _build_layout() -> void:
	_table = FOUR_PLAYER_TABLE.instantiate()
	_table.position = Vector2(0, 0)
	add_child(_table)

	_action_panel = PLAYER_ACTION_PANEL.instantiate()
	# ActionPanel 在桌面右下角内（不超出 800 高）：PANEL 480×110，桌面 720 高
	# 放在 (cx-PANEL_W/2, TABLE_HEIGHT-110) = (300, 610)，紧贴玩家手牌右上侧
	# 但玩家手牌 row 在 y~580 占 60-90 px → 用 y=595 让 PANEL 顶部贴手牌底部
	_action_panel.position = Vector2((_table.TABLE_WIDTH - PlayerActionPanel.PANEL_W) / 2.0, 670.0)
	add_child(_action_panel)

func play_hand_async(bc: PlayableBattleController) -> Dictionary:
	_bc = bc
	if _table.seat_panels.size() >= 1:
		_seat_panel_player = _table.seat_panels[0]
		if not _seat_panel_player.player_card_clicked.is_connected(_on_player_tile_clicked):
			_seat_panel_player.player_card_clicked.connect(_on_player_tile_clicked)
	_bc.bind_ui(_action_panel, _seat_panel_player, get_tree())
	_table.bind_battle_state(bc.state, 0, 4)
	_action_panel.enter_idle("准备开局…")
	_attach_event_polling()
	var result: Dictionary = await bc.run_to_end_async()
	_action_panel.enter_idle("本局结束")
	_table.bind_battle_state(bc.state, 0, 4)
	return result

var _last_event_count: int = 0
var _polling_active: bool = false

func _attach_event_polling() -> void:
	if _polling_active:
		return
	_polling_active = true
	_polling_loop()

func _polling_loop() -> void:
	var debug_tick: int = 0
	while _polling_active and _bc != null:
		await get_tree().process_frame
		if _bc == null:
			return
		var n: int = _bc.events.size()
		# 每 30 帧（~0.5s）刷一次 debug 总览
		debug_tick += 1
		if debug_tick % 30 == 0:
			var probe_count: int = 0
			var entry_count: int = 0
			var step_after_ron: int = 0
			var step_after_claim: int = 0
			var default_hook_count: int = 0
			for ev in _bc.events:
				if ev.type == &"PLAYER_CLAIM_PROBE":
					probe_count += 1
				elif ev.type == &"PLAYER_CLAIM_ENTRY":
					entry_count += 1
				elif ev.type == &"DEFAULT_HOOK_CALLED":
					default_hook_count += 1
				elif ev.type == &"STEP_END_TRACE":
					if String(ev.extra.get("after", "")) == "ron":
						step_after_ron += 1
					else:
						step_after_claim += 1
			var bc_kind: String = "Playable" if _bc is PlayableBattleController else "Battle"
			_append_debug_log("[poll] step_end=%d defaultHook=%d entry=%d probe=%d bc=%s" % [
				step_after_claim, default_hook_count, entry_count, probe_count, bc_kind])
		if n != _last_event_count:
			for i in range(_last_event_count, n):
				_handle_event_for_debug(_bc.events[i])
			_last_event_count = n
			if is_instance_valid(_table) and _bc.state != null:
				_table.bind_battle_state(_bc.state, 0, 4)
		if n < _last_event_count:
			_last_event_count = 0

# debug only：把 PLAYER_CLAIM_PROBE event trace 显示到屏幕 debug log
func _handle_event_for_debug(ev) -> void:
	if ev.type != &"PLAYER_CLAIM_PROBE":
		return
	var c_chi: bool = bool(ev.extra.get("can_chi", false))
	var c_pon: bool = bool(ev.extra.get("can_pon", false))
	var c_kan: bool = bool(ev.extra.get("can_minkan", false))
	var pc: int = int(ev.extra.get("player_count", 0))
	var tid: int = int(ev.extra.get("tile_id", -1))
	var ds: int = int(ev.extra.get("discarder_seat", -1))
	_append_debug_log("AI%d 切 %s | 你 ×%d | chi=%s pon=%s kan=%s" % [
		ds, CardTileBack.tile_short_name(tid), pc,
		"✓" if c_chi else "x", "✓" if c_pon else "x", "✓" if c_kan else "x"])

func _exit_tree() -> void:
	_polling_active = false

func _on_player_tile_clicked(tile_id: int) -> void:
	if _action_panel != null:
		_action_panel.on_hand_tile_clicked(tile_id)

# Debug helper：按 D 自动切玩家手牌第一张（绕开鼠标点击的 Dock 误判）
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not (k.pressed and not k.echo):
		return
	match k.keycode:
		KEY_D:
			if _bc != null and _action_panel != null:
				var hand_ids: Array = _bc.state.seats[0].hand.to_id_array()
				if hand_ids.size() > 0:
					_action_panel.on_hand_tile_clicked(int(hand_ids[0]))
		KEY_S:
			# 跳过响应（rion/claim 窗口）
			if _action_panel != null:
				_action_panel.player_action_chosen.emit({"action": "skip"})
		KEY_R:
			# 立直 yes
			if _action_panel != null:
				_action_panel.player_action_chosen.emit({"action": "riichi_yes"})
