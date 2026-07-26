extends SceneTree

# Issue #326 目视矩阵：真实生产 view API、四槽、同 ID 多实例、armed/disabled。

const LOGICAL_SIZE := Vector2i(1600, 900)


func _initialize() -> void:
	_run()


func _run() -> void:
	root.content_scale_size = LOGICAL_SIZE
	var table = load("res://ui/four_player_table/four_player_table.gd").new()
	root.add_child(table)
	await _frames(8)
	var reward_view := {
		"phase": "OPEN",
		"discard_count": 18,
		"prize_pool": [
			"iron_shield_v1", "dora_charm_v1",
			"relic_lucky_cat_v1", "furiten_bomb_v1",
		],
		"character_ids": ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"],
	}
	var inventory_view := {"seat": 0, "items": [
		{"item_instance_id": "ii_iron_a7f2", "item_id": "iron_shield_v1", "status": "held"},
		{"item_instance_id": "ii_iron_b9d4", "item_id": "iron_shield_v1", "status": "armed", "armed_for_window_id": "window_02"},
		{"item_instance_id": "ii_cat_c1e8", "item_id": "relic_lucky_cat_v1", "status": "held"},
	]}
	table.apply_reward_views(reward_view, inventory_view)
	await _capture(table, Vector2i(1600, 900), false, "armed_compact")
	await _capture(table, Vector2i(1600, 900), true, "armed_inventory_multi")

	# 无真实角色 ID 时必须明确 disabled + unknown seal，不能猜默认角色。
	reward_view["character_ids"] = []
	table.apply_reward_views(reward_view, inventory_view)
	await _capture(table, Vector2i(1280, 720), false, "disabled_compact")
	await _capture(table, Vector2i(1280, 720), true, "disabled_inventory_multi")
	table.queue_free()
	await process_frame
	quit()


func _capture(table: Control, window_size: Vector2i, drawer_open: bool, tag: String) -> void:
	DisplayServer.window_set_size(window_size)
	if drawer_open:
		table.open_inventory_drawer()
	else:
		table.close_inventory_drawer()
	await _frames(12)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "/tmp/shot_table_icon_hud_326_%s_%dx%d.png" % [
		tag, window_size.x, window_size.y,
	]
	image.save_png(path)
	print("[capture-326] ", path, " actual=", image.get_width(), "x", image.get_height())


func _frames(count: int) -> void:
	for _i in range(count):
		await process_frame
