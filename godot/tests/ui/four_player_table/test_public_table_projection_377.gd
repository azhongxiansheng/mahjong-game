extends GutTest

# #377：committed 公共快照 → 真实牌桌只读投影（本席下方 + 旋转）。
# 生产链：LocalLoopbackServer → NetworkedEvent → PublicCasualNetworkSession/NBC → PlayableTable。

const PlayableScr := preload("res://ui/four_player_table/playable_table.gd")
const ADAPTER_PATH := "res://ui/four_player_table/public_table_projection_adapter.gd"
const ROOM := "room-377-projection"
const CHARS := ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"]
const PARTS := ["HUMAN", "AI", "AI", "AI"]
const DECISION := "550e8400-e29b-41d4-a716-4466554400aa"
const CMD := "550e8400-e29b-41d4-a716-446655440000"

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


func _canonical_iid(tile_id: int, copy_index: int) -> int:
	var idx: int = TileId.ALL.find(tile_id)
	assert_true(idx >= 0)
	return idx * 4 + copy_index


func _tile(tile_id: int, copy_index: int, red := false) -> Dictionary:
	return {
		"instance_id": _canonical_iid(tile_id, copy_index),
		"tile_id": tile_id,
		"is_red_dora": red,
		"owner_seat": copy_index,
	}


func _seat(
	s: int,
	concealed: Array,
	count: int,
	river: Array = [],
	melds: Array = [],
	score: int = 25000,
	riichi := false,
	riichi_idx: int = -1
) -> Dictionary:
	var d := {
		"seat": s,
		"seat_wind": [TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N][s],
		"score": score,
		"concealed_tiles": concealed.duplicate(true),
		"concealed_count": count,
		"last_drawn_tile_instance_id": -1,
		"river": river.duplicate(true),
		"melds": melds.duplicate(true),
		"riichi_declared": riichi,
		"riichi_double": false,
		"riichi_discard_index": riichi_idx,
	}
	assert_eq(d.keys().size(), SEAT_KEYS.size())
	return d


func _chi_meld(from_seat: int = 0) -> Dictionary:
	var w1 := _tile(TileId.W1, 1)
	var w2 := _tile(TileId.W2, 1)
	var w3 := _tile(TileId.W3, 0)
	return {
		"meld_id": 1, "kind": "CHI", "from_seat": from_seat,
		"called_tile_instance_id": int(w3["instance_id"]),
		"added_tile_instance_id": -1,
		"tiles": [w1, w2, w3],
	}


func _core(
	recip: int,
	phase := "DRAW",
	wall := 70,
	honba := 1,
	sticks := 2,
	dealer := 0,
	round_wind: int = TileId.E,
	hand_number: int = 1
) -> Dictionary:
	# 本席两张可见：赤五(copy0) + 同值普通五(copy1)；他席仅 count；seat1 有副露；各席有河。
	# 全局 instance_id 唯一：河用 W4、副露用 W1-3、dora 用 S1、手牌用 W5×2。
	var own_a := _tile(TileId.W5, 0, true)
	var own_b := _tile(TileId.W5, 1, false)
	var seats: Array = []
	for s in range(4):
		var river: Array = [_tile(TileId.W4, s)]
		var melds: Array = [_chi_meld(0)] if s == 1 else []
		if s == recip:
			seats.append(_seat(s, [own_a, own_b], 2, river, melds, 26000 + s * 100, false, -1))
		else:
			seats.append(_seat(s, [], 13, river, melds, 25000 + s * 100, s == 2, 0 if s == 2 else -1))
	var p := {
		"recipient_seat": recip,
		"hand_seq": 0,
		"dealer_seat": dealer,
		"current_seat": recip,
		"phase": phase,
		"round_wind": round_wind,
		"hand_number": hand_number,
		"honba": honba,
		"riichi_sticks": sticks,
		"live_wall_count": wall,
		"dora_indicators": [_tile(TileId.S1, 0)],
		"seats": seats,
	}
	assert_eq(p.keys().size(), CORE_KEYS.size())
	return p


func _meta_mod(
	chars: Array = CHARS,
	parts: Array = PARTS
) -> Dictionary:
	return MatchingMetaSnapshotProvider.fixture_module(chars, parts)


func _snap(seq: int, recip: int, core: Dictionary = {}, modules: Array = []) -> Dictionary:
	var c: Dictionary = core if not core.is_empty() else _core(recip)
	var mods: Array = modules if not modules.is_empty() else [
		{"module_key": "core_table", "schema_version": 1, "payload": c.duplicate(true)},
		_meta_mod(),
	]
	return {
		"snapshot_server_seq": seq,
		"next_server_seq": seq + 1,
		"seat_view": recip,
		"modules": mods,
	}


func _rs(seq: int, payload: Dictionary, room := ROOM) -> NetworkedEvent:
	var h := ProtocolViewCodec.compute_view_hash(payload)
	var ne := NetworkedEvent.make("ROOM_SNAPSHOT", seq, room, payload, h)
	assert_not_null(ne, "ROOM_SNAPSHOT 须合法")
	return ne


func _tp(seq: int, vh: String, seat: int, hand_tile: Dictionary, room := ROOM) -> NetworkedEvent:
	var p := {
		"hand_seq": 0,
		"decision_id": DECISION,
		"seat": seat,
		"hand": [hand_tile],
		"last_drawn_tile_instance_id": -1,
		"allowed_actions": [{
			"kind": "DISCARD",
			"payload_options": [{"tile_instance_id": int(hand_tile["instance_id"])}],
		}],
	}
	var ne := NetworkedEvent.make("TURN_PROMPT", seq, room, p, vh)
	assert_not_null(ne, "TURN_PROMPT 须合法")
	return ne


func _aa(seq: int, vh: String, actor_seat: int = 0, room := ROOM) -> NetworkedEvent:
	var p := {
		"causation_command_id": CMD, "hand_seq": 0, "decision_id": DECISION,
		"seat": actor_seat, "action_kind": "PASS", "resolved_payload": {},
	}
	var ne := NetworkedEvent.make("ACTION_APPLIED", seq, room, p, vh)
	assert_not_null(ne)
	return ne


