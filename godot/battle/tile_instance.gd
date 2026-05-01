class_name TileInstance

var tile: Tile
var owner_seat: int
var holder_seat: int = -1
var skill: SkillResource

static func make(p_tile: Tile, p_owner: int, p_skill: SkillResource = null) -> TileInstance:
	var ti := TileInstance.new()
	ti.tile = p_tile
	ti.owner_seat = p_owner
	ti.skill = p_skill
	return ti
