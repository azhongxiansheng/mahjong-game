extends GutTest

# Issue #379 Round 6 — 双真实奖励窗：同 item_id 两不同 instance_id
# 入口：RewardWindowModule 公共 open → scoring_close → try_settle FULL_GRANT
#      → ItemAuthority.grant_full_from_settled（生产发放链，非测试直调 grant_for_seat）
# 快速：begin_scoring_close 非 24 弃 path；≤120s

const RULE_VERSION := "trash_talk_rules_v1"
const NOW0 := 1_700_000_000_000
const CHARS := ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"]
# seed=0：window0/1 共享 relic_red_string_v1（探针确认），保证双实例断言无条件逃逸
const SEED := 0


func _open_input(window_index: int, hand_seq: int) -> Dictionary:
	return {
		"seed": SEED,
		"hand_seq": hand_seq,
		"window_index": window_index,
		"rule_version": RULE_VERSION,
		"room_id": "room-379-dual",
		"character_ids": CHARS,
		"language": "zh",
		"participants": ["HUMAN", "HUMAN", "HUMAN", "HUMAN"],
		"public_initial": {
			"hand_seq": hand_seq,
			"dealer_seat": 0,
			"scores": [25000, 25000, 25000, 25000],
		},
	}


func _settle_full_grant(window_index: int, hand_seq: int) -> Dictionary:
	var rw := RewardWindowModule.new()
	var opened: Dictionary = rw.open(_open_input(window_index, hand_seq))
	assert_true(bool(opened.get("ok", false)), "open w%d: %s" % [window_index, str(opened)])
	# 非终场 scoring close → FULL_GRANT（公共 API，无需 24 次 DISCARD 权威服）
	for i in range(4):
		rw.on_discard_applied({
			"server_seq": 10 + i + window_index * 100,
			"seat": i % 4,
			"kind": "DISCARD",
			"now_ms": NOW0,
		})
	var sc: Dictionary = rw.begin_scoring_close({
		"result_server_seq": 50 + window_index,
		"now_ms": NOW0,
		"is_match_end": false,
	})
	assert_true(bool(sc.get("ok", false)), "scoring_close w%d: %s" % [window_index, str(sc)])
	var settled: Dictionary = rw.try_settle({"now_ms": NOW0})
	assert_true(bool(settled.get("ok", false)), "settle w%d: %s" % [window_index, str(settled)])
	assert_eq(String(settled.get("kind", "")), "REWARD_WINDOW_SETTLED")
	var payload: Dictionary = settled["payload"]
	assert_eq(String(payload.get("outcome", "")), "FULL_GRANT")
	assert_eq(int(payload.get("grant_count", 0)), 4)
	assert_eq((payload.get("assignment", {}) as Dictionary).size(), 4)
	return payload


func test_two_real_reward_windows_yield_distinct_instance_ids_same_item_id() -> void:
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace("379-dual-rw")
	var by_item: Dictionary = {} # item_id -> Array[instance_id]
	for wi in [0, 1]:
		var payload: Dictionary = _settle_full_grant(wi, 0)
		var matrix: Array = []
		if payload.has("matrix") and payload["matrix"] is Array:
			matrix = payload["matrix"] as Array
		var next_wid := ItemInventoryModule.next_window_id_same_hand(
			int(payload.get("hand_seq", 0)), wi)
		var granted: Dictionary = ItemAuthority.grant_full_from_settled(
			inv, payload, matrix, CHARS, next_wid, false, "379-dual-rw")
		assert_true(bool(granted.get("ok", false)), "grant_full w%d: %s" % [wi, str(granted)])
		for g in granted.get("grants", []):
			var gp: Dictionary = (g as Dictionary).get("payload", {}) as Dictionary
			var item_id := str(gp.get("item_id", ""))
			var iid := str(gp.get("item_instance_id", ""))
			assert_false(item_id.is_empty())
			assert_false(iid.is_empty())
			if not by_item.has(item_id):
				by_item[item_id] = []
			(by_item[item_id] as Array).append(iid)

	assert_eq(inv.instance_count(), 8, "两窗各 4 授予 → 8 实例")
	# seed=0 探针：relic_red_string_v1 必跨两窗
	assert_true(by_item.has("relic_red_string_v1"),
		"seed=0 须授予 relic_red_string_v1；got %s" % str(by_item.keys()))
	var ids: Array = by_item["relic_red_string_v1"]
	assert_gte(ids.size(), 2, "同 item_id 须来自两个真实窗")
	assert_ne(str(ids[0]), str(ids[1]), "同 item_id 须不同 instance_id")
	assert_not_null(inv.find_instance(str(ids[0])))
	assert_not_null(inv.find_instance(str(ids[1])))
	assert_eq(str(inv.find_instance(str(ids[0])).item_id), "relic_red_string_v1")
	assert_eq(str(inv.find_instance(str(ids[1])).item_id), "relic_red_string_v1")