func _claim_window(seq: int, vh: String, discarded_by: int) -> NetworkedEvent:
	var discarded := _tile(TileId.W4, discarded_by)
	var p := {
		"hand_seq": 0,
		"decision_id": DECISION,
		"discarded_by_seat": discarded_by,
		"discarded_tile": discarded,
		"allowed_actions": [
			{"kind": "PASS", "payload_options": [{}]},
			{"kind": "RON", "payload_options": [{}]},
		],
	}
	var ne := NetworkedEvent.make("CLAIM_WINDOW", seq, ROOM, p, vh)
	return ne


## 与 test_decision_window_protocol 同形：顶层 KAN + kan_kind 子型
func _full_turn_prompt(seq: int, vh: String, seat: int = 0, room := ROOM) -> NetworkedEvent:
	# 避免与 core 默认 dora(S1c0)/河(W4)/副露(W1-3) instance 冲突
	var t0 := _tile(TileId.W1, 0)
	var t1 := _tile(TileId.S2, 0)
	var a0 := _tile(TileId.W5, 0, true)
	var a1 := _tile(TileId.W5, 1)
	var a2 := _tile(TileId.W5, 2)
	var a3 := _tile(TileId.W5, 3)
	var added := _tile(TileId.HAKU, 0)
	var t0_iid: int = int(t0["instance_id"])
	var t1_iid: int = int(t1["instance_id"])
	var a0_iid: int = int(a0["instance_id"])
	var a1_iid: int = int(a1["instance_id"])
	var a2_iid: int = int(a2["instance_id"])
	var a3_iid: int = int(a3["instance_id"])
	var added_iid: int = int(added["instance_id"])
	var p := {
		"hand_seq": 0,
		"decision_id": DECISION,
		"seat": seat,
		"hand": [t0, t1, a0, a1, a2, a3, added],
		"last_drawn_tile_instance_id": t1_iid,
		"allowed_actions": [
			{
				"kind": "DISCARD",
				"payload_options": [
					{"tile_instance_id": t0_iid},
					{"tile_instance_id": t1_iid},
				],
			},
			{"kind": "RIICHI", "payload_options": [{"tile_instance_id": t1_iid}]},
			{
				"kind": "KAN",
				"payload_options": [
					{
						"kan_kind": "ANKAN",
						"tile_instance_ids": [a0_iid, a1_iid, a2_iid, a3_iid],
					},
					{
						"kan_kind": "ADDED_KAN",
						"meld_id": 1,
						"added_tile_instance_id": added_iid,
					},
				],
			},
			{"kind": "TSUMO", "payload_options": [{}]},
			{
				"kind": "DECLARE_ABORTIVE_DRAW",
				"payload_options": [{"reason": "KYUUSYU_KYUUHAI"}],
			},
		],
	}
	var ne := NetworkedEvent.make("TURN_PROMPT", seq, room, p, vh)
	assert_not_null(ne, "全合法 TURN_PROMPT 须通过 NetworkedEvent.make")
	return ne


func _full_claim_window(seq: int, vh: String, discarded_by: int, room := ROOM) -> NetworkedEvent:
	var discarded := _tile(TileId.W5, 0, true)
	var chi_a := _tile(TileId.W4, 0)
	var chi_b := _tile(TileId.W6, 0)
	var w5_1 := _tile(TileId.W5, 1)
	var w5_2 := _tile(TileId.W5, 2)
	var w5_3 := _tile(TileId.W5, 3)
	var p := {
		"hand_seq": 0,
		"decision_id": DECISION,
		"discarded_by_seat": discarded_by,
		"discarded_tile": discarded,
		"allowed_actions": [
			{"kind": "PASS", "payload_options": [{}]},
			{
				"kind": "CHI",
				"payload_options": [{
					"companion_tile_instance_ids": [
						int(chi_a["instance_id"]), int(chi_b["instance_id"]),
					],
				}],
			},
			{
				"kind": "PON",
				"payload_options": [{
					"companion_tile_instance_ids": [
						int(w5_1["instance_id"]), int(w5_2["instance_id"]),
					],
				}],
			},
			{
				"kind": "KAN",
				"payload_options": [{
					"kan_kind": "MINKAN",
					"companion_tile_instance_ids": [
						int(w5_1["instance_id"]),
						int(w5_2["instance_id"]),
						int(w5_3["instance_id"]),
					],
				}],
			},
			{"kind": "RON", "payload_options": [{}]},
		],
	}
	var ne := NetworkedEvent.make("CLAIM_WINDOW", seq, room, p, vh)
	assert_not_null(ne, "全合法 CLAIM_WINDOW 须通过 NetworkedEvent.make")
	return ne


## 本席手牌含 TURN fixture 实体，便于 dim 可见
func _core_with_turn_hand(recip: int) -> Dictionary:
	var core := _core(recip, "DISCARD", 70)
	var seats: Array = core["seats"]
	var own := seats[recip] as Dictionary
	own["concealed_tiles"] = [
		_tile(TileId.W1, 0),
		_tile(TileId.S2, 0),
		_tile(TileId.W5, 0, true),
		_tile(TileId.W5, 1),
		_tile(TileId.W5, 2),
		_tile(TileId.W5, 3),
		_tile(TileId.HAKU, 0),
	]
	own["concealed_count"] = 7
	own["last_drawn_tile_instance_id"] = int(_tile(TileId.S2, 0)["instance_id"])
	seats[recip] = own
	core["seats"] = seats
	return core


func _pair() -> Array:
	var table = PlayableScr.new()
	add_child_autofree(table)
	await get_tree().process_frame
	# 生产场景：完整 PlayableTable 内嵌 FourPlayerTable
	if table._table == null:
		var fpt = load("res://ui/four_player_table/four_player_table.gd").new()
		table.add_child(fpt)
		table._table = fpt
		await get_tree().process_frame
	return [table, table._table]


