class_name MeldCollection
extends RefCounted

var _seat_id: int
var _melds: Array[Meld] = []
var _next_local_index: int = 0


func _init(p_seat_id: int) -> void:
	assert(p_seat_id >= 0 and p_seat_id <= 3, "MeldCollection seat_id 越界")
	_seat_id = p_seat_id


func size() -> int:
	return _melds.size()


func is_empty() -> bool:
	return _melds.is_empty()


func all() -> Array[Meld]:
	return _melds.duplicate()


func last() -> Meld:
	if _melds.is_empty():
		return null
	return _melds[-1]


func clone() -> MeldCollection:
	var copy := MeldCollection.new(_seat_id)
	copy._melds = _melds.duplicate()
	copy._next_local_index = _next_local_index
	return copy


func find_by_id(meld_id: Variant) -> Meld:
	if not Meld.is_valid_meld_id(meld_id):
		return null
	for meld in _melds:
		if meld.meld_id == meld_id:
			return meld
	return null


func next_local_index() -> int:
	return _next_local_index


func add_chi(tiles: Array[Tile], from_seat: int, called_tile: Tile) -> Meld:
	return _add(Meld.Kind.CHI, tiles, from_seat, called_tile)


func add_pon(tiles: Array[Tile], from_seat: int, called_tile: Tile) -> Meld:
	return _add(Meld.Kind.PON, tiles, from_seat, called_tile)


func add_minkan(tiles: Array[Tile], from_seat: int, called_tile: Tile) -> Meld:
	return _add(Meld.Kind.MINKAN, tiles, from_seat, called_tile)


func add_ankan(tiles: Array[Tile]) -> Meld:
	return _add(Meld.Kind.ANKAN, tiles, Meld.NO_SOURCE_SEAT, null)


# 夹具/导入边界：接收已构造 Meld；缺少 identity 时按本集合分配规范 identity。
# 正常对局行动应使用 add_chi/add_pon/add_minkan/add_ankan。
func add_existing(meld: Meld) -> bool:
	if meld == null:
		return false
	if not Meld.is_valid_meld_id(meld.meld_id):
		var added: Meld = _add(meld.kind, meld.tiles, meld.from_seat, meld.called_tile)
		return added != null
	if meld.kind != Meld.Kind.ANKAN and meld.called_tile == null and not meld.tiles.is_empty():
		meld = Meld.new(meld.kind, meld.tiles, meld.from_seat, meld.meld_id, meld.tiles[0])
	if not _is_structurally_valid(meld) or find_by_id(meld.meld_id) != null:
		return false
	if _shares_entity_with_collection(meld, _melds):
		return false
	_melds.append(meld)
	@warning_ignore("integer_division")
	var next_after_id: int = meld.meld_id / 4 + 1
	_next_local_index = maxi(_next_local_index, next_after_id)
	return true


func promote_pon(meld_id: Variant, tile: Tile) -> bool:
	var meld := find_by_id(meld_id)
	if meld == null or tile == null:
		return false
	for existing in _melds:
		if existing == meld:
			continue
		for existing_tile in existing.tiles:
			if Tile.is_valid_instance_id(tile.instance_id) \
					and existing_tile.instance_id == tile.instance_id:
				return false
	return meld.promote_to_added_kan(tile)


func restore(melds: Array, next_local_index_arg: int) -> bool:
	if next_local_index_arg < 0:
		return false
	var seen: Dictionary = {}
	var staged: Array[Meld] = []
	for raw in melds:
		if not (raw is Meld):
			return false
		var meld: Meld = raw as Meld
		if meld.kind != Meld.Kind.ANKAN and meld.called_tile == null and not meld.tiles.is_empty():
			meld = Meld.new(meld.kind, meld.tiles, meld.from_seat, meld.meld_id, meld.tiles[0])
		if not _is_structurally_valid(meld) or seen.has(meld.meld_id):
			return false
		if _shares_entity_with_collection(meld, staged):
			return false
		seen[meld.meld_id] = true
		staged.append(meld)
		@warning_ignore("integer_division")
		var local_index: int = meld.meld_id / 4
		if next_local_index_arg <= local_index:
			return false
	_melds = staged
	_next_local_index = next_local_index_arg
	return true


