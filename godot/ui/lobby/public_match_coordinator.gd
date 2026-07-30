class_name PublicMatchCoordinator extends Node

# #323：大厅公共匹配生产协调层。UI 仅消费 get_view/view_changed 与真实 actions。
# #380：终场再次匹配 / 返回大厅 — 幂等导航与完整资源释放。

signal view_changed(view: Dictionary)

const PLAYABLE_TABLE_SCENE := preload("res://ui/four_player_table/playable_table.tscn")
const DEFAULT_CONTROL_PLANE_URL := "http://127.0.0.1:8081"
const POLL_INTERVAL_MS := 500

var _queue: CasualQueueClient = null
var _session: PublicCasualNetworkSession = null
var _table: PlayableTable = null
var _queue_configured := false
var _view: Dictionary = {
	"state": "idle", "round_kind": "", "game_mode": "", "queued_at": "", "deadline_at": "",
	"room_id": "", "seat": -1, "error_code": "", "message": "",
	"can_cancel": false, "can_retry": false,
}
var _next_poll_ms := 0
## #380：最近一次公共 intent（再次匹配复用局制/玩法/角色）
var _last_intent: SessionIntent = null
## #380：终场导航锁 — 首次再次匹配/返回大厅后连点无效
var _settlement_nav_lock: bool = false
## #380：MATCH 终场锁存 — 直至再次匹配/返回大厅消费；SNAP/断线/terminal 不得覆盖
var _match_settled_latched: bool = false


func _ready() -> void:
	var lobby := get_parent() as LobbyShell
	if lobby != null and not lobby.session_intent_confirmed.is_connected(_on_session_intent):
		lobby.session_intent_confirmed.connect(_on_session_intent)
	_queue = CasualQueueClient.new()
	_queue.name = "CasualQueueClient"
	add_child(_queue)
	var base_url := OS.get_environment("CONTROL_PLANE_URL").strip_edges()
	if base_url.is_empty():
		base_url = DEFAULT_CONTROL_PLANE_URL
	_queue_configured = _queue.configure(base_url)
	_queue.ticket_updated.connect(_on_ticket_updated)
	_queue.request_failed.connect(_on_queue_failed)
	if not _queue_configured:
		_set_configuration_terminal(null)


func _process(_delta: float) -> void:
	if str(_view.get("state", "")) != "waiting" or _queue == null or _queue.is_busy():
		return
	var now := Time.get_ticks_msec()
	if now >= _next_poll_ms and _queue.poll_ticket():
		_next_poll_ms = now + POLL_INTERVAL_MS


func _on_session_intent(intent: SessionIntent) -> void:
	if intent == null or intent.room_kind != &"PUBLIC_CASUAL" or _queue == null:
		return
	if str(_view.get("state", "idle")) not in ["idle", "cancelled", "terminal_error"]:
		return
	_last_intent = intent
	_settlement_nav_lock = false
	_match_settled_latched = false
	_clear_network_runtime()
	if not _queue_configured:
		_set_configuration_terminal(intent)
		return
	_set_view({
		"state": "joining", "round_kind": String(intent.round_kind),
		"game_mode": String(intent.game_mode), "can_cancel": false, "can_retry": false,
	})
	if not _queue.begin(intent):
		_set_terminal("QUEUE_BUSY", "无法开始匹配")


func request_cancel() -> bool:
	return str(_view.get("state", "")) == "waiting" and _queue != null and _queue.cancel_ticket()


func request_retry() -> bool:
	if str(_view.get("state", "")) != "reconnecting" or _session == null:
		return false
	return _session.retry_reconnect() == OK


func get_view() -> Dictionary:
	return _view.duplicate(true)


func get_active_session() -> PublicCasualNetworkSession:
	return _session


func get_active_table() -> PlayableTable:
	return _table if _table != null and is_instance_valid(_table) else null


## #380 测试：注入再次匹配用 intent。
func set_last_public_intent_for_test(intent: SessionIntent) -> void:
	_last_intent = intent


