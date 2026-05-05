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

# ---- M10 net foundation: 序列化（spec §4.3 Phase 2 联机预留）----
#
# skill 字段不进 dict — server 权威下 skill 是 registered state，事件本身
# 只负责 reference 透传。client 重放时 skill 由本地 registry 通过
# (id, owner_seat) 反查。
func to_dict() -> Dictionary:
	if tile == null:
		return {}
	return {
		"tile_id": tile.id,
		"is_red_dora": tile.is_red_dora,
		"tile_owner_seat": tile.owner_seat,
		"owner_seat": owner_seat,
		"holder_seat": holder_seat,
		# skill 不序列化（见类注释）
	}

static func from_dict(d: Dictionary) -> TileInstance:
	if d == null or d.is_empty():
		return null
	var t := Tile.new(int(d.get("tile_id", 0)), bool(d.get("is_red_dora", false)),
		int(d.get("tile_owner_seat", -1)))
	var ti := TileInstance.new()
	ti.tile = t
	ti.owner_seat = int(d.get("owner_seat", -1))
	ti.holder_seat = int(d.get("holder_seat", -1))
	# skill 留 null（server replay 路径下由 registry 反查）
	return ti
