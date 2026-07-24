class_name ProtocolViewCodec extends RefCounted

# E2-02（#232）集中 view codec：TileView / MeldView 校验 + compute_view_hash。
# 无双协议兼容；fail-closed。

const TILE_KEYS := ["instance_id", "tile_id", "is_red_dora", "owner_seat"]
const MELD_KEYS := [
	"meld_id", "kind", "from_seat", "called_tile_instance_id",
	"added_tile_instance_id", "tiles",
]
const MELD_KINDS := ["CHI", "PON", "MINKAN", "ANKAN", "ADDED_KAN"]
const RED_DORA_TILE_IDS := [TileId.W5, TileId.T5, TileId.S5]


## 领域 Tile → exact 四键 TileView；非法/非 Tile → null
static func tile_view_from_tile(tile: Variant) -> Variant:
	if tile == null:
		return null
	if not (tile is Tile):
		return null
	var t: Tile = tile
	return tile_view_from_dict({
		"instance_id": t.instance_id,
		"tile_id": t.id,
		"is_red_dora": t.is_red_dora,
		"owner_seat": t.owner_seat,
	})


## 领域 Meld → exact 六键 MeldView（保留 m.tiles 领域顺序）；非法/非 Meld → null
static func meld_view_from_meld(meld: Variant) -> Variant:
	if meld == null:
		return null
	if not (meld is Meld):
		return null
	var m: Meld = meld
	var kind_str := ""
	match m.kind:
		Meld.Kind.CHI:
			kind_str = "CHI"
		Meld.Kind.PON:
			kind_str = "PON"
		Meld.Kind.MINKAN:
			kind_str = "MINKAN"
		Meld.Kind.ANKAN:
			kind_str = "ANKAN"
		Meld.Kind.ADDED_KAN:
			kind_str = "ADDED_KAN"
		_:
			return null
	var tiles_raw: Array = []
	for t in m.tiles:
		var tv: Variant = tile_view_from_tile(t)
		if tv == null:
			return null
		tiles_raw.append(tv)
	return meld_view_from_dict({
		"meld_id": m.meld_id,
		"kind": kind_str,
		"from_seat": m.from_seat,
		"called_tile_instance_id": m.called_tile_instance_id,
		"added_tile_instance_id": m.added_tile_instance_id,
		"tiles": tiles_raw,
	})


## 合法 → exact 四键 Dictionary（deep copy）；非法 → null
static func tile_view_from_dict(raw: Variant) -> Variant:
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = raw
	if not _has_exact_keys(d, TILE_KEYS):
		return null

	if typeof(d["instance_id"]) != TYPE_INT:
		return null
	var instance_id: int = d["instance_id"]
	if instance_id < 0 or instance_id > ProtocolConstants.MAX_SAFE_INT:
		return null

	if typeof(d["tile_id"]) != TYPE_INT:
		return null
	var tile_id: int = d["tile_id"]
	if not TileId.ALL.has(tile_id):
		return null

	if typeof(d["is_red_dora"]) != TYPE_BOOL:
		return null
	var is_red: bool = d["is_red_dora"]

	if typeof(d["owner_seat"]) != TYPE_INT:
		return null
	var owner_seat: int = d["owner_seat"]
	if owner_seat < -1 or owner_seat > 3:
		return null

	# Wall canonical identity：instance_id 唯一绑定 tile_id / is_red_dora / owner_seat
	if not _matches_canonical_identity(instance_id, tile_id, is_red, owner_seat):
		return null

	return {
		"instance_id": instance_id,
		"tile_id": tile_id,
		"is_red_dora": is_red,
		"owner_seat": owner_seat,
	}


## serial = iid % 136；tile = ALL[serial/4]；owner = serial%4；赤五仅 copy0
static func _matches_canonical_identity(
	instance_id: int,
	tile_id: int,
	is_red: bool,
	owner_seat: int
) -> bool:
	var serial: int = instance_id % ProtocolConstants.TILES_PER_HAND
	@warning_ignore("integer_division")
	var tile_index: int = serial / 4
	if tile_index < 0 or tile_index >= TileId.ALL.size():
		return false
	var canonical_tile_id: int = TileId.ALL[tile_index]
	var canonical_owner: int = serial % 4
	var canonical_red: bool = (
		canonical_tile_id in RED_DORA_TILE_IDS and canonical_owner == 0
	)
	return (
		tile_id == canonical_tile_id
		and owner_seat == canonical_owner
		and is_red == canonical_red
	)