## #380：终场「再次匹配」— 释放旧 runtime 后以相同局制/玩法/角色重新入队。
## 连点幂等：首次后锁存，旧 token/session 不复用。
## 缺 _last_intent 时明确 terminal，绝不默认角色。
func request_rematch() -> bool:
	if _settlement_nav_lock:
		return false
	# #380：仅 MATCH 终场锁存后可再次匹配；HAND/matched/playing 等无副作用
	if not _match_settled_latched or str(_view.get("state", "")) != "match_settled":
		return false
	var intent: SessionIntent = _last_intent
	if intent == null or String(intent.selected_character_id).is_empty():
		_settlement_nav_lock = true
		_match_settled_latched = false
		_clear_network_runtime(true)
		_set_terminal("NO_INTENT", "缺少对局 intent，无法再次匹配")
		return false
	_settlement_nav_lock = true
	_match_settled_latched = false
	# 完整释放：WS / voice / table / inventory 展示 / token 引用
	_clear_network_runtime(true)
	_set_view({
		"state": "joining",
		"round_kind": String(intent.round_kind),
		"game_mode": String(intent.game_mode),
		"can_cancel": false,
		"can_retry": false,
	})
	if not _queue_configured or _queue == null:
		_set_terminal("INVALID_CONTROL_PLANE_URL", "控制面地址无效")
		return false
	if not _queue.begin(intent):
		# 队列忙仍保持已释放；允许后续 terminal 重试走 _on_session_intent
		_settlement_nav_lock = false
		_set_terminal("QUEUE_BUSY", "无法开始匹配")
		return false
	return true


## #380：终场「返回大厅」— 完整释放运行态、恢复大厅 BGM、焦点 %MatchButton。
func request_return_lobby() -> bool:
	var st := str(_view.get("state", ""))
	if st == "idle" and _session == null and _table == null:
		return false
	if _settlement_nav_lock and st == "idle":
		return false
	# #380：仅 MATCH 终场锁存后可返回大厅；未终场调用无副作用
	if not _match_settled_latched or st != "match_settled":
		return false
	_settlement_nav_lock = true
	_match_settled_latched = false
	var rk := str(_view.get("round_kind", ""))
	var gm := str(_view.get("game_mode", ""))
	_clear_network_runtime(true)
	_set_view({
		"state": "idle",
		"round_kind": rk,
		"game_mode": gm,
		"can_cancel": false,
		"can_retry": false,
	})
	var lobby := get_parent()
	if lobby != null and is_instance_valid(lobby):
		if lobby.has_method("request_lobby_bgm"):
			lobby.request_lobby_bgm()
		var match_btn: Control = null
		if lobby.has_method("get_node_or_null"):
			match_btn = lobby.get_node_or_null("%MatchButton") as Control
		if match_btn != null and is_instance_valid(match_btn):
			match_btn.focus_mode = Control.FOCUS_ALL
			match_btn.grab_focus()
		elif lobby is Control:
			(lobby as Control).focus_mode = Control.FOCUS_ALL
			(lobby as Control).grab_focus()
	return true


## 兼容别名（测试 / 信号）
func on_public_rematch_requested() -> bool:
	return request_rematch()


func on_public_return_lobby_requested() -> bool:
	return request_return_lobby()


## #380 测试 seam：从合法 assigned 启动真实 runtime（不写私有字段拼装）。
func begin_network_from_assigned_for_test(assigned: Dictionary) -> void:
	if assigned.is_empty():
		return
	_start_network(assigned)


func _on_ticket_updated(ticket: Dictionary) -> void:
	_consume_ticket(ticket, true)


func consume_ticket_for_test(ticket: Dictionary) -> void:
	_consume_ticket(ticket, false)


func _consume_ticket(ticket: Dictionary, start_network: bool) -> void:
	match str(ticket.get("status", "")):
		"waiting":
			_next_poll_ms = Time.get_ticks_msec() + POLL_INTERVAL_MS
			_set_view({
				"state": "waiting", "round_kind": str(ticket.get("round_kind", "")),
				"game_mode": str(ticket.get("game_mode", "")),
				"queued_at": str(ticket.get("queued_at", "")),
				"deadline_at": str(ticket.get("deadline_at", "")),
				"can_cancel": true, "can_retry": false,
			})
		"cancelled":
			_set_view(_context_view("cancelled"))
		"failed":
			_set_terminal(str(ticket.get("code", "ROOM_FAILED")), "匹配房间不可用")
		"assigned":
			if not _assignment_valid(ticket):
				_set_terminal("INVALID_ASSIGNMENT", "房间分配无效")
				return
			_set_view({
				"state": "matched", "round_kind": str(ticket.get("round_kind", "")),
				"game_mode": str(ticket.get("game_mode", "")),
				"room_id": str(ticket.get("room_id", "")),
				"seat": int(ticket.get("seat", -1)),
				"can_cancel": false, "can_retry": false,
			})
			if start_network:
				_start_network(ticket)
		_:
			_set_terminal("INVALID_RESPONSE", "未知匹配状态")


