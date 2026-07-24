class_name Tile

# 0e 扩展：owner_seat 字段，默认 NO_OWNER。卡组系统（里程碑 6）真正接入时填实际座位；
# v1 (M3 收尾) 由 Wall.new_full_set 按 copy_index 给每张牌做"卡组合并"占位分配。
# spec §5 设计了 TileInstance 含 owner_seat / skill / is_revealed_to —— 0e 阶段
# 仅引入 owner_seat，其余字段在里程碑 1 技能框架时由 TileInstance 包装。
#
# E2-02 / #232：instance_id 是牌实体 identity；owner_seat 不承担 identity。
# 纯规则 fixture 可用 INVALID_INSTANCE_ID；正式墙由 Wall 按 hand_seq 命名空间分配。
# identity 只读：仅构造器写入，无 setter。

const NO_OWNER: int = -1
const INVALID_INSTANCE_ID: int = -1
# JSON / JS Number 安全整数上限（2^53 - 1）
const MAX_SAFE_INSTANCE_ID: int = 9007199254740991
# 一局实体命名空间：instance_id = hand_seq * TILES_PER_HAND + serial(0..135)
const TILES_PER_HAND: int = 136

var id: int
var is_red_dora: bool
var owner_seat: int
var _instance_id: int = INVALID_INSTANCE_ID
var instance_id: int:
	get:
		return _instance_id

func _init(p_id: int, p_red: bool = false, p_owner: int = NO_OWNER,
		p_instance_id: int = INVALID_INSTANCE_ID) -> void:
	id = p_id
	is_red_dora = p_red
	owner_seat = p_owner
	_instance_id = p_instance_id

# 仅 TYPE_INT 且 0..MAX_SAFE_INSTANCE_ID 为合法；String/float/bool/负数/超界全拒。
static func is_valid_instance_id(value: Variant) -> bool:
	if typeof(value) != TYPE_INT:
		return false
	var v: int = value
	return v >= 0 and v <= MAX_SAFE_INSTANCE_ID


## hand_seq 命名空间：iid 必须落在 [hs*136, hs*136+135]。
static func is_instance_id_in_hand_seq(iid: Variant, hand_seq: Variant) -> bool:
	if typeof(iid) != TYPE_INT or typeof(hand_seq) != TYPE_INT:
		return false
	var candidate: int = iid
	var hs: int = hand_seq
	if hs < 0:
		return false
	if not is_valid_instance_id(candidate):
		return false
	var base: int = hs * TILES_PER_HAND
	return candidate >= base and candidate <= base + (TILES_PER_HAND - 1)

func equals_by_id(other: Tile) -> bool:
	return id == other.id

func clone() -> Tile:
	return Tile.new(id, is_red_dora, owner_seat, _instance_id)

# internal-only 快照：供引擎/存档/测试 roundtrip。
# 不是 TileView，也不是客户端可见协议载荷。
func to_dict() -> Dictionary:
	return {
		"id": id,
		"is_red_dora": is_red_dora,
		"owner_seat": owner_seat,
		"instance_id": _instance_id,
	}

# 严格解析：无 int()/bool() 静默强转；非法一律 null。
# 恰好四个 key：id / is_red_dora / owner_seat / instance_id。
static func from_dict(d: Variant) -> Tile:
	if typeof(d) != TYPE_DICTIONARY:
		return null
	var dict: Dictionary = d
	if dict.size() != 4:
		return null
	if not dict.has("id") or not dict.has("is_red_dora") \
			or not dict.has("owner_seat") or not dict.has("instance_id"):
		return null
	var raw_id: Variant = dict["id"]
	if typeof(raw_id) != TYPE_INT:
		return null
	var tid: int = raw_id
	if not TileId.ALL.has(tid):
		return null
	var raw_red: Variant = dict["is_red_dora"]
	if typeof(raw_red) != TYPE_BOOL:
		return null
	var red: bool = raw_red
	if red and tid != TileId.W5 and tid != TileId.T5 and tid != TileId.S5:
		return null
	var raw_owner: Variant = dict["owner_seat"]
	if typeof(raw_owner) != TYPE_INT:
		return null
	var owner: int = raw_owner
	if owner < NO_OWNER or owner > 3:
		return null
	var raw_iid: Variant = dict["instance_id"]
	if typeof(raw_iid) != TYPE_INT:
		return null
	var iid: int = raw_iid
	if iid != INVALID_INSTANCE_ID and not is_valid_instance_id(iid):
		return null
	return Tile.new(tid, red, owner, iid)

static func make_red_five_man() -> Tile:
	return Tile.new(TileId.W5, true)

static func make_red_five_pin() -> Tile:
	return Tile.new(TileId.T5, true)

static func make_red_five_sou() -> Tile:
	return Tile.new(TileId.S5, true)
