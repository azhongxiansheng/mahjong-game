class_name BattleEvent

const NO_CHAIN := 0

var type: StringName
var actor_seat: int
var tile_anchor: TileSkillAnchor
var chain_id: int = NO_CHAIN
var extra: Dictionary = {}

static func make(
	p_type: StringName,
	p_actor: int,
	p_tile: TileSkillAnchor = null,
	p_extra: Dictionary = {}
) -> BattleEvent:
	var ev := BattleEvent.new()
	ev.type = p_type
	ev.actor_seat = p_actor
	ev.tile_anchor = p_tile
	ev.extra = p_extra
	return ev

# ---- M10 net foundation: 序列化（spec §4.3 Phase 2 联机预留）----
#
# 用途：server 权威 + 事件回放架构下，事件需要在网络上传输，
# 也需要落盘成 replay log。spec §4 强调"所有副作用走 event bus"
# 的承诺正是为此预留 — 序列化能力让 v1 day 1 就锁住"事件总线 = 单一事实
# 源" 这个不变量。
func to_dict() -> Dictionary:
	return {
		"type": String(type),
		"actor_seat": actor_seat,
		"tile": tile_anchor.to_dict() if tile_anchor != null else {},
		"chain_id": chain_id,
		"extra": _serialize_extra(extra),
	}

static func from_dict(d: Dictionary) -> BattleEvent:
	if d == null or d.is_empty():
		return null
	var ev := BattleEvent.new()
	ev.type = StringName(String(d.get("type", "")))
	ev.actor_seat = int(d.get("actor_seat", -1))
	var tile_dict: Dictionary = d.get("tile", {})
	if not tile_dict.is_empty():
		ev.tile_anchor = TileSkillAnchor.from_dict(tile_dict)
	ev.chain_id = int(d.get("chain_id", NO_CHAIN))
	ev.extra = d.get("extra", {}).duplicate(true)
	return ev

# extra 字段是任意 Dictionary（payout / han / fu / discarder_seat 等）。
# 大部分值是 int / bool / Dictionary，JSON 兼容；不需要特殊处理。
# 这里 duplicate 仅是防别名共享。Phase 2 网络层若需 wire format 紧凑可换 Bytes。
static func _serialize_extra(e: Dictionary) -> Dictionary:
	return e.duplicate(true)
