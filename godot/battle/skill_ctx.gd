class_name SkillCtx

var _state: BattleState
var _event: BattleEvent
var han_deltas: Dictionary = {}
var beneficiary_seat: int = -1  # 由 scheduler 在每个 candidate 派发前设置

func _init(p_state: BattleState, p_event: BattleEvent) -> void:
	_state = p_state
	_event = p_event

# ---- Mutations (spec §6.3 + 本里程碑追加) ----

func add_han(seat: int, n: int) -> void:
	han_deltas[seat] = int(han_deltas.get(seat, 0)) + n

func cancel_ron(seat: int) -> void:
	_state.ron_cancelled[seat] = true

func steal_score(from_seat: int, to_seat: int, fraction: float) -> void:
	var amount := int(_state.scores[from_seat] * fraction)
	_state.scores[from_seat] -= amount
	_state.scores[to_seat] += amount

func transfer_points(from_seat: int, to_seat: int, amount: int) -> void:
	_state.scores[from_seat] -= amount
	_state.scores[to_seat] += amount

func reveal_tile_to(tile: TileInstance, target_seat: int) -> void:
	_state.revealed_tiles.append({"tile": tile, "visible_to": [target_seat]})

func clear_furiten(seat: int) -> void:
	_state.furiten_flags[seat] = false

func force_tsumo(seat: int) -> void:
	_state.haitei_forced_seat = seat

# ---- Read-only accessors ----

func get_score(seat: int) -> int:
	return _state.scores[seat]

func is_furiten(seat: int) -> bool:
	return _state.furiten_flags[seat]

func get_event() -> BattleEvent:
	return _event