func _start_network(assigned: Dictionary) -> void:
	_clear_network_runtime()
	_session = PublicCasualNetworkSession.new()
	_session.name = "PublicCasualNetworkSession"
	add_child(_session)
	if not _session.configure_from_assigned(assigned, _queue.get_session_id()):
		_fail_network_start("INVALID_ASSIGNMENT", "房间分配无效")
		return
	var bundle := ModeModuleBundle.for_public_transport(StringName(_session.game_mode))
	if bundle == null or not _session.bind_mode_modules(bundle):
		_fail_network_start("INVALID_MODE", "玩法模块不可用")
		return
	_session.reconnecting.connect(_on_reconnecting)
	_session.recovered.connect(_on_recovered)
	_session.terminal_error.connect(_on_terminal_error)
	if not _session.room_started_hint.is_connected(_on_room_started_hint):
		_session.room_started_hint.connect(_on_room_started_hint)
	if _session.has_signal("settlement_view_changed") \
			and not _session.settlement_view_changed.is_connected(_on_settlement_view_changed):
		_session.settlement_view_changed.connect(_on_settlement_view_changed)
	_settlement_nav_lock = false
	_mount_table()
	if _table == null:
		_fail_network_start("TABLE_MOUNT_FAILED", "牌桌挂载失败")
		return
	_session.bind_playable_table(_table)
	_match_settled_latched = false
	var err := _session.start()
	if err != OK:
		_fail_network_start("CONNECT_FAILED", error_string(err))


func _mount_table() -> void:
	if _table != null and is_instance_valid(_table):
		return
	var lobby := get_parent() as Control
	if lobby == null:
		return
	_table = PLAYABLE_TABLE_SCENE.instantiate() as PlayableTable
	_table.name = "PublicPlayableTable"
	_table.set_anchors_preset(Control.PRESET_FULL_RECT)
	_table.mouse_filter = Control.MOUSE_FILTER_STOP
	lobby.add_child(_table)
	lobby.move_child(_table, lobby.get_child_count() - 1)


func _on_reconnecting(code: String, message: String) -> void:
	consume_connection_fact_for_test(&"reconnecting", code, message)


func _on_recovered() -> void:
	# #377：新合法 committed snapshot 触发 recovered → 回到 playing 并把焦点交还牌桌
	consume_connection_fact_for_test(&"recovered")


func _on_room_started_hint() -> void:
	# 仅 session 在 NBC 成功提交 ROOM_SNAPSHOT 后发出
	notify_public_snapshot_committed_for_test()


func _on_settlement_view_changed(view: Dictionary) -> void:
	# #380：终场投影 → view.state=match_settled 锁存，直至导航消费
	if str(view.get("phase", "")) == "match_result":
		_match_settled_latched = true
		var next := _context_view("match_settled")
		next.merge({"error_code": "", "message": "", "can_retry": false, "can_cancel": false}, true)
		_set_view(next)
		_settlement_nav_lock = false
		_focus_public_table()


func _on_terminal_error(code: String, message: String) -> void:
	consume_connection_fact_for_test(&"terminal_error", code, message)


## #377：首个/恢复 committed snapshot → playing（解除 matched 遮罩）。
func notify_public_snapshot_committed_for_test() -> void:
	consume_connection_fact_for_test(&"playing")


func consume_connection_fact_for_test(fact: StringName, code: String = "", message: String = "") -> void:
	# #380：终场锁存期间忽略会覆盖 match_settled 的连接/局况 fact
	if _match_settled_latched and fact in [
		&"reconnecting", &"recovered", &"playing", &"entered", &"terminal_error"
	]:
		return
	match fact:
		&"reconnecting":
			var next := _context_view("reconnecting")
			next.merge({"error_code": code, "message": message, "can_retry": true}, true)
			_set_view(next)
			_freeze_public_table_if_any()
		&"recovered":
			# #301 非阻断 recovered 提示；#377 同时把焦点交还牌桌（committed 已由 session 保证）
			_set_view(_context_view("recovered"))
			_focus_public_table()
		&"playing", &"entered":
			# 仅 matched → 首个合法 committed 使用（非 reconnect 路径）
			_enter_playing_view()
		&"terminal_error":
			_set_terminal(code, message)


