class_name PracticeMatchCoordinator extends Node

# E2-03（#233）+ E2-05（#235）：大厅与本地练习牌桌协调层。
# 拥有整场生命周期：启动 → 对局 → 结算 → 再来一局 / 返回大厅。
# 公共匹配没有本地权威入口；网络链路未端到端验证。
# 不接 Run 奖励 / 金币 / HP / 章节。

signal practice_started(config: GameSessionConfig)
signal practice_finished(summary: Dictionary)
signal practice_failed(error: StringName)

const PLAYABLE_TABLE_SCENE := preload("res://ui/four_player_table/playable_table.tscn")
const RULE_VERSION := "e2-03-v1"

enum Phase {
	IDLE = 0,
	RUNNING = 1,
	SETTLED = 2,
}

var _table: PlayableTable = null
var _running: bool = false
var _phase: int = Phase.IDLE
var _generation: int = 0
var _active_config: GameSessionConfig = null
var _active_driver: GameDriver = null
var _settlement_panel: MatchSettlementPanel = null


func _ready() -> void:
	var lobby := get_parent() as LobbyShell
	if lobby != null and not lobby.session_intent_confirmed.is_connected(_on_session_intent):
		lobby.session_intent_confirmed.connect(_on_session_intent)


func is_busy() -> bool:
	return _running or _phase != Phase.IDLE


func get_active_table() -> PlayableTable:
	if _table != null and is_instance_valid(_table):
		return _table
	return null


func get_active_driver() -> GameDriver:
	return _active_driver


func get_active_config() -> GameSessionConfig:
	return _active_config


func prepare_practice(
	intent: SessionIntent,
	seed_value: int,
	session_id: String
) -> Dictionary:
	if intent == null:
		return {"ok": false, "error": &"NULL_INTENT"}
	if intent.room_kind != &"PRACTICE":
		return {"ok": false, "error": &"PUBLIC_NOT_LOCAL"}
	var converted := GameSessionConfig.from_intent(
		intent, seed_value, session_id, RULE_VERSION, {}
	)
	if not converted.ok:
		return {"ok": false, "error": converted.error_code}
	var driver := PracticeSessionLauncher.new().launch(converted.config)
	if driver == null:
		return {"ok": false, "error": &"LAUNCH_FAILED"}
	return {
		"ok": true,
		"config": converted.config,
		"driver": driver,
	}


func mount_playable_table() -> PlayableTable:
	if _table != null and is_instance_valid(_table):
		return _table
	var lobby := get_parent() as Control
	if lobby == null:
		return null
	_table = PLAYABLE_TABLE_SCENE.instantiate() as PlayableTable
	_table.name = "PracticePlayableTable"
	_table.set_anchors_preset(Control.PRESET_FULL_RECT)
	_table.mouse_filter = Control.MOUSE_FILTER_STOP
	lobby.add_child(_table)
	lobby.move_child(_table, lobby.get_child_count() - 1)
	return _table


## 测试与生产共用：在现有牌桌上展示整场结算。
func present_settlement(
	summary: Dictionary,
	config: GameSessionConfig,
	driver: GameDriver
) -> void:
	_active_config = config
	_active_driver = driver
	if _table == null or not is_instance_valid(_table):
		if mount_playable_table() == null:
			practice_failed.emit(&"TABLE_MOUNT_FAILED")
			_teardown_to_idle()
			return
	_phase = Phase.SETTLED
	_running = true
	_show_settlement_panel(summary)


## 再来一局：释放旧运行态，生成新 config/driver/table（不自动跑牌）。
func rebuild_for_rematch(seed_value: int, session_id: String) -> Dictionary:
	var old_config := _active_config
	if old_config == null:
		return {"ok": false, "error": &"NO_CONFIG"}
	_clear_settlement_panel()
	_free_table()
	_active_driver = null
	var new_config := GameSessionConfig.create_rematch_from(old_config, seed_value, session_id)
	if new_config == null:
		return {"ok": false, "error": &"REMATCH_CONFIG_FAILED"}
	var driver := PracticeSessionLauncher.new().launch(new_config)
	if driver == null:
		return {"ok": false, "error": &"REMATCH_LAUNCH_FAILED"}
	var table := mount_playable_table()
	if table == null:
		return {"ok": false, "error": &"TABLE_MOUNT_FAILED"}
	_active_config = new_config
	_active_driver = driver
	return {
		"ok": true,
		"config": new_config,
		"driver": driver,
		"table": table,
	}


