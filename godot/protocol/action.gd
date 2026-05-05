class_name Action extends RefCounted

# 麻将王 — M12 Path C 第 1 步：联机协议 Action 数据类型
#
# server-authoritative 联机架构下，client 把"玩家想做什么"发给 server 仲裁；
# server 验证 + 排序后回 NetworkedEvent 广播给所有 client。本类是 client →
# server 的统一信封。
#
# v1 设计原则：
# - Kind 是 enum（小整数 wire size）；payload 用 Dictionary 容纳 tile_id /
#   meld_tiles 等不定字段
# - to_dict / from_dict 走 BattleEvent 已有的序列化套路（spec §4.3 闭环）
# - 不携带 client-side state（state 由 server 持有，client 只发 intent）
# - 不携带 timestamp（server 决定排序）；可选 client_seq 用作 echo / debug
#
# 不在本 PR 范围（留 M12+）：
# - validation：合法性校验（rules engine 在 server 端）
# - 鉴权：client 只能发自家 seat 的 action
# - 序号 / 反作弊：留 M14

# Action 种类 — 与 TurnEngine state machine 转移对应
enum Kind {
	UNKNOWN = 0,
	# 摸牌：v1 server 决定，client 不主动发 DRAW；保留 enum 作 future PAUSE/RESUME 等扩展
	DRAW = 1,
	# 弃牌：payload {tile_id: int}
	DISCARD = 2,
	# 立直宣告（弃这张同时立直）：payload {tile_id: int}
	RIICHI = 3,
	# 鸣牌通过（让出窗口）：payload 空
	PASS_CLAIM = 4,
	# 吃：payload {tiles: [tid, tid, tid]}（含被吃的 discarded tile）
	CHI = 5,
	# 碰：payload {tile_id: int}
	PON = 6,
	# 明杠（大明杠 / 加杠 / 暗杠的 server-side 区分由验证器做）：payload {tile_id: int, kind: "minkan|added|ankan"}
	KAN = 7,
	# 荣胡：payload {tile_id: int, discarder_seat: int}
	RON = 8,
	# 自摸：payload 空（drawn tile 已在 server-side state）
	TSUMO = 9,
}

var kind: int = Kind.UNKNOWN
var seat: int = -1               # 发起方 seat（server 验证必须等于 client_id 对应 seat）
var payload: Dictionary = {}     # 动作参数；按 Kind 不同含 tile_id / tiles / discarder_seat 等
var client_seq: int = 0          # 可选；client 端递增帮 echo / debug；server 不必依赖

# ---- 构造器 helpers ----

static func discard(seat_id: int, tile_id: int, client_seq_id: int = 0) -> Action:
	var a := Action.new()
	a.kind = Kind.DISCARD
	a.seat = seat_id
	a.payload = {"tile_id": tile_id}
	a.client_seq = client_seq_id
	return a

static func riichi(seat_id: int, tile_id: int, client_seq_id: int = 0) -> Action:
	var a := Action.new()
	a.kind = Kind.RIICHI
	a.seat = seat_id
	a.payload = {"tile_id": tile_id}
	a.client_seq = client_seq_id
	return a

static func pass_claim(seat_id: int, client_seq_id: int = 0) -> Action:
	var a := Action.new()
	a.kind = Kind.PASS_CLAIM
	a.seat = seat_id
	a.client_seq = client_seq_id
	return a

static func chi(seat_id: int, tiles: Array, client_seq_id: int = 0) -> Action:
	var a := Action.new()
	a.kind = Kind.CHI
	a.seat = seat_id
	a.payload = {"tiles": tiles.duplicate()}
	a.client_seq = client_seq_id
	return a

static func pon(seat_id: int, tile_id: int, client_seq_id: int = 0) -> Action:
	var a := Action.new()
	a.kind = Kind.PON
	a.seat = seat_id
	a.payload = {"tile_id": tile_id}
	a.client_seq = client_seq_id
	return a

static func kan(seat_id: int, tile_id: int, sub_kind: String = "minkan", client_seq_id: int = 0) -> Action:
	var a := Action.new()
	a.kind = Kind.KAN
	a.seat = seat_id
	a.payload = {"tile_id": tile_id, "kind": sub_kind}
	a.client_seq = client_seq_id
	return a

static func ron(seat_id: int, tile_id: int, discarder_seat: int, client_seq_id: int = 0) -> Action:
	var a := Action.new()
	a.kind = Kind.RON
	a.seat = seat_id
	a.payload = {"tile_id": tile_id, "discarder_seat": discarder_seat}
	a.client_seq = client_seq_id
	return a

static func tsumo(seat_id: int, client_seq_id: int = 0) -> Action:
	var a := Action.new()
	a.kind = Kind.TSUMO
	a.seat = seat_id
	a.client_seq = client_seq_id
	return a

# ---- 序列化（和 BattleEvent.to_dict 风格对齐） ----

func to_dict() -> Dictionary:
	return {
		"kind": kind,
		"seat": seat,
		"payload": payload.duplicate(true),
		"client_seq": client_seq,
	}

static func from_dict(d: Dictionary) -> Action:
	if d == null or d.is_empty():
		return null
	var a := Action.new()
	a.kind = int(d.get("kind", Kind.UNKNOWN))
	a.seat = int(d.get("seat", -1))
	a.payload = d.get("payload", {}).duplicate(true)
	a.client_seq = int(d.get("client_seq", 0))
	return a

# 用作 debug / log
func describe() -> String:
	var kind_name: String = ""
	match kind:
		Kind.UNKNOWN: kind_name = "UNKNOWN"
		Kind.DRAW: kind_name = "DRAW"
		Kind.DISCARD: kind_name = "DISCARD"
		Kind.RIICHI: kind_name = "RIICHI"
		Kind.PASS_CLAIM: kind_name = "PASS_CLAIM"
		Kind.CHI: kind_name = "CHI"
		Kind.PON: kind_name = "PON"
		Kind.KAN: kind_name = "KAN"
		Kind.RON: kind_name = "RON"
		Kind.TSUMO: kind_name = "TSUMO"
	return "Action[%s seat=%d payload=%s]" % [kind_name, seat, payload]
