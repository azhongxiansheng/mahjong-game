extends GutTest

# 道具 L0/L1 规则对齐批：即时消耗品失败的使用不消耗实例（2026-07-28 spec §2.1）。
# 以牌墙崩塌为例：活牌墙将低于 14 张时权威拒绝 ITEM_USE，实例保持 held。

const CMD_A := "550e8400-e29b-41d4-a716-000000000001"
const CMD_B := "550e8400-e29b-41d4-a716-000000000002"


func _grant(inv: ItemInventoryModule, item_id: String) -> String:
	var granted: Dictionary = inv.grant_for_seat({
		"seat": 0,
		"item_id": item_id,
		"window_id": "w1",
		"hand_seq": 0,
		"score": 0,
	})
	assert_true(bool(granted.get("ok", false)))
	return String((granted["payload"] as Dictionary)["item_instance_id"])


func test_wall_collapse_use_rejected_keeps_instance_held():
	var bc := BattleController.new(42, 0, false, TileId.E)
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace("m-guard")
	var iid := _grant(inv, "wall_collapse_v1")
	# 把活牌墙抽到 19 张：移除 6 张会低于 14 → 必须拒绝
	while bc.state.wall.live_wall_size() > 19:
		bc.state.wall.draw()
	var res: Dictionary = ItemAuthority.use_item(bc, inv, 0, iid, CMD_A)
	assert_false(bool(res.get("accepted", true)), "低于安全余量应拒绝")
	assert_eq(bc.state.wall.live_wall_size(), 19, "拒绝时不得移除任何牌")
	var inst: ItemInstance = inv.find_instance(iid)
	assert_not_null(inst)
	assert_eq(inst.status, ItemInstance.STATUS_HELD, "失败的使用不消耗实例")


func test_wall_collapse_use_accepted_consumes_and_removes_six():
	var bc := BattleController.new(42, 0, false, TileId.E)
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace("m-ok")
	var iid := _grant(inv, "wall_collapse_v1")
	var before: int = bc.state.wall.live_wall_size()
	var res: Dictionary = ItemAuthority.use_item(bc, inv, 0, iid, CMD_B)
	assert_true(bool(res.get("accepted", false)))
	assert_eq(bc.state.wall.live_wall_size(), before - 6)
	# 消耗后实例从库存移除（库存只投影 GRANTED/CONSUMED）
	assert_null(inv.find_instance(iid), "成功使用后实例应被消耗移除")
