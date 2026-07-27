class_name AuthorityReplaySnapshot
extends RefCounted

const REVEALED_PROJECTION_KIND_KEY := "projection_kind"
const SEAT_DRAW_FORECAST_PROJECTION_KIND := "viewer_seat_draw_forecast@1"

# E2-02 / #232：服务端内部权威恢复结构。
# 完整捕获/恢复公共场继续执行所需状态；typed/严格 canonical + 稳定 SHA-256。
# 绝不进入 NetworkedEvent envelope/payload/modules。
# 不恢复 BattleState.snapshot_dict/snapshot_hash 或旧裸 Dictionary replay API。

var _data: Dictionary = {}


static func capture(bc: Variant) -> AuthorityReplaySnapshot:
	if bc == null or not (bc is Object):
		return null
	var obj: Object = bc as Object
	if obj.get("state") == null:
		return null
	var st: BattleState = obj.get("state") as BattleState
	if st == null:
		return null
	var snap := AuthorityReplaySnapshot.new()
	snap._data = _capture_dict(obj, st)
	return snap


func to_dict() -> Dictionary:
	return _data.duplicate(true)


func sha256() -> String:
	var canon: Variant = _canonical_json(_data)
	if canon == null:
		return ""
	var bytes: PackedByteArray = str(canon).to_utf8_buffer()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


## 仅验证该快照能否完整构造 staging；不触碰任何现存 controller。
## 权威事务在 mutation 前调用，避免进入一个事后无法回滚的状态。
func can_restore() -> bool:
	if _data.is_empty() or _canonical_json(_data) == null:
		return false
	if not _validate_restore_data(_data):
		return false
	var staging: BattleController = _make_staging_controller(_data)
	if staging == null or staging.state == null:
		return false
	return _restore_dict(staging, staging.state, _data)


func restore_into(bc: Variant) -> bool:
	if bc == null or not (bc is Object):
		return false
	if _data.is_empty():
		return false
	# 与 sha256 同一套 _canonical_json：任意嵌套 wire 键冲突/不支持类型 → null → false。
	# 须在触碰 target、构造 staging 之前完成；不另起第二套规范化。
	if _canonical_json(_data) == null:
		return false
	var obj: Object = bc as Object
	var st: BattleState = obj.get("state") as BattleState
	if st == null:
		return false
	# 严格：先纯校验 _data；失败绝不触碰 target
	if not _validate_restore_data(_data):
		return false
	# 原子：staging 完整 restore，成功后一次性 commit；禁止 target 原地 restore/回滚
	var staging: BattleController = _make_staging_controller(_data)
	if staging == null or staging.state == null:
		return false
	# 空 ai 语义：与旧 _restore_dict 一致——保持 target 既有 ai
	var ai_raw = _data.get("ai", {})
	if typeof(ai_raw) != TYPE_DICTIONARY or (ai_raw as Dictionary).is_empty():
		staging.ai = obj.get("ai")
	if not _restore_dict(staging, staging.state, _data):
		return false
	_commit_staged_controller(obj, staging)
	return true


## 纯严格校验：不写任何 controller。失败 → restore_into false。
## 实体完整性（hand_seq namespace / wall canonical / seats 活动区引用）必须在 staging 前拒绝。
static func _validate_restore_data(d: Dictionary) -> bool:
	if not _validate_restore_shape(d):
		return false
	# 1) hand_seq 合法：[0, Wall.MAX_HAND_SEQ]
	var hs: int = d["hand_seq"]
	if hs < 0 or hs > Wall.MAX_HAND_SEQ:
		return false

	var wall_raw = d.get("wall", {})
	var wall_tiles_raw: Array = (wall_raw as Dictionary).get("tiles", []) as Array
	if wall_tiles_raw.size() != 136:
		return false
	# wall 实体 map：iid → Tile；顺序已 shuffle，canonical 只由 serial=iid-hs*136 推导
	var by_iid: Dictionary = {}
	for td in wall_tiles_raw:
		var t: Tile = Tile.from_dict(td)
		if t == null:
			return false
		var iid: int = int(t.instance_id)
		# 本局 namespace：[hs*136, hs*136+135]
		if not Tile.is_instance_id_in_hand_seq(iid, hs):
			return false
		if by_iid.has(iid):
			return false
		if not _validate_wall_tile_canonical(t, hs):
			return false
		by_iid[iid] = t
	# 136 + unique + 全在 namespace → 完整覆盖 [hs*136 .. hs*136+135]
	if by_iid.size() != 136:
		return false
	for key in ["dora", "ura"]:
		for td in d[key] as Array:
			if not _validate_snapshot_tile_ref(td, by_iid):
				return false
	var last_discarded: Dictionary = d["last_discarded"] as Dictionary
	if not last_discarded.is_empty() \
			and not _validate_snapshot_tile_ref(last_discarded, by_iid):
		return false

	# 2) 活动区引用：seats hand/river/meld + revealed 真实 tile + skill tile-anchor
	# 共用 seen_active；校验失败零污染（本函数不写 controller）
	if not _validate_active_tile_refs(d, by_iid):
		return false

	var aj_raw = d.get("action_journal", [])
	for ad in aj_raw as Array:
		if typeof(ad) != TYPE_DICTIONARY:
			return false
		if Action.from_dict(ad) == null:
			return false

	var ej_raw = d.get("event_journal", [])
	for ed in ej_raw as Array:
		if typeof(ed) != TYPE_DICTIONARY:
			return false
		if not _validate_battle_event_shape(ed as Dictionary):
			return false
		if BattleEvent.from_dict(ed as Dictionary) == null:
			return false

	var win_raw = d.get("window", {})
	var win_d: Dictionary = win_raw as Dictionary
	if not win_d.is_empty():
		var restored_window: DecisionWindow = _restore_window(win_d, by_iid)
		if restored_window == null:
			return false
		# responded / allowed_kinds 等派生字段必须与重建结果完全一致，
		# 禁止 restore 成功后 recapture 静默归一化并改变权威哈希。
		if _canonical_json(_window_dict(restored_window)) != _canonical_json(win_d):
			return false

	# ai：必须 Dictionary；{} 合法（restore 保留 target.ai）；非空严格 schema
	if not _validate_ai_restore_data(d):
		return false
	return true