func _bind_public(table: Node, nbc: NetworkedBattleController, seat: int, room := ROOM) -> PublicCasualNetworkSession:
	var sess := PublicCasualNetworkSession.new()
	add_child_autofree(sess)
	sess.room_id = room
	sess.seat = seat
	sess.session_id = "guest-377"
	sess.worker_url = "ws://127.0.0.1:9"
	sess.room_token = "tok-377"
	sess.nbc = nbc
	# 生产路径：bridge 绑定 NBC（不直连 ingest）
	sess.seq_bridge.bind_networked_controller(nbc)
	sess.bind_playable_table(table)
	return sess


func _feed_wire(sess: PublicCasualNetworkSession, ne: NetworkedEvent) -> void:
	assert_not_null(ne)
	var text := JSON.stringify(ne.to_dict())
	if sess.has_method("ingest_authority_wire_for_test"):
		sess.ingest_authority_wire_for_test(text)
	else:
		sess._on_game_text(text)


func _release(sess: PublicCasualNetworkSession, table: Node) -> void:
	if table != null and is_instance_valid(table):
		if table.get("_public_reward_session") == sess:
			table._reward_sync_active = false
			if table.has_method("_disconnect_public_transcript"):
				table._disconnect_public_transcript()
			table._public_reward_session = null
	if sess != null and is_instance_valid(sess):
		sess.release()


func _sync_public(table: Node) -> void:
	if table.has_method("sync_public_table_projection"):
		table.sync_public_table_projection()
	elif table.has_method("_sync_reward_feedback_if_advanced"):
		table._sync_reward_feedback_if_advanced()
	await get_tree().process_frame


func _ingest_stream(nbc: NetworkedBattleController, events: Array) -> void:
	for ev in events:
		assert_true(nbc.ingest_networked_event(ev), "ingest %s" % str(ev.kind if ev is NetworkedEvent else ev))


func _loopback_journal(seat: int) -> Array:
	var cfg := GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PUBLIC_CASUAL,
		GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_STANDARD,
		PARTS,
		CHARS,
		77,
		"sid-377-%d" % seat,
		"rv-377"
	)
	assert_not_null(cfg)
	var server := LocalLoopbackServer.new(cfg, 0)
	assert_true(server.start(), "LocalLoopbackServer.start")
	return server.event_journal(seat)


func _rel(abs_seat: int, recip: int) -> int:
	return (abs_seat - recip + 4) % 4


# ── 1) 座位旋转：本席永远在下方 ─────────────────────────────

func _adapter_script() -> GDScript:
	if not ResourceLoader.exists(ADAPTER_PATH):
		return null
	return load(ADAPTER_PATH) as GDScript


func test_relative_seat_mapping_for_all_recipients() -> void:
	var AdapterScr: GDScript = _adapter_script()
	assert_not_null(AdapterScr, "须存在只读投影 adapter: %s" % ADAPTER_PATH)
	if AdapterScr == null:
		return
	for recip in range(4):
		for abs_s in range(4):
			var rel: int = AdapterScr.relative_seat(abs_s, recip)
			assert_eq(rel, (abs_s - recip + 4) % 4, "recip=%d abs=%d" % [recip, abs_s])
			assert_eq(AdapterScr.absolute_seat(rel, recip), abs_s)
		assert_eq(AdapterScr.relative_seat(recip, recip), 0, "本席 relative 必须为 0（下方）")


func test_loopback_to_table_rotation_places_self_at_bottom() -> void:
	for recip in range(4):
		var sid := "sid-377-%d" % recip
		var journal: Array = _loopback_journal(recip)
		assert_gte(journal.size(), 1, "seat%d 须有 journal" % recip)
		# LocalLoopback room_id = session_id
		var nbc := NetworkedBattleController.new(sid, recip)
		var pair: Array = await _pair()
		var table = pair[0]
		var fpt = pair[1]
		var sess := _bind_public(table, nbc, recip, sid)
		for ne in journal:
			if ne is NetworkedEvent:
				assert_true(nbc.ingest_networked_event(ne),
					"journal ingest seat%d kind=%s" % [recip, ne.kind])
		await _sync_public(table)
		var core: Dictionary = nbc.get_core_table_view()
		assert_false(core.is_empty(), "须有 committed core_table")
		assert_eq(int(core.get("recipient_seat", -1)), recip)
		# 下方槽 = relative 0 = 本席绝对 seat
		assert_true(fpt.has_method("screen_seat_absolute") or fpt.seat_panels.size() == 4)
		if fpt.has_method("screen_seat_absolute"):
			assert_eq(int(fpt.screen_seat_absolute(0)), recip, "下方绝对 seat 须为本席")
		var bottom = fpt.seat_panels[0]
		var own_count := 0
		for sv in core.get("seats", []):
			if int(sv.get("seat", -1)) == recip:
				own_count = int(sv.get("concealed_count", 0))
				break
		assert_gt(own_count, 0)
		# 本席手牌张数落在下方 panel
		assert_eq(int(bottom.get("_hand_size")), own_count,
			"recip=%d 下方手牌数须等于本席 concealed_count" % recip)
		_release(sess, table)


# ── 2) core_table 字段投影 ─────────────────────────────────

func test_core_table_fields_projected_without_battle_state() -> void:
	var recip := 2
	var core := _core(recip, "DISCARD", 68, 3, 1)
	var payload := _snap(1, recip, core)
	var nbc := NetworkedBattleController.new(ROOM, recip)
	assert_true(nbc.ingest_networked_event(_rs(1, payload)))
	var pair: Array = await _pair()
	var table = pair[0]
	var fpt = pair[1]
	var sess := _bind_public(table, nbc, recip)
	await _sync_public(table)

	assert_true(table.get("_bc") == null, "公共不得启动 _bc")
	assert_false(core.is_empty())
	assert_eq(int(fpt.center_info.get("_honba")), 3)
	assert_eq(int(fpt.center_info.get("_riichi_sticks")), 1)
	assert_eq(int(fpt.center_info.get("_wall_remaining")), 68)
	# 本席可见两张；他席仅 count=13、无正面手牌
	assert_eq(int(fpt.seat_panels[0].get("_hand_size")), 2)
	for rel in range(1, 4):
		assert_eq(int(fpt.seat_panels[rel].get("_hand_size")), 13,
			"他席 rel=%d 只显示暗手数量" % rel)
	# 分数按绝对 seat 旋转后写入相对槽
	for abs_s in range(4):
		var rel := _rel(abs_s, recip)
		var expected_score := 26000 + abs_s * 100 if abs_s == recip else 25000 + abs_s * 100
		assert_eq(int(fpt.seat_panels[rel].get("_score")), expected_score)
	# 当前绝对座位高亮落在相对槽
	var cur_rel := _rel(recip, recip)
	assert_true(bool(fpt.seat_panels[cur_rel].get("_active")))
	_release(sess, table)