## 返回大厅：释放牌局 / 模式模块引用，停 SFX，恢复大厅 BGM。
func return_to_lobby() -> void:
	_generation += 1
	_teardown_to_idle()
	var am := get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("stop_all"):
		am.stop_all()
	var lobby := get_parent() as LobbyShell
	if lobby != null and lobby.has_method("request_lobby_bgm"):
		lobby.request_lobby_bgm()


func _on_session_intent(intent: SessionIntent) -> void:
	if is_busy() or intent == null or intent.room_kind != &"PRACTICE":
		return
	var now: int = Time.get_ticks_usec()
	var prepared := prepare_practice(intent, now, "practice-%d" % now)
	if not prepared.get("ok", false):
		practice_failed.emit(prepared.get("error", &"PREPARE_FAILED"))
		return
	var table := mount_playable_table()
	if table == null:
		practice_failed.emit(&"TABLE_MOUNT_FAILED")
		return
	_generation += 1
	var gen: int = _generation
	await _execute_match(prepared["config"], prepared["driver"], table, gen)


func _execute_match(
	config: GameSessionConfig,
	driver: GameDriver,
	table: PlayableTable,
	gen: int
) -> void:
	_phase = Phase.RUNNING
	_running = true
	_active_config = config
	_active_driver = driver
	practice_started.emit(config)
	var summary: Dictionary = await PracticeMatchRunner.new().run_async(
		config,
		driver,
		func(bc: PlayableBattleController):
			return await table.play_hand_async(bc)
	)
	if gen != _generation:
		return
	if not summary.get("completed", false):
		practice_failed.emit(summary.get("error", &"MATCH_FAILED"))
		_teardown_to_idle()
		return
	practice_finished.emit(summary)
	present_settlement(summary, config, driver)


func _show_settlement_panel(summary: Dictionary) -> void:
	_clear_settlement_panel()
	if _table == null or not is_instance_valid(_table):
		return
	var finals: Array = summary.get("final_scores", [])
	var round_kind: StringName = summary.get("round_kind", &"")
	if round_kind == &"" and _active_config != null:
		round_kind = _active_config.round_kind
	var view: Dictionary = MatchSettlement.build_view(finals, round_kind)
	_settlement_panel = MatchSettlementPanel.new()
	_table.add_child(_settlement_panel)
	_settlement_panel.present(view)
	_settlement_panel.rematch_requested.connect(_on_rematch_requested)
	_settlement_panel.return_lobby_requested.connect(_on_return_requested)


func _on_rematch_requested() -> void:
	if _phase != Phase.SETTLED:
		return
	# 信号栈内不得同步 free 正在 emit 的面板；推迟到栈展开后。
	_generation += 1
	var gen: int = _generation
	call_deferred("_deferred_rematch_from_ui", gen)


func _deferred_rematch_from_ui(gen: int) -> void:
	if gen != _generation:
		return
	# 已返回大厅或代次被 supersede 则放弃
	if _phase == Phase.IDLE:
		return
	var seed_value: int = Time.get_ticks_usec()
	var session_id := "practice-%d" % seed_value
	var rebuilt: Dictionary = rebuild_for_rematch(seed_value, session_id)
	if not rebuilt.get("ok", false):
		practice_failed.emit(rebuilt.get("error", &"REMATCH_FAILED"))
		_teardown_to_idle()
		return
	# 从 deferred 启动协程；_execute_match 内部 await
	_execute_match(rebuilt["config"], rebuilt["driver"], rebuilt["table"], gen)


func _on_return_requested() -> void:
	if _phase != Phase.SETTLED:
		return
	# 推迟 teardown，避免在 rematch_requested/return_lobby_requested 发射栈内 free
	call_deferred("return_to_lobby")


func _teardown_to_idle() -> void:
	_clear_settlement_panel()
	_free_table()
	_active_driver = null
	_active_config = null
	_phase = Phase.IDLE
	_running = false


func _clear_settlement_panel() -> void:
	if _settlement_panel != null and is_instance_valid(_settlement_panel):
		var panel := _settlement_panel
		_settlement_panel = null
		_discard_node(panel)
	else:
		_settlement_panel = null


func _free_table() -> void:
	_settlement_panel = null
	if _table != null and is_instance_valid(_table):
		var table := _table
		_table = null
		# E4-01：返回大厅 / 再来一局前显式释放 PTT 采集与分座播放资源。
		if table.has_method("release_voice_runtime"):
			table.release_voice_runtime()
		_discard_node(table)
	else:
		_table = null


## 从树上摘下后 queue_free：信号/调用锁定期间安全，帧末真正释放。
func _discard_node(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.queue_free()
