class_name SnapshotPayloadCodec extends RefCounted

# ARCH-03 #393：房间/对局快照 payload codec —— ROOM_SNAPSHOT（core_table、seat_view、
# viewer optional modules）。校验语义与拆分前 NetworkedEvent 完全一致。

const ROOM_SNAPSHOT_TOP_KEYS := [
	"snapshot_server_seq", "next_server_seq", "seat_view", "modules",
]

const MODULE_ENTRY_KEYS := ["module_key", "schema_version", "payload"]

const CORE_TABLE_KEYS := [
	"recipient_seat", "hand_seq", "dealer_seat", "current_seat", "phase",
	"round_wind", "hand_number", "honba", "riichi_sticks", "live_wall_count",
	"dora_indicators", "seats",
]

const VIEWER_NEXT_DRAW_KEYS := ["recipient_seat", "hand_seq", "tile"]

const VIEWER_TENPAI_WAITS_KEYS := ["recipient_seat", "hand_seq", "subjects"]

const VIEWER_TENPAI_SUBJECT_KEYS := ["seat", "wait_tile_ids"]

const VIEWER_WALL_TOP_KEYS := ["recipient_seat", "hand_seq", "tiles"]

const VIEWER_WALL_TOP_ENTRY_KEYS := ["offset", "tile"]

const VIEWER_SEAT_DRAW_FORECAST_KEYS := ["recipient_seat", "hand_seq", "predictions"]

const VIEWER_SEAT_DRAW_FORECAST_ROW_KEYS := ["target_seat", "tile"]

const SEAT_VIEW_KEYS := [
	"seat", "seat_wind", "score", "concealed_tiles", "concealed_count",
	"last_drawn_tile_instance_id", "river", "melds", "riichi_declared",
	"riichi_double", "riichi_discard_index",
]

const LIVE_WALL_COUNT_MAX := 70

const DORA_INDICATORS_MIN := 1

const DORA_INDICATORS_MAX := 5

const CONCEALED_COUNT_MAX := 14

const RIVER_SIZE_MAX := 70

const MELDS_SIZE_MAX := 4

const SNAPSHOT_PHASES := ["DRAW", "DISCARD", "CLAIM", "SETTLE"]

const SEAT_WINDS := [TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N]

const ROUND_WINDS := [TileId.E, TileId.S_WIND]


