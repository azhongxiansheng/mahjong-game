extends RefCounted

# #377：公共 committed core_table@1 / matching_meta 只读投影。
# 无 class_name；不重建 BattleState，不跑本地权威。

const MELD_KIND_MAP := {
	"CHI": Meld.Kind.CHI,
	"PON": Meld.Kind.PON,
	"MINKAN": Meld.Kind.MINKAN,
	"ANKAN": Meld.Kind.ANKAN,
	"ADDED_KAN": Meld.Kind.ADDED_KAN,
}


static func relative_seat(absolute_seat: int, recipient_seat: int) -> int:
	return (absolute_seat - recipient_seat + 4) % 4


static func absolute_seat(relative_slot: int, recipient_seat: int) -> int:
	return (relative_slot + recipient_seat) % 4


static func tile_from_view(tv: Variant) -> Tile:
	if typeof(tv) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = tv
	var t := Tile.new(
		int(d.get("tile_id", -1)),
		bool(d.get("is_red_dora", false)),
		int(d.get("owner_seat", Tile.NO_OWNER)),
		int(d.get("instance_id", Tile.INVALID_INSTANCE_ID))
	)
	if not t.is_valid():
		return null
	return t


static func tiles_from_views(views: Array) -> Array:
	var out: Array = []
	for v in views:
		var t := tile_from_view(v)
		if t != null:
			out.append(t)
	return out


static func meld_from_view(mv: Variant) -> Meld:
	if typeof(mv) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = mv
	var kind_s := str(d.get("kind", ""))
	if not MELD_KIND_MAP.has(kind_s):
		return null
	var kind: Meld.Kind = MELD_KIND_MAP[kind_s]
	var tile_arr: Array[Tile] = []
	for tv in d.get("tiles", []):
		var t := tile_from_view(tv)
		if t == null:
			return null
		tile_arr.append(t)
	var from_seat: int = int(d.get("from_seat", Meld.NO_SOURCE_SEAT))
	var meld_id: int = int(d.get("meld_id", Tile.INVALID_INSTANCE_ID))
	var called_iid: int = int(d.get("called_tile_instance_id", Tile.INVALID_INSTANCE_ID))
	var called: Tile = null
	if Tile.is_valid_instance_id(called_iid):
		for t in tile_arr:
			if t.instance_id == called_iid:
				called = t
				break
	var meld := Meld.new(kind, tile_arr, from_seat, meld_id, called)
	var added_iid: int = int(d.get("added_tile_instance_id", Tile.INVALID_INSTANCE_ID))
	if kind == Meld.Kind.ADDED_KAN and Tile.is_valid_instance_id(added_iid):
		# 展示用：若已是 ADDED_KAN wire，直接写私有字段不走 promote 校验
		meld.set("_added_tile_instance_id", added_iid)
	return meld


static func melds_from_views(views: Array) -> Array:
	var out: Array = []
	for v in views:
		var m := meld_from_view(v)
		if m != null:
			out.append(m)
	return out


