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
	_adapter.on_hand_tile_clicked(TileId.W1)
	await get_tree().process_frame
	assert_eq(result.choice, {"action": "discard", "tile_id": TileId.W1})


func test_idle_presentation_disables_hand_input() -> void:
	_seat.set_hand_clickable(true)
	_adapter.present(&"idle", {"text": "AI 出牌中…"})

	assert_eq(_panel._state, PlayerActionPanel.State.IDLE)
	assert_false(_seat._hand_clickable)
	assert_eq(_panel._label_status.text, "AI 出牌中…")