static func validate_room_snapshot(p: Dictionary) -> Variant:
	if not EventPayloadCodecUtil._has_exact_keys(p, ROOM_SNAPSHOT_TOP_KEYS):
		return null

	var snap: Variant = EventPayloadCodecUtil._require_nonneg_safe_int(p["snapshot_server_seq"])
	if snap == null:
		return null
	var snap_i: int = snap
	if snap_i < 1:
		return null

	var next: Variant = EventPayloadCodecUtil._require_nonneg_safe_int(p["next_server_seq"])
	if next == null:
		return null
	var next_i: int = next
	if next_i != snap_i + 1:
		return null

	var seat_view: Variant = EventPayloadCodecUtil._require_seat(p["seat_view"])
	if seat_view == null:
		return null
	var seat_view_i: int = seat_view

	if typeof(p["modules"]) != TYPE_ARRAY:
		return null
	var raw_mods: Array = p["modules"]
	if raw_mods.is_empty():
		return null

	var modules_out: Array = []
	var seen_keys: Dictionary = {}
	var prev_key: String = ""
	var has_prev := false
	var core_count := 0
	var core_hand_seq := -1

	for item in raw_mods:
		if typeof(item) != TYPE_DICTIONARY:
			return null
		var md: Dictionary = item
		if not EventPayloadCodecUtil._has_exact_keys(md, MODULE_ENTRY_KEYS):
			return null

		if typeof(md["module_key"]) != TYPE_STRING:
			return null
		var mkey: String = md["module_key"]
		if mkey.is_empty() or mkey != mkey.strip_edges():
			return null
		if seen_keys.has(mkey):
			return null
		seen_keys[mkey] = true
		# 输入必须已按 module_key String 升序；禁止静默排序
		if has_prev and not (mkey > prev_key):
			return null
		has_prev = true
		prev_key = mkey

		if typeof(md["schema_version"]) != TYPE_INT:
			return null
		var sver: int = md["schema_version"]
		if sver < 1 or sver > ProtocolConstants.MAX_SAFE_INT:
			return null

		var pl_raw: Variant = md["payload"]
		var pl_out: Variant = null
		if mkey == "core_table":
			if sver != 1:
				return null
			core_count += 1
			if typeof(pl_raw) != TYPE_DICTIONARY:
				return null
			pl_out = _validate_core_table(pl_raw as Dictionary, seat_view_i)
			if pl_out == null:
				return null
			core_hand_seq = int((pl_out as Dictionary)["hand_seq"])
		elif mkey == "viewer_next_draw" and sver == 1:
			if typeof(pl_raw) != TYPE_DICTIONARY:
				return null
			pl_out = _validate_viewer_next_draw(
				pl_raw as Dictionary, seat_view_i, core_hand_seq)
			if pl_out == null:
				return null
		elif mkey == "viewer_wall_top" and sver == 1:
			if typeof(pl_raw) != TYPE_DICTIONARY:
				return null
			pl_out = _validate_viewer_wall_top(
				pl_raw as Dictionary, seat_view_i, core_hand_seq)
			if pl_out == null:
				return null
		elif mkey == "viewer_seat_draw_forecast" and sver == 1:
			if typeof(pl_raw) != TYPE_DICTIONARY:
				return null
			pl_out = _validate_viewer_seat_draw_forecast(
				pl_raw as Dictionary, seat_view_i, core_hand_seq)
			if pl_out == null:
				return null
		elif mkey == "viewer_tenpai_waits" and sver == 1:
			if typeof(pl_raw) != TYPE_DICTIONARY:
				return null
			pl_out = _validate_viewer_tenpai_waits(
				pl_raw as Dictionary, seat_view_i, core_hand_seq)
			if pl_out == null:
				return null
		else:
			# unknown module：JSON-safe domain + deep copy；保序
			if ProtocolViewCodec.compute_view_hash(pl_raw).is_empty():
				return null
			pl_out = EventPayloadCodecUtil._deep_copy_json_safe(pl_raw)
			if typeof(pl_raw) != TYPE_NIL and pl_out == null:
				return null

		modules_out.append({
			"module_key": mkey,
			"schema_version": sver,
			"payload": pl_out,
		})

	if core_count != 1:
		return null

	return {
		"snapshot_server_seq": snap_i,
		"next_server_seq": next_i,
		"seat_view": seat_view_i,
		"modules": modules_out,
	}