## capture v1 的完整内部 schema。所有 restore 使用的字段先做 exact type/shape 校验，
## 后续 _restore_dict 中的显式转换只负责赋值，不再承担输入归一化。
static func _validate_restore_shape(d: Dictionary) -> bool:
	const KEYS := [
		"hand_seq", "phase", "current_seat", "dealer_seat", "round_wind",
		"hand_number", "honba", "riichi_sticks", "scores", "turn_count",
		"first_round_active", "furiten_flags", "ron_cancelled", "haitei_forced_seat",
		"extra_dora_count", "extra_red_dora_count", "event_chain_depth", "revealed",
		"tenpai_flags", "tenpai_wait_reveals",
		"kuikae", "momentum_total", "momentum_scores", "wall", "dora", "ura",
		"seats", "skills", "reg_next_order", "sched_next_chain", "window",
		"action_journal", "expected_replay", "event_journal", "settled", "last_event",
		"last_discarder", "last_discarded", "window_seq", "replay_status", "replay_idx",
		"battle_seed", "action_cmd_seq", "active_window_phase", "pending_added_kan", "ai",
	]
	if not _exact_keys(d, KEYS):
		return false
	for key in [
		"hand_seq", "phase", "current_seat", "dealer_seat", "round_wind",
		"hand_number", "honba", "riichi_sticks", "turn_count", "haitei_forced_seat",
		"event_chain_depth", "reg_next_order", "sched_next_chain", "last_discarder",
		"window_seq", "replay_idx", "battle_seed", "action_cmd_seq", "active_window_phase",
	]:
		if typeof(d[key]) != TYPE_INT:
			return false
	for key in ["first_round_active", "settled"]:
		if typeof(d[key]) != TYPE_BOOL:
			return false
	for key in ["last_event", "replay_status"]:
		if typeof(d[key]) != TYPE_STRING:
			return false
	if typeof(d["momentum_total"]) != TYPE_FLOAT:
		return false
	for key in [
		"scores", "furiten_flags", "ron_cancelled", "tenpai_flags", "extra_dora_count",
		"extra_red_dora_count", "revealed", "kuikae", "dora", "ura", "seats",
		"skills", "action_journal", "expected_replay", "event_journal",
	]:
		if typeof(d[key]) != TYPE_ARRAY:
			return false
	for key in ["tenpai_wait_reveals", "momentum_scores", "wall", "window", "last_discarded", "pending_added_kan", "ai"]:
		if typeof(d[key]) != TYPE_DICTIONARY:
			return false

	if not _typed_array(d["scores"] as Array, 4, TYPE_INT):
		return false
	if not _typed_array(d["furiten_flags"] as Array, 4, TYPE_BOOL):
		return false
	if not _typed_array(d["ron_cancelled"] as Array, 4, TYPE_BOOL):
		return false
	if not _typed_array(d["tenpai_flags"] as Array, 4, TYPE_BOOL):
		return false
	if not _validate_tenpai_wait_reveals(
		d["tenpai_wait_reveals"] as Dictionary, d["tenpai_flags"] as Array
	):
		return false
	if not _typed_array(d["extra_dora_count"] as Array, 4, TYPE_INT):
		return false
	if not _typed_array(d["extra_red_dora_count"] as Array, 4, TYPE_INT):
		return false
	var kuikae: Array = d["kuikae"] as Array
	if kuikae.size() != 4:
		return false
	for restricted in kuikae:
		if typeof(restricted) != TYPE_ARRAY:
			return false
		for tile_id in restricted as Array:
			if typeof(tile_id) != TYPE_INT or not TileId.ALL.has(tile_id):
				return false

	var wall: Dictionary = d["wall"] as Dictionary
	if not _exact_keys(wall, ["tiles", "draw_index", "dead_size", "rinshan_taken", "live"]):
		return false
	if typeof(wall["tiles"]) != TYPE_ARRAY:
		return false
	for key in ["draw_index", "dead_size", "rinshan_taken", "live"]:
		if typeof(wall[key]) != TYPE_INT:
			return false
	var draw_index: int = wall["draw_index"]
	var dead_size: int = wall["dead_size"]
	var rinshan_taken: int = wall["rinshan_taken"]
	if draw_index < 0 or dead_size < 0 or rinshan_taken < 0 or rinshan_taken > 4:
		return false
	if draw_index + dead_size > Tile.TILES_PER_HAND:
		return false
	if wall["live"] != Tile.TILES_PER_HAND - draw_index - dead_size:
		return false

	var momentum: Dictionary = d["momentum_scores"] as Dictionary
	# E2-04：空 scores + total=0 → STANDARD null Momentum；否则须完整 Attribute 字典
	if momentum.is_empty():
		if not is_equal_approx(float(d["momentum_total"]), 0.0):
			return false
	else:
		if momentum.size() != Momentum.Attribute.size():
			return false
		var momentum_sum: float = 0.0
		for key in momentum.keys():
			if typeof(key) != TYPE_STRING or not (key as String).is_valid_int():
				return false
			var attr: int = (key as String).to_int()
			if attr < 0 or attr >= Momentum.Attribute.size() or key != str(attr):
				return false
			if typeof(momentum[key]) != TYPE_FLOAT:
				return false
			momentum_sum += momentum[key]
		var expected_momentum: float = clampf(
			momentum_sum / float(Momentum.Attribute.size()), 0.0, 1.0
		)
		if not is_equal_approx(d["momentum_total"], expected_momentum):
			return false

	if not _validate_seat_shapes(d["seats"] as Array):
		return false
	if not _validate_skill_shapes(d["skills"] as Array):
		return false
	if not _validate_revealed_shapes(d["revealed"] as Array):
		return false
	if not _validate_pending_kan_shape(d["pending_added_kan"] as Dictionary):
		return false
	for raw in d["expected_replay"] as Array:
		if typeof(raw) != TYPE_DICTIONARY or Action.from_dict(raw) == null:
			return false
	return _validate_window_shape(d["window"] as Dictionary)


static func _validate_tenpai_wait_reveals(raw: Dictionary, flags: Array) -> bool:
	for viewer_value in raw.keys():
		if typeof(viewer_value) != TYPE_INT or int(viewer_value) < 0 or int(viewer_value) > 3:
			return false
		var subjects_value: Variant = raw[viewer_value]
		if typeof(subjects_value) != TYPE_DICTIONARY:
			return false
		var subjects := subjects_value as Dictionary
		if subjects.is_empty():
			return false
		for subject_value in subjects.keys():
			if typeof(subject_value) != TYPE_INT or int(subject_value) < 0 \
					or int(subject_value) > 3 or int(subject_value) == int(viewer_value):
				return false
			if not bool(flags[int(subject_value)]):
				return false
			var waits_value: Variant = subjects[subject_value]
			if typeof(waits_value) != TYPE_ARRAY or (waits_value as Array).is_empty():
				return false
			var previous := -1
			for tile_id in waits_value as Array:
				if typeof(tile_id) != TYPE_INT or not TileId.ALL.has(tile_id) \
						or int(tile_id) <= previous:
					return false
				previous = int(tile_id)
	return true


static func _exact_keys(d: Dictionary, keys: Array) -> bool:
	if d.size() != keys.size():
		return false
	for key in keys:
		if not d.has(key):
			return false
	return true


static func _typed_array(values: Array, size: int, value_type: int) -> bool:
	if values.size() != size:
		return false
	for value in values:
		if typeof(value) != value_type:
			return false
	return true


static func _validate_snapshot_tile_ref(raw: Variant, by_iid: Dictionary) -> bool:
	var tile: Tile = Tile.from_dict(raw)
	if tile == null or not by_iid.has(tile.instance_id):
		return false
	var canonical: Tile = by_iid[tile.instance_id] as Tile
	return canonical != null \
		and tile.id == canonical.id \
		and tile.is_red_dora == canonical.is_red_dora \
		and tile.owner_seat == canonical.owner_seat


static func _validate_battle_event_shape(event: Dictionary) -> bool:
	if not _exact_keys(event, ["type", "actor_seat", "tile", "chain_id", "extra"]):
		return false
	if typeof(event["type"]) != TYPE_STRING or (event["type"] as String).is_empty():
		return false
	if typeof(event["actor_seat"]) != TYPE_INT:
		return false
	var actor: int = event["actor_seat"]
	if actor < -1 or actor > 3:
		return false
	if typeof(event["chain_id"]) != TYPE_INT or event["chain_id"] < 0:
		return false
	if typeof(event["tile"]) != TYPE_DICTIONARY or typeof(event["extra"]) != TYPE_DICTIONARY:
		return false
	var tile: Dictionary = event["tile"] as Dictionary
	return tile.is_empty() or TileSkillAnchor.from_dict(tile) != null


static func _validate_seat_shapes(seats: Array) -> bool:
	if seats.size() != 4:
		return false
	for raw in seats:
		if typeof(raw) != TYPE_DICTIONARY:
			return false
		var seat: Dictionary = raw
		if not _exact_keys(seat, [
			"seat_id", "seat_wind", "hand", "river", "melds", "next_meld_id",
			"last_draw", "rinshan", "points", "riichi", "furiten",
		]):
			return false
		for key in ["seat_id", "seat_wind", "next_meld_id", "last_draw", "points"]:
			if typeof(seat[key]) != TYPE_INT:
				return false
		if typeof(seat["rinshan"]) != TYPE_BOOL:
			return false
		for key in ["hand", "river", "melds"]:
			if typeof(seat[key]) != TYPE_ARRAY:
				return false
		if typeof(seat["riichi"]) != TYPE_DICTIONARY or typeof(seat["furiten"]) != TYPE_DICTIONARY:
			return false
		var riichi: Dictionary = seat["riichi"]
		if not _exact_keys(riichi, ["declared", "declared_turn", "ippatsu", "stick", "double", "discard_index"]):
			return false
		for key in ["declared", "ippatsu", "stick", "double"]:
			if typeof(riichi[key]) != TYPE_BOOL:
				return false
		for key in ["declared_turn", "discard_index"]:
			if typeof(riichi[key]) != TYPE_INT:
				return false
		var furiten: Dictionary = seat["furiten"]
		if not _exact_keys(furiten, ["permanent", "temporary", "waits"]):
			return false
		if typeof(furiten["permanent"]) != TYPE_BOOL or typeof(furiten["temporary"]) != TYPE_BOOL:
			return false
		if typeof(furiten["waits"]) != TYPE_ARRAY:
			return false
		for wait in furiten["waits"] as Array:
			if typeof(wait) != TYPE_INT or not TileId.ALL.has(wait):
				return false
		for meld_raw in seat["melds"] as Array:
			if typeof(meld_raw) != TYPE_DICTIONARY:
				return false
			var meld: Dictionary = meld_raw
			if not _exact_keys(meld, ["kind", "from", "meld_id", "called", "added", "tiles"]):
				return false
			for key in ["kind", "from", "meld_id", "called", "added"]:
				if typeof(meld[key]) != TYPE_INT:
					return false
			if typeof(meld["tiles"]) != TYPE_ARRAY:
				return false
	return true


static func _validate_skill_shapes(skills: Array) -> bool:
	const KEYS := [
		"id", "display_name", "description", "hook_path", "consumed", "is_ability",
		"rarity", "attached_tile", "owner_triggers", "holder_triggers", "params",
		"anchor_kind", "anchor", "anchor_owner", "anchor_holder", "reg_order",
	]
	for raw in skills:
		if typeof(raw) != TYPE_DICTIONARY:
			return false
		var skill: Dictionary = raw
		if not _exact_keys(skill, KEYS):
			return false
		for key in ["id", "display_name", "description", "hook_path", "anchor_kind"]:
			if typeof(skill[key]) != TYPE_STRING:
				return false
		var hook_path: String = skill["hook_path"]
		if not hook_path.is_empty():
			if not ResourceLoader.exists(hook_path) or not (load(hook_path) is GDScript):
				return false
		for key in ["consumed", "is_ability"]:
			if typeof(skill[key]) != TYPE_BOOL:
				return false
		for key in ["rarity", "attached_tile", "anchor_owner", "anchor_holder", "reg_order"]:
			if typeof(skill[key]) != TYPE_INT:
				return false
		for key in ["owner_triggers", "holder_triggers"]:
			if typeof(skill[key]) != TYPE_ARRAY:
				return false
			for trigger in skill[key] as Array:
				if typeof(trigger) != TYPE_STRING:
					return false
		if typeof(skill["params"]) != TYPE_DICTIONARY:
			return false
	return true


