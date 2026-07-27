class_name RecipientViewProjector
extends RefCounted

const ViewerRevealResolver := preload("res://battle/viewer_reveal_resolver.gd")

# E2-02 / #232：按 recipient 生成严格 core_table 投影。
# 本人可见完整 concealed TileView；他席默认仅 concealed_count，信息能力可附带
# 只对该 recipient 授权且仍在目标手牌中的可见子集。
# 不泄露牌墙内容、他手、裏 dora、决策窗、RNG 或 AuthorityReplaySnapshot。

const CORE_KEYS := [
	"recipient_seat", "hand_seq", "dealer_seat", "current_seat", "phase",
	"round_wind", "hand_number", "honba", "riichi_sticks", "live_wall_count",
	"dora_indicators", "viewer_next_draw", "seats",
]
const SEAT_KEYS := [
	"seat", "seat_wind", "score", "concealed_tiles", "concealed_count",
	"last_drawn_tile_instance_id", "river", "melds",
	"riichi_declared", "riichi_double", "riichi_discard_index",
]


## static project_core_table(state, recipient_seat) → exact-13 Dictionary 或 null
static func project_core_table(state: Variant, recipient_seat: Variant) -> Variant:
	if state == null or not (state is BattleState):
		return null
	if typeof(recipient_seat) != TYPE_INT:
		return null
	var recip: int = recipient_seat
	if recip < 0 or recip > 3:
		return null
	var st: BattleState = state as BattleState
	if st.seats == null or st.seats.size() != 4:
		return null
	if st.wall == null or st.dora_indicators == null:
		return null

	var dora_out: Array = []
	for t in st.dora_indicators.visible_tiles():
		var tv: Variant = ProtocolViewCodec.tile_view_from_tile(t)
		if tv == null:
			return null
		dora_out.append(tv)

	var seats_out: Array = []
	var revealed_by_holder: Dictionary = ViewerRevealResolver.tiles_by_holder(st, recip)
	for i in range(4):
		var sv: Variant = _project_seat(st, i, recip, revealed_by_holder)
		if sv == null:
			return null
		seats_out.append(sv)
	var viewer_next_draw: Dictionary = {}
	var predicted := ViewerRevealResolver.next_draw_for_viewer(st, recip)
	if predicted != null:
		var predicted_view: Variant = ProtocolViewCodec.tile_view_from_tile(predicted.tile)
		if predicted_view == null:
			return null
		viewer_next_draw = predicted_view as Dictionary

	return {
		"recipient_seat": recip,
		"hand_seq": int(st.hand_seq),
		"dealer_seat": int(st.dealer_seat),
		"current_seat": int(st.current_seat),
		"phase": BattlePhase.phase_name(st.phase),
		"round_wind": int(st.round_wind),
		"hand_number": int(st.hand_number),
		"honba": int(st.honba),
		"riichi_sticks": int(st.riichi_sticks),
		"live_wall_count": int(st.wall.live_wall_size()),
		"dora_indicators": dora_out,
		"viewer_next_draw": viewer_next_draw,
		"seats": seats_out,
	}


static func _project_seat(
	st: BattleState,
	seat_i: int,
	recip: int,
	revealed_by_holder: Dictionary
) -> Variant:
	var seat: Seat = st.seats[seat_i] as Seat
	if seat == null or seat.hand == null:
		return null
	var n: int = seat.hand.size()
	var concealed_tiles: Array = []
	var last_drawn: int = -1
	if seat_i == recip:
		for t in seat.hand.tiles():
			var tv: Variant = ProtocolViewCodec.tile_view_from_tile(t)
			if tv == null:
				return null
			concealed_tiles.append(tv)
		var ld: int = int(seat.last_drawn_instance_id)
		if Tile.is_valid_instance_id(ld):
			last_drawn = ld
		else:
			last_drawn = -1
	elif revealed_by_holder.has(seat_i):
		for instance_value in revealed_by_holder[seat_i] as Array:
			var instance := instance_value as TileSkillAnchor
			var tv: Variant = ProtocolViewCodec.tile_view_from_tile(instance.tile)
			if tv == null:
				return null
			concealed_tiles.append(tv)

	var river_out: Array = []
	var river_src: Array = seat.river.tiles()
	for t in river_src:
		var rtv: Variant = ProtocolViewCodec.tile_view_from_tile(t)
		if rtv == null:
			return null
		river_out.append(rtv)

	var melds_out: Array = []
	for m in seat.melds.all():
		if not (m is Meld):
			return null
		var mv: Variant = _meld_view_preserve_order(m as Meld)
		if mv == null:
			return null
		melds_out.append(mv)

	var ri = seat.riichi
	var declared: bool = ri.declared if ri else false
	var dbl: bool = ri.double_riichi if ri else false
	var ridx: int = seat.river.riichi_discard_index()
	if not declared:
		ridx = -1

	var score: int = 25000
	if seat_i < st.scores.size():
		score = int(st.scores[seat_i])

	return {
		"seat": seat_i,
		"seat_wind": int(seat.seat_wind),
		"score": score,
		"concealed_tiles": concealed_tiles,
		"concealed_count": n,
		"last_drawn_tile_instance_id": last_drawn,
		"river": river_out,
		"melds": melds_out,
		"riichi_declared": declared,
		"riichi_double": dbl,
		"riichi_discard_index": ridx,
	}


## 领域 meld.tiles 保序（禁止按 iid 重排）
static func _meld_view_preserve_order(m: Meld) -> Variant:
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
		var tv: Variant = ProtocolViewCodec.tile_view_from_tile(t)
		if tv == null:
			return null
		tiles_raw.append(tv)
	return ProtocolViewCodec.meld_view_from_dict({
		"meld_id": int(m.meld_id),
		"kind": kind_str,
		"from_seat": int(m.from_seat),
		"called_tile_instance_id": int(m.called_tile_instance_id),
		"added_tile_instance_id": int(m.added_tile_instance_id),
		"tiles": tiles_raw,
	})