static func _validate_core_table(p: Dictionary, seat_view: int) -> Variant:
	if not EventPayloadCodecUtil._has_exact_keys(p, CORE_TABLE_KEYS):
		return null

	var recipient: Variant = EventPayloadCodecUtil._require_seat(p["recipient_seat"])
	if recipient == null:
		return null
	var recipient_i: int = recipient
	if recipient_i != seat_view:
		return null

	if typeof(p["hand_seq"]) != TYPE_INT:
		return null
	var hs: int = p["hand_seq"]
	if hs < 0 or hs > ProtocolConstants.MAX_HAND_SEQ:
		return null

	var dealer: Variant = EventPayloadCodecUtil._require_seat(p["dealer_seat"])
	if dealer == null:
		return null
	var current: Variant = EventPayloadCodecUtil._require_seat(p["current_seat"])
	if current == null:
		return null

	if typeof(p["phase"]) != TYPE_STRING:
		return null
	var phase: String = p["phase"]
	if phase not in SNAPSHOT_PHASES:
		return null

	if typeof(p["round_wind"]) != TYPE_INT:
		return null
	var rw: int = p["round_wind"]
	if rw not in ROUND_WINDS:
		return null

	if typeof(p["hand_number"]) != TYPE_INT:
		return null
	var hn: int = p["hand_number"]
	if hn < 1 or hn > 4:
		return null

	var honba: Variant = EventPayloadCodecUtil._require_nonneg_safe_int(p["honba"])
	if honba == null:
		return null
	var sticks: Variant = EventPayloadCodecUtil._require_nonneg_safe_int(p["riichi_sticks"])
	if sticks == null:
		return null
	var live: Variant = EventPayloadCodecUtil._require_nonneg_safe_int(p["live_wall_count"])
	if live == null:
		return null
	if int(live) > LIVE_WALL_COUNT_MAX:
		return null

	if typeof(p["dora_indicators"]) != TYPE_ARRAY:
		return null
	var dora_size: int = (p["dora_indicators"] as Array).size()
	if dora_size < DORA_INDICATORS_MIN or dora_size > DORA_INDICATORS_MAX:
		return null
	var dora_out: Array = []
	for item in p["dora_indicators"]:
		var tv: Variant = ProtocolViewCodec.tile_view_from_dict(item)
		if tv == null:
			return null
		dora_out.append(tv)

	if typeof(p["seats"]) != TYPE_ARRAY:
		return null
	var seats_raw: Array = p["seats"]
	if seats_raw.size() != 4:
		return null
	var seats_out: Array = []
	var wind_seen: Dictionary = {}
	var global_meld_ids: Dictionary = {}
	for i in range(4):
		if typeof(seats_raw[i]) != TYPE_DICTIONARY:
			return null
		var sv: Variant = _validate_seat_view(
			seats_raw[i] as Dictionary, i, recipient_i, hs
		)
		if sv == null:
			return null
		var svd: Dictionary = sv
		var wind: int = svd["seat_wind"]
		if wind_seen.has(wind):
			return null
		wind_seen[wind] = true
		# meld_id 四席全局唯一（仅同席唯一不够）
		for mv0 in svd["melds"]:
			var mid0: int = int((mv0 as Dictionary)["meld_id"])
			if global_meld_ids.has(mid0):
				return null
			global_meld_ids[mid0] = true
		seats_out.append(svd)

	# 可见物理实体：dora + recipient 手牌 + 四席河 + 副露 tiles；全局唯一 + namespace
	# last_drawn / called / added 仅为引用，不重复计入
	var visible_ids: Dictionary = {}
	for dora_tv in dora_out:
		var did: int = int((dora_tv as Dictionary)["instance_id"])
		if not EventPayloadCodecUtil._collect_visible_tile_id(visible_ids, did, hs):
			return null
	for svd2 in seats_out:
		var seat_d: Dictionary = svd2
		for ct in seat_d["concealed_tiles"]:
			var cid: int = int((ct as Dictionary)["instance_id"])
			if not EventPayloadCodecUtil._collect_visible_tile_id(visible_ids, cid, hs):
				return null
		for rv in seat_d["river"]:
			var rid: int = int((rv as Dictionary)["instance_id"])
			if not EventPayloadCodecUtil._collect_visible_tile_id(visible_ids, rid, hs):
				return null
		for mv in seat_d["melds"]:
			var meld_d: Dictionary = mv
			for mt in meld_d["tiles"]:
				var mid: int = int((mt as Dictionary)["instance_id"])
				if not EventPayloadCodecUtil._collect_visible_tile_id(visible_ids, mid, hs):
					return null

	return {
		"recipient_seat": recipient_i,
		"hand_seq": hs,
		"dealer_seat": int(dealer),
		"current_seat": int(current),
		"phase": phase,
		"round_wind": rw,
		"hand_number": hn,
		"honba": int(honba),
		"riichi_sticks": int(sticks),
		"live_wall_count": int(live),
		"dora_indicators": dora_out,
		"seats": seats_out,
	}


