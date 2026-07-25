extends GutTest

# E4-04 / #246：奖励反馈投影 — 仅 schema-valid NetworkedEvent；四语义文案。

const ProjScr := preload("res://ui/four_player_table/reward_feedback_projector.gd")
const TableScr := preload("res://ui/four_player_table/four_player_table.gd")

const ROOM := "room_x"
const WINDOW_ID := "hand_3_window_1"
const PRIZE_POOL := ["item_a", "item_b", "item_c", "item_d"]
const VIEW_HASH := "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"


func _env(kind: String, seq: int, payload: Dictionary) -> Dictionary:
	return {
		"protocol_version": 1,
		"server_seq": seq,
		"room_id": ROOM,
		"kind": kind,
		"payload": payload.duplicate(true),
		"view_hash": VIEW_HASH,
	}


func _settled_full(seq: int = 120) -> Dictionary:
	return _env("REWARD_WINDOW_SETTLED", seq, {
		"window_id": WINDOW_ID,
		"outcome": "FULL_GRANT",
		"settle_reason": "FULL_24_NO_WIN",
		"rule_version": "reward_v2",
		"assignment_version": "assign_v1",
		"prize_pool": PRIZE_POOL.duplicate(),
		"matrix_summary": {
			"scores": [
				[1000, 0, 0, 0],
				[0, 1000, 0, 0],
				[0, 0, 1000, 0],
				[0, 0, 0, 1000],
			],
		},
		"assignment": {"0": "item_a", "1": "item_b", "2": "item_c", "3": "item_d"},
		"closing_boundary_server_seq": 110,
		"context_boundary_server_seq": 118,
		"grace_deadline_at": "2026-07-22T12:00:01.500Z",
		"grant_count": 4,
		"hand_seq": 3,
		"transcript_summary": {},
	})


func _settled_display(seq: int = 120) -> Dictionary:
	var base: Dictionary = _settled_full(seq)
	var p: Dictionary = (base["payload"] as Dictionary).duplicate(true)
	p["outcome"] = "DISPLAY_ONLY"
	p["settle_reason"] = "MATCH_END_NO_WIN"
	p["grant_count"] = 0
	return _env("REWARD_WINDOW_SETTLED", seq, p)


func _cancelled(seq: int = 121) -> Dictionary:
	return _env("REWARD_WINDOW_CANCELLED", seq, {
		"window_id": WINDOW_ID,
		"cancel_reason": "CANCELLED_BY_WIN",
		"closing_boundary_server_seq": 110,
		"grace_aborted": true,
		"scored": false,
		"grant_count": 0,
		"hand_seq": 3,
	})


func _item_granted(seat: int = 0, seq: int = 122) -> Dictionary:
	return _env("ITEM_GRANTED", seq, {
		"window_id": WINDOW_ID,
		"rule_version": "reward_v2",
		"assignment_version": "assign_v1",
		"matched_rule_ids": ["stable_rule_id"],
		"item_id": PRIZE_POOL[seat],
		"item_instance_id": "inst_seat_%d" % seat,
		"seat": seat,
		"hand_seq": 3,
		"score": 1000,
		"affinity_match": seat == 0,
		"armed_for_window_id": "hand_3_window_2",
	})


func test_settled_full_grant_waiting_not_granted() -> void:
	var p = ProjScr.new()
	var wire: Dictionary = _settled_full()
	assert_not_null(NetworkedEvent.from_dict(wire), "fixture 必须 schema-valid")
	var r: Dictionary = p.project(wire)
	assert_true(bool(r.get("ok", false)), str(r))
	assert_eq(String(r.get("message", "")), "分配完成，等待到账事件")
	assert_ne(String(r.get("message", "")), "到账")
	assert_false(String(r.get("message", "")).contains("item_a"))


func test_settled_display_only() -> void:
	var p = ProjScr.new()
	var r: Dictionary = p.project(_settled_display())
	assert_true(bool(r.get("ok", false)), str(r))
	assert_eq(String(r.get("message", "")), "仅本场统计，未发放")