## 将 committed core_table@1 转为牌实体 renderer 可直接消费的只读视图。
##
## renderer 坐标固定为 screen_seat（0=本席下方）；副露的 from_seat 仍是权威绝对席，
## 因此同时保留 absolute_seat/layout_claimant_absolute，禁止混用两个坐标系。
## concealed_tiles 已由上游按 recipient 裁剪：保留授权子集，但绝不超过 concealed_count；
## 无授权数据的他席仍只投影数量，不凭空创建 Tile/实例身份。
static func renderer_view(core: Dictionary) -> Dictionary:
	var recipient_value: Variant = core.get("recipient_seat", null)
	if typeof(recipient_value) != TYPE_INT:
		return {}
	var recipient: int = int(recipient_value)
	if not _is_valid_seat(recipient):
		return {}

	var current_absolute: int = _seat_field_or_invalid(core, "current_seat")
	var dealer_absolute: int = _seat_field_or_invalid(core, "dealer_seat")
	var current_screen: int = relative_seat(current_absolute, recipient) \
		if _is_valid_seat(current_absolute) else -1
	var dealer_screen: int = relative_seat(dealer_absolute, recipient) \
		if _is_valid_seat(dealer_absolute) else -1

	var indicator_views: Array = _array_field(core, "dora_indicators")
	var indicators: Array = tiles_from_views(indicator_views)
	var dora_ids: Array = []
	for indicator in indicators:
		if indicator is Tile:
			dora_ids.append(DoraIndicator.dora_from_indicator((indicator as Tile).id))

	var projected_seats: Array = []
	for screen_seat in range(4):
		var absolute: int = absolute_seat(screen_seat, recipient)
		var source: Dictionary = _seat_view(core, absolute)
		var concealed_count: int = clampi(
			int(source.get("concealed_count", 0)), 0, 14)
		var concealed: Array = tiles_from_views(
			_array_field(source, "concealed_tiles"))
		# 即使绕过 wire validator 调用，也不投影超过声明暗手数量的身份。
		if concealed.size() > concealed_count:
			concealed = concealed.slice(0, concealed_count)
		var last_drawn: int = Tile.INVALID_INSTANCE_ID
		var has_drawn: bool = concealed_count % 3 == 2
		if screen_seat == 0:
			var candidate: int = int(source.get(
				"last_drawn_tile_instance_id", Tile.INVALID_INSTANCE_ID))
			if _tiles_contain_instance_id(concealed, candidate):
				last_drawn = candidate
			has_drawn = Tile.is_valid_instance_id(last_drawn)

		projected_seats.append({
			# seat 保持 BattleState-like 的 renderer 屏幕槽语义；绝对席另列。
			"seat": screen_seat,
			"screen_seat": screen_seat,
			"absolute_seat": absolute,
			"layout_claimant_absolute": absolute,
			"seat_wind": int(source.get("seat_wind", -1)),
			"score": int(source.get("score", 0)),
			"concealed_tiles": concealed,
			"concealed_count": concealed_count,
			"last_drawn_tile_instance_id": last_drawn,
			"has_drawn": has_drawn,
			"river": tiles_from_views(_array_field(source, "river")),
			"melds": melds_from_views(_array_field(source, "melds")),
			"riichi_declared": bool(source.get("riichi_declared", false)),
			"riichi_double": bool(source.get("riichi_double", false)),
			"riichi_discard_index": int(source.get("riichi_discard_index", -1)),
			"is_current": absolute == current_absolute,
			"is_dealer": absolute == dealer_absolute,
		})

	return {
		"recipient_seat": recipient,
		"hand_seq": int(core.get("hand_seq", 0)),
		"phase": str(core.get("phase", "")),
		"round_wind": int(core.get("round_wind", TileId.E)),
		"hand_number": int(core.get("hand_number", 1)),
		"honba": int(core.get("honba", 0)),
		"riichi_sticks": int(core.get("riichi_sticks", 0)),
		"live_wall_count": int(core.get("live_wall_count", 0)),
		# current_seat/dealer_seat 是 renderer 屏幕槽；绝对席使用显式后缀。
		"current_seat": current_screen,
		"dealer_seat": dealer_screen,
		"current_screen_seat": current_screen,
		"dealer_screen_seat": dealer_screen,
		"current_absolute_seat": current_absolute,
		"dealer_absolute_seat": dealer_absolute,
		"dora_indicators": indicators,
		"dora_ids": dora_ids,
		"seats": projected_seats,
	}


static func _is_valid_seat(seat: int) -> bool:
	return seat >= 0 and seat < 4


static func _seat_field_or_invalid(source: Dictionary, key: String) -> int:
	var value: Variant = source.get(key, null)
	if typeof(value) != TYPE_INT:
		return -1
	var seat: int = int(value)
	return seat if _is_valid_seat(seat) else -1


