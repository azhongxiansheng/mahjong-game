extends GutTest

# E4-04 / #246：公共场本地字幕注入不得驱动真实 RewardWindow / 库存 / ITEM_GRANTED。

const TableScr := preload("res://ui/four_player_table/four_player_table.gd")
const ModelScr := preload("res://ui/four_player_table/seat_caption_model.gd")

const RULE_VERSION := "trash_talk_rules_v1"
const CHARS := ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"]
const ROOM := "room_cap_246"
const SEED := 42
const NOW0 := 1_700_000_000_000
const VIEW_HASH := "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"


func _open_input() -> Dictionary:
	return {
		"seed": SEED,
		"hand_seq": 0,
		"window_index": 0,
		"rule_version": RULE_VERSION,
		"room_id": ROOM,
		"character_ids": CHARS,
		"language": "zh",
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"public_initial": {
			"hand_seq": 0,
			"dealer_seat": 0,
			"scores": [25000, 25000, 25000, 25000],
		},
	}


func test_local_caption_does_not_mutate_reward_window_or_inventory() -> void:
	var rw := RewardWindowModule.new()
	var inv := ItemInventoryModule.new()
	assert_true(bool(rw.open(_open_input()).get("ok", false)))
	var phase0: String = String(rw.phase)
	var pe0: int = rw.public_events_count()
	var disc0: int = rw.discard_count
	var inv0: int = inv.instance_count()

	var model = ModelScr.new()
	assert_true(bool(model.ingest({
		"seat": 0, "utterance_id": "local_utt_1", "text": "公共场本地字幕",
		"kind": "partial", "source": "local_mic", "lang": "zh", "now_ms": NOW0,
	}).get("ok", false)))
	assert_true(bool(model.ingest({
		"seat": 0, "utterance_id": "local_utt_1", "text": "公共场本地字幕 final",
		"kind": "final", "source": "local_mic", "lang": "zh", "now_ms": NOW0 + 100,
	}).get("ok", false)))

	assert_eq(String(rw.phase), phase0)
	assert_eq(rw.public_events_count(), pe0)
	assert_eq(rw.discard_count, disc0)
	assert_eq(inv.instance_count(), inv0)
	assert_true(model.side_effect_event_kinds().is_empty())


func test_table_caption_inject_cannot_produce_item_granted() -> void:
	var rw := RewardWindowModule.new()
	var inv := ItemInventoryModule.new()
	assert_true(bool(rw.open(_open_input()).get("ok", false)))
	var pe0: int = rw.public_events_count()
	var inv0: int = inv.instance_count()
	var phase0: String = String(rw.phase)

	var table = TableScr.new()
	add_child_autofree(table)
	await get_tree().process_frame

	for kind in ["partial", "final"]:
		assert_true(bool(table.inject_caption_display({
			"seat": 1, "utterance_id": "utt_iso_%s" % kind, "text": "本地字幕",
			"kind": kind,
			"source": "local_mic" if kind == "partial" else "server_stt",
			"lang": "zh",
		}).get("ok", false)))

	assert_true(bool(table.inject_ai_caption_display(
		TrashTalkAiLineSelector.select_ai_line({
			"rule_version": RULE_VERSION, "has_first_discard": true,
			"seed": 42, "hand_seq": 1, "window_id": "hand_1_window_0",
			"seat": 2, "discard_server_seq": 17,
			"character_id": "lin_yeche", "language": "zh",
			"public_context_tags": [],
		})
	).get("ok", false)))

	assert_eq(rw.public_events_count(), pe0)
	assert_eq(inv.instance_count(), inv0)
	assert_eq(String(rw.phase), phase0)

	# schema-valid 展示投影不驱动真实 settle
	var settled_wire := {
		"protocol_version": 1, "server_seq": 120, "room_id": ROOM,
		"kind": "REWARD_WINDOW_SETTLED",
		"payload": {
			"window_id": "hand_3_window_1", "outcome": "FULL_GRANT",
			"settle_reason": "FULL_24_NO_WIN", "rule_version": "reward_v2",
			"assignment_version": "assign_v1",
			"prize_pool": ["item_a", "item_b", "item_c", "item_d"],
			"matrix_summary": {"scores": [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]},
			"assignment": {"0": "item_a", "1": "item_b", "2": "item_c", "3": "item_d"},
			"closing_boundary_server_seq": 110, "context_boundary_server_seq": 118,
			"grace_deadline_at": "2026-07-22T12:00:01.500Z",
			"grant_count": 4, "hand_seq": 3, "transcript_summary": {},
		},
		"view_hash": VIEW_HASH,
	}
	assert_true(bool(table.inject_reward_feedback(settled_wire).get("ok", false)))
	assert_eq(rw.public_events_count(), pe0)
	assert_eq(inv.instance_count(), inv0)
	assert_eq(String(rw.phase), RewardWindowModule.PHASE_OPEN)


func test_caption_api_does_not_prefill_reward_utterances() -> void:
	var rw := RewardWindowModule.new()
	assert_true(bool(rw.open(_open_input()).get("ok", false)))
	var table = TableScr.new()
	add_child_autofree(table)
	await get_tree().process_frame
	table.inject_caption_display({
		"seat": 0, "utterance_id": "never_in_rw", "text": "x",
		"kind": "final", "source": "local_mic", "lang": "zh",
	})
	var first: Dictionary = rw.ingest_utterance({
		"seat": 0, "utterance_id": "never_in_rw", "text": "authority",
		"language": "zh", "terminal": true, "ptt_end_server_seq": 10,
	})
	assert_true(bool(first.get("ok", false)), str(first))
	assert_true(bool(first.get("accepted", false)), str(first))
	assert_false(bool(first.get("idempotent", false)))