static func _validate_revealed_shapes(revealed: Array) -> bool:
	for raw in revealed:
		if typeof(raw) != TYPE_DICTIONARY:
			return false
		var item: Dictionary = raw
		var has_projection_kind := item.has(REVEALED_PROJECTION_KIND_KEY)
		var expected_keys := ["tile", "visible_to", REVEALED_PROJECTION_KIND_KEY] \
			if has_projection_kind else ["tile", "visible_to"]
		if not _exact_keys(item, expected_keys):
			return false
		if has_projection_kind and (
			typeof(item[REVEALED_PROJECTION_KIND_KEY]) != TYPE_STRING \
			or str(item[REVEALED_PROJECTION_KIND_KEY]) \
					!= SEAT_DRAW_FORECAST_PROJECTION_KIND
		):
			return false
		if typeof(item["tile"]) != TYPE_DICTIONARY or typeof(item["visible_to"]) != TYPE_ARRAY:
			return false
		if has_projection_kind:
			var forecast_anchor := TileSkillAnchor.from_dict(item["tile"])
			if forecast_anchor == null or forecast_anchor.holder_seat != -1 \
					or forecast_anchor.owner_seat < 0 \
					or forecast_anchor.owner_seat > 3 \
					or (item["visible_to"] as Array).size() != 1:
				return false
		var seen: Dictionary = {}
		for seat in item["visible_to"] as Array:
			if typeof(seat) != TYPE_INT or seat < 0 or seat > 3 or seen.has(seat):
				return false
			seen[seat] = true
	return true


static func _validate_pending_kan_shape(pending: Dictionary) -> bool:
	if pending.is_empty():
		return true
	if not _exact_keys(pending, ["seat", "meld_id", "added_iid"]):
		return false
	for key in ["seat", "meld_id", "added_iid"]:
		if typeof(pending[key]) != TYPE_INT:
			return false
	return pending["seat"] >= 0 and pending["seat"] <= 3


static func _validate_window_shape(window: Dictionary) -> bool:
	if window.is_empty():
		return true
	if not _exact_keys(window, [
		"kind", "decision_id", "hand_seq", "subject_seat", "subject_tile_instance_id",
		"discarder_seat", "responded", "contexts", "intents",
	]):
		return false
	for key in ["kind", "decision_id"]:
		if typeof(window[key]) != TYPE_STRING:
			return false
	for key in ["hand_seq", "subject_seat", "subject_tile_instance_id", "discarder_seat"]:
		if typeof(window[key]) != TYPE_INT:
			return false
	for key in ["responded", "contexts", "intents"]:
		if typeof(window[key]) != TYPE_ARRAY:
			return false
	var responded_seen: Dictionary = {}
	for seat in window["responded"] as Array:
		if typeof(seat) != TYPE_INT or seat < 0 or seat > 3 or responded_seen.has(seat):
			return false
		responded_seen[seat] = true
	for raw in window["contexts"] as Array:
		if typeof(raw) != TYPE_DICTIONARY:
			return false
		var ctx: Dictionary = raw
		if not _exact_keys(ctx, [
			"window_kind", "hand_seq", "decision_id", "seat", "claimed_tile_instance_id",
			"discarder_seat", "allowed_actions", "allowed_kinds",
		]):
			return false
		for key in ["window_kind", "decision_id"]:
			if typeof(ctx[key]) != TYPE_STRING:
				return false
		for key in ["hand_seq", "seat", "claimed_tile_instance_id", "discarder_seat"]:
			if typeof(ctx[key]) != TYPE_INT:
				return false
		for key in ["allowed_actions", "allowed_kinds"]:
			if typeof(ctx[key]) != TYPE_ARRAY:
				return false
	return true


## 非空 ai 严格 schema：禁止 int()/bool()/str() 静默 coercion；缺字段 typeof(null) 拒绝。
## 顶层必须有 ai；显式 {} 合法（restore 保留 target.ai）；非空 exact key set。
## kind 仅 SimpleAi/HeuristicAi（TYPE_STRING）；seed/state TYPE_INT。
## SimpleAi 恰好 {kind,seed,state}；HeuristicAi 恰好九键。
## HeuristicAi：shanten bool；三数组 + hand_index/total_hands 范围；
## discards 每 int ∈ TileId.ALL；riichi seats 0..3 且无重复。
static func _validate_ai_restore_data(d: Dictionary) -> bool:
	if not d.has("ai"):
		return false
	var ai_raw = d.get("ai")
	if typeof(ai_raw) != TYPE_DICTIONARY:
		return false
	var ai_d: Dictionary = ai_raw as Dictionary
	if ai_d.is_empty():
		return true

	var kind_raw: Variant = ai_d.get("kind")
	if typeof(kind_raw) != TYPE_STRING:
		return false
	var kind: String = kind_raw
	if kind != "SimpleAi" and kind != "HeuristicAi":
		return false

	# exact key set：未知 extra 或任一遗漏 → false
	if kind == "SimpleAi":
		if ai_d.size() != 3 \
			or not ai_d.has("kind") \
			or not ai_d.has("seed") \
			or not ai_d.has("state"):
			return false
	else:
		# HeuristicAi：恰好且仅九键
		if ai_d.size() != 9 \
			or not ai_d.has("kind") \
			or not ai_d.has("seed") \
			or not ai_d.has("state") \
			or not ai_d.has("use_shanten_aware_discard") \
			or not ai_d.has("_cumulative_scores") \
			or not ai_d.has("_hand_index") \
			or not ai_d.has("_total_hands") \
			or not ai_d.has("_opponent_riichi_seats") \
			or not ai_d.has("_opponent_discards_flat"):
			return false

	if typeof(ai_d.get("seed")) != TYPE_INT:
		return false
	if typeof(ai_d.get("state")) != TYPE_INT:
		return false

	if kind == "SimpleAi":
		return true

	# HeuristicAi
	if typeof(ai_d.get("use_shanten_aware_discard")) != TYPE_BOOL:
		return false
	if typeof(ai_d.get("_cumulative_scores")) != TYPE_ARRAY:
		return false
	if typeof(ai_d.get("_opponent_riichi_seats")) != TYPE_ARRAY:
		return false
	if typeof(ai_d.get("_opponent_discards_flat")) != TYPE_ARRAY:
		return false
	if typeof(ai_d.get("_hand_index")) != TYPE_INT:
		return false
	if typeof(ai_d.get("_total_hands")) != TYPE_INT:
		return false

	var scores: Array = ai_d.get("_cumulative_scores") as Array
	# 允许空；非空必须恰四席
	if not scores.is_empty() and scores.size() != 4:
		return false
	for v in scores:
		if typeof(v) != TYPE_INT:
			return false

	var riichi: Array = ai_d.get("_opponent_riichi_seats") as Array
	var riichi_seen: Dictionary = {}
	for seat_v in riichi:
		if typeof(seat_v) != TYPE_INT:
			return false
		var seat: int = seat_v
		if seat < 0 or seat > 3:
			return false
		if riichi_seen.has(seat):
			return false
		riichi_seen[seat] = true

	var discards: Array = ai_d.get("_opponent_discards_flat") as Array
	for tid_v in discards:
		if typeof(tid_v) != TYPE_INT:
			return false
		var tid: int = tid_v
		if not TileId.ALL.has(tid):
			return false

	var hand_index: int = ai_d.get("_hand_index")
	var total_hands: int = ai_d.get("_total_hands")
	if hand_index < 0 or total_hands < 0:
		return false
	if total_hands > 0 and hand_index >= total_hands:
		return false
	return true


## wall 实体字段须与 serial 推导的 canonical 一致（绝不能按数组 index 判断）。
## serial = iid - hs*136；id = TileId.ALL[serial/4]；copy = serial%4；
## owner_seat == copy；is_red_dora 仅当 copy==0 且 id∈{W5,T5,S5}。
static func _validate_wall_tile_canonical(t: Tile, hs: int) -> bool:
	var serial: int = int(t.instance_id) - hs * Tile.TILES_PER_HAND
	if serial < 0 or serial > 135:
		return false
	@warning_ignore("integer_division")
	var tid_idx: int = serial / 4
	if tid_idx < 0 or tid_idx >= TileId.ALL.size():
		return false
	var canon_id: int = int(TileId.ALL[tid_idx])
	var copy: int = serial % 4
	if int(t.id) != canon_id:
		return false
	if int(t.owner_seat) != copy:
		return false
	var expect_red: bool = (
		copy == 0
		and (canon_id == TileId.W5 or canon_id == TileId.T5 or canon_id == TileId.S5)
	)
	if bool(t.is_red_dora) != expect_red:
		return false
	return true