static func _array_field(source: Dictionary, key: String) -> Array:
	var value: Variant = source.get(key, [])
	return value as Array if typeof(value) == TYPE_ARRAY else []


static func _tiles_contain_instance_id(tiles: Array, instance_id: int) -> bool:
	if not Tile.is_valid_instance_id(instance_id):
		return false
	for tile in tiles:
		if tile is Tile and (tile as Tile).instance_id == instance_id:
			return true
	return false


## 将 core_table@1 投影到 FourPlayerTable（屏幕槽 0=本席下方）。
static func apply_core_table(table: FourPlayerTable, core: Dictionary) -> void:
	if table == null or core.is_empty():
		return
	var recip: int = int(core.get("recipient_seat", 0))
	if recip < 0 or recip > 3:
		return
	table.set_meta("public_recipient_seat", recip)
	table.set_local_seat(recip)

	var dora_ids: Array = []
	var dora_indicator_ids: Array = []
	for ind in core.get("dora_indicators", []):
		var t := tile_from_view(ind)
		if t != null:
			dora_ids.append(DoraIndicator.dora_from_indicator(t.id))
			dora_indicator_ids.append(t.id)

	var dealer_abs: int = int(core.get("dealer_seat", 0))
	var phase_s := str(core.get("phase", ""))
	if table.center_info != null:
		var ci = table.center_info
		# round_wind + hand_number → 东/南 N 局（hand_number 1-based）
		var hand_idx := hand_index_from_round(
			int(core.get("round_wind", TileId.E)),
			int(core.get("hand_number", 1))
		)
		if ci.has_method("set_hands_per_round"):
			ci.set_hands_per_round(4)
		ci.set_hand_index(hand_idx)
		ci.set_honba(int(core.get("honba", 0)))
		ci.set_riichi_sticks(int(core.get("riichi_sticks", 0)))
		ci.set_wall_remaining(int(core.get("live_wall_count", 0)))
		ci.set_dora_indicators(dora_indicator_ids)
		var cur_abs: int = int(core.get("current_seat", 0))
		var turn_name := "你" if cur_abs == recip else _public_name_for_absolute(table, cur_abs)
		if not phase_s.is_empty():
			turn_name = "%s · %s" % [turn_name, phase_s]
		if ci.has_method("set_turn_name"):
			ci.set_turn_name(turn_name)
		if ci.has_method("set_public_phase"):
			ci.set_public_phase(phase_s)
		var summary: Array = []
		for rel in range(4):
			var abs_s := absolute_seat(rel, recip)
			var sv := _seat_view(core, abs_s)
			summary.append({
				"wind": int(sv.get("seat_wind", -1)),
				"score": int(sv.get("score", 0)),
				"riichi": bool(sv.get("riichi_declared", false)),
				"active": abs_s == cur_abs,
				"dealer": abs_s == dealer_abs,
			})
		ci.set_seats_summary(summary)

	var seats_arr: Array = core.get("seats", [])
	for abs_s in range(4):
		var rel := relative_seat(abs_s, recip)
		var sv2 := _seat_view(core, abs_s)
		if rel < 0 or rel >= table.seat_panels.size():
			continue
		var sp: SeatPanel = table.seat_panels[rel]
		sp.set_dora_ids(dora_ids)
		if sp.has_method("bind_seat_view"):
			sp.bind_seat_view(sv2, rel == 0)
		else:
			sp.set_score(int(sv2.get("score", 0)))
			sp.set_hand_size(int(sv2.get("concealed_count", 0)))
		sp.set_active(abs_s == int(core.get("current_seat", -1)))
		sp.set_riichi(bool(sv2.get("riichi_declared", false)))
		if sp.has_method("set_is_dealer"):
			sp.set_is_dealer(abs_s == dealer_abs)
		sp.set_discards_count((sv2.get("river", []) as Array).size())

		if rel < table.discard_rivers.size():
			var dr = table.discard_rivers[rel]
			var river_tiles := tiles_from_views(sv2.get("river", []) as Array)
			var riichi_idx: int = int(sv2.get("riichi_discard_index", -1))
			dr.set_dora_ids(dora_ids)
			dr.set_tiles(river_tiles, riichi_idx)

		if rel < table.meld_areas.size():
			var ma = table.meld_areas[rel]
			var melds := melds_from_views(sv2.get("melds", []) as Array)
			# 屏幕槽 = rel；MeldLayout 用绝对 claimant 以保持 from_seat 相对源
			if ma.has_method("set_melds"):
				ma.call("set_melds", melds, rel, abs_s)
			var has_meld: bool = not melds.is_empty()
			var meld_main_extent: float = 0.0
			if has_meld and ma.has_method("get_layout_bounds"):
				meld_main_extent = ma.get_layout_bounds().size.x
			sp.apply_reference_hand_layout(meld_main_extent)
			if has_meld and ma.has_method("apply_reference_layout"):
				var hand_metrics: Dictionary = sp.get_reference_hand_metrics()
				ma.apply_reference_layout(
					float(hand_metrics.get("main_extent", 0.0)),
					bool(hand_metrics.get("has_drawn", false)))


