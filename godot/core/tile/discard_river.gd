class_name DiscardRiver
extends RefCounted

var _tiles: Array[Tile] = []
var _riichi_discard_index: int = -1


func size() -> int:
	return _tiles.size()


func is_empty() -> bool:
	return _tiles.is_empty()


func tiles() -> Array[Tile]:
	return _tiles.duplicate()


func last_tile() -> Tile:
	if _tiles.is_empty():
		return null
	return _tiles[-1]


func riichi_discard_index() -> int:
	return _riichi_discard_index


func append_discard(tile: Tile, marks_riichi: bool = false) -> bool:
	if tile == null or not tile.is_valid():
		return false
	if tile.instance_id != Tile.INVALID_INSTANCE_ID:
		if not Tile.is_valid_instance_id(tile.instance_id):
			return false
		for existing in _tiles:
			if existing.instance_id == tile.instance_id:
				return false
	_tiles.append(tile)
	if marks_riichi:
		_riichi_discard_index = _tiles.size() - 1
	return true


func claim_last(expected_instance_id: Variant) -> Tile:
	if not Tile.is_valid_instance_id(expected_instance_id):
		return null
	var tile := last_tile()
	if tile == null or tile.instance_id != expected_instance_id:
		return null
	var claimed_index := _tiles.size() - 1
	_tiles.pop_back()
	if _riichi_discard_index == claimed_index:
		_riichi_discard_index = -1
	return tile


func contains_tile_id(tile_id: int) -> bool:
	for tile in _tiles:
		if tile.id == tile_id:
			return true
	return false


func restore(p_tiles: Array, p_riichi_index: int = -1) -> bool:
	if p_riichi_index < -1 or p_riichi_index >= p_tiles.size():
		return false
	var staged := DiscardRiver.new()
	for raw in p_tiles:
		if not (raw is Tile) or not staged.append_discard(raw as Tile):
			return false
	staged._riichi_discard_index = p_riichi_index
	_tiles = staged._tiles
	_riichi_discard_index = staged._riichi_discard_index
	return true