## 活动区：seats 四席 hand/river/meld.tiles + revealed 真实 tile + skill tile-anchor。
## 共用 seen_active：全局活动位置 iid 唯一。
## seats hand/river/meld：Dictionary + Tile.from_dict、iid∈by_iid、四字段与 wall 一致。
## revealed：支持 TileSkillAnchor 六键或 Tile 四键；真实 iid∈by_iid 且 id/red/owner/iid 与 wall 一致。
## skills：须 Array、每项 Dictionary；只接受 int / tile / virtual_tile 三种锚点。
## tile 的 anchor/owner/holder 严格 TYPE_INT，iid∈by_iid，且不得与其它活动区重复。
## virtual_tile 保存完整 Tile 字典，instance_id 必须为 INVALID_INSTANCE_ID；不占实体活动区。
## 未知 anchor_kind 或任一类型非法 → false。
static func _validate_active_tile_refs(d: Dictionary, by_iid: Dictionary) -> bool:
	var seats_raw = d.get("seats", null)
	if typeof(seats_raw) != TYPE_ARRAY:
		return false
	var seats: Array = seats_raw as Array
	if seats.size() != 4:
		return false
	var seen_active: Dictionary = {}
	for si in range(4):
		if typeof(seats[si]) != TYPE_DICTIONARY:
			return false
		var sd: Dictionary = seats[si] as Dictionary
		var hand_raw = sd.get("hand", null)
		if typeof(hand_raw) != TYPE_ARRAY:
			return false
		if not _validate_active_tile_list(hand_raw as Array, by_iid, seen_active):
			return false
		var river_raw = sd.get("river", null)
		if typeof(river_raw) != TYPE_ARRAY:
			return false
		if not _validate_active_tile_list(river_raw as Array, by_iid, seen_active):
			return false
		var melds_raw = sd.get("melds", null)
		if typeof(melds_raw) != TYPE_ARRAY:
			return false
		for md in melds_raw as Array:
			if typeof(md) != TYPE_DICTIONARY:
				return false
			var tiles_raw = (md as Dictionary).get("tiles", null)
			if typeof(tiles_raw) != TYPE_ARRAY:
				return false
			if not _validate_active_tile_list(tiles_raw as Array, by_iid, seen_active):
				return false

	# revealed：真实 tile iid 进同一 seen_active
	var rev_raw = d.get("revealed", [])
	if typeof(rev_raw) != TYPE_ARRAY:
		return false
	for item in rev_raw as Array:
		if typeof(item) != TYPE_DICTIONARY:
			return false
		var tile_raw = (item as Dictionary).get("tile", null)
		if typeof(tile_raw) != TYPE_DICTIONARY:
			return false
		if not _validate_revealed_tile_ref(tile_raw as Dictionary, by_iid, seen_active):
			return false

	# skills：实体锚点占用 seen_active；虚拟锚点不占实体活动区
	var skills_raw = d.get("skills", [])
	if typeof(skills_raw) != TYPE_ARRAY:
		return false
	for sk in skills_raw as Array:
		if typeof(sk) != TYPE_DICTIONARY:
			return false
		var sk_d: Dictionary = sk as Dictionary
		var anchor_kind_raw: Variant = sk_d.get("anchor_kind")
		if typeof(anchor_kind_raw) != TYPE_STRING:
			return false
		var anchor_kind: String = anchor_kind_raw
		if anchor_kind == "int":
			if typeof(sk_d.get("anchor")) != TYPE_INT:
				return false
			continue
		var raw_owner: Variant = sk_d.get("anchor_owner")
		var raw_holder: Variant = sk_d.get("anchor_holder")
		if typeof(raw_owner) != TYPE_INT or typeof(raw_holder) != TYPE_INT:
			return false
		var aown: int = raw_owner
		var ahold: int = raw_holder
		if aown < -1 or aown > 3 or ahold < -1 or ahold > 3:
			return false
		if anchor_kind == "virtual_tile":
			var virtual_tile: Tile = Tile.from_dict(sk_d.get("anchor"))
			if virtual_tile == null \
					or int(virtual_tile.instance_id) != Tile.INVALID_INSTANCE_ID:
				return false
			continue
		if anchor_kind != "tile":
			return false
		var raw_anchor: Variant = sk_d.get("anchor")
		if typeof(raw_anchor) != TYPE_INT:
			return false
		var aid: int = raw_anchor
		if not by_iid.has(aid):
			return false
		if seen_active.has(aid):
			return false
		seen_active[aid] = true
	return true


## 单列表活动 tile：Dictionary → from_dict → wall 实体四字段一致 + 全局唯一。
static func _validate_active_tile_list(
	arr: Array, by_iid: Dictionary, seen_active: Dictionary
) -> bool:
	for item in arr:
		if typeof(item) != TYPE_DICTIONARY:
			return false
		var t: Tile = Tile.from_dict(item)
		if t == null:
			return false
		var iid: int = int(t.instance_id)
		if not by_iid.has(iid):
			return false
		var wall_t: Tile = by_iid[iid] as Tile
		if int(t.id) != int(wall_t.id):
			return false
		if bool(t.is_red_dora) != bool(wall_t.is_red_dora):
			return false
		if int(t.owner_seat) != int(wall_t.owner_seat):
			return false
		if int(t.instance_id) != int(wall_t.instance_id):
			return false
		if seen_active.has(iid):
			return false
		seen_active[iid] = true
	return true


## revealed.tile：TileSkillAnchor 六键（tile_instance_id / tile_id / tile_owner_seat）
## 或 Tile 四键（instance_id / id / owner_seat）。iid∈by_iid 且底层四字段与 wall 一致。
## #253：揭示是可见性投影，可引用已在 hand/river 的活动牌；不得因「二次占用」失败。
## 仅当 iid 尚未出现在活动区时才写入 seen_active（墙顶 peek 等独占引用）。
static func _validate_revealed_tile_ref(
	td: Dictionary, by_iid: Dictionary, seen_active: Dictionary
) -> bool:
	var iid: int = Tile.INVALID_INSTANCE_ID
	var tid: int = -1
	var red: bool = false
	var owner: int = Tile.NO_OWNER
	if td.has("tile_instance_id"):
		# TileSkillAnchor 六键结构（capture 自 TileSkillAnchor.to_dict）
		if typeof(td.get("tile_instance_id")) != TYPE_INT:
			return false
		if typeof(td.get("tile_id")) != TYPE_INT:
			return false
		if typeof(td.get("is_red_dora")) != TYPE_BOOL:
			return false
		if typeof(td.get("tile_owner_seat")) != TYPE_INT:
			return false
		iid = td["tile_instance_id"]
		tid = td["tile_id"]
		red = td["is_red_dora"]
		owner = td["tile_owner_seat"]
	elif td.has("instance_id"):
		# Tile 四键结构（capture 自 Tile.to_dict）
		if typeof(td.get("instance_id")) != TYPE_INT:
			return false
		if typeof(td.get("id")) != TYPE_INT:
			return false
		if typeof(td.get("is_red_dora")) != TYPE_BOOL:
			return false
		if typeof(td.get("owner_seat")) != TYPE_INT:
			return false
		iid = td["instance_id"]
		tid = td["id"]
		red = td["is_red_dora"]
		owner = td["owner_seat"]
	else:
		return false
	if not by_iid.has(iid):
		return false
	var wall_t: Tile = by_iid[iid] as Tile
	if wall_t == null:
		return false
	if int(tid) != int(wall_t.id):
		return false
	if bool(red) != bool(wall_t.is_red_dora):
		return false
	if int(owner) != int(wall_t.owner_seat):
		return false
	if int(iid) != int(wall_t.instance_id):
		return false
	# 已在 hand/river 等活动区：允许 reveal 投影；不重复占用
	if not seen_active.has(iid):
		seen_active[iid] = true
	return true


## 临时 staging BC：seed/dealer/round_wind/hand_seq 来自 snapshot；AI kind 由 ai.kind。
static func _make_staging_controller(d: Dictionary) -> BattleController:
	var battle_seed: int = int(d.get("battle_seed", 0))
	var dealer_seat: int = int(d.get("dealer_seat", 0))
	var round_wind: int = int(d.get("round_wind", TileId.E))
	var hand_seq: int = int(d.get("hand_seq", 0))
	var use_heuristic: bool = false
	var ai_raw = d.get("ai", {})
	if typeof(ai_raw) == TYPE_DICTIONARY:
		use_heuristic = str((ai_raw as Dictionary).get("kind", "")) == "HeuristicAi"
	var staging := BattleController.new(
		battle_seed, dealer_seat, use_heuristic, round_wind, hand_seq
	)
	if staging == null or staging.state == null:
		return null
	return staging