static func _validate_viewer_next_draw(
	p: Dictionary, seat_view: int, core_hand_seq: int
) -> Variant:
	if not EventPayloadCodecUtil._has_exact_keys(p, VIEWER_NEXT_DRAW_KEYS):
		return null
	var recipient: Variant = EventPayloadCodecUtil._require_seat(p["recipient_seat"])
	if recipient == null or int(recipient) != seat_view:
		return null
	if typeof(p["hand_seq"]) != TYPE_INT:
		return null
	var hand_seq := int(p["hand_seq"])
	if hand_seq < 0 or hand_seq != core_hand_seq:
		return null
	var tile: Variant = ProtocolViewCodec.tile_view_from_dict(p["tile"])
	if tile == null:
		return null
	if not EventPayloadCodecUtil._is_instance_id_in_hand_namespace(int((tile as Dictionary)["instance_id"]), hand_seq):
		return null
	return {
		"recipient_seat": int(recipient),
		"hand_seq": hand_seq,
		"tile": tile,
	}


static func _validate_viewer_wall_top(
	p: Dictionary, seat_view: int, core_hand_seq: int
) -> Variant:
	if not EventPayloadCodecUtil._has_exact_keys(p, VIEWER_WALL_TOP_KEYS):
		return null
	var recipient: Variant = EventPayloadCodecUtil._require_seat(p["recipient_seat"])
	if recipient == null or int(recipient) != seat_view \
			or typeof(p["hand_seq"]) != TYPE_INT:
		return null
	var hand_seq := int(p["hand_seq"])
	if hand_seq < 0 or hand_seq != core_hand_seq or typeof(p["tiles"]) != TYPE_ARRAY:
		return null
	var raw_tiles := p["tiles"] as Array
	if raw_tiles.is_empty() or raw_tiles.size() > 3:
		return null
	var tiles_out: Array = []
	var seen: Dictionary = {}
	for index in range(raw_tiles.size()):
		if typeof(raw_tiles[index]) != TYPE_DICTIONARY:
			return null
		var entry := raw_tiles[index] as Dictionary
		if not EventPayloadCodecUtil._has_exact_keys(entry, VIEWER_WALL_TOP_ENTRY_KEYS) \
				or typeof(entry["offset"]) != TYPE_INT or int(entry["offset"]) != index:
			return null
		var tile: Variant = ProtocolViewCodec.tile_view_from_dict(entry["tile"])
		if tile == null:
			return null
		var iid := int((tile as Dictionary)["instance_id"])
		if seen.has(iid) or not EventPayloadCodecUtil._is_instance_id_in_hand_namespace(iid, hand_seq):
			return null
		seen[iid] = true
		tiles_out.append({"offset": index, "tile": tile})
	return {
		"recipient_seat": int(recipient),
		"hand_seq": hand_seq,
		"tiles": tiles_out,
	}


static func _validate_viewer_seat_draw_forecast(
	p: Dictionary, seat_view: int, core_hand_seq: int
) -> Variant:
	if not EventPayloadCodecUtil._has_exact_keys(p, VIEWER_SEAT_DRAW_FORECAST_KEYS):
		return null
	var recipient: Variant = EventPayloadCodecUtil._require_seat(p["recipient_seat"])
	if recipient == null or int(recipient) != seat_view:
		return null
	if typeof(p["hand_seq"]) != TYPE_INT:
		return null
	var hand_seq := int(p["hand_seq"])
	if hand_seq < 0 or hand_seq != core_hand_seq or typeof(p["predictions"]) != TYPE_ARRAY:
		return null
	var rows := p["predictions"] as Array
	if rows.is_empty() or rows.size() > 4:
		return null
	var targets: Dictionary = {}
	var instances: Dictionary = {}
	var out: Array = []
	for value in rows:
		if typeof(value) != TYPE_DICTIONARY:
			return null
		var row := value as Dictionary
		if not EventPayloadCodecUtil._has_exact_keys(row, VIEWER_SEAT_DRAW_FORECAST_ROW_KEYS):
			return null
		var target: Variant = EventPayloadCodecUtil._require_seat(row["target_seat"])
		if target == null or targets.has(int(target)):
			return null
		var tile: Variant = ProtocolViewCodec.tile_view_from_dict(row["tile"])
		if tile == null:
			return null
		var iid := int((tile as Dictionary)["instance_id"])
		if instances.has(iid) or not EventPayloadCodecUtil._is_instance_id_in_hand_namespace(iid, hand_seq):
			return null
		targets[int(target)] = true
		instances[iid] = true
		out.append({"target_seat": int(target), "tile": tile})
	return {
		"recipient_seat": int(recipient),
		"hand_seq": hand_seq,
		"predictions": out,
	}