# ── 3) 红五 / instance_id / 绝对 from_seat ─────────────────

func test_red_five_and_instance_id_survive_rotation_clicks() -> void:
	var recip := 1
	var core := _core(recip)
	var payload := _snap(1, recip, core)
	var nbc := NetworkedBattleController.new(ROOM, recip)
	assert_true(nbc.ingest_networked_event(_rs(1, payload)))
	var pair: Array = await _pair()
	var table = pair[0]
	var fpt = pair[1]
	var sess := _bind_public(table, nbc, recip)
	await _sync_public(table)

	var red_iid := int(_tile(TileId.W5, 0, true)["instance_id"])
	var plain_iid := int(_tile(TileId.W5, 1, false)["instance_id"])
	assert_ne(red_iid, plain_iid)
	var bottom = fpt.seat_panels[0]
	var found_red := false
	var found_plain := false
	var hand_slots: Array = bottom.get("_hand_slots") if bottom.get("_hand_slots") != null else []
	for slot in hand_slots:
		if slot == null or not is_instance_valid(slot):
			continue
		var iid := int(slot.get_meta("hand_instance_id", Tile.INVALID_INSTANCE_ID))
		if iid == red_iid:
			found_red = true
		if iid == plain_iid:
			found_plain = true
	assert_true(found_red, "红五 instance_id 须保留在下方手牌槽")
	assert_true(found_plain, "同值普通五 instance_id 须保留")
	# 直接以 entity identity 触发点击链
	if table.has_method("_on_player_tile_clicked"):
		table._on_player_tile_clicked(red_iid)
	# 副露 from_seat 保持权威绝对编号（seat1 CHI from 0）
	var abs1_rel := _rel(1, recip)
	var ma = fpt.meld_areas[abs1_rel]
	var melds_v: Array = ma.get("_melds") if ma.get("_melds") != null else []
	assert_false(melds_v.is_empty(), "seat1 相对槽须有副露")
	if not melds_v.is_empty():
		var m0 = melds_v[0]
		assert_eq(int(m0.from_seat), 0, "from_seat 必须仍是绝对 0")
	_release(sess, table)


# ── 4) matching_meta roster 旋转、无私有泄漏 ───────────────

func test_matching_meta_roster_rotates_with_absolute_seats() -> void:
	var recip := 3
	var chars := ["qiu_jue", "lin_yeche", "an_cheng", "bai_touli"]
	var parts := ["AI", "HUMAN", "AI", "AI"]
	var core := _core(recip)
	var payload := _snap(1, recip, core, [
		{"module_key": "core_table", "schema_version": 1, "payload": core.duplicate(true)},
		_meta_mod(chars, parts),
	])
	var nbc := NetworkedBattleController.new(ROOM, recip)
	var pair: Array = await _pair()
	var table = pair[0]
	var fpt = pair[1]
	var sess := _bind_public(table, nbc, recip)
	_feed_wire(sess, _rs(1, payload))
	await _sync_public(table)

	var meta: Dictionary = nbc.get_matching_meta_view()
	assert_eq(meta.get("character_ids"), chars)
	assert_eq(meta.get("participants"), parts)
	for abs_s in range(4):
		var rel := _rel(abs_s, recip)
		var ch: Character = CharacterPool.find(StringName(chars[abs_s]))
		assert_not_null(ch)
		var li = fpt.seat_panels[rel].get("_label_seat_info")
		var label_text := String(li.text) if li != null else ""
		assert_true(label_text.contains(ch.display_name),
			"abs=%d rel=%d 可见名须含 %s，实际=%s" % [abs_s, rel, ch.display_name, label_text])
		var part_s := str(parts[abs_s])
		assert_true(label_text.contains(part_s),
			"abs=%d rel=%d 须可见 %s，实际=%s" % [abs_s, rel, part_s, label_text])
	# 他席不得有 concealed_tiles 正面
	for abs_s2 in range(4):
		if abs_s2 == recip:
			continue
		var sv: Dictionary = (core["seats"] as Array)[abs_s2]
		assert_eq((sv.get("concealed_tiles", []) as Array).size(), 0)
	_release(sess, table)


# ── 5) matched → session room_started_hint → playing ─────────

func test_matched_blocks_until_first_committed_snapshot() -> void:
	var coordinator := PublicMatchCoordinator.new()
	add_child_autofree(coordinator)
	await get_tree().process_frame
	coordinator.consume_ticket_for_test({
		"status": "assigned",
		"round_kind": "EAST",
		"game_mode": "STANDARD",
		"room_id": ROOM,
		"seat": 2,
		"worker": "ws://127.0.0.1:9",
		"room_token": "tok-377",
	})
	var view0 := coordinator.get_view()
	assert_eq(view0.get("state"), "matched")

	var overlay := PublicMatchStatusOverlay.new()
	add_child_autofree(overlay)
	overlay.present(view0)
	assert_true(overlay.is_blocking(), "matched 须全屏阻断")

	# 真实 session wire → room_started_hint → coordinator playing（禁止仅 notify 自证）
	var nbc := NetworkedBattleController.new(ROOM, 2)
	var pair: Array = await _pair()
	var table = pair[0]
	var sess := _bind_public(table, nbc, 2)
	coordinator._session = sess
	if not sess.room_started_hint.is_connected(coordinator._on_room_started_hint):
		sess.room_started_hint.connect(coordinator._on_room_started_hint)
	if not sess.reconnecting.is_connected(coordinator._on_reconnecting):
		sess.reconnecting.connect(coordinator._on_reconnecting)
	if not sess.recovered.is_connected(coordinator._on_recovered):
		sess.recovered.connect(coordinator._on_recovered)
	_feed_wire(sess, _rs(1, _snap(1, 2)))
	await get_tree().process_frame
	var st := str(coordinator.get_view().get("state", ""))
	assert_true(st == "playing" or st == "entered",
		"session room_started_hint 后须 playing/entered，实际=%s" % st)
	overlay.present(coordinator.get_view())
	assert_false(overlay.is_blocking(), "playing 须解除 matched 遮罩")
	_release(sess, table)