## 一次性把 staging 权威引用与捕获字段提交给 target；不碰 Playable 端口/UI。
static func _commit_staged_controller(target: Object, staging: BattleController) -> void:
	target.set("state", staging.state)
	target.set("engine", staging.engine)
	target.set("registry", staging.registry)
	target.set("scheduler", staging.scheduler)
	target.set("ai", staging.ai)
	target.set("events", staging.events)
	target.set("_settled", staging.get("_settled"))
	target.set("_last_event_type", staging.get("_last_event_type"))
	target.set("_last_discarder_seat", staging.get("_last_discarder_seat"))
	target.set("_last_discarded_tile", staging.get("_last_discarded_tile"))
	target.set("_window_seq", staging.get("_window_seq"))
	target.set("_expected_replay_idx", staging.get("_expected_replay_idx"))
	target.set("_battle_seed", staging.get("_battle_seed"))
	target.set("_action_cmd_seq", staging.get("_action_cmd_seq"))
	target.set("_active_window_phase", staging.get("_active_window_phase"))
	target.set("_pending_added_kan", staging.get("_pending_added_kan"))
	target.set("_replay_status", staging.get("_replay_status"))
	target.set("_action_journal", staging.get("_action_journal"))
	target.set("_expected_replay", staging.get("_expected_replay"))
	target.set("_active_window", staging.get("_active_window"))


# ---- capture ----

static func _capture_dict(bc: Object, st: BattleState) -> Dictionary:
	var wall: Wall = st.wall
	var wall_tiles: Array = []
	for t in wall.authority_tiles():
		wall_tiles.append(_tile_dict(t as Tile))

	var seats_out: Array = []
	for si in range(4):
		var seat: Seat = st.seats[si] as Seat
		var hand_tiles: Array = []
		for t in seat.hand.tiles():
			hand_tiles.append(_tile_dict(t as Tile))
		var river_tiles: Array = []
		for t in seat.river.tiles():
			river_tiles.append(_tile_dict(t as Tile))
		var melds_out: Array = []
		for m in seat.melds.all():
			melds_out.append(_meld_dict(m as Meld))
		var ri: RiichiState = seat.riichi
		var fu: FuritenState = seat.furiten
		seats_out.append({
			"seat_id": int(seat.seat_id),
			"seat_wind": int(seat.seat_wind),
			"hand": hand_tiles,
			"river": river_tiles,
			"melds": melds_out,
			"next_meld_id": int(seat.melds.next_local_index()),
			"last_draw": int(seat.last_drawn_instance_id),
			"rinshan": bool(seat.last_draw_is_rinshan),
			"points": int(seat.points),
			"riichi": {
				"declared": bool(ri.declared),
				"declared_turn": int(ri.declared_turn),
				"ippatsu": bool(ri.ippatsu_window),
				"stick": bool(ri.riichi_stick_paid),
				"double": bool(ri.double_riichi),
				"discard_index": int(seat.river.riichi_discard_index()),
			},
			"furiten": {
				"permanent": bool(fu.permanent),
				"temporary": bool(fu.temporary),
				"waits": fu.waits.duplicate(),
			},
		})

	var dora_out: Array = []
	for t in st.dora_indicators.visible_tiles():
		dora_out.append(_tile_dict(t as Tile))
	var ura_out: Array = []
	for t in st.dora_indicators.uradora_tiles():
		ura_out.append(_tile_dict(t as Tile))

	var reg: SkillRegistry = bc.get("registry") as SkillRegistry
	var skills: Array = []
	if reg != null:
		for e in reg.get_all_entries():
			skills.append(_skill_entry_dict(e as Dictionary))

	var win_out: Dictionary = {}
	var win = bc.get("_active_window")
	if win is DecisionWindow:
		win_out = _window_dict(win as DecisionWindow)

	var action_journal: Array = []
	if bc.has_method("action_journal"):
		for a in bc.call("action_journal"):
			if a is Action:
				action_journal.append((a as Action).to_dict())

	var expected_replay: Array = []
	var raw_replay = bc.get("_expected_replay")
	if raw_replay is Array:
		for a in raw_replay:
			if a is Action:
				expected_replay.append((a as Action).to_dict())

	var event_journal: Array = []
	var raw_events = bc.get("events")
	if raw_events is Array:
		for ev in raw_events:
			if ev is BattleEvent:
				event_journal.append((ev as BattleEvent).to_dict())

	var last_discarded: Dictionary = {}
	var ld = bc.get("_last_discarded_tile")
	if ld is Tile:
		last_discarded = _tile_dict(ld as Tile)

	var pending_kan: Dictionary = {}
	var pk = bc.get("_pending_added_kan")
	if pk is Dictionary:
		pending_kan = (pk as Dictionary).duplicate(true)

	var mom: Momentum = st.momentum
	var mom_scores: Dictionary = {}
	if mom != null:
		for k in mom.scores.keys():
			mom_scores[str(int(k))] = float(mom.scores[k])

	var replay_status := "IDLE"
	if bc.has_method("replay_status"):
		replay_status = str(bc.call("replay_status"))

	var sched: SkillScheduler = bc.get("scheduler") as SkillScheduler
	var sched_next: int = 1
	if sched != null:
		sched_next = int(sched.get("_next_chain_id"))

	var reg_next: int = 0
	if reg != null:
		reg_next = int(reg.get("_next_order"))

	return {
		"hand_seq": int(st.hand_seq),
		"phase": int(st.phase),
		"current_seat": int(st.current_seat),
		"dealer_seat": int(st.dealer_seat),
		"round_wind": int(st.round_wind),
		"hand_number": int(st.hand_number),
		"honba": int(st.honba),
		"riichi_sticks": int(st.riichi_sticks),
		"scores": st.scores.duplicate(),
		"turn_count": int(st.turn_count),
		"first_round_active": bool(st.first_round_active),
		"furiten_flags": st.furiten_flags.duplicate(),
		"ron_cancelled": st.ron_cancelled.duplicate(),
		"tenpai_flags": st.tenpai_flags.duplicate(),
		"tenpai_wait_reveals": st.tenpai_wait_reveals.duplicate(true),
		"haitei_forced_seat": int(st.haitei_forced_seat),
		"extra_dora_count": st.extra_dora_count.duplicate(),
		"extra_red_dora_count": st.extra_red_dora_count.duplicate(),
		"event_chain_depth": int(st.event_chain_depth),
		"revealed": _revealed_norm(st.revealed_tiles),
		"kuikae": st.kuikae_restricted.duplicate(true),
		"momentum_total": float(mom.total_momentum) if mom else 0.0,
		"momentum_scores": mom_scores,
		"wall": {
			"tiles": wall_tiles,
			"draw_index": wall.draw_index(),
			"dead_size": wall.dead_wall_size(),
			"rinshan_taken": wall.rinshan_taken(),
			"live": int(wall.live_wall_size()),
		},
		"dora": dora_out,
		"ura": ura_out,
		"seats": seats_out,
		"skills": skills,
		"reg_next_order": reg_next,
		"sched_next_chain": sched_next,
		"window": win_out,
		"action_journal": action_journal,
		"expected_replay": expected_replay,
		"event_journal": event_journal,
		"settled": bool(bc.get("_settled")) if bc.get("_settled") != null else false,
		"last_event": str(bc.get("_last_event_type")) if bc.get("_last_event_type") != null else "",
		"last_discarder": int(bc.get("_last_discarder_seat")) if bc.get("_last_discarder_seat") != null else -1,
		"last_discarded": last_discarded,
		"window_seq": int(bc.get("_window_seq")) if bc.get("_window_seq") != null else 0,
		"replay_status": replay_status,
		"replay_idx": int(bc.get("_expected_replay_idx")) if bc.get("_expected_replay_idx") != null else 0,
		"battle_seed": int(bc.get("_battle_seed")) if bc.get("_battle_seed") != null else 0,
		"action_cmd_seq": int(bc.get("_action_cmd_seq")) if bc.get("_action_cmd_seq") != null else 0,
		"active_window_phase": int(bc.get("_active_window_phase")) if bc.get("_active_window_phase") != null else -1,
		"pending_added_kan": pending_kan,
		"ai": _capture_ai_dict(bc),
	}


## 捕获 bc.ai：kind + RNG；HeuristicAi 额外配置。空/未知 → {}。
static func _capture_ai_dict(bc: Object) -> Dictionary:
	var ai = bc.get("ai")
	if ai == null:
		return {}
	# 判型必须先 HeuristicAi 再 SimpleAi（HeuristicAi extends SimpleAi）
	if ai is HeuristicAi:
		var h: HeuristicAi = ai as HeuristicAi
		return {
			"kind": "HeuristicAi",
			"seed": int(h._rng.seed),
			"state": int(h._rng.state),
			"use_shanten_aware_discard": bool(h.use_shanten_aware_discard),
			"_cumulative_scores": h._cumulative_scores.duplicate(),
			"_hand_index": int(h._hand_index),
			"_total_hands": int(h._total_hands),
			"_opponent_riichi_seats": h._opponent_riichi_seats.duplicate(),
			"_opponent_discards_flat": h._opponent_discards_flat.duplicate(),
		}
	if ai is SimpleAi:
		var s: SimpleAi = ai as SimpleAi
		return {
			"kind": "SimpleAi",
			"seed": int(s._rng.seed),
			"state": int(s._rng.state),
		}
	return {}