func _enter_playing_view() -> void:
	var next := _context_view("playing")
	next.merge({"error_code": "", "message": "", "can_retry": false, "can_cancel": false}, true)
	_set_view(next)
	_focus_public_table()


func _freeze_public_table_if_any() -> void:
	if _table != null and is_instance_valid(_table) and _table.has_method("sync_public_table_projection"):
		# 触发冻结判定（NBC resync / reconnecting 时不改最后 committed 画面）
		if _session != null and _session.nbc != null and _session.nbc.resync_required():
			_table.sync_public_table_projection()


func _focus_public_table() -> void:
	if _table == null or not is_instance_valid(_table):
		return
	if _table is Control:
		(_table as Control).focus_mode = Control.FOCUS_ALL
		(_table as Control).grab_focus()


func _on_queue_failed(code: String, message: String) -> void:
	_set_terminal(code, message)


func _set_configuration_terminal(intent: SessionIntent) -> void:
	_set_view({
		"state": "terminal_error",
		"round_kind": String(intent.round_kind) if intent != null else "",
		"game_mode": String(intent.game_mode) if intent != null else "",
		"error_code": "INVALID_CONTROL_PLANE_URL",
		"message": "控制面地址无效",
	})


func _fail_network_start(code: String, message: String) -> void:
	_clear_network_runtime()
	_set_terminal(code, message)


func _clear_network_runtime(discard_nodes := true) -> void:
	if _table != null and is_instance_valid(_table):
		var old_table := _table
		_table = null
		if old_table.has_method("release_voice_runtime"):
			old_table.release_voice_runtime()
		if discard_nodes:
			_discard_node(old_table)
	else:
		_table = null
	if _session != null and is_instance_valid(_session):
		var old_session := _session
		_session = null
		old_session.release()
		if discard_nodes:
			_discard_node(old_session)
	else:
		_session = null


func _discard_node(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.queue_free()


func _set_terminal(code: String, message: String) -> void:
	var next := _context_view("terminal_error")
	next.merge({"error_code": code, "message": message}, true)
	_set_view(next)


func _assignment_valid(ticket: Dictionary) -> bool:
	var mode := str(ticket.get("game_mode", ""))
	var seat := int(ticket.get("seat", -1))
	if str(ticket.get("worker", "")).is_empty() or str(ticket.get("room_id", "")).is_empty():
		return false
	if str(ticket.get("room_token", "")).is_empty() or seat < 0 or seat > 3:
		return false
	if mode != "STANDARD" and mode != "TRASH_TALK":
		return false
	return mode != "TRASH_TALK" or not str(ticket.get("voice_worker", "")).is_empty()


func _context_view(state: String) -> Dictionary:
	return {
		"state": state,
		"round_kind": str(_view.get("round_kind", "")),
		"game_mode": str(_view.get("game_mode", "")),
		"queued_at": str(_view.get("queued_at", "")),
		"deadline_at": str(_view.get("deadline_at", "")),
		"room_id": str(_view.get("room_id", "")),
		"seat": int(_view.get("seat", -1)),
	}


func _set_view(next: Dictionary) -> void:
	_view = {
		"state": str(next.get("state", "idle")),
		"round_kind": str(next.get("round_kind", "")),
		"game_mode": str(next.get("game_mode", "")),
		"queued_at": str(next.get("queued_at", "")),
		"deadline_at": str(next.get("deadline_at", "")),
		"room_id": str(next.get("room_id", "")),
		"seat": int(next.get("seat", -1)),
		"error_code": str(next.get("error_code", "")),
		"message": str(next.get("message", "")),
		"can_cancel": bool(next.get("can_cancel", false)),
		"can_retry": bool(next.get("can_retry", false)),
	}
	view_changed.emit(get_view())


func _exit_tree() -> void:
	_clear_network_runtime(false)
