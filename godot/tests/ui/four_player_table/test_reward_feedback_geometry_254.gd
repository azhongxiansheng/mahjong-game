extends GutTest

# E5-06 / #254：1600×900 HUD / 抽屉 / 字幕 / 手牌 / 行动栏 / PTT 几何不冲突。

const TableScr := preload("res://ui/four_player_table/four_player_table.gd")
const OverlayScr := preload("res://ui/four_player_table/seat_caption_overlay.gd")
const DrawerScr := preload("res://ui/four_player_table/item_inventory_drawer.gd")
const HudScr := preload("res://ui/four_player_table/reward_pool_hud.gd")

const VIEW := Vector2(1600.0, 900.0)

# 方案 A（约）：HUD x=480..1120 y=132..224
const HUD_RECT := Rect2(480.0, 132.0, 640.0, 92.0)
# 抽屉 x=1160..1584 y=96..776（底边避开 seat0 手牌 y=778）
const DRAWER_RECT := Rect2(1160.0, 96.0, 424.0, 680.0)
const PTT_RECT := Rect2(1424.0, 820.0, 160.0, 40.0)
const ACTION_RECT := Rect2(
	(1600.0 - 720.0) / 2.0,
	TableLayout.ACTION_BAR_Y,
	720.0,
	PlayerActionPanel.PANEL_H
)
# 自家手牌生产锚点
const SELF_HAND := Rect2(302.0, 778.0, 996.0, 92.0)


func _rects_overlap(a: Rect2, b: Rect2) -> bool:
	return a.intersects(b)


func test_hud_rect_matches_scheme_a() -> void:
	var table = TableScr.new()
	add_child_autofree(table)
	await get_tree().process_frame
	var hud: Control = table.get_node_or_null("RewardPoolHud") as Control
	assert_not_null(hud)
	var r := Rect2(hud.position, hud.size)
	if r.size == Vector2.ZERO:
		r = Rect2(hud.position, hud.custom_minimum_size)
	assert_eq(r.position.x, HUD_RECT.position.x)
	assert_eq(r.position.y, HUD_RECT.position.y)
	assert_eq(r.size.x, HUD_RECT.size.x)
	assert_eq(r.size.y, HUD_RECT.size.y)
	assert_eq(HudScr.HUD_W, 640.0)
	assert_eq(HudScr.HUD_H, 92.0)


func test_drawer_rect_matches_scheme_a_and_default_closed() -> void:
	var table = TableScr.new()
	add_child_autofree(table)
	await get_tree().process_frame
	var drawer: Control = table.get_node_or_null("ItemInventoryDrawer") as Control
	assert_not_null(drawer)
	assert_false(drawer.visible, "抽屉默认关闭")
	table.open_inventory_drawer()
	assert_true(drawer.visible)
	var r := Rect2(drawer.position, drawer.size)
	if r.size == Vector2.ZERO:
		r = Rect2(drawer.position, drawer.custom_minimum_size)
	assert_eq(r.position.x, DRAWER_RECT.position.x)
	assert_eq(r.position.y, DRAWER_RECT.position.y)
	assert_eq(r.size.x, DRAWER_RECT.size.x)
	assert_eq(r.size.y, DRAWER_RECT.size.y)
	assert_eq(DrawerScr.DRAWER_W, 424.0)
	assert_eq(DrawerScr.DRAWER_H, 680.0)


func test_no_overlap_hud_captions_hand_action_ptt() -> void:
	var overlay = OverlayScr.new()
	add_child_autofree(overlay)
	await get_tree().process_frame

	# HUD 不得与四席字幕重叠
	for seat in range(4):
		var cap: Rect2 = overlay.slot_rect(seat)
		assert_false(_rects_overlap(HUD_RECT, cap),
			"HUD 不得与 seat%d 字幕重叠" % seat)

	assert_false(_rects_overlap(HUD_RECT, ACTION_RECT), "HUD 不得遮挡行动栏")
	assert_false(_rects_overlap(HUD_RECT, PTT_RECT), "HUD 不得遮挡 PTT")
	assert_false(_rects_overlap(HUD_RECT, SELF_HAND), "HUD 不得遮挡自家手牌")

	# 抽屉：不挡行动栏 / PTT / 自家手牌；右侧 seat1 字幕允许在打开时被盖住
	assert_false(_rects_overlap(DRAWER_RECT, ACTION_RECT), "抽屉不得遮挡行动栏")
	assert_false(_rects_overlap(DRAWER_RECT, PTT_RECT), "抽屉不得遮挡 PTT")
	assert_false(_rects_overlap(DRAWER_RECT, SELF_HAND), "抽屉不得遮挡自家手牌")
	# seat0 / seat2 / seat3 字幕仍不与抽屉重叠
	for seat in [0, 2, 3]:
		var cap2: Rect2 = overlay.slot_rect(seat)
		assert_false(_rects_overlap(DRAWER_RECT, cap2),
			"抽屉不得与 seat%d 字幕重叠" % seat)

	var table = TableScr.new()
	add_child_autofree(table)
	await get_tree().process_frame
	assert_eq(table.custom_minimum_size.x, VIEW.x)
	assert_eq(table.custom_minimum_size.y, VIEW.y)


func test_drawer_scroll_no_capacity_cap() -> void:
	var table = TableScr.new()
	add_child_autofree(table)
	await get_tree().process_frame
	for i in range(30):
		table.inject_reward_feedback({
			"protocol_version": 1,
			"server_seq": 300 + i,
			"room_id": "room_geo",
			"kind": "ITEM_GRANTED",
			"payload": {
				"window_id": "hand_0_window_0",
				"rule_version": "trash_talk_rules_v1",
				"assignment_version": "assign_v1",
				"matched_rule_ids": [],
				"item_id": "iron_shield_v1",
				"item_instance_id": "ii_geo_%d" % i,
				"seat": 0,
				"hand_seq": 0,
				"score": 0,
				"affinity_match": false,
				"armed_for_window_id": null,
			},
			"view_hash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		})
	assert_eq(table.inventory_count(), 30, "滚动视图不得截断权威实例数")
	table.open_inventory_drawer()
	assert_eq(table.inventory_row_ids().size(), 30)