func test_cancelled_by_win_no_matrix_leak() -> void:
	var p = ProjScr.new()
	# 合法 cancel wire（schema 不允许夹带 matrix；恶意裸 dict 应 schema 拒绝）
	var r: Dictionary = p.project(_cancelled())
	assert_true(bool(r.get("ok", false)), str(r))
	assert_eq(String(r.get("message", "")), "和牌优先，本窗作废")
	var msg := String(r.get("message", ""))
	assert_false(msg.contains("leaked"))
	assert_false(msg.contains("分配"))
	assert_false(msg.contains("item"))
	assert_false(r.has("matrix_summary"))
	assert_false(r.has("assignment"))

	# 恶意夹带 matrix 的非法 envelope → 拒绝
	var evil: Dictionary = {
		"kind": "REWARD_WINDOW_CANCELLED",
		"payload": {
			"window_id": WINDOW_ID,
			"cancel_reason": "CANCELLED_BY_WIN",
			"matrix_summary": {"scores": [[9]]},
			"assignment": {"0": "leaked_item"},
		},
	}
	var rej: Dictionary = p.project(evil)
	assert_false(bool(rej.get("ok", false)))


func test_item_granted_shows_arrival_only_when_schema_valid() -> void:
	var p = ProjScr.new()
	var wire: Dictionary = _item_granted()
	var ne: NetworkedEvent = NetworkedEvent.from_dict(wire)
	assert_not_null(ne)
	var r: Dictionary = p.project(ne)
	assert_true(bool(r.get("ok", false)), str(r))
	assert_eq(String(r.get("message", "")), "到账")

	# 空/裸 ITEM_GRANTED 必须拒绝
	assert_false(bool(p.project({"kind": "ITEM_GRANTED", "payload": {}}).get("ok", false)))
	assert_false(bool(p.project({"kind": "ITEM_GRANTED"}).get("ok", false)))
	assert_false(bool(p.project({
		"protocol_version": 1, "server_seq": 1, "room_id": "r",
		"kind": "ITEM_GRANTED", "payload": {}, "view_hash": VIEW_HASH,
	}).get("ok", false)))


func test_rejects_bare_dict_and_caption_payload() -> void:
	var p = ProjScr.new()
	assert_false(bool(p.project({}).get("ok", false)))
	assert_false(bool(p.project({
		"kind": "REWARD_WINDOW_SETTLED",
		"payload": {"outcome": "FULL_GRANT"},
	}).get("ok", false)))
	assert_false(bool(p.project({
		"seat": 0, "utterance_id": "x", "text": "hi",
		"kind": "partial", "source": "local_mic", "lang": "zh",
	}).get("ok", false)))
	assert_false(bool(p.project({
		"kind": "REWARD_WINDOW_OPENED",
		"payload": {},
	}).get("ok", false)))


func test_table_banner_schema_gate_and_zero_side_effect_on_reject() -> void:
	var table = TableScr.new()
	add_child_autofree(table)
	await get_tree().process_frame
	# 合法 SETTLED
	var r: Dictionary = table.inject_reward_feedback(_settled_full())
	assert_true(bool(r.get("ok", false)), str(r))
	assert_true(table.reward_feedback_text().contains("分配完成"))
	var banner = table.get_node_or_null("SeatCaptionOverlay/RewardFeedbackBanner")
	assert_not_null(banner)
	assert_eq(banner.mouse_filter, Control.MOUSE_FILTER_IGNORE)

	# 裸 ITEM_GRANTED 不得改 banner
	var before := table.reward_feedback_text()
	var bad: Dictionary = table.inject_reward_feedback({"kind": "ITEM_GRANTED", "payload": {}})
	assert_false(bool(bad.get("ok", false)))
	assert_eq(table.reward_feedback_text(), before, "拒绝不得改 banner")

	# 合法 ITEM_GRANTED 才显示到账
	assert_true(bool(table.inject_reward_feedback(_item_granted()).get("ok", false)))
	assert_eq(table.reward_feedback_text(), "到账")