static func _validate_viewer_tenpai_waits(
	p: Dictionary, seat_view: int, core_hand_seq: int
) -> Variant:
	if not EventPayloadCodecUtil._has_exact_keys(p, VIEWER_TENPAI_WAITS_KEYS):
		return null
	var recipient: Variant = EventPayloadCodecUtil._require_seat(p["recipient_seat"])
	if recipient == null or int(recipient) != seat_view \
			or typeof(p["hand_seq"]) != TYPE_INT \
			or int(p["hand_seq"]) != core_hand_seq \
			or typeof(p["subjects"]) != TYPE_ARRAY:
		return null
	var subjects := p["subjects"] as Array
	if subjects.is_empty() or subjects.size() > 3:
		return null
	var out: Array = []
	var previous_seat := -1
	for subject_value in subjects:
		if typeof(subject_value) != TYPE_DICTIONARY:
			return null
		var subject := subject_value as Dictionary
		if not EventPayloadCodecUtil._has_exact_keys(subject, VIEWER_TENPAI_SUBJECT_KEYS) \
				or typeof(subject["seat"]) != TYPE_INT \
				or typeof(subject["wait_tile_ids"]) != TYPE_ARRAY:
			return null
		var subject_seat := int(subject["seat"])
		if subject_seat <= previous_seat or subject_seat < 0 or subject_seat > 3 \
				or subject_seat == seat_view:
			return null
		previous_seat = subject_seat
		var waits := subject["wait_tile_ids"] as Array
		if waits.is_empty() or waits.size() > TileId.ALL.size():
			return null
		var waits_out: Array = []
		var previous_tile := -1
		for tile_id in waits:
			if typeof(tile_id) != TYPE_INT or not TileId.ALL.has(tile_id) \
					or int(tile_id) <= previous_tile:
				return null
			previous_tile = int(tile_id)
			waits_out.append(int(tile_id))
		out.append({"seat": subject_seat, "wait_tile_ids": waits_out})
	return {
		"recipient_seat": int(recipient),
		"hand_seq": int(p["hand_seq"]),
		"subjects": out,
	}


