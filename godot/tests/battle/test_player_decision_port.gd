extends GutTest


class FakeDecisionPort extends PlayerDecisionPort:
	var requests: Array[Dictionary] = []
	var presentations: Array[Dictionary] = []
	var queued_choices: Array[Dictionary] = []

	func request(kind: StringName, context: Dictionary = {}) -> Dictionary:
		requests.append({"kind": kind, "context": context.duplicate(true)})
		if queued_choices.is_empty():
			return {}
		return queued_choices.pop_front()

	func present(state_name: StringName, context: Dictionary = {}) -> void:
		presentations.append({"state": state_name, "context": context.duplicate(true)})


func test_controller_consumes_discard_from_decision_port_without_ui_nodes() -> void:
	var bc := PlayableBattleController.new(42, 0, false)
	bc.set_ai_think_delay(0.0)
	var port := FakeDecisionPort.new()
	var seat: Seat = bc.state.seats[0]
	var expected_id: int = int(seat.hand.to_id_array()[0])
	port.queued_choices.append({"action": "discard", "tile_id": expected_id})
	bc.bind_decision_port(port)

	var picked: Tile = await bc._get_discard_decision(seat, 0)

	assert_not_null(picked)
	assert_eq(picked.id, expected_id)
	assert_eq(port.requests.size(), 1)
	assert_eq(port.requests[0].kind, &"discard")
	assert_true(port.presentations.any(func(item): return item.state == &"idle"))
