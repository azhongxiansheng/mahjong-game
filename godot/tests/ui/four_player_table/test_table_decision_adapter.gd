extends GutTest


const ACTION_PANEL := preload("res://ui/four_player_table/player_action_panel.tscn")
const SEAT_PANEL := preload("res://ui/four_player_table/seat_panel.tscn")


var _panel: PlayerActionPanel
var _seat: SeatPanel
var _adapter: TableDecisionAdapter


func before_each() -> void:
	_panel = ACTION_PANEL.instantiate()
	_seat = SEAT_PANEL.instantiate()
	add_child_autofree(_panel)
	add_child_autofree(_seat)
	await get_tree().process_frame
	_adapter = TableDecisionAdapter.new(_panel, _seat)


func test_discard_request_maps_to_panel_and_returns_choice() -> void:
	var result := {}
	var request_runner := func():
		result["choice"] = await _adapter.request(&"discard", {
			"can_tsumo": false,
			"can_ankan": false,
			"can_added_kan": false,
			"has_consumable": false,
		})
	request_runner.call()

	assert_eq(_panel._state, PlayerActionPanel.State.WAITING_DISCARD)
	assert_true(_seat._hand_clickable)
	# E2-02 / #232：动作 identity = tile_instance_id
	_adapter.on_hand_tile_clicked(9001)
	await get_tree().process_frame
	assert_eq(result.choice, {"action": "discard", "tile_instance_id": 9001})
	assert_false(result.choice.has("tile_id"), "不保留 choice.tile_id 兼容")


func test_claim_companions_request_uses_allowed_tile_instance_ids() -> void:
	var result := {}
	var request_runner := func():
		result["choice"] = await _adapter.request(&"claim_companions", {
			"claim_kind": "PON",
			"options": [[11, 12], [12, 14]],
			"discarded_tile_id": TileId.W3,
			"selected_tile_instance_ids": [12],
			"allowed_tile_instance_ids": [11, 12, 14],
		})
	request_runner.call()
	await get_tree().process_frame
	assert_true(_seat._hand_clickable)
	_adapter.on_hand_tile_clicked(12)
	await get_tree().process_frame
	assert_eq(result.choice, {"action": "claim_tile_pick", "tile_instance_id": 12})
	assert_false(result.choice.has("tile_id"))
	assert_false(result.choice.has("allowed_tile_ids"))


func test_idle_presentation_disables_hand_input() -> void:
	_seat.set_hand_clickable(true)
	_adapter.present(&"idle", {"text": "AI 出牌中…"})

	assert_eq(_panel._state, PlayerActionPanel.State.IDLE)
	assert_false(_seat._hand_clickable)
	assert_eq(_panel._label_status.text, "AI 出牌中…")


# E2-02：claim_companions 搭子选择窗口须保留 claim 倒计时；超时 skip 且只 emit 一次
func test_claim_companions_timeout_emits_skip_once() -> void:
	var result := {}
	var request_runner := func():
		result["choice"] = await _adapter.request(&"claim_companions", {
			"claim_kind": "CHI",
			"options": [[11, 12], [12, 14]],
			"discarded_tile_id": TileId.W3,
			"selected_tile_instance_ids": [],
			"allowed_tile_instance_ids": [11, 12, 14],
		})
	request_runner.call()
	await get_tree().process_frame

	assert_eq(_panel._state, PlayerActionPanel.State.WAITING_CLAIM)
	assert_true(_panel.is_countdown_active(), "claim_companions 须启动 claim 倒计时")
	assert_eq(_panel._countdown_kind, &"claim")

	watch_signals(_panel)
	# 直接触发 finished，避免等真实秒数
	_panel._on_countdown_finished()
	await get_tree().process_frame

	assert_eq(result.choice, {"action": "skip"})
	assert_signal_emit_count(_panel, "player_action_chosen", 1)

	# 再次 finished 不得二次 emit
	_panel._on_countdown_finished()
	await get_tree().process_frame
	assert_signal_emit_count(_panel, "player_action_chosen", 1)
