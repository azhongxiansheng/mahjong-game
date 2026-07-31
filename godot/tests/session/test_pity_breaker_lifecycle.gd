extends GutTest

# 天命打破（relic_pity_breaker_v1）跨局充能语义（2026-07-28 spec §5.3）。
# 连续未胡计数存 ItemInventoryModule（会话内部，不进 wire schema）；
# prepare_new_hand 重建 relic 技能时注入 pity_charged / pity_extra_han。

const PITY := "relic_pity_breaker_v1"


func _inv() -> ItemInventoryModule:
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace("m-pity")
	return inv


func _grant(inv: ItemInventoryModule, seat: int, window_id: String) -> String:
	var granted: Dictionary = inv.grant_for_seat({
		"seat": seat,
		"item_id": PITY,
		"window_id": window_id,
		"hand_seq": 0,
		"score": 0,
	})
	assert_true(bool(granted.get("ok", false)), str(granted))
	return String((granted["payload"] as Dictionary)["item_instance_id"])


func test_miss_counts_increment_and_reset_on_owner_win():
	var inv := _inv()
	var iid := _grant(inv, 0, "w1")
	inv.pity_record_hand_completed([1])
	assert_eq(inv.pity_miss_count(iid), 1, "他家胡牌计 1 局未胡")
	inv.pity_record_hand_completed([])
	assert_eq(inv.pity_miss_count(iid), 2, "流局也计 1 局未胡")
	inv.pity_record_hand_completed([0])
	assert_eq(inv.pity_miss_count(iid), 0, "owner 胡牌后全部重置")


func test_capture_restore_roundtrip_keeps_pity_counts():
	var inv := _inv()
	var iid := _grant(inv, 0, "w1")
	inv.pity_record_hand_completed([1])
	inv.pity_record_hand_completed([2])
	var snap: Dictionary = inv.capture_state()
	inv.pity_record_hand_completed([3])
	assert_eq(inv.pity_miss_count(iid), 3)
	assert_true(inv.restore_state(snap))
	assert_eq(inv.pity_miss_count(iid), 2, "restore 应还原计数")


func test_prepare_new_hand_injects_charge_and_single_aggregate_extra_han():
	var bc := BattleController.new(42, 0, false, TileId.E)
	var inv := _inv()
	var iid_a := _grant(inv, 0, "w1")
	var iid_b := _grant(inv, 0, "w2")
	inv.pity_record_hand_completed([1])
	inv.pity_record_hand_completed([2])
	var prep: Dictionary = ItemAuthority.prepare_new_hand(bc, inv, [])
	assert_true(bool(prep.get("ok", false)), str(prep))
	var sk_a: SkillResource = inv.registered_skill(iid_a)
	var sk_b: SkillResource = inv.registered_skill(iid_b)
	assert_not_null(sk_a)
	assert_not_null(sk_b)
	assert_true(bool(sk_a.params.get("pity_charged", false)), "两局未胡应充能")
	assert_true(bool(sk_b.params.get("pity_charged", false)))
	# N=2 件充能 → 追加 N-1=1 番，由字典序最小实例统一施加
	var extras: Array = [
		int(sk_a.params.get("pity_extra_han", -1)),
		int(sk_b.params.get("pity_extra_han", -1)),
	]
	extras.sort()
	assert_eq(extras, [0, 1], "聚合追加番只落在一个实例上")
	var smallest: String = iid_a if iid_a < iid_b else iid_b
	assert_eq(int(inv.registered_skill(smallest).params.get("pity_extra_han", -1)), 1)


func test_prepare_new_hand_uncharged_below_two_misses():
	var bc := BattleController.new(42, 0, false, TileId.E)
	var inv := _inv()
	var iid := _grant(inv, 0, "w1")
	inv.pity_record_hand_completed([1])
	var prep: Dictionary = ItemAuthority.prepare_new_hand(bc, inv, [])
	assert_true(bool(prep.get("ok", false)))
	var sk: SkillResource = inv.registered_skill(iid)
	assert_not_null(sk)
	assert_false(bool(sk.params.get("pity_charged", true)), "仅 1 局未胡不充能")
	assert_eq(int(sk.params.get("pity_extra_han", -1)), 0)
