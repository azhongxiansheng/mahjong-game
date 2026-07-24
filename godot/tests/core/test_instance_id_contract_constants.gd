extends GutTest

# E2-02 / #232 P2-2 常量契约 Red（可 Parse Red）。
# 直接断言 Tile.MAX_SAFE_INSTANCE_ID / is_valid_instance_id / Wall.MAX_HAND_SEQ。


func test_tile_max_safe_instance_id_is_js_safe_max() -> void:
	assert_eq(Tile.MAX_SAFE_INSTANCE_ID, 9007199254740991)


func test_is_valid_instance_id_requires_exact_type_int_and_bounds() -> void:
	# 合法边界：0 与 MAX
	assert_true(Tile.is_valid_instance_id(0))
	assert_true(Tile.is_valid_instance_id(Tile.MAX_SAFE_INSTANCE_ID))
	# 非法边界
	assert_false(Tile.is_valid_instance_id(Tile.INVALID_INSTANCE_ID))
	assert_false(Tile.is_valid_instance_id(-2))
	assert_false(Tile.is_valid_instance_id(9007199254740992))
	# 精确 TYPE_INT：非 int 一律 false（参数为 Variant，可直接传入）
	assert_false(Tile.is_valid_instance_id(1.0))
	assert_false(Tile.is_valid_instance_id("1"))
	assert_false(Tile.is_valid_instance_id(true))
	assert_false(Tile.is_valid_instance_id(false))
	assert_false(Tile.is_valid_instance_id(null))


func test_wall_max_hand_seq_legal_and_plus_one_overflows() -> void:
	assert_true(Wall.MAX_HAND_SEQ >= 0)
	var max_iid_at_cap: int = Wall.MAX_HAND_SEQ * 136 + 135
	assert_true(max_iid_at_cap <= Tile.MAX_SAFE_INSTANCE_ID,
		"MAX_HAND_SEQ 合法：最大 serial 仍 ≤ MAX_SAFE_INSTANCE_ID")
	var overflow_iid: int = (Wall.MAX_HAND_SEQ + 1) * 136 + 135
	assert_true(overflow_iid > Tile.MAX_SAFE_INSTANCE_ID,
		"MAX_HAND_SEQ+1 会使 hand_seq*136+135 溢出 safe 上限")


# ---- E. Meld.is_valid_meld_id：exact TYPE_INT + 安全范围 ----

func test_is_valid_meld_id_requires_exact_type_int_and_bounds() -> void:
	assert_true(Meld.is_valid_meld_id(0))
	assert_true(Meld.is_valid_meld_id(Tile.MAX_SAFE_INSTANCE_ID))
	assert_false(Meld.is_valid_meld_id(Tile.INVALID_INSTANCE_ID), "-1 拒")
	assert_false(Meld.is_valid_meld_id(-2), "-2 拒")
	assert_false(Meld.is_valid_meld_id(9007199254740992), "超界拒")
	assert_false(Meld.is_valid_meld_id(1.0))
	assert_false(Meld.is_valid_meld_id("1"))
	assert_false(Meld.is_valid_meld_id(true))
	assert_false(Meld.is_valid_meld_id(false))
	assert_false(Meld.is_valid_meld_id(null))
