class_name Tile

var id: int
var is_red_dora: bool

func _init(p_id: int, p_red: bool = false) -> void:
	id = p_id
	is_red_dora = p_red

func equals_by_id(other: Tile) -> bool:
	return id == other.id

static func make_red_five_man() -> Tile:
	return Tile.new(TileId.W5, true)

static func make_red_five_pin() -> Tile:
	return Tile.new(TileId.T5, true)

static func make_red_five_sou() -> Tile:
	return Tile.new(TileId.S5, true)
