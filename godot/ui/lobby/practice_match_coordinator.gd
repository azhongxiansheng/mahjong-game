class_name PracticeMatchCoordinator extends Node

# E2-03（#233）：大厅与本地练习牌桌之间的独立协调层。
# 公共匹配没有本地权威入口；网络链路未端到端验证。

signal practice_started(config: GameSessionConfig)
signal practice_finished(summary: Dictionary)
signal practice_failed(error: StringName)

const PLAYABLE_TABLE_SCENE := preload("res://ui/four_player_table/playable_table.tscn")
const RULE_VERSION := "e2-03-v1"

var _table: PlayableTable = null
var _running: bool = false


func _ready() -> void:
	var lobby := get_parent() as LobbyShell
	if lobby != null and not lobby.session_intent_confirmed.is_connected(_on_session_intent):
		lobby.session_intent_confirmed.connect(_on_session_intent)


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


func _on_session_intent(intent: SessionIntent) -> void:
	if _running or intent == null or intent.room_kind != &"PRACTICE":
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

	_running = true
	var config: GameSessionConfig = prepared["config"]
	var driver: GameDriver = prepared["driver"]
	practice_started.emit(config)
	var summary: Dictionary = await PracticeMatchRunner.new().run_async(
		config,
		driver,
		func(bc: PlayableBattleController):
			return await table.play_hand_async(bc)
	)
	_running = false
	if not summary.get("completed", false):
		practice_failed.emit(summary.get("error", &"MATCH_FAILED"))
		return
	practice_finished.emit(summary)