static func _tile_dict(t: Tile) -> Dictionary:
	if t == null:
		return {}
	return t.to_dict()


static func _meld_dict(m: Meld) -> Dictionary:
	var tiles: Array = []
	for t in m.tiles:
		tiles.append(_tile_dict(t as Tile))
	return {
		"kind": int(m.kind),
		"from": int(m.from_seat),
		"meld_id": int(m.meld_id),
		"called": int(m.called_tile_instance_id),
		"added": int(m.added_tile_instance_id),
		"tiles": tiles,
	}


static func _skill_entry_dict(e: Dictionary) -> Dictionary:
	var sk: SkillResource = e["skill"] as SkillResource
	var anchor = e["anchor"]
	var anchor_kind := "int"
	var anchor_val: Variant = 0
	var anchor_owner: int = 0
	var anchor_holder: int = -1
	if typeof(anchor) == TYPE_INT:
		anchor_val = int(anchor)
	elif anchor is TileSkillAnchor and (anchor as TileSkillAnchor).tile != null:
		var ti: TileSkillAnchor = anchor as TileSkillAnchor
		if int(ti.tile.instance_id) == Tile.INVALID_INSTANCE_ID:
			anchor_kind = "virtual_tile"
			anchor_val = ti.tile.to_dict()
		else:
			anchor_kind = "tile"
			# 底层真实 wall tile iid + TileSkillAnchor owner/holder
			anchor_val = int(ti.tile.instance_id)
		anchor_owner = int(ti.owner_seat)
		anchor_holder = int(ti.holder_seat)
	else:
		anchor_kind = "other"
		anchor_val = str(anchor)
	var hook_path := ""
	if sk != null and sk.hook_script != null:
		hook_path = sk.hook_script.resource_path
	# triggers 存为 plain string，保证 canonical JSON 兼容（禁 StringName）
	var ot: Array = []
	var ht: Array = []
	if sk != null:
		for t in sk.owner_triggers:
			ot.append(str(t))
		for t in sk.holder_triggers:
			ht.append(str(t))
	return {
		"id": str(sk.id) if sk else "",
		"display_name": sk.display_name if sk else "",
		"description": sk.description if sk else "",
		"hook_path": hook_path,
		"consumed": bool(sk.consumed) if sk else false,
		"is_ability": bool(sk.is_ability) if sk else false,
		"rarity": int(sk.rarity) if sk else 0,
		"attached_tile": int(sk.attached_tile) if sk else -1,
		"owner_triggers": ot,
		"holder_triggers": ht,
		"params": (sk.params.duplicate(true) if sk else {}),
		"anchor_kind": anchor_kind,
		"anchor": anchor_val,
		"anchor_owner": anchor_owner,
		"anchor_holder": anchor_holder,
		"reg_order": int(e["reg_order"]),
	}


static func _window_dict(win: DecisionWindow) -> Dictionary:
	var intents: Array = []
	for a in win.intents():
		intents.append((a as Action).to_dict())
	var ctxs: Array = []
	for s in win.seats():
		var c: DecisionContext = win.context_for_seat(int(s))
		if c:
			ctxs.append(c.to_dict())
	var responded: Array = []
	for s in win.seats():
		if win.has_responded(int(s)):
			responded.append(int(s))
	responded.sort()
	return {
		"kind": win.kind,
		"decision_id": win.decision_id,
		"hand_seq": win.hand_seq,
		"subject_seat": win.subject_seat,
		"subject_tile_instance_id": int(win.subject_tile_instance_id),
		"discarder_seat": int(win.discarder_seat),
		"responded": responded,
		"contexts": ctxs,
		"intents": intents,
	}


static func _revealed_norm(items: Array) -> Array:
	var out: Array = []
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var tile_d := {}
		var t = d.get("tile", null)
		if t is TileSkillAnchor:
			tile_d = (t as TileSkillAnchor).to_dict()
		elif t is Tile:
			tile_d = (t as Tile).to_dict()
		elif typeof(t) == TYPE_DICTIONARY:
			tile_d = (t as Dictionary).duplicate(true)
		var vis: Array = []
		if d.get("visible_to") is Array:
			vis = (d["visible_to"] as Array).duplicate()
		var normalized := {"tile": tile_d, "visible_to": vis}
		if d.has(REVEALED_PROJECTION_KIND_KEY):
			normalized[REVEALED_PROJECTION_KIND_KEY] = d.get(
				REVEALED_PROJECTION_KIND_KEY)
		out.append(normalized)
	return out


# ---- restore ----

