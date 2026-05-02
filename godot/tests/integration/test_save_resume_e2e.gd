extends GutTest

# 麻将王 — M5 第 4 步：存档恢复 e2e 集成测试
#
# 模拟 RunFlow 启动 → 玩 N 节点 → 退出 → 重启 → 继续。
# 不实例化 RunFlow（UI），直接模拟其状态机的存读路径。

func _save_system() -> Node:
	return get_tree().root.get_node_or_null("SaveSystem")

func before_each() -> void:
	var ss := _save_system()
	if ss:
		ss.clear_run()

func after_each() -> void:
	var ss := _save_system()
	if ss:
		ss.clear_run()

# ---- 启动检测 ----

func test_initial_no_save_means_show_starter_picker():
	# 模拟 RunFlow._ready 的判断逻辑
	var ss := _save_system()
	assert_false(ss.has_save())

func test_after_new_run_save_exists():
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_control")
	var ss := _save_system()
	ss.save_run(rs)
	assert_true(ss.has_save())

# ---- save → load → continue 完整路径 ----

func test_save_load_continue_preserves_state():
	# 玩家创建 Run（M6 后 apply_to 会注入 control pack 牌；本测试覆盖同 TileId
	# 验证 add 同 TileId 覆盖；count 仍是 pack_size）
	var rs1 := RunState.new(42)
	StarterPacks.apply_to(rs1, &"starter_control")
	var pack_size: int = rs1.player_deck.tile_variant_count()

	# 走几步：选 entry，加点假抽卡
	rs1.choose_next_node(rs1.current_map.entry_node)
	rs1.gold = 75
	# 用 TileId.W1（control pack 已有 xray_1w_v1）以覆盖；count 不变
	var v := TileVariant.new(&"saved_tile", TileId.W1, Rarity.Kind.UNCOMMON)
	v.display_name = "保存测试"
	rs1.player_deck.add_tile_variant(v)
	rs1.pity_state.record_draw(Rarity.Kind.COMMON)
	rs1.pity_state.record_draw(Rarity.Kind.COMMON)
	rs1.pity_state.record_draw(Rarity.Kind.COMMON)

	# 模拟 RunFlow 在每节点完成时存档
	var ss := _save_system()
	ss.save_run(rs1)

	# 模拟玩家退出 / 重启
	assert_true(ss.has_save())
	var rs2 = ss.load_run()
	assert_not_null(rs2)

	# 验证：所有关键状态都跨重启保留
	assert_eq(rs2.run_seed, 42)
	assert_eq(rs2.gold, 75)
	assert_eq(rs2.current_map.current_node, rs1.current_map.entry_node)
	assert_eq(rs2.player_deck.tile_variant_count(), pack_size, "deck size 跨重启保留")
	assert_eq(rs2.player_deck.get_tile_variant(TileId.W1).display_name, "保存测试")
	assert_eq(rs2.pity_state.node_single_no_epic_streak, 3)

# ---- 失败 / 通关 后清档 ----

func test_run_failed_clears_save():
	var rs := RunState.new(42)
	var ss := _save_system()
	ss.save_run(rs)
	assert_true(ss.has_save())

	# 模拟 RunFlow._on_run_failed 的清档逻辑
	ss.clear_run()
	assert_false(ss.has_save())

# ---- 损坏存档 fallback ----

func test_load_corrupted_returns_null_safely():
	# 模拟"存档文件 JSON 解析失败"——直接写一个非法 JSON 文件
	var file := FileAccess.open("user://savegame.json", FileAccess.WRITE)
	assert_not_null(file)
	file.store_string("{ this is not valid json")
	file.close()
	var ss := _save_system()
	assert_true(ss.has_save(), "文件存在但内容损坏")
	var rs = ss.load_run()
	assert_null(rs, "损坏存档 load_run 应返 null")
	# RunFlow 会因此 fallback 到 _on_new_run_after_clear，调 clear_run 后 OK
	ss.clear_run()
	assert_false(ss.has_save())

# ---- ContinuePrompt 摘要文案 ----

func test_continue_prompt_summary_contains_chapter():
	var rs := RunState.new(42)
	rs.chapter = 2
	rs.hp = 3
	rs.gold = 80
	var s: String = ContinuePrompt.format_save_summary(rs)
	assert_true(s.find("Chapter 2") >= 0)
	assert_true(s.find("HP 3") >= 0)
	assert_true(s.find("80") >= 0)

func test_continue_prompt_summary_null_safe():
	assert_eq(ContinuePrompt.format_save_summary(null), "无效存档")
