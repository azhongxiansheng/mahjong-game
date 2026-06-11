extends GutTest

# T5(spec 2026-06-11 G5-b)— DiscardRiver 增量渲染。
# 关键不变量:前缀不变只 append(旧节点实例存活,入场动画不被打断);
# 缩水/立直回溯/dora 变化走全量 rebuild 兜底。

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
	for child in _river.get_children():
		if child is TextureRect:
			return child
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

func test_dora_change_rebuilds_for_gold_border():
	_river.set_tiles(_tiles([TileId.W5]))
	var first := _first_tile_node()
	_river.set_dora_ids([TileId.W5])  # 杠翻出新指示牌,W5 变宝牌
	_river.set_tiles(_tiles([TileId.W5, TileId.T1]))
	await wait_physics_frames(2)
	# 全量重建后 W5 应带金边(borders = panel 节点数 ≥ 2:金边 + 最新高亮)
	var panels := 0
	for child in _river.get_children():
		if child is Panel:
			panels += 1
	assert_true(panels >= 2, "dora 金边 + 最新弃牌高亮都在")
	assert_false(_first_tile_node() == first and is_instance_valid(first),
		"dora 集变化触发全量重算")