static func _restore_dict(bc: Object, st: BattleState, d: Dictionary) -> bool:
	# 1) wall：重建 136 实体 + 索引
	var wall_d: Dictionary = d.get("wall", {}) as Dictionary
	var wall_tiles_raw: Array = wall_d.get("tiles", []) as Array
	if wall_tiles_raw.size() != 136:
		return false
	var wall: Wall = st.wall
	if wall == null:
		wall = Wall.new()
		st.wall = wall
	var new_tiles: Array[Tile] = []
	var by_iid: Dictionary = {}
	for td in wall_tiles_raw:
		var t: Tile = Tile.from_dict(td)
		if t == null:
			return false
		new_tiles.append(t)
		by_iid[int(t.instance_id)] = t
	if not wall.restore_authority_state(
		new_tiles,
		int(wall_d.get("draw_index", 0)),
		int(wall_d.get("dead_size", 0)),
		int(wall_d.get("rinshan_taken", 0))
	):
		return false

	# 2) scalar state
	st.hand_seq = int(d.get("hand_seq", 0))
	st.phase = int(d.get("phase", 0))
	st.current_seat = int(d.get("current_seat", 0))
	st.dealer_seat = int(d.get("dealer_seat", 0))
	st.round_wind = int(d.get("round_wind", TileId.E))
	st.hand_number = int(d.get("hand_number", 1))
	st.honba = int(d.get("honba", 0))
	st.riichi_sticks = int(d.get("riichi_sticks", 0))
	st.turn_count = int(d.get("turn_count", 0))
	st.first_round_active = bool(d.get("first_round_active", true))
	st.haitei_forced_seat = int(d.get("haitei_forced_seat", -1))
	st.event_chain_depth = int(d.get("event_chain_depth", 0))

	var scores_raw: Array = d.get("scores", []) as Array
	var scores_typed: Array[int] = []
	for s in scores_raw:
		scores_typed.append(int(s))
	while scores_typed.size() < 4:
		scores_typed.append(25000)
	st.scores = scores_typed

	var ff: Array = d.get("furiten_flags", []) as Array
	var ff_t: Array[bool] = []
	for v in ff:
		ff_t.append(bool(v))
	while ff_t.size() < 4:
		ff_t.append(false)
	st.furiten_flags = ff_t

	var rc: Array = d.get("ron_cancelled", []) as Array
	var rc_t: Array[bool] = []
	for v in rc:
		rc_t.append(bool(v))
	while rc_t.size() < 4:
		rc_t.append(false)
	st.ron_cancelled = rc_t

	var tf: Array = d.get("tenpai_flags", []) as Array
	var tf_t: Array[bool] = []
	for v in tf:
		tf_t.append(bool(v))
	while tf_t.size() < 4:
		tf_t.append(false)
	st.tenpai_flags = tf_t
	st.tenpai_wait_reveals = (d.get("tenpai_wait_reveals", {}) as Dictionary).duplicate(true)

	var ed: Array = d.get("extra_dora_count", []) as Array
	var ed_t: Array[int] = []
	for v in ed:
		ed_t.append(int(v))
	while ed_t.size() < 4:
		ed_t.append(0)
	st.extra_dora_count = ed_t

	var er: Array = d.get("extra_red_dora_count", []) as Array
	var er_t: Array[int] = []
	for v in er:
		er_t.append(int(v))
	while er_t.size() < 4:
		er_t.append(0)
	st.extra_red_dora_count = er_t

	st.kuikae_restricted = (d.get("kuikae", [[], [], [], []]) as Array).duplicate(true)

	# momentum：空 scores → STANDARD null；非空 → 回填（不得强制 new 污染 STANDARD）
	var ms: Dictionary = d.get("momentum_scores", {}) as Dictionary
	if ms.is_empty():
		st.momentum = null
	else:
		if st.momentum == null:
			st.momentum = Momentum.new()
		for k in ms.keys():
			var attr: int = int(k)
			st.momentum.scores[attr] = float(ms[k])
		st.momentum._recalculate_total()

	# dora / ura：引用 wall map 中同 iid 实体
	if st.dora_indicators == null:
		st.dora_indicators = DoraIndicators.new()
	var visible_dora: Array[Tile] = []
	var hidden_dora: Array[Tile] = []
	for td in d.get("dora", []) as Array:
		var t2: Tile = _resolve_tile(td, by_iid)
		if t2 == null:
			return false
		visible_dora.append(t2)
	for td in d.get("ura", []) as Array:
		var t3: Tile = _resolve_tile(td, by_iid)
		if t3 == null:
			return false
		hidden_dora.append(t3)
	if not st.dora_indicators.restore_pairs(visible_dora, hidden_dora):
		return false

	# seats
	var seats_raw: Array = d.get("seats", []) as Array
	if seats_raw.size() != 4:
		return false
	for si in range(4):
		var sd: Dictionary = seats_raw[si] as Dictionary
		var seat: Seat = st.seats[si] as Seat
		seat.seat_id = int(sd.get("seat_id", si))
		seat.seat_wind = int(sd.get("seat_wind", seat.seat_wind))
		seat.points = int(sd.get("points", 25000))
		seat.last_drawn_instance_id = int(sd.get("last_draw", Tile.INVALID_INSTANCE_ID))
		seat.last_draw_is_rinshan = bool(sd.get("rinshan", false))
		# hand
		seat.hand = Hand.new()
		for td in sd.get("hand", []) as Array:
			var ht: Tile = _resolve_tile(td, by_iid)
			if ht != null:
				seat.hand.add(ht)
		# river
		var river: Array = []
		for td in sd.get("river", []) as Array:
			var rt: Tile = _resolve_tile(td, by_iid)
			if rt != null:
				river.append(rt)
		var ri_d: Dictionary = sd.get("riichi", {}) as Dictionary
		var discard_index := int(ri_d.get("discard_index", -1))
		if not seat.river.restore(river, discard_index):
			return false
		# melds
		var restored_melds: Array[Meld] = []
		for md in sd.get("melds", []) as Array:
			var meld: Meld = _restore_meld(md as Dictionary, by_iid)
			if meld == null:
				return false
			restored_melds.append(meld)
		if not seat.melds.restore(restored_melds, int(sd.get("next_meld_id", 0))):
			return false
		# riichi / furiten
		seat.riichi.declared = bool(ri_d.get("declared", false))
		seat.riichi.declared_turn = int(ri_d.get("declared_turn", -1))
		seat.riichi.ippatsu_window = bool(ri_d.get("ippatsu", false))
		seat.riichi.riichi_stick_paid = bool(ri_d.get("stick", false))
		seat.riichi.double_riichi = bool(ri_d.get("double", false))
		var fu_d: Dictionary = sd.get("furiten", {}) as Dictionary
		seat.furiten.permanent = bool(fu_d.get("permanent", false))
		seat.furiten.temporary = bool(fu_d.get("temporary", false))
		seat.furiten.waits = (fu_d.get("waits", []) as Array).duplicate()

	# revealed
	st.revealed_tiles = []
	for item in d.get("revealed", []) as Array:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var idict: Dictionary = item
		var tile_raw = idict.get("tile", {})
		var ti: TileSkillAnchor = null
		if typeof(tile_raw) == TYPE_DICTIONARY:
			var tdict: Dictionary = tile_raw
			if tdict.has("tile_instance_id"):
				var parsed: TileSkillAnchor = TileSkillAnchor.from_dict(tdict)
				if parsed != null and parsed.tile != null \
						and by_iid.has(parsed.tile.instance_id):
					var canonical: Tile = by_iid[parsed.tile.instance_id] as Tile
					ti = TileSkillAnchor.make(canonical, parsed.owner_seat, null)
					ti.holder_seat = parsed.holder_seat
			elif tdict.has("instance_id"):
				var tile_ent: Tile = _resolve_tile(tdict, by_iid)
				if tile_ent != null:
					ti = TileSkillAnchor.make(tile_ent, int(tdict.get("owner_seat", 0)), null)
		if ti != null:
			var vis: Array = []
			if idict.get("visible_to") is Array:
				vis = (idict["visible_to"] as Array).duplicate()
			var restored_record := {"tile": ti, "visible_to": vis}
			if idict.has(REVEALED_PROJECTION_KIND_KEY):
				restored_record[REVEALED_PROJECTION_KIND_KEY] = idict.get(
					REVEALED_PROJECTION_KIND_KEY)
			st.revealed_tiles.append(restored_record)

	# skills / registry
	var reg: SkillRegistry = bc.get("registry") as SkillRegistry
	if reg == null:
		reg = SkillRegistry.new()
		bc.set("registry", reg)
	var entries: Array = []
	var skill_by_id: Dictionary = {}
	for sk_d in d.get("skills", []) as Array:
		var entry: Dictionary = _restore_skill_entry(sk_d as Dictionary, by_iid, reg)
		if entry.is_empty():
			return false
		entries.append(entry)
		var sk: SkillResource = entry["skill"] as SkillResource
		if sk != null:
			skill_by_id[str(sk.id)] = sk
	reg.set("_entries", entries)
	# 保留捕获时的 reg_order / _next_order（勿按 size 重算）
	reg.set("_next_order", int(d.get("reg_next_order", entries.size())))

	# scheduler
	var sched: SkillScheduler = bc.get("scheduler") as SkillScheduler
	if sched == null:
		sched = SkillScheduler.new(reg, st)
		bc.set("scheduler", sched)
	else:
		sched.set("_registry", reg)
		sched.set("_state", st)
	sched.set("_next_chain_id", int(d.get("sched_next_chain", 1)))

	# engine 对齐 state
	var engine: TurnEngine = bc.get("engine") as TurnEngine
	if engine == null:
		bc.set("engine", TurnEngine.new(st))
	else:
		engine.state = st

	# controller fields
	bc.set("_settled", bool(d.get("settled", false)))
	bc.set("_last_event_type", StringName(str(d.get("last_event", ""))))
	bc.set("_last_discarder_seat", int(d.get("last_discarder", -1)))
	bc.set("_window_seq", int(d.get("window_seq", 0)))
	bc.set("_expected_replay_idx", int(d.get("replay_idx", 0)))
	bc.set("_battle_seed", int(d.get("battle_seed", 0)))
	bc.set("_action_cmd_seq", int(d.get("action_cmd_seq", 0)))
	bc.set("_active_window_phase", int(d.get("active_window_phase", -1)))
	bc.set("_pending_added_kan", (d.get("pending_added_kan", {}) as Dictionary).duplicate(true))
	bc.set("_replay_status", StringName(str(d.get("replay_status", "IDLE"))))

	var last_d: Dictionary = d.get("last_discarded", {}) as Dictionary
	if last_d.is_empty():
		bc.set("_last_discarded_tile", null)
	else:
		bc.set("_last_discarded_tile", _resolve_tile(last_d, by_iid))

	# action journal（严格：非法不得静默 skip；校验已通过时应全部成功）
	var journal: Array = []
	for ad in d.get("action_journal", []) as Array:
		if typeof(ad) != TYPE_DICTIONARY:
			return false
		var act: Action = Action.from_dict(ad)
		if act == null:
			return false
		journal.append(act)
	bc.set("_action_journal", journal)

	# expected replay
	var exp_replay: Array = []
	for ad in d.get("expected_replay", []) as Array:
		var act2: Action = Action.from_dict(ad)
		if act2 != null:
			exp_replay.append(act2)
	bc.set("_expected_replay", exp_replay)

	# events（严格：非法不得静默 skip）
	var evs: Array = []
	for ed_raw in d.get("event_journal", []) as Array:
		if typeof(ed_raw) != TYPE_DICTIONARY:
			return false
		var bev: BattleEvent = BattleEvent.from_dict(ed_raw as Dictionary)
		if bev == null:
			return false
		evs.append(bev)
	bc.set("events", evs)

	# decision window（严格签名；非空必须完整解析）
	var win_raw = d.get("window", {})
	if typeof(win_raw) != TYPE_DICTIONARY:
		return false
	var win_d: Dictionary = win_raw as Dictionary
	if win_d.is_empty():
		bc.set("_active_window", null)
	else:
		var win: DecisionWindow = _restore_window(win_d, by_iid)
		if win == null:
			return false
		bc.set("_active_window", win)

	# AI 连续性：空 ai 保持现有 bc.ai 不动（不扩 strict/atomic 语义）
	var ai_raw = d.get("ai", {})
	if typeof(ai_raw) == TYPE_DICTIONARY and not (ai_raw as Dictionary).is_empty():
		_restore_ai(bc, ai_raw as Dictionary)

	return true


## 按 kind 重建 AI；先 seed 构造，再写 _rng.seed / _rng.state。
static func _restore_ai(bc: Object, ai_d: Dictionary) -> void:
	if ai_d.is_empty():
		return
	var kind: String = str(ai_d.get("kind", ""))
	var rng_seed: int = int(ai_d.get("seed", 0))
	var rng_state: int = int(ai_d.get("state", 0))
	var restored_ai = null
	if kind == "HeuristicAi":
		var h := HeuristicAi.new(rng_seed)
		h._rng.seed = rng_seed
		h._rng.state = rng_state
		h.set_strategic_context(
			(ai_d.get("_cumulative_scores", []) as Array).duplicate(),
			int(ai_d.get("_hand_index", 0)),
			int(ai_d.get("_total_hands", 0))
		)
		h.set_defense_context(
			(ai_d.get("_opponent_riichi_seats", []) as Array).duplicate(),
			(ai_d.get("_opponent_discards_flat", []) as Array).duplicate()
		)
		h.use_shanten_aware_discard = bool(ai_d.get("use_shanten_aware_discard", false))
		restored_ai = h
	elif kind == "SimpleAi":
		var s := SimpleAi.new(rng_seed)
		s._rng.seed = rng_seed
		s._rng.state = rng_state
		restored_ai = s
	else:
		return
	bc.set("ai", restored_ai)