# ── 6) 真实 session+bridge：gap timeout resync → 恢复 snapshot ─

func test_session_bridge_gap_resync_then_recover_snapshot() -> void:
	var recip := 0
	var room := "room-377-resync"
	var nbc := NetworkedBattleController.new(room, recip)
	var pair: Array = await _pair()
	var table = pair[0]
	var fpt = pair[1]
	var sess := _bind_public(table, nbc, recip, room)
	var reconnect_count := [0]
	var recovered_count := [0]
	var terminal_count := [0]
	sess.reconnecting.connect(func(_c, _m): reconnect_count[0] += 1)
	sess.recovered.connect(func(): recovered_count[0] += 1)
	sess.terminal_error.connect(func(_c, _m): terminal_count[0] += 1)

	# 基线 snap seq1 via wire
	var core1 := _core(recip, "DRAW", 70)
	_feed_wire(sess, _rs(1, _snap(1, recip, core1), room))
	await _sync_public(table)
	assert_eq(int(fpt.center_info.get("_wall_remaining")), 70)
	assert_false(nbc.resync_required())

	# 缺 seq2：hold 未来 ACTION seq3，tick 超时 → resync
	sess.seq_bridge.set_hold_window_ms(10)
	sess.seq_bridge.set_clock_ms_for_test(0)
	var core_future := _core(recip, "DISCARD", 55)
	var payload_f := _snap(4, recip, core_future)
	var vh_f := ProtocolViewCodec.compute_view_hash(payload_f)
	_feed_wire(sess, _aa(3, vh_f, 0, room))  # held (expected=2)
	assert_false(nbc.resync_required(), "hold 期间尚未 resync")
	sess.seq_bridge.set_clock_ms_for_test(100)
	var tick_r: Dictionary = sess.seq_bridge.tick(100)
	# 生产 poll 观察 tick
	sess._observe_bridge_result(tick_r)
	assert_true(nbc.resync_required(), "gap timeout 须 resync")
	assert_eq(reconnect_count[0], 1, "只发一次 reconnecting")
	assert_eq(terminal_count[0], 0, "resync 不得 terminal")
	await _sync_public(table)
	assert_eq(int(fpt.center_info.get("_wall_remaining")), 70, "冻结最后 committed")

	# 恢复 snap 必须经 session→bridge→NBC（不得直连 NBC）
	var core3 := _core(recip, "DISCARD", 55)
	_feed_wire(sess, _rs(10, _snap(10, recip, core3), room))
	assert_false(nbc.resync_required(), "恢复 snap 须清 resync")
	assert_eq(recovered_count[0], 1)
	await _sync_public(table)
	assert_eq(int(fpt.center_info.get("_wall_remaining")), 55, "新 committed 更新桌面")
	_release(sess, table)


# ── 7) TURN/CLAIM 只读；后续 snapshot 清空 decision ──────────

func test_turn_prompt_decision_view_without_network_command() -> void:
	var recip := 0
	var core := _core(recip)
	var payload := _snap(1, recip, core)
	var vh := ProtocolViewCodec.compute_view_hash(payload)
	var nbc := NetworkedBattleController.new(ROOM, recip)
	var pair: Array = await _pair()
	var table = pair[0]
	var sess := _bind_public(table, nbc, recip)
	_feed_wire(sess, _rs(1, payload))
	var hand_tile := _tile(TileId.W5, 0, true)
	_feed_wire(sess, _tp(2, vh, recip, hand_tile))
	await _sync_public(table)

	var decision: Dictionary = table.get_public_decision_view()
	assert_false(decision.is_empty(), "须有本席 decision view")
	assert_eq(int(decision.get("seat", -1)), recip)
	var allowed: Array = decision.get("allowed_actions", [])
	assert_gte(allowed.size(), 1)
	assert_eq(str(allowed[0].get("kind", "")), "DISCARD")
	# #378：公共 session 暴露 submit_action；无 OPEN peer 时 UI 不得计成功发送
	assert_true(table.get("_bc") == null, "公共不得挂 _bc 命令路径")
	assert_true(sess.has_method("submit_action"), "session 须有 submit_action")
	assert_false(sess.has_method("send_command"), "session 无第二套 send_command")
	assert_false(sess.has_method("submit_item_use"), "ITEM_USE 复用 submit_action，无专用 API")
	# 真实 UI：无 peer 时库存 use + 动作按钮不得形成成功网络发送
	table._on_inventory_use_requested("item-x")
	if table._action_panel != null:
		table._action_panel.player_action_chosen.emit({"action": "skip"})
		if table.has_method("_on_player_tile_clicked"):
			table._on_player_tile_clicked(int(hand_tile["instance_id"]))
	assert_eq(int(table.public_network_command_attempts()), 0)
	# 公共未 start：无 JOIN/READY
	assert_false(sess.is_game_ready_sent())
	_release(sess, table)


