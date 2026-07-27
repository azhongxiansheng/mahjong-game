class_name Hand

var _tiles: Array[Tile] = []

func tiles() -> Array[Tile]:
	return _tiles.duplicate()

func tile_at(index: int) -> Tile:
	if index < 0 or index >= _tiles.size():
		return null
	return _tiles[index]

func first() -> Tile:
	return tile_at(0)

func size() -> int:
	return _tiles.size()

# 返回 true 表示加入成功。
# INVALID_INSTANCE_ID 可重复（规则 fixture）。
# 0..MAX_SAFE 合法但重复 → false；其它非法 identity（-2 / 超界）→ false 且不追加。
func add(t: Tile) -> bool:
	if t == null or not t.is_valid():
		return false
	var iid: int = t.instance_id
	if iid == Tile.INVALID_INSTANCE_ID:
		_tiles.append(t)
		return true
	if not Tile.is_valid_instance_id(iid):
		return false
	if find_by_instance_id(iid) != null:
		return false
	_tiles.append(t)
	return true

# fail-closed：非合法 TYPE_INT 范围 → null，不 int() 静默强转。
func find_by_instance_id(instance_id: Variant) -> Tile:
	if not Tile.is_valid_instance_id(instance_id):
		return null
	var iid: int = instance_id
	for t in _tiles:
		if t.instance_id == iid:
			return t
	return null

func take_by_instance_id(instance_id: Variant) -> Tile:
	if not Tile.is_valid_instance_id(instance_id):
		return null
	var iid: int = instance_id
	for i in range(_tiles.size()):
		if _tiles[i].instance_id == iid:
			var t: Tile = _tiles[i]
			_tiles.remove_at(i)
			return t
	return null

# 批量精确取牌：非空、无重复、全部合法且存在；先完整预检再删除。
# 成功按请求顺序返回 Array[Tile]；失败 null 且内容和顺序零修改。
# 禁止 int(raw) 静默强转：String/float/bool/超界一律失败。
func take_many_by_instance_ids(instance_ids: Array) -> Variant:
	if instance_ids.is_empty():
		return null
	var seen: Dictionary = {}
	var indices: Array[int] = []
	for raw in instance_ids:
		if not Tile.is_valid_instance_id(raw):
			return null
		var iid: int = raw
		if seen.has(iid):
			return null
		seen[iid] = true
		var idx: int = -1
		for i in range(_tiles.size()):
			if _tiles[i].instance_id == iid:
				idx = i
				break
		if idx < 0:
			return null
		indices.append(idx)
	# 全部合法：按请求顺序收集，再从高 index 往低删以免偏移
	var result: Array[Tile] = []
	for i in range(instance_ids.size()):
		result.append(_tiles[indices[i]])
	var remove_order: Array[int] = indices.duplicate()
	remove_order.sort()
	remove_order.reverse()
	for idx in remove_order:
		_tiles.remove_at(idx)
	return result

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

# 返回当前手牌按内部顺序的 owner_seat 数组（不排序，与 _tiles 顺序对应）。
# 用于 UI 层渲染"按座位 owner 着色的手牌色块"（plan-3 D2/D5）。
func to_owner_array() -> Array:
	var owners := []
	for t in _tiles:
		owners.append(t.owner_seat)
	return owners

func clone() -> Hand:
	var c := Hand.new()
	for t in _tiles:
		c._tiles.append(t.clone())
	return c

# 权威恢复专用：先完整校验，再一次替换；失败时当前手牌零修改。
func restore_tiles(p_tiles: Array) -> bool:
	var staged := Hand.new()
	for raw in p_tiles:
		if not (raw is Tile) or not staged.add(raw as Tile):
			return false
	_tiles = staged._tiles
	return true