static func _resolve_tile(raw: Variant, by_iid: Dictionary) -> Tile:
	if raw is Tile:
		var t0: Tile = raw as Tile
		if by_iid.has(int(t0.instance_id)):
			return by_iid[int(t0.instance_id)] as Tile
		return t0
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = raw
	var iid: int = int(d.get("instance_id", Tile.INVALID_INSTANCE_ID))
	if by_iid.has(iid):
		# 同步可变字段（owner 等）到权威实体
		var ent: Tile = by_iid[iid] as Tile
		return ent
	return Tile.from_dict(d)


static func _restore_meld(md: Dictionary, by_iid: Dictionary) -> Meld:
	var tiles: Array[Tile] = []
	for td in md.get("tiles", []) as Array:
		var t: Tile = _resolve_tile(td, by_iid)
		if t == null:
			return null
		tiles.append(t)
	var kind: int = int(md.get("kind", 0))
	var from_seat: int = int(md.get("from", -1))
	var meld_id: int = int(md.get("meld_id", Tile.INVALID_INSTANCE_ID))
	var called: int = int(md.get("called", Tile.INVALID_INSTANCE_ID))
	var added: int = int(md.get("added", Tile.INVALID_INSTANCE_ID))
	var called_tile: Tile = null
	for t in tiles:
		if int(t.instance_id) == called:
			called_tile = t
			break
	var meld: Meld = Meld.new(kind as Meld.Kind, tiles, from_seat, meld_id, called_tile)
	# added_tile_instance_id 只能经 promote；若已是 ADDED_KAN 且有 added，直接写私有字段
	if kind == int(Meld.Kind.ADDED_KAN) and added != Tile.INVALID_INSTANCE_ID:
		meld.set("_added_tile_instance_id", added)
	return meld


static func _restore_skill_entry(sk_d: Dictionary, by_iid: Dictionary, reg: SkillRegistry) -> Dictionary:
	var sk := SkillResource.new()
	sk.id = StringName(str(sk_d.get("id", "")))
	sk.display_name = str(sk_d.get("display_name", sk.id))
	sk.description = str(sk_d.get("description", ""))
	sk.consumed = bool(sk_d.get("consumed", false))
	sk.is_ability = bool(sk_d.get("is_ability", false))
	sk.rarity = int(sk_d.get("rarity", 0))
	sk.attached_tile = int(sk_d.get("attached_tile", -1))
	var ot: Array[StringName] = []
	for t in sk_d.get("owner_triggers", []) as Array:
		ot.append(StringName(str(t)))
	sk.owner_triggers = ot
	var ht: Array[StringName] = []
	for t in sk_d.get("holder_triggers", []) as Array:
		ht.append(StringName(str(t)))
	sk.holder_triggers = ht
	# params 深拷贝；JSON-compatible 字典原样还原
	var params_raw: Variant = sk_d.get("params", {})
	if typeof(params_raw) == TYPE_DICTIONARY:
		sk.params = (params_raw as Dictionary).duplicate(true)
	else:
		sk.params = {}
	var hook_path: String = str(sk_d.get("hook_path", ""))
	if not hook_path.is_empty() and ResourceLoader.exists(hook_path):
		sk.hook_script = load(hook_path) as GDScript
	var anchor: Variant = null
	var anchor_kind: String = str(sk_d.get("anchor_kind", "int"))
	if anchor_kind == "tile":
		var aid: int = int(sk_d.get("anchor", -1))
		# 禁止伪造 fallback：iid 不在 by_iid → 空 Dictionary（不静默降级）
		if not by_iid.has(aid):
			return {}
		var at: Tile = by_iid[aid] as Tile
		if at == null:
			return {}
		var owner_seat: int = int(sk_d.get("anchor_owner", 0))
		var holder_seat: int = int(sk_d.get("anchor_holder", -1))
		# make 恢复 skill 引用；再写 holder_seat
		var ti: TileSkillAnchor = TileSkillAnchor.make(at, owner_seat, sk)
		ti.holder_seat = holder_seat
		anchor = ti
	elif anchor_kind == "virtual_tile":
		var virtual_tile: Tile = Tile.from_dict(sk_d.get("anchor"))
		if virtual_tile == null \
				or int(virtual_tile.instance_id) != Tile.INVALID_INSTANCE_ID:
			return {}
		var virtual_owner: int = int(sk_d.get("anchor_owner", 0))
		var virtual_holder: int = int(sk_d.get("anchor_holder", -1))
		var virtual_anchor := TileSkillAnchor.make(virtual_tile, virtual_owner, sk)
		virtual_anchor.holder_seat = virtual_holder
		anchor = virtual_anchor
	elif anchor_kind == "int":
		anchor = int(sk_d.get("anchor", 0))
	else:
		return {}
	var hook = null
	if sk.hook_script != null:
		hook = sk.hook_script.new()
		if hook is SkillHook:
			# 与 SkillRegistry.register 一致：传入真实 registry，非 null
			hook.on_register(sk, reg)
	return {
		"skill": sk,
		"anchor": anchor,
		"hook": hook,
		"reg_order": int(sk_d.get("reg_order", 0)),
	}


## 严格恢复 DecisionWindow：任一项非法 → null（不得 continue 静默丢坏项）。
## by_iid：wall map；subject / claimed（非 -1）iid 必须存在。
static func _restore_window(win_d: Dictionary, by_iid: Dictionary) -> DecisionWindow:
	var kind: String = str(win_d.get("kind", ""))
	var hand_seq: int = int(win_d.get("hand_seq", 0))
	var decision_id: String = str(win_d.get("decision_id", ""))
	var subject: int = int(win_d.get("subject_seat", 0))
	var subject_tile: int = int(win_d.get("subject_tile_instance_id", -1))
	var discarder: int = int(win_d.get("discarder_seat", -1))
	var win: DecisionWindow = DecisionWindow.make(
		kind, hand_seq, decision_id, subject, subject_tile, discarder
	)
	if win == null:
		return null
	if subject_tile != Tile.INVALID_INSTANCE_ID and not by_iid.has(subject_tile):
		return null
	for ctx_raw in win_d.get("contexts", []) as Array:
		if typeof(ctx_raw) != TYPE_DICTIONARY:
			return null
		var cd: Dictionary = ctx_raw
		var claimed: int = int(cd.get("claimed_tile_instance_id", -1))
		var ctx: DecisionContext = DecisionContext.make(
			str(cd.get("window_kind", kind)),
			int(cd.get("hand_seq", hand_seq)),
			str(cd.get("decision_id", decision_id)),
			int(cd.get("seat", -1)),
			cd.get("allowed_actions", []),
			claimed,
			int(cd.get("discarder_seat", -1))
		)
		if ctx == null:
			return null
		if claimed != Tile.INVALID_INSTANCE_ID and not by_iid.has(claimed):
			return null
		if not win.add_context(ctx):
			return null
	for intent_raw in win_d.get("intents", []) as Array:
		if typeof(intent_raw) != TYPE_DICTIONARY:
			return null
		var act: Action = Action.from_dict(intent_raw)
		if act == null:
			return null
		if not win.register_intent(act):
			return null
	return win


# ---- canonical JSON（允许 float，供内部 sha 使用） ----
# Dictionary 键：允许 TYPE_INT / TYPE_STRING；规范化为 JSON wire 键名
# （int 0 → "0"）。同一 Dictionary 内 wire 键冲突（如同时含 0 与 "0"）→
# 返回 null（sha256 空串），任意嵌套均向上传播；不得静默丢键/覆盖/崩溃。

static func _canonical_json(v: Variant) -> Variant:
	match typeof(v):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_INT:
			return str(int(v))
		TYPE_FLOAT:
			# 稳定十进制：避免 float 哈希抖动
			return JSON.stringify(v)
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
			var dict: Dictionary = v
			# wire 名 → 原始键（用于取值）；仅 string 键的 map，避免 int/string 混淆
			var orig_by_wire: Dictionary = {}
			var wire_keys: Array = []
			for k in dict.keys():
				var wire: String = ""
				match typeof(k):
					TYPE_STRING:
						wire = k as String
					TYPE_INT:
						wire = str(int(k))
					_:
						# 非 int/string 键：严格拒绝
						return null
				if orig_by_wire.has(wire):
					# wire 键冲突（例如 0 与 "0"）：拒绝，不得覆盖
					return null
				orig_by_wire[wire] = k
				wire_keys.append(wire)
			wire_keys.sort()
			var parts2: PackedStringArray = PackedStringArray()
			for wire in wire_keys:
				var orig_key: Variant = orig_by_wire[wire]
				var c2: Variant = _canonical_json(dict[orig_key])
				if c2 == null:
					return null
				parts2.append(JSON.stringify(wire) + ":" + str(c2))
			return "{" + ",".join(parts2) + "}"
		_:
			return null