func test_turn_prompt_maps_real_kan_riichi_kyuusyu_and_dim_discards() -> void:
	# 协议真实 shape：顶层 KAN + kan_kind；DISCARD 仅部分 tile_instance_id
	var recip := 0
	var core := _core_with_turn_hand(recip)
	var snap_p := _snap(1, recip, core)
	var vh := ProtocolViewCodec.compute_view_hash(snap_p)
	var nbc := NetworkedBattleController.new(ROOM, recip)
	var pair: Array = await _pair()
	var table = pair[0]
	var fpt = pair[1]
	var sess := _bind_public(table, nbc, recip)
	_feed_wire(sess, _rs(1, snap_p))
	var tp := _full_turn_prompt(2, vh, recip)
	assert_not_null(tp)
	_feed_wire(sess, tp)
	await _sync_public(table)

	# decision view 保持权威 payload（未改 kind/instance_id）
	var dv: Dictionary = table.get_public_decision_view()
	assert_false(dv.is_empty())
	var kinds: Array = []
	for o in dv.get("allowed_actions", []):
		kinds.append(str((o as Dictionary).get("kind", "")))
	assert_true(kinds.has("DISCARD"))
	assert_true(kinds.has("RIICHI"))
	assert_true(kinds.has("KAN"))
	assert_true(kinds.has("TSUMO"))
	assert_true(kinds.has("DECLARE_ABORTIVE_DRAW"))
	# 顶层不得出现伪 ANKAN/ADDED_KAN
	assert_false(kinds.has("ANKAN"))
	assert_false(kinds.has("ADDED_KAN"))

	var panel: PlayerActionPanel = table._action_panel
	assert_not_null(panel)
	assert_true(panel.get("_btn_tsumo").visible, "TSUMO 须可见")
	assert_true(panel.get("_btn_ankan").visible, "ANKAN(kan_kind) 须映射为暗杠按钮")
	assert_true(panel.get("_btn_added_kan").visible, "ADDED_KAN(kan_kind) 须映射为加杠按钮")
	assert_true(panel.get("_btn_riichi").visible, "RIICHI 须可见")
	assert_true(panel.get("_btn_kyuusyu").visible, "KYUUSYU_KYUUHAI 须可见")

	# DISCARD 仅 t0/t1 合法；其余手牌 dim
	var allow_t0: int = int(_tile(TileId.W1, 0)["instance_id"])
	var allow_t1: int = int(_tile(TileId.S2, 0)["instance_id"])
	var blocked_w5: int = int(_tile(TileId.W5, 1)["instance_id"])
	var renderer := fpt.get_tile_entity_renderer() as MahjongTable3D
	assert_not_null(renderer, "生产默认入口必须由混合 3D 牌层接收手牌候选状态")
	var saw_allowed := false
	var saw_blocked_dim := false
	for tile_n in renderer._hand_tiles:
		var iid: int = int((tile_n as Tile3D).tile_instance_id)
		if iid == allow_t0 or iid == allow_t1:
			assert_false(tile_n.is_dim(), "合法 DISCARD 实体不得 dim iid=%d" % iid)
			saw_allowed = true
		elif iid == blocked_w5:
			assert_true(tile_n.is_dim(), "非 DISCARD 实体须 dim iid=%d" % iid)
			saw_blocked_dim = true
	assert_true(saw_allowed, "须渲染合法 DISCARD 实体")
	assert_true(saw_blocked_dim, "须 dim 非法 DISCARD 实体")

	assert_true(table.get("_bc") == null)
	assert_true(sess.has_method("submit_action"))
	table._on_inventory_use_requested("x")
	panel.player_action_chosen.emit({"action": "tsumo"})
	# 无 OPEN peer：不得计成功发送
	assert_eq(int(table.public_network_command_attempts()), 0)
	_release(sess, table)


func test_claim_window_maps_minkan_and_discarded_by_seat() -> void:
	var recip := 0
	var discarded_by := 2
	var core := _core(recip, "CLAIM", 70)
	var snap_p := _snap(1, recip, core)
	var vh := ProtocolViewCodec.compute_view_hash(snap_p)
	var nbc := NetworkedBattleController.new(ROOM, recip)
	var pair: Array = await _pair()
	var table = pair[0]
	var sess := _bind_public(table, nbc, recip)
	_feed_wire(sess, _rs(1, snap_p))
	var claim := _full_claim_window(2, vh, discarded_by)
	assert_not_null(claim)
	_feed_wire(sess, claim)
	await _sync_public(table)

	var dv: Dictionary = table.get_public_decision_view()
	assert_eq(int(dv.get("discarded_by_seat", -1)), discarded_by,
		"decision view 保留权威 discarded_by_seat")
	assert_false(dv.has("discarder_seat"), "不得改写/注入 discarder_seat")
	var kinds: Array = []
	for o in dv.get("allowed_actions", []):
		kinds.append(str((o as Dictionary).get("kind", "")))
	assert_true(kinds.has("PASS"))
	assert_true(kinds.has("CHI"))
	assert_true(kinds.has("PON"))
	assert_true(kinds.has("KAN"))
	assert_true(kinds.has("RON"))
	assert_false(kinds.has("MINKAN"), "MINKAN 须在 kan_kind 而非顶层")

	var panel: PlayerActionPanel = table._action_panel
	assert_not_null(panel)
	assert_true(panel.get("_btn_ron").visible, "RON 须可见")
	assert_true(panel.get("_btn_chi").visible, "CHI 须可见")
	assert_true(panel.get("_btn_pon").visible, "PON 须可见")
	assert_true(panel.get("_btn_minkan").visible, "MINKAN(kan_kind) 须映射杠按钮")
	assert_true(panel.get("_btn_skip").visible, "PASS → 跳过")
	assert_eq(int(panel.get("_claim_discarder_seat")), discarded_by,
		"UI 须用 discarded_by_seat 作为权威绝对来源席")

	assert_true(table.get("_bc") == null)
	panel.player_action_chosen.emit({"action": "ron", "discarder_seat": discarded_by})
	# 无 OPEN peer：不得计成功发送
	assert_eq(int(table.public_network_command_attempts()), 0)
	assert_false(sess.has_method("send_command"))
	_release(sess, table)


