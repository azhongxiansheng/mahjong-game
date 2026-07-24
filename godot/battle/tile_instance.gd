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
#
# exact 六键：tile_id / is_red_dora / tile_owner_seat / tile_instance_id /
# owner_seat / holder_seat。严格 typeof，无 int()/bool() 静默强转。
func to_dict() -> Dictionary:
	if tile == null:
		return {}
	return {
		"tile_id": tile.id,
		"is_red_dora": tile.is_red_dora,
		"tile_owner_seat": tile.owner_seat,
		"tile_instance_id": tile.instance_id,
		"owner_seat": owner_seat,
		"holder_seat": holder_seat,
		# skill 不序列化（见类注释）
	}

static func from_dict(d: Variant) -> TileInstance:
	if typeof(d) != TYPE_DICTIONARY:
		return null
	var dict: Dictionary = d
	if dict.size() != 6:
		return null
	if not dict.has("tile_id") or not dict.has("is_red_dora") \
			or not dict.has("tile_owner_seat") or not dict.has("tile_instance_id") \
			or not dict.has("owner_seat") or not dict.has("holder_seat"):
		return null

	var raw_tid: Variant = dict["tile_id"]
	if typeof(raw_tid) != TYPE_INT:
		return null
	var tid: int = raw_tid
	if not TileId.ALL.has(tid):
		return null

	var raw_red: Variant = dict["is_red_dora"]
	if typeof(raw_red) != TYPE_BOOL:
		return null
	var red: bool = raw_red
	if red and tid != TileId.W5 and tid != TileId.T5 and tid != TileId.S5:
		return null

	var raw_tile_owner: Variant = dict["tile_owner_seat"]
	if typeof(raw_tile_owner) != TYPE_INT:
		return null
	var tile_owner: int = raw_tile_owner
	if tile_owner < -1 or tile_owner > 3:
		return null

	var raw_iid: Variant = dict["tile_instance_id"]
	if typeof(raw_iid) != TYPE_INT:
		return null
	var iid: int = raw_iid
	if iid != Tile.INVALID_INSTANCE_ID and not Tile.is_valid_instance_id(iid):
		return null

	var raw_owner: Variant = dict["owner_seat"]
	if typeof(raw_owner) != TYPE_INT:
		return null
	var p_owner: int = raw_owner
	if p_owner < -1 or p_owner > 3:
		return null

	var raw_holder: Variant = dict["holder_seat"]
	if typeof(raw_holder) != TYPE_INT:
		return null
	var p_holder: int = raw_holder
	if p_holder < -1 or p_holder > 3:
		return null

	var t := Tile.new(tid, red, tile_owner, iid)
	var ti := TileInstance.new()
	ti.tile = t
	ti.owner_seat = p_owner
	ti.holder_seat = p_holder
	# skill 留 null（server replay 路径下由 registry 反查）
	return ti
