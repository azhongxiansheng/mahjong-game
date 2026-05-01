class_name BattleEvent

const NO_CHAIN := 0

var type: StringName
var actor_seat: int
var tile_instance: TileInstance
var chain_id: int = NO_CHAIN
var extra: Dictionary = {}

static func make(
	p_type: StringName,
	p_actor: int,
	p_tile: TileInstance = null,
	p_extra: Dictionary = {}
) -> BattleEvent:
	var ev := BattleEvent.new()
	ev.type = p_type
	ev.actor_seat = p_actor
	ev.tile_instance = p_tile
	ev.extra = p_extra
	return ev