## 合法 → exact 六键 Dictionary（tiles 保序 deep copy，不排序）；非法 → null
static func meld_view_from_dict(raw: Variant) -> Variant:
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = raw
	if not _has_exact_keys(d, MELD_KEYS):
		return null

	if typeof(d["meld_id"]) != TYPE_INT:
		return null
	var meld_id: int = d["meld_id"]
	if meld_id < 0 or meld_id > ProtocolConstants.MAX_SAFE_INT:
		return null

	if typeof(d["kind"]) != TYPE_STRING:
		return null
	var kind: String = d["kind"]
	if kind not in MELD_KINDS:
		return null

	if typeof(d["from_seat"]) != TYPE_INT:
		return null
	var from_seat: int = d["from_seat"]

	if typeof(d["called_tile_instance_id"]) != TYPE_INT:
		return null
	var called: int = d["called_tile_instance_id"]

	if typeof(d["added_tile_instance_id"]) != TYPE_INT:
		return null
	var added: int = d["added_tile_instance_id"]

	if typeof(d["tiles"]) != TYPE_ARRAY:
		return null
	var raw_tiles: Array = d["tiles"]
	if raw_tiles.is_empty():
		return null

	var expected_count := 3 if kind in ["CHI", "PON"] else 4
	if raw_tiles.size() != expected_count:
		return null

	var tiles: Array = []
	var seen_ids: Dictionary = {}
	for item in raw_tiles:
		var tv: Variant = tile_view_from_dict(item)
		if tv == null:
			return null
		var td: Dictionary = tv
		var iid: int = td["instance_id"]
		if seen_ids.has(iid):
			return null
		seen_ids[iid] = true
		tiles.append(td)

	if not _validate_meld_cross(kind, from_seat, called, added, tiles):
		return null

	return {
		"meld_id": meld_id,
		"kind": kind,
		"from_seat": from_seat,
		"called_tile_instance_id": called,
		"added_tile_instance_id": added,
		"tiles": tiles.duplicate(true),
	}


## JSON-compatible public view → 64 位小写 hex SHA-256；非法输入 → 空串
static func compute_view_hash(view: Variant) -> String:
	var canon: Variant = _canonical_json(view)
	if canon == null:
		return ""
	var bytes: PackedByteArray = str(canon).to_utf8_buffer()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


# ---- Meld 交叉校验 ----

static func _validate_meld_cross(
	kind: String,
	from_seat: int,
	called: int,
	added: int,
	tiles: Array
) -> bool:
	var tile_ids: Array = []
	var instance_ids: Dictionary = {}
	for t in tiles:
		var td: Dictionary = t
		tile_ids.append(int(td["tile_id"]))
		instance_ids[int(td["instance_id"])] = true

	match kind:
		"CHI":
			if from_seat < 0 or from_seat > 3:
				return false
			if added != -1:
				return false
			if not instance_ids.has(called):
				return false
			return _is_chi_sequence(tile_ids)
		"PON", "MINKAN":
			if from_seat < 0 or from_seat > 3:
				return false
			if added != -1:
				return false
			if not instance_ids.has(called):
				return false
			return _all_same_tile_id(tile_ids)
		"ANKAN":
			if from_seat != -1 or called != -1 or added != -1:
				return false
			return _all_same_tile_id(tile_ids)
		"ADDED_KAN":
			if from_seat < 0 or from_seat > 3:
				return false
			if called < 0 or added < 0:
				return false
			if called == added:
				return false
			if not instance_ids.has(called) or not instance_ids.has(added):
				return false
			return _all_same_tile_id(tile_ids)
		_:
			return false


static func _all_same_tile_id(tile_ids: Array) -> bool:
	if tile_ids.is_empty():
		return false
	var first: int = tile_ids[0]
	for tid in tile_ids:
		if int(tid) != first:
			return false
	return true


static func _is_chi_sequence(tile_ids: Array) -> bool:
	# 输入序必须同花色且数值连续升序；禁止先排序再判定。
	if tile_ids.size() != 3:
		return false
	var t0: int = tile_ids[0]
	var suit0: TileId.Suit = TileId.suit(t0)
	if suit0 == TileId.Suit.HONOR:
		return false
	var n0: int = TileId.number(t0)
	for i in range(3):
		var t: int = tile_ids[i]
		if TileId.suit(t) != suit0:
			return false
		if TileId.number(t) != n0 + i:
			return false
	return true


# ---- canonical JSON ----

static func _canonical_json(v: Variant) -> Variant:
	match typeof(v):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_INT:
			var n: int = v
			# JS Number 安全整数域；越界拒绝（含嵌套）
			if n < -ProtocolConstants.MAX_SAFE_INT or n > ProtocolConstants.MAX_SAFE_INT:
				return null
			return str(n)
		TYPE_FLOAT:
			# 严格 domain：任何 float（含 1.0/0.0）拒绝，禁止静默整型化
			return null
		TYPE_STRING:
			return JSON.stringify(v)
		TYPE_ARRAY:
			var parts: PackedStringArray = PackedStringArray()
			for item in v:
				var c: Variant = _canonical_json(item)
				if c == null:
					return null
				parts.append(str(c))
			return "[" + ",".join(parts) + "]"
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var keys: Array = []
			for k in d.keys():
				if typeof(k) != TYPE_STRING:
					return null
				keys.append(str(k))
			keys.sort()
			var parts: PackedStringArray = PackedStringArray()
			for k in keys:
				var c: Variant = _canonical_json(d[k])
				if c == null:
					return null
				parts.append(JSON.stringify(k) + ":" + str(c))
			return "{" + ",".join(parts) + "}"
		_:
			# Object / 非 JSON-compatible 拒绝
			return null


static func _has_exact_keys(d: Dictionary, expected: Array) -> bool:
	if d.keys().size() != expected.size():
		return false
	for k in expected:
		if not d.has(k):
			return false
	return true