func test_snapshot_after_prompt_clears_stale_decision() -> void:
	var recip := 0
	var core1 := _core(recip, "DRAW", 70)
	var p1 := _snap(1, recip, core1)
	var vh1 := ProtocolViewCodec.compute_view_hash(p1)
	var nbc := NetworkedBattleController.new(ROOM, recip)
	var pair: Array = await _pair()
	var table = pair[0]
	var sess := _bind_public(table, nbc, recip)
	_feed_wire(sess, _rs(1, p1))
	_feed_wire(sess, _tp(2, vh1, recip, _tile(TileId.W5, 0, true)))
	await _sync_public(table)
	assert_false(table.get_public_decision_view().is_empty(), "prompt 后须有 decision")

	# 后续 committed snapshot（seq 连续 3）闭合窗口；不得因 resync 静默跳过
	var core2 := _core(recip, "DISCARD", 60)
	_feed_wire(sess, _rs(3, _snap(3, recip, core2)))
	await _sync_public(table)
	assert_false(nbc.resync_required(), "后续 snap 须被 session/bridge 接受且 resync=false")
	assert_true(table.get_public_decision_view().is_empty(),
		"后续 ROOM_SNAPSHOT 后 decision 须清空")
	var status := ""
	if table._action_panel != null and table._action_panel.get("_label_status") != null:
		status = str(table._action_panel.get("_label_status").text)
	assert_true(
		status.contains("DISCARD") or status.contains("阶段") or status.contains("等待"),
		"清空后 action 须 idle/phase，实际=%s" % status
	)
	_release(sess, table)


# ── 6b) pending/hash 分叉不更新桌面 ──────────────────────────

func test_pending_hash_fork_does_not_update_table_view() -> void:
	var recip := 0
	var room := "room-377-pending"
	var nbc := NetworkedBattleController.new(room, recip)
	var pair: Array = await _pair()
	var table = pair[0]
	var fpt = pair[1]
	var sess := _bind_public(table, nbc, recip, room)
	var terminal_count := [0]
	sess.terminal_error.connect(func(_c, _m): terminal_count[0] += 1)

	var core1 := _core(recip, "DRAW", 70)
	_feed_wire(sess, _rs(1, _snap(1, recip, core1), room))
	await _sync_public(table)
	assert_eq(int(fpt.center_info.get("_wall_remaining")), 70)
	var hand0 := int(fpt.seat_panels[0].get("_hand_size"))

	# 异 hash ACTION → pending（未提交）；桌面须保持最后 committed
	var core_future := _core(recip, "DISCARD", 40)
	var payload_f := _snap(3, recip, core_future)
	var vh_f := ProtocolViewCodec.compute_view_hash(payload_f)
	_feed_wire(sess, _aa(2, vh_f, 0, room))
	await _sync_public(table)
	assert_eq(int(fpt.center_info.get("_wall_remaining")), 70,
		"pending 不得把未来 wall 投影到桌面")
	assert_eq(int(fpt.seat_panels[0].get("_hand_size")), hand0,
		"pending 不得改本席手牌张数")
	assert_eq(int(nbc.current_seq()), 1, "pending 不得推进 committed seq")
	assert_eq(terminal_count[0], 0, "pending 不得 terminal")
	# decision 不得来自未提交未来态
	assert_true(table.get_public_decision_view().is_empty()
		or int(table.get_public_decision_view().get("seat", -1)) == recip)
	_release(sess, table)


# ── 6c) authority resync + OPEN peer 时 retry 生产链 ──────────

func test_authority_resync_retry_via_overlay_with_open_peer() -> void:
	# 活跃（非 CLOSED）peer 上 authority resync 后，
	# overlay → coordinator.request_retry → session.retry_reconnect 必须能开新连接。
	var room := "room-377-retry-open"
	var nbc := NetworkedBattleController.new(room, 0)
	var pair: Array = await _pair()
	var table = pair[0]
	var fpt = pair[1]
	var sess := _bind_public(table, nbc, 0, room)

	# 基线 committed
	_feed_wire(sess, _rs(1, _snap(1, 0, _core(0, "DRAW", 70)), room))
	await _sync_public(table)
	assert_eq(int(fpt.center_info.get("_wall_remaining")), 70)

	# 注入非 CLOSED peer（CONNECTING），复现旧 retry ERR_BUSY
	var open_peer := WebSocketPeer.new()
	var connect_err: Error = open_peer.connect_to_url(sess.worker_url)
	sess._game_peer = open_peer
	var pre_state: int = open_peer.get_ready_state()
	# 若 OS 立刻 CLOSED，仍通过 close 后立即再 connect 争取 CONNECTING；否则用 state 断言路径
	if pre_state == WebSocketPeer.STATE_CLOSED:
		open_peer = WebSocketPeer.new()
		connect_err = open_peer.connect_to_url("ws://127.0.0.1:65530")
		sess._game_peer = open_peer
		pre_state = open_peer.get_ready_state()
	assert_ne(pre_state, WebSocketPeer.STATE_CLOSED,
		"本测需要非 CLOSED peer 以覆盖 ERR_BUSY；connect_err=%s state=%d" % [error_string(connect_err), pre_state])

	# gap timeout → authority resync
	sess.seq_bridge.set_hold_window_ms(5)
	sess.seq_bridge.set_clock_ms_for_test(0)
	var vh_f := ProtocolViewCodec.compute_view_hash(_snap(4, 0, _core(0, "DISCARD", 40)))
	_feed_wire(sess, _aa(3, vh_f, 0, room))
	sess.seq_bridge.set_clock_ms_for_test(50)
	sess._observe_bridge_result(sess.seq_bridge.tick(50))
	assert_true(nbc.resync_required())
	assert_true(sess._recovering)

	var coordinator := PublicMatchCoordinator.new()
	add_child_autofree(coordinator)
	await get_tree().process_frame
	coordinator._session = sess
	coordinator.consume_connection_fact_for_test(
		&"reconnecting", "RESYNC_REQUIRED", "authority resync required")
	assert_eq(str(coordinator.get_view().get("state")), "reconnecting")
	assert_true(bool(coordinator.get_view().get("can_retry")))

	var overlay := PublicMatchStatusOverlay.new()
	add_child_autofree(overlay)
	overlay.present(coordinator.get_view())
	assert_true(overlay.is_blocking())
	var retry_btn: Button = overlay.find_child("PublicMatchRetryButton", true, false) as Button
	assert_not_null(retry_btn)
	assert_false(retry_btn.disabled)

	# resync 后若实现已关闭 peer，再注入非 CLOSED peer 以覆盖 ERR_BUSY 场景
	if sess._game_peer == null \
			or sess._game_peer.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		var reinject := WebSocketPeer.new()
		reinject.connect_to_url(sess.worker_url)
		sess._game_peer = reinject
		assert_ne(reinject.get_ready_state(), WebSocketPeer.STATE_CLOSED,
			"reinject 须非 CLOSED 以验证 retry 替换")
	var old_peer = sess._game_peer
	var old_state: int = old_peer.get_ready_state()
	assert_ne(old_state, WebSocketPeer.STATE_CLOSED, "retry 前 peer 须非 CLOSED")

	# 生产链：overlay retry_requested → coordinator.request_retry → session.retry_reconnect
	var retry_results: Array = []
	overlay.retry_requested.connect(func():
		retry_results.append(coordinator.request_retry())
	)
	retry_btn.pressed.emit()
	await get_tree().process_frame
	assert_eq(retry_results.size(), 1, "须经 overlay.retry_requested 真实入口")
	assert_true(bool(retry_results[0]),
		"request_retry 须 true（retry_reconnect!=ERR_BUSY）；old_state=%d" % old_state)
	assert_ne(sess._game_peer, old_peer, "须替换为新 game peer")

	await _sync_public(table)
	assert_eq(int(fpt.center_info.get("_wall_remaining")), 70, "retry 后仍冻结 last committed")
	_feed_wire(sess, _rs(10, _snap(10, 0, _core(0, "DISCARD", 55)), room))
	await _sync_public(table)
	assert_false(nbc.resync_required())
	assert_eq(int(fpt.center_info.get("_wall_remaining")), 55)
	_release(sess, table)