static func apply_matching_meta(table: FourPlayerTable, meta: Dictionary, recipient: int) -> void:
	if table == null or meta.is_empty():
		return
	var chars: Variant = meta.get("character_ids", null)
	var parts: Variant = meta.get("participants", null)
	if typeof(chars) != TYPE_ARRAY or (chars as Array).size() != 4:
		return
	var char_arr: Array = chars
	var part_arr: Array = parts if typeof(parts) == TYPE_ARRAY else []
	for abs_s in range(4):
		var rel := relative_seat(abs_s, recipient)
		if rel < 0 or rel >= table.seat_panels.size():
			continue
		var cid := String(char_arr[abs_s])
		var ch: Character = CharacterPool.find(StringName(cid))
		var display := ch.display_name if ch != null else cid
		var style := "HUMAN" if (
			part_arr.size() == 4 and str(part_arr[abs_s]) == "HUMAN"
		) else "AI"
		var portrait := ch.portrait_path if ch != null else ""
		var sp: SeatPanel = table.seat_panels[rel]
		sp.set_ai_persona(display, style, portrait)
		# #377 P2-2：公共投影四席均显示 HUMAN/AI（不改练习场默认标签）
		if sp.has_method("set_public_participant_visible"):
			sp.set_public_participant_visible(true)
	table.set_meta("public_matching_meta", meta.duplicate(true))


## round_wind + hand_number(1-based) → CenterInfoPanel hand_index（东 0–3 / 南 4–7）
static func hand_index_from_round(round_wind: int, hand_number: int) -> int:
	var local: int = maxi(0, hand_number - 1) % 4
	match round_wind:
		TileId.E:
			return local
		TileId.S_WIND:
			return 4 + local
		TileId.W_WIND:
			return 8 + local
		TileId.N:
			return 12 + local
		_:
			return local


static func _seat_view(core: Dictionary, abs_seat: int) -> Dictionary:
	for s in core.get("seats", []):
		if typeof(s) == TYPE_DICTIONARY and int(s.get("seat", -1)) == abs_seat:
			return s
	return {}


static func _public_name_for_absolute(table: FourPlayerTable, abs_seat: int) -> String:
	var meta: Dictionary = table.get_meta("public_matching_meta", {})
	if meta.has("character_ids"):
		var chars: Array = meta["character_ids"]
		if abs_seat >= 0 and abs_seat < chars.size():
			var ch: Character = CharacterPool.find(StringName(str(chars[abs_seat])))
			if ch != null:
				return ch.display_name
	return "席 %d" % abs_seat
