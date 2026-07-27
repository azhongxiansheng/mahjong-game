class_name RecipientViewProjector
extends RefCounted

const ViewerRevealResolver := preload("res://battle/viewer_reveal_resolver.gd")
const SeatDrawForecastCoordinator := preload(
	"res://battle/seat_draw_forecast_coordinator.gd")

# E2-02 / #232：按 recipient 生成严格 core_table 投影。
# 本人可见完整 concealed TileView；他席默认仅 concealed_count，信息能力可附带
# 只对该 recipient 授权且仍在目标手牌中的可见子集。
# 不泄露牌墙内容、他手、裏 dora、决策窗、RNG 或 AuthorityReplaySnapshot。

const CORE_KEYS := [
	"recipient_seat", "hand_seq", "dealer_seat", "current_seat", "phase",
	"round_wind", "hand_number", "honba", "riichi_sticks", "live_wall_count",
	"dora_indicators", "seats",
]
const SEAT_KEYS := [
	"seat", "seat_wind", "score", "concealed_tiles", "concealed_count",
	"last_drawn_tile_instance_id", "river", "melds",
	"riichi_declared", "riichi_double", "riichi_discard_index",
]


## static project_core_table(state, recipient_seat) → stable core_table@1 exact-12 或 null
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
		"seats": seats_out,
	}


## #344：独立 viewer_next_draw@1 payload 的 tile 字段；不改变 core_table@1。
static func project_viewer_next_draw(state: Variant, recipient_seat: Variant) -> Variant:
	if not (state is BattleState) or typeof(recipient_seat) != TYPE_INT:
		return null
	var st := state as BattleState
	var recip := int(recipient_seat)
	var predicted := ViewerRevealResolver.next_draw_for_viewer(st, recip)
	if predicted == null:
		return null
	return ProtocolViewCodec.tile_view_from_tile(predicted.tile)


## Issue #345：独立 viewer_wall_top@1 的有序 TileView 数组。
static func project_viewer_wall_top(state: Variant, recipient_seat: Variant) -> Array:
	var out: Array = []
	if not (state is BattleState) or typeof(recipient_seat) != TYPE_INT:
		return out
	var instances: Array = ViewerRevealResolver.wall_top_for_viewer(
		state as BattleState, int(recipient_seat), 3)
	for instance_value in instances:
		var instance := instance_value as TileSkillAnchor
		var tile_view: Variant = ProtocolViewCodec.tile_view_from_tile(instance.tile)
		if tile_view == null:
			return []
		out.append(tile_view)
	return out


static func project_viewer_seat_draw_forecast(
	state: Variant, recipient_seat: Variant
) -> Variant:
	if not (state is BattleState) or typeof(recipient_seat) != TYPE_INT:
		return null
	var rows := SeatDrawForecastCoordinator.predictions_for_viewer(
		state as BattleState, int(recipient_seat))
	if rows.is_empty():
		return null
	var out: Array = []
	for value in rows:
		var row := value as Dictionary
		var anchor := row.get("tile", null) as TileSkillAnchor
		if anchor == null or anchor.tile == null:
			return null
		var tile_view: Variant = ProtocolViewCodec.tile_view_from_tile(anchor.tile)
		if tile_view == null:
			return null
		out.append({
			"target_seat": int(row.get("target_seat", -1)),
			"tile": tile_view,
		})
	return out


## Issue #346：纪枢 recipient 私有等待牌集合；仅牌种，不投影对手暗手实体。
static func project_viewer_tenpai_waits(state: Variant, recipient_seat: Variant) -> Array:
	var out: Array = []
	if not (state is BattleState) or typeof(recipient_seat) != TYPE_INT:
		return out
	var st := state as BattleState
	var recipient := int(recipient_seat)
	if recipient < 0 or recipient > 3:
		return out
	var by_subject_value: Variant = st.tenpai_wait_reveals.get(recipient, null)
	if typeof(by_subject_value) != TYPE_DICTIONARY:
		return out
	var by_subject := by_subject_value as Dictionary
	var subjects: Array = by_subject.keys()
	subjects.sort()
	for subject_value in subjects:
		var subject := int(subject_value)
		var waits: Array = (by_subject.get(subject, []) as Array).duplicate()
		if subject < 0 or subject > 3 or subject == recipient or waits.is_empty():
			return []
		if subject >= st.tenpai_flags.size() or not bool(st.tenpai_flags[subject]):
			return []
		waits.sort()
		out.append({"seat": subject, "wait_tile_ids": waits})
	return out


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
