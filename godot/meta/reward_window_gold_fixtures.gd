class_name RewardWindowGoldFixtures extends RefCounted

# E5-04 / #252：奖励窗口黄金 fixture。
# expected 全部为硬编码字面值；构造时禁止调用被测实现。

const ASSIGNMENT_VERSION := "assign_v1"
const RULE_VERSION := "trash_talk_rules_v1"
const SEED := 42
const HAND_SEQ := 0
const WINDOW_INDEX := 0
const ROOM := "room_rw_gold"
const CHARS := ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"]

## seed=42 hand=0 window=0 rule_version 下确定性奖池（硬编码）
const GOLD_PRIZE_POOL := [
	"relic_patience_stone_v1",
	"wall_collapse_v1",
	"dora_flip_v1",
	"furiten_bomb_v1",
]
const GOLD_OPEN_DIGEST := "7d51b4dc"

## 全零矩阵 → 字典序最小双射
const GOLD_ZERO_ASSIGNMENT := {
	"0": "dora_charm_v1",
	"1": "double_payout_v1",
	"2": "iron_shield_v1",
	"3": "wall_peek_v1",
}
const GOLD_ZERO_SUM := 0

## 同分多解：seat0/1 对 item_a/item_b 各 100 → 最大和 200，字典序最小
const GOLD_TIE_ASSIGNMENT := {
	"0": "item_a",
	"1": "item_b",
	"2": "item_c",
	"3": "item_d",
}
const GOLD_TIE_SUM := 200


static func all() -> Array:
	return [
		gold_open_pool(),
		gold_zero_assignment(),
		gold_tiebreak_assignment(),
		gold_cancelled_payload(),
	]


static func gold_open_pool() -> Dictionary:
	return {
		"fixture_id": "rw_gold_open_pool_v1",
		"seed": SEED,
		"hand_seq": HAND_SEQ,
		"window_index": WINDOW_INDEX,
		"rule_version": RULE_VERSION,
		"expected_prize_pool": GOLD_PRIZE_POOL.duplicate(),
		"expected_open_digest": GOLD_OPEN_DIGEST,
		"expected_count": 4,
	}


static func gold_zero_assignment() -> Dictionary:
	var pool := [
		"dora_charm_v1",
		"double_payout_v1",
		"iron_shield_v1",
		"wall_peek_v1",
	]
	var matrix: Array = []
	for seat in range(4):
		for item_id in pool:
			matrix.append({
				"seat": seat,
				"item_id": item_id,
				"persona": 0,
				"item_tag": 0,
				"public_context": 0,
				"expression": 0,
				"total_score": 0,
				"matched_rule_ids": [],
			})
	return {
		"fixture_id": "rw_gold_zero_assignment_v1",
		"pool_item_ids": pool,
		"matrix": matrix,
		"expected_assignment": GOLD_ZERO_ASSIGNMENT.duplicate(true),
		"expected_sum": GOLD_ZERO_SUM,
	}


static func gold_tiebreak_assignment() -> Dictionary:
	var pool := ["item_a", "item_b", "item_c", "item_d"]
	var matrix: Array = []
	for seat in range(4):
		for item_id in pool:
			var score := 0
			if seat == 0 and (item_id == "item_b" or item_id == "item_a"):
				score = 100
			elif seat == 1 and (item_id == "item_a" or item_id == "item_b"):
				score = 100
			matrix.append({
				"seat": seat,
				"item_id": item_id,
				"total_score": score,
			})
	return {
		"fixture_id": "rw_gold_tiebreak_assignment_v1",
		"pool_item_ids": pool,
		"matrix": matrix,
		"expected_assignment": GOLD_TIE_ASSIGNMENT.duplicate(true),
		"expected_sum": GOLD_TIE_SUM,
	}


static func gold_cancelled_payload() -> Dictionary:
	return {
		"fixture_id": "rw_gold_cancelled_v1",
		"expected_payload": {
			"window_id": "hand_0_window_0",
			"cancel_reason": "CANCELLED_BY_WIN",
			"closing_boundary_server_seq": null,
			"grace_aborted": false,
			"scored": false,
			"grant_count": 0,
			"hand_seq": 0,
		},
	}


static func stable_digest(value: Variant) -> String:
	return TrashTalkGoldFixtures.stable_digest(value)


static func stable_stringify(value: Variant) -> String:
	return TrashTalkGoldFixtures.stable_stringify(value)
