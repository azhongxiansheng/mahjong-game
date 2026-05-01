class_name Hand

var _tiles: Array[Tile] = []

func size() -> int:
	return _tiles.size()

func add(t: Tile) -> void:
	_tiles.append(t)

func remove_by_id(tid: int) -> bool:
	for i in range(_tiles.size()):
		if _tiles[i].id == tid:
			_tiles.remove_at(i)
			return true
	return false

func count_of(tid: int) -> int:
	var c := 0
	for t in _tiles:
		if t.id == tid:
			c += 1
	return c

func id_count_dict() -> Dictionary:
	var d := {}
	for t in _tiles:
		d[t.id] = d.get(t.id, 0) + 1
	return d

func to_id_array() -> Array:
	var ids := []
	for t in _tiles:
		ids.append(t.id)
	ids.sort()
	return ids

func clone() -> Hand:
	var c := Hand.new()
	for t in _tiles:
		c._tiles.append(Tile.new(t.id, t.is_red_dora))
	return c
