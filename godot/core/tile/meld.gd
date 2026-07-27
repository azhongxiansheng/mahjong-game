class_name Meld

enum Kind { CHI, PON, MINKAN, ANKAN, ADDED_KAN }

# 暗杠不来自任何人，from_seat 用此哨兵表示
const NO_SOURCE_SEAT: int = -1

var _kind: Kind
var kind: Kind:
	get:
		return _kind
var _tiles: Array[Tile] = []
var tiles: Array[Tile]:
	get:
		return _tiles.duplicate()
var _from_seat: int
var from_seat: int:  # 牌来自哪个 seat（暗杠 = NO_SOURCE_SEAT）
	get:
		return _from_seat
# E2-02 / #232：副露 identity + 叫牌实体 id 只读；called_tile 仅 getter。
# added_tile_instance_id 只能经 promote_to_added_kan 一次性写入。
# 唯一契约：第 4 参 = meld_id(int)，第 5 参 = called Tile（可选）；无 Tile 第 4 参兼容。
var _meld_id: int = Tile.INVALID_INSTANCE_ID
var meld_id: int:
	get:
		return _meld_id
var _called_tile_instance_id: int = Tile.INVALID_INSTANCE_ID
var called_tile_instance_id: int:
	get:
		return _called_tile_instance_id
var _added_tile_instance_id: int = Tile.INVALID_INSTANCE_ID
var added_tile_instance_id: int:
	get:
		return _added_tile_instance_id

# 从 tiles 按 called_tile_instance_id 派生；INVALID_INSTANCE_ID 或找不到 → null。
var called_tile: Tile:
	get:
		if _called_tile_instance_id == Tile.INVALID_INSTANCE_ID:
			return null
		for t in _tiles:
			if t.instance_id == _called_tile_instance_id:
				return t
		return null

func _init(p_kind: Kind, p_tiles: Array[Tile], p_from: int,
		p_meld_id: int = Tile.INVALID_INSTANCE_ID,
		p_called_tile: Tile = null) -> void:
	_kind = p_kind
	_tiles = p_tiles.duplicate()
	_from_seat = p_from
	_meld_id = p_meld_id
	if p_called_tile != null:
		_called_tile_instance_id = p_called_tile.instance_id
	else:
		_called_tile_instance_id = Tile.INVALID_INSTANCE_ID
	_added_tile_instance_id = Tile.INVALID_INSTANCE_ID

# 仅 TYPE_INT 且 0..MAX_SAFE_INSTANCE_ID；-1/-2/超界/String/float/bool 全拒。
static func is_valid_meld_id(value: Variant) -> bool:
	if typeof(value) != TYPE_INT:
		return false
	var v: int = value
	return v >= 0 and v <= Tile.MAX_SAFE_INSTANCE_ID

static func make_chi(p_tiles: Array[Tile], p_from: int,
		p_meld_id: int = Tile.INVALID_INSTANCE_ID,
		p_called_tile: Tile = null) -> Meld:
	return Meld.new(Kind.CHI, p_tiles, p_from, p_meld_id, p_called_tile)

static func make_pon(p_tiles: Array[Tile], p_from: int,
		p_meld_id: int = Tile.INVALID_INSTANCE_ID,
		p_called_tile: Tile = null) -> Meld:
	return Meld.new(Kind.PON, p_tiles, p_from, p_meld_id, p_called_tile)

static func make_minkan(p_tiles: Array[Tile], p_from: int,
		p_meld_id: int = Tile.INVALID_INSTANCE_ID,
		p_called_tile: Tile = null) -> Meld:
	return Meld.new(Kind.MINKAN, p_tiles, p_from, p_meld_id, p_called_tile)

static func make_ankan(p_tiles: Array[Tile],
		p_meld_id: int = Tile.INVALID_INSTANCE_ID) -> Meld:
	return Meld.new(Kind.ANKAN, p_tiles, NO_SOURCE_SEAT, p_meld_id, null)

static func make_added_kan(p_tiles: Array[Tile], p_from: int,
		p_meld_id: int = Tile.INVALID_INSTANCE_ID,
		p_called_tile: Tile = null) -> Meld:
	return Meld.new(Kind.ADDED_KAN, p_tiles, p_from, p_meld_id, p_called_tile)

# 唯一允许写入 added_tile_instance_id 的路径：PON → ADDED_KAN 一次性升级。
func promote_to_added_kan(tile: Tile) -> bool:
	if kind != Kind.PON:
		return false
	if tile == null:
		return false
	if not Tile.is_valid_instance_id(tile.instance_id):
		return false
	if _added_tile_instance_id != Tile.INVALID_INSTANCE_ID:
		return false
	if _tiles.is_empty() or tile.id != _tiles[0].id:
		return false
	_tiles.append(tile)
	_kind = Kind.ADDED_KAN
	_added_tile_instance_id = tile.instance_id
	return true

func is_concealed() -> bool:
	return kind == Kind.ANKAN

func is_kan() -> bool:
	return kind == Kind.MINKAN or kind == Kind.ANKAN or kind == Kind.ADDED_KAN

func to_id_array() -> Array:
	var ids := []
	for t in _tiles:
		ids.append(t.id)
	return ids
