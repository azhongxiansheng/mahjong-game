extends GutTest

# T5(spec 2026-06-11 G5-b)— DiscardRiver 增量渲染。
# 关键不变量:前缀不变只 append(旧节点实例存活,入场动画不被打断);
# dora 只更新现有节点金边；缩水/立直回溯走全量 rebuild 兜底。

var _river: DiscardRiver

func before_each() -> void:
	_river = DiscardRiver.new()
	add_child_autofree(_river)

func _tiles(ids: Array) -> Array:
	var out: Array = []
	for tid in ids:
		out.append(Tile.new(tid))
	return out

func _first_tile_node() -> TextureRect:
	for e in _river._tile_nodes:
		var node := e.get("node") as TextureRect
		if node != null and is_instance_valid(node):
			return node
	return null

func test_append_keeps_existing_nodes_alive():
	_river.set_tiles(_tiles([TileId.W1]))
	var first := _first_tile_node()
	assert_not_null(first)
	_river.set_tiles(_tiles([TileId.W1, TileId.T5]))
	assert_true(is_instance_valid(first), "前缀节点不被重建")
	assert_eq(_first_tile_node(), first, "首张牌还是同一实例(增量 append)")
	assert_eq(_river._rendered_ids, [TileId.W1, TileId.T5])

func test_same_state_rebind_is_noop():
	_river.set_tiles(_tiles([TileId.W1, TileId.T5]))
	var first := _first_tile_node()
	# bind_battle_state 每个事件都重调 — 状态没变时节点不动
	_river.set_tiles(_tiles([TileId.W1, TileId.T5]))
	assert_eq(_first_tile_node(), first, "等价 rebind 不重建")

func test_shrink_triggers_full_rebuild():
	_river.set_tiles(_tiles([TileId.W1, TileId.T5, TileId.S9]))
	var first := _first_tile_node()
	# 被鸣走最后一张 → 缩水 → 全量 rebuild
	_river.set_tiles(_tiles([TileId.W1, TileId.T5]))
	await wait_physics_frames(2)  # queue_free 生效
	assert_false(is_instance_valid(first) and first.is_inside_tree() \
		and not first.is_queued_for_deletion(), "缩水后旧节点重建")
	assert_eq(_river._rendered_ids, [TileId.W1, TileId.T5])

func test_equal_size_different_tail_rebuilds():
	# 同帧批处理边界:被鸣走 + 新弃 → 等长但末尾不同
	_river.set_tiles(_tiles([TileId.W1, TileId.T5]))
	_river.set_tiles(_tiles([TileId.W1, TileId.S9]))
	assert_eq(_river._rendered_ids, [TileId.W1, TileId.S9], "末尾不同走 rebuild,状态正确")

func test_riichi_on_new_tile_appends():
	_river.set_tiles(_tiles([TileId.W1]))
	var first := _first_tile_node()
	# 第 2 张弃牌同时是立直宣告牌(idx=1 落在新增区)→ 仍增量
	_river.set_tiles(_tiles([TileId.W1, TileId.T5]), 1)
	assert_eq(_first_tile_node(), first, "立直标记在新增区不触发全量")
	assert_eq(_river._rendered_riichi, 1)

func test_riichi_backdated_rebuilds():
	_river.set_tiles(_tiles([TileId.W1, TileId.T5]))
	# 立直标记回溯到第 0 张(回放/纠错)→ 全量
	_river.set_tiles(_tiles([TileId.W1, TileId.T5]), 0)
	assert_eq(_river._rendered_riichi, 0, "回溯走 rebuild 后状态正确")

func test_dora_change_reconciles_border_without_replaying_old_spring():
	_river.set_tiles(_tiles([TileId.W5]))
	var first := _first_tile_node()
	var first_root := first.get_parent() as Node2D
	for _frame in range(120):
		_river._process(1.0 / 60.0)
	assert_true(_river._enter_animations.is_empty(), "先让首张牌完成入场")
	_river.set_dora_ids([TileId.W5])  # 杠翻出新指示牌,W5 变宝牌
	var dora_borders := _river.find_children("DoraBorder", "Panel", true, false)
	assert_eq(dora_borders.size(), 1, "纯 dora 变化立即原位补金边")
	assert_eq(_first_tile_node(), first, "参考 keyed 弃牌节点不得 remount")
	assert_false(_river._enter_animations.any(func(state: Dictionary):
		return state.get("node") == first_root), "旧牌不得重播 spring")

	_river.set_tiles(_tiles([TileId.W5, TileId.T1]))
	var second := _river._tile_nodes[1].get("node") as TextureRect
	var second_root := second.get_parent() as Node2D
	assert_eq(_first_tile_node(), first, "dora 变化后 append 仍保留旧节点")
	assert_eq(_river._enter_animations.size(), 1, "只给新增弃牌入场")
	assert_eq(_river._enter_animations[0].get("node"), second_root)
	assert_eq(second_root.modulate.a, 0.0)
	assert_eq(second_root.position,
		(second_root.get_meta("row_position") as Vector2) + Vector2(0, 16))
	await get_tree().process_frame
	assert_eq(_river.find_children("LatestGlow", "Panel", true, false).size(), 1,
		"最新弃牌临时高亮仍在")

func test_same_won_indices_append_keeps_existing_visible_node():
	_river.call("set_tiles", _tiles([TileId.W1, TileId.T5]), -1, [0])
	var first_visible := _first_tile_node()
	assert_not_null(first_visible)
	_river.call("set_tiles", _tiles([TileId.W1, TileId.T5, TileId.S9]), -1, [0])
	assert_eq(_first_tile_node(), first_visible,
		"won 集不变且只增尾牌时仍走增量 append")

func test_won_indices_change_rebuilds_and_compacts_visible_nodes():
	_river.set_tiles(_tiles([TileId.W1, TileId.T5, TileId.S9]))
	var first := _first_tile_node()
	_river.call("set_tiles", _tiles([TileId.W1, TileId.T5, TileId.S9]), -1, [0])
	await wait_physics_frames(2)
	assert_false(_first_tile_node() == first and is_instance_valid(first),
		"wonDiscardIndices 改变会重建并跳过原索引")
	assert_eq(_river._tile_nodes.size(), 2)