static func _validate_seat_view(
	p: Dictionary,
	expect_seat: int,
	recipient: int,
	hand_seq: int
) -> Variant:
	if not EventPayloadCodecUtil._has_exact_keys(p, SEAT_VIEW_KEYS):
		return null

	var seat: Variant = EventPayloadCodecUtil._require_seat(p["seat"])
	if seat == null:
		return null
	var seat_i: int = seat
	if seat_i != expect_seat:
		return null

	if typeof(p["seat_wind"]) != TYPE_INT:
		return null
	var wind: int = p["seat_wind"]
	if wind not in SEAT_WINDS:
		return null

	var score: Variant = EventPayloadCodecUtil._require_safe_int(p["score"])
	if score == null:
		return null

	if typeof(p["concealed_tiles"]) != TYPE_ARRAY:
		return null
	var ct_out: Array = []
	var ct_ids: Dictionary = {}
	for item in p["concealed_tiles"]:
		var tv: Variant = ProtocolViewCodec.tile_view_from_dict(item)
		if tv == null:
			return null
		var td: Dictionary = tv
		var iid: int = td["instance_id"]
		if not EventPayloadCodecUtil._is_instance_id_in_hand_namespace(iid, hand_seq):
			return null
		if ct_ids.has(iid):
			return null
		ct_ids[iid] = true
		ct_out.append(td)

	var ccount: Variant = EventPayloadCodecUtil._require_nonneg_safe_int(p["concealed_count"])
	if ccount == null:
		return null
	var ccount_i: int = ccount
	if ccount_i > CONCEALED_COUNT_MAX:
		return null

	if typeof(p["last_drawn_tile_instance_id"]) != TYPE_INT:
		return null
	var last_drawn: int = p["last_drawn_tile_instance_id"]
	if last_drawn < -1 or last_drawn > ProtocolConstants.MAX_SAFE_INT:
		return null

	if seat_i == recipient:
		if ct_out.size() != ccount_i:
			return null
		# last_drawn 是 concealed 内引用，不重复计数
		if last_drawn >= 0 and not ct_ids.has(last_drawn):
			return null
	else:
		# 信息能力允许服务端向 recipient 投影对手手牌的可见子集；权限由
		# RecipientViewProjector 决定。wire 层只接受不超过真实手牌张数的子集。
		if ct_out.size() > ccount_i:
			return null
		if last_drawn != -1:
			return null

	if typeof(p["river"]) != TYPE_ARRAY:
		return null
	if (p["river"] as Array).size() > RIVER_SIZE_MAX:
		return null
	var river_out: Array = []
	for item in p["river"]:
		var rtv: Variant = ProtocolViewCodec.tile_view_from_dict(item)
		if rtv == null:
			return null
		var rtd: Dictionary = rtv
		if not EventPayloadCodecUtil._is_instance_id_in_hand_namespace(int(rtd["instance_id"]), hand_seq):
			return null
		river_out.append(rtd)

	if typeof(p["melds"]) != TYPE_ARRAY:
		return null
	if (p["melds"] as Array).size() > MELDS_SIZE_MAX:
		return null
	var melds_out: Array = []
	var meld_ids_seen: Dictionary = {}
	for item in p["melds"]:
		var mv: Variant = ProtocolViewCodec.meld_view_from_dict(item)
		if mv == null:
			return null
		var md: Dictionary = mv
		# 同席 meld_id 唯一（全局唯一在 core_table 再检）
		var meld_id: int = int(md["meld_id"])
		if meld_ids_seen.has(meld_id):
			return null
		meld_ids_seen[meld_id] = true
		# from_seat 相对持有席：ANKAN=-1；CHI/PON/MINKAN/ADDED_KAN 不得等于 holder
		# CHI 必须来自上家 (holder+3)%4
		if not EventPayloadCodecUtil._meld_from_seat_rules(md, seat_i):
			return null
		# tiles 全量 namespace；called/added 仅为 tiles 内引用
		if not EventPayloadCodecUtil._meld_tiles_in_hand_namespace(md, hand_seq):
			return null
		melds_out.append(md)

	if typeof(p["riichi_declared"]) != TYPE_BOOL:
		return null
	var declared: bool = p["riichi_declared"]
	if typeof(p["riichi_double"]) != TYPE_BOOL:
		return null
	var double_r: bool = p["riichi_double"]
	if double_r and not declared:
		return null

	if typeof(p["riichi_discard_index"]) != TYPE_INT:
		return null
	var ridx: int = p["riichi_discard_index"]
	if not declared:
		if ridx != -1:
			return null
	else:
		# 宣言牌被鸣走时允许 -1；>=0 须落在河内
		if ridx == -1:
			pass
		elif ridx < 0 or ridx >= river_out.size():
			return null

	return {
		"seat": seat_i,
		"seat_wind": wind,
		"score": int(score),
		"concealed_tiles": ct_out,
		"concealed_count": ccount_i,
		"last_drawn_tile_instance_id": last_drawn,
		"river": river_out,
		"melds": melds_out,
		"riichi_declared": declared,
		"riichi_double": double_r,
		"riichi_discard_index": ridx,
	}