func _add(kind: Meld.Kind, tiles: Array[Tile], from_seat: int, called_tile: Tile) -> Meld:
	var meld_id := _next_local_index * 4 + _seat_id
	var meld: Meld
	match kind:
		Meld.Kind.CHI:
			meld = Meld.make_chi(tiles, from_seat, meld_id, called_tile)
		Meld.Kind.PON:
			meld = Meld.make_pon(tiles, from_seat, meld_id, called_tile)
		Meld.Kind.MINKAN:
			meld = Meld.make_minkan(tiles, from_seat, meld_id, called_tile)
		Meld.Kind.ANKAN:
			meld = Meld.make_ankan(tiles, meld_id)
		_:
			return null
	if not _is_structurally_valid(meld):
		return null
	if _shares_entity_with_collection(meld, _melds):
		return null
	_melds.append(meld)
	_next_local_index += 1
	return meld


func _is_structurally_valid(meld: Meld) -> bool:
	if meld == null or not Meld.is_valid_meld_id(meld.meld_id):
		return false
	if meld.meld_id % 4 != _seat_id:
		return false
	var expected := 4 if meld.is_kan() else 3
	if meld.tiles.size() != expected:
		return false
	var seen: Dictionary = {}
	for tile in meld.tiles:
		if tile == null or not tile.is_valid():
			return false
		if tile.instance_id != Tile.INVALID_INSTANCE_ID:
			if seen.has(tile.instance_id):
				return false
			seen[tile.instance_id] = true
	if meld.kind == Meld.Kind.ANKAN:
		return meld.from_seat == Meld.NO_SOURCE_SEAT \
			and _all_same_tile_id(meld.tiles)
	if meld.from_seat < 0 or meld.from_seat > 3 or meld.from_seat == _seat_id:
		return false
	var has_physical_entity := not seen.is_empty()
	if has_physical_entity and meld.called_tile == null:
		return false
	match meld.kind:
		Meld.Kind.CHI:
			if not _is_valid_chi(meld.tiles):
				return false
		Meld.Kind.PON, Meld.Kind.MINKAN, Meld.Kind.ADDED_KAN:
			if not _all_same_tile_id(meld.tiles):
				return false
		_:
			return false
	if meld.kind == Meld.Kind.ADDED_KAN:
		if not Tile.is_valid_instance_id(meld.added_tile_instance_id):
			return false
		var added_found := false
		for tile in meld.tiles:
			if tile.instance_id == meld.added_tile_instance_id:
				added_found = true
				break
		if not added_found:
			return false
	if meld.called_tile != null:
		return true
	# 纯规则 fixture 可使用 INVALID_INSTANCE_ID；权威实体副露仍必须携带 called identity。
	for tile in meld.tiles:
		if tile.instance_id != Tile.INVALID_INSTANCE_ID:
			return false
	return true


func _shares_entity_with_collection(meld: Meld, existing_melds: Array[Meld]) -> bool:
	var occupied: Dictionary = {}
	for existing in existing_melds:
		for tile in existing.tiles:
			if Tile.is_valid_instance_id(tile.instance_id):
				occupied[tile.instance_id] = true
	for tile in meld.tiles:
		if Tile.is_valid_instance_id(tile.instance_id) and occupied.has(tile.instance_id):
			return true
	return false


func _all_same_tile_id(tiles: Array[Tile]) -> bool:
	if tiles.is_empty():
		return false
	var tile_id: int = tiles[0].id
	for tile in tiles:
		if tile.id != tile_id:
			return false
	return true


func _is_valid_chi(tiles: Array[Tile]) -> bool:
	if tiles.size() != 3:
		return false
	var ids: Array[int] = []
	for tile in tiles:
		if TileId.suit(tile.id) == TileId.Suit.HONOR:
			return false
		ids.append(tile.id)
	ids.sort()
	return TileId.suit(ids[0]) == TileId.suit(ids[2]) \
		and ids[1] == ids[0] + 1 and ids[2] == ids[1] + 1