func test_claim_window_cleared_by_later_snapshot() -> void:
	var recip := 0
	var core1 := _core(recip, "CLAIM", 70)
	var p1 := _snap(1, recip, core1)
	var vh1 := ProtocolViewCodec.compute_view_hash(p1)
	var nbc := NetworkedBattleController.new(ROOM, recip)
	var pair: Array = await _pair()
	var table = pair[0]
	var sess := _bind_public(table, nbc, recip)
	_feed_wire(sess, _rs(1, p1))
	var claim := _claim_window(2, vh1, 1)
	assert_not_null(claim, "CLAIM_WINDOW 须合法")
	if claim == null:
		_release(sess, table)
		return
	_feed_wire(sess, claim)
	await _sync_public(table)
	assert_false(table.get_public_decision_view().is_empty(), "CLAIM 后须有 decision")
	var core2 := _core(recip, "DRAW", 65)
	_feed_wire(sess, _rs(3, _snap(3, recip, core2)))
	await _sync_public(table)
	assert_false(nbc.resync_required(), "CLAIM 后 snap 不得 resync")
	assert_true(table.get_public_decision_view().is_empty(),
		"CLAIM 后 snapshot 须清空 decision")
	_release(sess, table)


# ── 8) core 字段可见：南场 / dealer / phase ─────────────────

func test_core_fields_south_dealer_phase_visible() -> void:
	var recip := 1
	var core := _core(recip, "DISCARD", 50, 2, 1, 2, TileId.S_WIND, 2)
	var nbc := NetworkedBattleController.new(ROOM, recip)
	var pair: Array = await _pair()
	var table = pair[0]
	var fpt = pair[1]
	var sess := _bind_public(table, nbc, recip)
	_feed_wire(sess, _rs(1, _snap(1, recip, core)))
	await _sync_public(table)

	var round_text := String(fpt.center_info.get_node("VBox/Round").text)
	assert_true(round_text.contains("南"), "南场须显示南，实际=%s" % round_text)
	assert_true(round_text.contains("2"), "南 2 局，实际=%s" % round_text)
	var turn_text := ""
	if fpt.center_info.get("_turn_label") != null:
		turn_text = str(fpt.center_info.get("_turn_label").text)
	assert_true(turn_text.contains("DISCARD") or turn_text.contains("阶段"),
		"phase 须可见，实际=%s" % turn_text)
	# dealer_seat=2 → relative 于 recip1 = (2-1)%4=1 右席显示庄
	var dealer_rel := _rel(2, recip)
	var dealer_lbl_node = fpt.seat_panels[dealer_rel].get("_label_seat_info")
	var dealer_label := String(dealer_lbl_node.text) if dealer_lbl_node != null else ""
	assert_true(dealer_label.contains("庄"),
		"dealer_seat 驱动庄标识 rel=%d 文本=%s" % [dealer_rel, dealer_label])
	_release(sess, table)


# ── 9) 练习场 seat0 不回归 ─────────────────────────────────

func test_practice_seat0_bind_battle_state_still_works() -> void:
	var cfg := GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE,
		GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_STANDARD,
		PARTS,
		CHARS,
		11,
		"practice-377",
		"rv-p"
	)
	assert_not_null(cfg)
	var driver: GameDriver = PracticeSessionLauncher.new().launch(cfg)
	assert_not_null(driver)
	var bc: PlayableBattleController = driver.start_hand() as PlayableBattleController
	assert_not_null(bc)
	var pair: Array = await _pair()
	var table = pair[0]
	var fpt = pair[1]
	fpt.set_local_seat(0)
	fpt.bind_battle_state(bc.state, 0, 4)
	assert_eq(int(fpt.seat_panels[0].get("_hand_size")), bc.state.seats[0].hand.size())
	assert_eq(int(fpt.seat_panels[0].get("_score")), bc.state.seats[0].points)
	# 练习场不启公共 session
	assert_true(table.get("_public_reward_session") == null)
	# 他席标签不强制 HUMAN/AI 公共 flag
	assert_false(bool(fpt.seat_panels[1].get("_public_participant_visible")))
	assert_not_null(bc.state)
