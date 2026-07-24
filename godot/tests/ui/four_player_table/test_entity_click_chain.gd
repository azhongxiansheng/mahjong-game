extends GutTest

# E2-02 / #232 Red：Playable/UI 实体点击链契约。
# 玩家动作 identity = Tile.instance_id；tile_id 仅渲染 / 同名 hover。
# 本文件在生产 Green 前应失败（不在此阶段运行）。

const SEAT_PANEL := preload("res://ui/four_player_table/seat_panel.tscn")
const ACTION_PANEL := preload("res://ui/four_player_table/player_action_panel.tscn")


func _click_card(tile: CardTileBack) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	tile._on_gui_input(ev)


func _click_tile3d(tile: Tile3D) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	tile._input_event(null, ev, Vector3.ZERO, Vector3.UP, 0)


func _tile(tid: int, iid: int, red: bool = false) -> Tile:
	return Tile.new(tid, red, 0, iid)


func _hand_with(entries: Array) -> Hand:
	# entries: Array[{id, iid, red?}]
	var h := Hand.new()
	for e in entries:
		h.add(Tile.new(int(e["id"]), bool(e.get("red", false)), 0, int(e["iid"])))
	return h


# ---------------------------------------------------------------------------
# 1) CardTileBack / Tile3D：点击发 instance_id，禁止 tile_id fallback
# ---------------------------------------------------------------------------

func test_card_tile_back_click_emits_instance_id_not_tile_id() -> void:
	var card := CardTileBack.new()
	add_child_autofree(card)
	await get_tree().process_frame
	watch_signals(card)

	# 现有 API 建实体：Tile.instance_id → TileInstance → set_tile_instance
	# 禁止静态 3 参 set_face_up（生产尚未扩参 → parse error）
	var tile := Tile.new(TileId.W5, false, 0, 9001)
	var ti := TileInstance.make(tile, 0)
	card.set_tile_instance(ti)
	assert_eq(card._tile_id, TileId.W5, "tile_id 仍可保存供渲染")
	var stored_iid: Variant = card.get("tile_instance_id")
	assert_true(stored_iid != null, "必须暴露 tile_instance_id 属性（由 Tile.instance_id 写入）")
	if stored_iid == null:
		return
	assert_eq(int(stored_iid), 9001, "必须保存 tile_instance_id")

	card.set_clickable(true)
	_click_card(card)

	assert_signal_emitted(card, "card_clicked")
	var params: Array = get_signal_parameters(card, "card_clicked")
	assert_eq(params.size(), 1)
	assert_eq(int(params[0]), 9001, "card_clicked 必须发 tile_instance_id，绝非 tile_id")
	assert_ne(int(params[0]), TileId.W5,
		"instance_id 与 tile_id 数值不同时不得 fallback 到 tile_id")


func test_card_tile_back_without_valid_instance_id_does_not_emit_action_click() -> void:
	var card := CardTileBack.new()
	add_child_autofree(card)
	await get_tree().process_frame
	watch_signals(card)

	# 无 identity 展示：现有两参 set_face_up（候补条 / 装饰牌）
	card.set_face_up(TileId.W3, false)
	card.set_clickable(true)
	_click_card(card)

	assert_signal_not_emitted(card, "card_clicked",
		"无有效 instance_id 的正面牌不可作为玩家动作提交（不发 click）")


func test_tile3d_click_emits_instance_id_not_tile_id() -> void:
	var t := Tile3D.new()
	add_child_autofree(t)
	await get_tree().process_frame
	watch_signals(t)

	# Green 目标唯一：setup_entity；禁止 4 参 setup / tile_id fallback
	assert_true(t.has_method("setup_entity"),
		"Tile3D 须提供 setup_entity(tile_id, face_up, red, instance_id)")
	if not t.has_method("setup_entity"):
		return
	t.callv("setup_entity", [TileId.T5, true, false, 4242])
	assert_eq(t.tile_id, TileId.T5, "tile_id 保留渲染")
	var stored_iid: Variant = t.get("tile_instance_id")
	assert_true(stored_iid != null, "setup_entity 须写入 tile_instance_id")
	if stored_iid == null:
		return
	assert_eq(int(stored_iid), 4242)
	t.set_clickable(true)
	_click_tile3d(t)

	assert_signal_emitted(t, "tile_clicked")
	var params: Array = get_signal_parameters(t, "tile_clicked")
	assert_eq(int(params[0]), 4242, "Tile3D.tile_clicked 发 instance_id")
	assert_ne(int(params[0]), TileId.T5)


# ---------------------------------------------------------------------------
# 2) SeatPanel：slot 存 hand_instance_id + tile_id + is_red；点击/定位按 instance
# ---------------------------------------------------------------------------

func test_seat_panel_player_slots_store_instance_and_emit_on_click() -> void:
	var seat_ui: SeatPanel = SEAT_PANEL.instantiate()
	add_child_autofree(seat_ui)
	seat_ui.set_seat_id(0)
	await get_tree().process_frame

	var seat := Seat.new(0, TileId.E)
	# 同值赤/黑 5m 各一张，instance 不同
	seat.hand.add(_tile(TileId.W5, 101, false))
	seat.hand.add(_tile(TileId.W5, 102, true))
	for tid in [TileId.W1, TileId.W2, TileId.W3, TileId.T1, TileId.T2, TileId.T3,
			TileId.S1, TileId.S2, TileId.S3, TileId.E, TileId.S_WIND]:
		seat.hand.add(_tile(tid, 200 + tid, false))
	seat.last_drawn_instance_id = Tile.INVALID_INSTANCE_ID
	seat_ui.bind_seat(seat)
	await get_tree().process_frame

	var black_slot: Control = null
	var red_slot: Control = null
	for s in seat_ui._hand_slots:
		if s == null or not is_instance_valid(s):
			continue
		assert_true(s.has_meta("hand_instance_id"), "slot 必须存 hand_instance_id")
		assert_true(s.has_meta("hand_id"), "slot 保留 tile_id 供渲染/同名 hover")
		assert_true(s.has_meta("hand_red"), "slot 存 is_red")
		var iid: int = int(s.get_meta("hand_instance_id"))
		if iid == 101:
			black_slot = s
			assert_eq(int(s.get_meta("hand_id")), TileId.W5)
			assert_false(bool(s.get_meta("hand_red")))
		elif iid == 102:
			red_slot = s
			assert_eq(int(s.get_meta("hand_id")), TileId.W5)
			assert_true(bool(s.get_meta("hand_red")))
	assert_not_null(black_slot, "应有黑 5m slot")
	assert_not_null(red_slot, "应有赤 5m slot")

	seat_ui.set_hand_clickable(true)
	watch_signals(seat_ui)

	var black_tile: CardTileBack = black_slot.get_node("Tile") as CardTileBack
	_click_card(black_tile)
	assert_signal_emitted(seat_ui, "player_card_clicked")
	var p1: Array = get_signal_parameters(seat_ui, "player_card_clicked")
	assert_eq(int(p1[0]), 101, "点黑 5 发 instance 101")

	var red_tile: CardTileBack = red_slot.get_node("Tile") as CardTileBack
	_click_card(red_tile)
	var p2: Array = get_signal_parameters(seat_ui, "player_card_clicked")
	assert_eq(int(p2[0]), 102, "点赤 5 发不同 instance 102")


func test_get_hand_slot_global_center_finds_by_instance_id() -> void:
	var seat_ui: SeatPanel = SEAT_PANEL.instantiate()
	add_child_autofree(seat_ui)
	seat_ui.set_seat_id(0)
	await get_tree().process_frame

	var seat := Seat.new(0, TileId.E)
	seat.hand.add(_tile(TileId.W5, 301, false))
	seat.hand.add(_tile(TileId.W5, 302, true))
	for i in range(11):
		seat.hand.add(_tile(TileId.W1 + (i % 9), 400 + i, false))
	seat_ui.bind_seat(seat)
	await get_tree().process_frame

	var c_black: Vector2 = seat_ui.get_hand_slot_global_center(301)
	var c_red: Vector2 = seat_ui.get_hand_slot_global_center(302)
	assert_ne(c_black, Vector2.ZERO, "instance 301 应定位到 slot")
	assert_ne(c_red, Vector2.ZERO, "instance 302 应定位到 slot")
	assert_ne(c_black, c_red, "同值赤黑必须落到不同 slot 中心（飞牌定位）")

	# 按 tile_id 查询不得作为动作定位契约（同值歧义）
	# get_hand_slot_global_center 的参数语义 = instance_id
	var miss: Vector2 = seat_ui.get_hand_slot_global_center(TileId.W5)
	# TileId.W5 通常 ≠ 301/302；若碰巧相等也不得把两张混成一张
	if TileId.W5 != 301 and TileId.W5 != 302:
		assert_eq(miss, Vector2.ZERO, "用 tile_id 当 instance 查找应 miss，禁止首张 fallback")


func test_get_hand_slot_invalid_instance_returns_zero() -> void:
	var seat_ui: SeatPanel = SEAT_PANEL.instantiate()
	add_child_autofree(seat_ui)
	seat_ui.set_seat_id(0)
	await get_tree().process_frame
	# 纯展示路径：slot 的 hand_instance_id = INVALID
	seat_ui._rebuild_player_hand_row([TileId.W1, TileId.W2, TileId.W3])
	await get_tree().process_frame
	assert_eq(seat_ui.get_hand_slot_global_center(Tile.INVALID_INSTANCE_ID), Vector2.ZERO,
		"INVALID 不得定位到纯展示 slot")
	assert_eq(seat_ui.get_hand_slot_global_center(-1), Vector2.ZERO)
	# 合法手牌存在时，非法 id 仍立即 ZERO
	var seat := Seat.new(0, TileId.E)
	seat.hand.add(_tile(TileId.W5, 901, false))
	for i in range(12):
		seat.hand.add(_tile(TileId.W1 + (i % 9), 910 + i, false))
	seat_ui.bind_seat(seat)
	await get_tree().process_frame
	assert_eq(seat_ui.get_hand_slot_global_center(Tile.INVALID_INSTANCE_ID), Vector2.ZERO)
	assert_ne(seat_ui.get_hand_slot_global_center(901), Vector2.ZERO, "合法 instance 仍可定位")


# ---------------------------------------------------------------------------
# 3) split_hand_for_display：只认 last_drawn_instance_id
# ---------------------------------------------------------------------------

func test_split_hand_uses_drawn_instance_id_for_red_black_pair() -> void:
	# 手中黑 5 + 刚摸赤 5：必须拆出赤 5 实体，黑 5 留在 sorted
	var h := _hand_with([
		{"id": TileId.W2, "iid": 1}, {"id": TileId.W3, "iid": 2}, {"id": TileId.W4, "iid": 3},
		{"id": TileId.T2, "iid": 4}, {"id": TileId.T3, "iid": 5}, {"id": TileId.T4, "iid": 6},
		{"id": TileId.S2, "iid": 7}, {"id": TileId.S3, "iid": 8}, {"id": TileId.S4, "iid": 9},
		{"id": TileId.S6, "iid": 10}, {"id": TileId.S7, "iid": 11}, {"id": TileId.S8, "iid": 12},
		{"id": TileId.W5, "iid": 50, "red": false},
		{"id": TileId.W5, "iid": 51, "red": true},  # 刚摸
	])
	var split: Dictionary = SeatPanel.split_hand_for_display(h, 51)
	assert_eq(split.drawn_ids.size(), 1)
	assert_eq(int(split.drawn_ids[0]), TileId.W5)
	assert_true(bool(split.drawn_reds[0]), "刚摸实体是赤 5")
	assert_eq(int(split.drawn_instance_ids[0]), 51, "drawn 必须是 instance 51")
	assert_true(split.sorted_instance_ids.has(50), "黑 5 instance 50 留在 sorted")
	assert_false(split.sorted_instance_ids.has(51))
	assert_eq(split.sorted_ids.size(), 13)


func test_split_hand_two_ordinary_same_value_picks_exact_drawn_entity() -> void:
	var h := _hand_with([
		{"id": TileId.W2, "iid": 1}, {"id": TileId.W3, "iid": 2}, {"id": TileId.W4, "iid": 3},
		{"id": TileId.T2, "iid": 4}, {"id": TileId.T3, "iid": 5}, {"id": TileId.T4, "iid": 6},
		{"id": TileId.S2, "iid": 7}, {"id": TileId.S3, "iid": 8}, {"id": TileId.S4, "iid": 9},
		{"id": TileId.S6, "iid": 10}, {"id": TileId.S7, "iid": 11}, {"id": TileId.S8, "iid": 12},
		{"id": TileId.W1, "iid": 80},
		{"id": TileId.W1, "iid": 81},  # 刚摸
	])
	var split: Dictionary = SeatPanel.split_hand_for_display(h, 81)
	assert_eq(int(split.drawn_instance_ids[0]), 81)
	assert_true(split.sorted_instance_ids.has(80))
	assert_false(split.sorted_instance_ids.has(81))
	# 剩余手牌顺序稳定：升序 by tile_id，同 id 保持相对稳定
	for i in range(split.sorted_ids.size() - 1):
		assert_true(int(split.sorted_ids[i]) <= int(split.sorted_ids[i + 1]))


func test_split_hand_invalid_drawn_instance_does_not_split() -> void:
	var h := _hand_with([
		{"id": TileId.W2, "iid": 1}, {"id": TileId.W3, "iid": 2}, {"id": TileId.W4, "iid": 3},
		{"id": TileId.T2, "iid": 4}, {"id": TileId.T3, "iid": 5}, {"id": TileId.T4, "iid": 6},
		{"id": TileId.S2, "iid": 7}, {"id": TileId.S3, "iid": 8}, {"id": TileId.S4, "iid": 9},
		{"id": TileId.S6, "iid": 10}, {"id": TileId.S7, "iid": 11}, {"id": TileId.S8, "iid": 12},
		{"id": TileId.CHUN, "iid": 13},
		{"id": TileId.W5, "iid": 14},
	])
	var split: Dictionary = SeatPanel.split_hand_for_display(h, Tile.INVALID_INSTANCE_ID)
	assert_eq(split.drawn_ids.size(), 0, "INVALID 不拆")
	assert_eq(split.drawn_instance_ids.size(), 0)
	assert_eq(split.sorted_ids.size(), 14)
	assert_eq(split.sorted_instance_ids.size(), 14)


# ---------------------------------------------------------------------------
# 4) PlayerActionPanel / TableDecisionAdapter choice 契约
# ---------------------------------------------------------------------------

func test_action_panel_discard_choice_uses_tile_instance_id() -> void:
	var panel: PlayerActionPanel = ACTION_PANEL.instantiate()
	add_child_autofree(panel)
	await get_tree().process_frame
	watch_signals(panel)

	panel.enter_waiting_discard(false, false, false, false)
	panel.on_hand_tile_clicked(7777)

	assert_signal_emitted(panel, "player_action_chosen")
	var choice: Dictionary = get_signal_parameters(panel, "player_action_chosen")[0]
	assert_eq(String(choice.get("action", "")), "discard")
	assert_eq(int(choice.get("tile_instance_id", -1)), 7777)
	assert_false(choice.has("tile_id"), "choice 不保留 tile_id 兼容字段")


func test_action_panel_claim_tile_pick_uses_tile_instance_id() -> void:
	var panel: PlayerActionPanel = ACTION_PANEL.instantiate()
	add_child_autofree(panel)
	await get_tree().process_frame
	watch_signals(panel)

	panel.enter_waiting_claim(false, true, false, false, 3)
	panel.on_hand_tile_clicked(8888)

	assert_signal_emitted(panel, "player_action_chosen")
	var choice: Dictionary = get_signal_parameters(panel, "player_action_chosen")[0]
	assert_eq(String(choice.get("action", "")), "claim_tile_pick")
	assert_eq(int(choice.get("tile_instance_id", -1)), 8888)
	assert_false(choice.has("tile_id"))


func test_adapter_claim_companions_context_uses_instance_id_lists() -> void:
	var panel: PlayerActionPanel = ACTION_PANEL.instantiate()
	var seat_ui: SeatPanel = SEAT_PANEL.instantiate()
	add_child_autofree(panel)
	add_child_autofree(seat_ui)
	await get_tree().process_frame
	var adapter := TableDecisionAdapter.new(panel, seat_ui)

	var result := {}
	var runner := func():
		result["choice"] = await adapter.request(&"claim_companions", {
			"claim_kind": "CHI",
			"options": [[1001, 1002], [1002, 1004]],
			"discarded_tile_id": TileId.W3,
			"selected_tile_instance_ids": [1002],
			"allowed_tile_instance_ids": [1001, 1002, 1004],
			"companion_tile_instance_ids": [],  # 选择前为空；选项在 options
		})
	runner.call()
	await get_tree().process_frame

	assert_true(seat_ui._hand_clickable)
	# dim 契约：按 instance 候选压暗（allowed_tile_instance_ids，非 allowed_tile_ids）
	adapter.on_hand_tile_clicked(1004)
	await get_tree().process_frame
	assert_eq(result.choice, {
		"action": "claim_tile_pick",
		"tile_instance_id": 1004,
	})
	assert_false(result.choice.has("tile_id"))
	assert_false(result.choice.has("allowed_tile_ids"))


func test_adapter_discard_returns_tile_instance_id() -> void:
	var panel: PlayerActionPanel = ACTION_PANEL.instantiate()
	var seat_ui: SeatPanel = SEAT_PANEL.instantiate()
	add_child_autofree(panel)
	add_child_autofree(seat_ui)
	await get_tree().process_frame
	var adapter := TableDecisionAdapter.new(panel, seat_ui)

	var result := {}
	var runner := func():
		result["choice"] = await adapter.request(&"discard", {
			"can_tsumo": false,
			"can_ankan": false,
			"can_added_kan": false,
			"has_consumable": false,
		})
	runner.call()
	adapter.on_hand_tile_clicked(55)
	await get_tree().process_frame
	assert_eq(result.choice, {"action": "discard", "tile_instance_id": 55})
	assert_false(result.choice.has("tile_id"))


# ---------------------------------------------------------------------------
# 5) MahjongTable3D：点击链与 2D 一致（不测布局/材质/动画）
# ---------------------------------------------------------------------------

func test_mahjong_table_3d_player_click_emits_instance_id() -> void:
	var table := MahjongTable3D.new()
	add_child_autofree(table)
	await get_tree().process_frame

	var seat := Seat.new(0, TileId.E)
	seat.hand.add(_tile(TileId.W2, 10))
	seat.hand.add(_tile(TileId.W3, 11))
	seat.hand.add(_tile(TileId.W4, 12))
	seat.hand.add(_tile(TileId.T2, 13))
	seat.hand.add(_tile(TileId.T3, 14))
	seat.hand.add(_tile(TileId.T4, 15))
	seat.hand.add(_tile(TileId.S2, 16))
	seat.hand.add(_tile(TileId.S3, 17))
	seat.hand.add(_tile(TileId.S4, 18))
	seat.hand.add(_tile(TileId.S6, 19))
	seat.hand.add(_tile(TileId.S7, 20))
	seat.hand.add(_tile(TileId.S8, 21))
	seat.hand.add(_tile(TileId.CHUN, 22))
	seat.hand.add(_tile(TileId.W5, 99, true))  # 刚摸赤 5
	# 只设 last_drawn_instance_id；不得靠 last_drawn_tile_id 掩盖 fallback
	seat.last_drawn_instance_id = 99

	table._rebuild_player_hand(seat, false)
	table.set_hand_clickable(true)
	assert_gt(table._hand_tiles.size(), 0)

	var target: Tile3D = null
	for n in table._hand_tiles:
		if n is Tile3D and int((n as Object).get("tile_instance_id")) == 99:
			target = n as Tile3D
			break
	assert_not_null(target, "3D 手牌须挂上刚摸实体 instance_id=99")

	watch_signals(table)
	_click_tile3d(target)
	assert_signal_emitted(table, "player_card_clicked")
	var params: Array = get_signal_parameters(table, "player_card_clicked")
	assert_eq(int(params[0]), 99, "MahjongTable3D 点击链与 2D 一致：发 instance_id")


func test_mahjong_table_3d_get_hand_slot_center_by_instance_id() -> void:
	var table := MahjongTable3D.new()
	add_child_autofree(table)
	await get_tree().process_frame
	table.custom_minimum_size = Vector2(800, 600)
	table.size = Vector2(800, 600)

	var seat := Seat.new(0, TileId.E)
	for i in range(13):
		seat.hand.add(_tile(TileId.W1 + (i % 9), 500 + i))
	seat.hand.add(_tile(TileId.HAKU, 599))
	seat.last_drawn_instance_id = 599
	table._rebuild_player_hand(seat, false)

	var center: Vector2 = table.get_hand_slot_global_center(599)
	assert_ne(center, Vector2.ZERO, "3D 飞牌定位按 instance_id 找到槽位")
	# 不得用 tile_id 首张 fallback
	if TileId.HAKU != 599:
		assert_eq(table.get_hand_slot_global_center(TileId.HAKU), Vector2.ZERO)


# ---------------------------------------------------------------------------
# 6) PlayableTable 结果快照 clone：实体 identity 必须完整保留
# ---------------------------------------------------------------------------

func test_clone_result_tile_preserves_entity_fields_and_is_independent() -> void:
	var src := Tile.new(TileId.S5, true, 2, 777)
	var cloned: Tile = PlayableTable._clone_result_tile(src)
	assert_not_null(cloned)
	assert_ne(cloned, src, "clone 必须是独立对象")
	assert_eq(cloned.instance_id, 777, "保留 instance_id")
	assert_eq(cloned.id, TileId.S5, "保留 tile_id")
	assert_true(cloned.is_red_dora, "保留 red")
	assert_eq(cloned.owner_seat, 2, "保留 owner")
	# 独立性：改源不得影响 clone
	src.id = TileId.W1
	assert_eq(cloned.id, TileId.S5)


func test_clone_result_meld_preserves_identity_and_derives_called_from_cloned_tiles() -> void:
	# 构造必须用新签名：int meld_id + called Tile；禁止旧第 4 参 Tile 兼容
	var called := Tile.new(TileId.W5, true, 1, 50)
	var c1 := Tile.new(TileId.W5, false, 0, 51)
	var c2 := Tile.new(TileId.W5, false, 0, 52)
	var src := Meld.make_pon([called, c1, c2], 1, 9, called)
	var fourth := Tile.new(TileId.W5, false, 0, 53)
	assert_true(src.promote_to_added_kan(fourth))
	assert_eq(src.meld_id, 9)
	assert_eq(src.called_tile_instance_id, 50)
	assert_eq(src.added_tile_instance_id, 53)

	var cloned: Meld = PlayableTable._clone_result_meld(src)
	assert_not_null(cloned)
	assert_ne(cloned, src, "meld clone 独立对象")
	assert_eq(cloned.kind, Meld.Kind.ADDED_KAN)
	assert_eq(cloned.from_seat, 1)
	assert_eq(cloned.meld_id, 9, "保留 meld_id")
	assert_eq(cloned.called_tile_instance_id, 50, "保留 called_tile_instance_id")
	assert_eq(cloned.added_tile_instance_id, 53, "保留 added_tile_instance_id")
	assert_eq(cloned.tiles.size(), 4)

	# 所有 tile instance 保留且对象独立
	var src_iids: Array = []
	var cloned_iids: Array = []
	for i in range(4):
		assert_ne(cloned.tiles[i], src.tiles[i], "tile 对象必须独立")
		src_iids.append(src.tiles[i].instance_id)
		cloned_iids.append(cloned.tiles[i].instance_id)
		assert_eq(cloned.tiles[i].instance_id, src.tiles[i].instance_id)
		assert_eq(cloned.tiles[i].id, src.tiles[i].id)
		assert_eq(cloned.tiles[i].is_red_dora, src.tiles[i].is_red_dora)
		assert_eq(cloned.tiles[i].owner_seat, src.tiles[i].owner_seat)
	src_iids.sort()
	cloned_iids.sort()
	assert_eq(cloned_iids, [50, 51, 52, 53])

	# called_tile 必须从 cloned tiles 按 instance 派生（非旧对象指针）
	assert_not_null(cloned.called_tile)
	assert_eq(cloned.called_tile.instance_id, 50)
	assert_ne(cloned.called_tile, called, "不得仍指向源 called Tile 对象")
	var derived_from_cloned := false
	for t in cloned.tiles:
		if t == cloned.called_tile:
			derived_from_cloned = true
			break
	assert_true(derived_from_cloned, "called_tile 必须是 cloned.tiles 中的成员")


# ---------------------------------------------------------------------------
# 7) focused 回归：INVALID 展示槽不命中 + clone fail-closed
# ---------------------------------------------------------------------------

func test_rebuild_display_row_invalid_instance_does_not_hit() -> void:
	var seat_ui: SeatPanel = SEAT_PANEL.instantiate()
	add_child_autofree(seat_ui)
	seat_ui.set_seat_id(0)
	await get_tree().process_frame

	# 纯展示路径：slot 的 hand_instance_id = INVALID
	seat_ui._rebuild_player_hand_row([TileId.W1])
	await get_tree().process_frame

	assert_gt(seat_ui._hand_slots.size(), 0, "须创建至少一枚纯展示 slot")
	assert_eq(
		seat_ui.get_hand_slot_global_center(Tile.INVALID_INSTANCE_ID),
		Vector2.ZERO,
		"非法 iid 不得命中纯展示 slot"
	)


# ADDED_KAN clone fail-closed：缺 added / 缺 called / promote 失败 → null（禁止静默 PON）
func test_clone_result_meld_added_kan_fail_closed_missing_added() -> void:
	# make_added_kan 不写 added_tile_instance_id（仍 INVALID）→ 找不到 added_copy
	var called := Tile.new(TileId.W5, true, 1, 50)
	var tiles: Array[Tile] = [
		called,
		Tile.new(TileId.W5, false, 0, 51),
		Tile.new(TileId.W5, false, 0, 52),
		Tile.new(TileId.W5, false, 0, 53),
	]
	var src := Meld.make_added_kan(tiles, 1, 9, called)
	assert_eq(src.kind, Meld.Kind.ADDED_KAN)
	assert_eq(src.added_tile_instance_id, Tile.INVALID_INSTANCE_ID)
	var cloned: Meld = PlayableTable._clone_result_meld(src)
	assert_null(cloned, "缺 added identity 必须 fail-closed 返回 null，禁止静默 PON")


func test_clone_result_meld_added_kan_fail_closed_missing_called() -> void:
	# called instance 不在 tiles 中 → 找不到 called_base
	var called_missing := Tile.new(TileId.W5, true, 1, 999)
	var c1 := Tile.new(TileId.W5, false, 0, 51)
	var c2 := Tile.new(TileId.W5, false, 0, 52)
	var c3 := Tile.new(TileId.W5, false, 0, 50)
	var src := Meld.make_pon([c1, c2, c3], 1, 9, called_missing)
	var fourth := Tile.new(TileId.W5, false, 0, 53)
	assert_true(src.promote_to_added_kan(fourth))
	assert_eq(src.called_tile_instance_id, 999)
	assert_null(src.called_tile, "源本身 called 不在 tiles")
	var cloned: Meld = PlayableTable._clone_result_meld(src)
	assert_null(cloned, "缺 called_base 必须 fail-closed 返回 null")


func test_clone_result_meld_added_kan_fail_closed_promote_fails() -> void:
	# promote 成功后破坏 added 张 tile_id → clone 时 promote 因 id 不匹配失败
	var called := Tile.new(TileId.W5, true, 1, 50)
	var c1 := Tile.new(TileId.W5, false, 0, 51)
	var c2 := Tile.new(TileId.W5, false, 0, 52)
	var src := Meld.make_pon([called, c1, c2], 1, 9, called)
	var fourth := Tile.new(TileId.W5, false, 0, 53)
	assert_true(src.promote_to_added_kan(fourth))
	assert_eq(src.tiles.size(), 4)
	src.tiles[3].id = TileId.W1  # 破坏 added 牌 id，使 promote 条件失败
	var cloned: Meld = PlayableTable._clone_result_meld(src)
	assert_null(cloned, "promote 失败必须 fail-closed 返回 null，禁止静默 PON")


# ---------------------------------------------------------------------------
# 8) clone fail-closed 矩阵：开放副露 CHI/PON/MINKAN + ANKAN
# ---------------------------------------------------------------------------

# 开放副露：called_tile_instance_id 不在 tiles → null；
# 合法 called 但 meld_id INVALID → null（禁止静默丢 identity）
func test_clone_result_meld_open_claim_fail_closed_matrix() -> void:
	# kind_key → factory(Array[Tile], from, meld_id, called) -> Meld
	var cases: Array = [
		{"kind": "CHI", "factory": "chi"},
		{"kind": "PON", "factory": "pon"},
		{"kind": "MINKAN", "factory": "minkan"},
	]
	for c in cases:
		var kind_label: String = String(c["kind"])
		var factory: String = String(c["factory"])

		# --- A) called_tile_instance_id 不在 tiles → null ---
		var missing_called: Tile
		var tiles_a: Array[Tile]
		var mid_a: int = 21
		match factory:
			"chi":
				missing_called = Tile.new(TileId.W2, false, 1, 999)
				tiles_a = [
					Tile.new(TileId.W1, false, 0, 10),
					Tile.new(TileId.W2, false, 0, 11),
					Tile.new(TileId.W3, false, 0, 12),
				]
			"pon":
				missing_called = Tile.new(TileId.W5, true, 1, 999)
				tiles_a = [
					Tile.new(TileId.W5, false, 0, 30),
					Tile.new(TileId.W5, false, 0, 31),
					Tile.new(TileId.W5, false, 0, 32),
				]
			_:
				missing_called = Tile.new(TileId.S1, false, 2, 999)
				tiles_a = [
					Tile.new(TileId.S1, false, 0, 40),
					Tile.new(TileId.S1, false, 0, 41),
					Tile.new(TileId.S1, false, 0, 42),
					Tile.new(TileId.S1, false, 0, 43),
				]
		var src_a: Meld
		match factory:
			"chi":
				src_a = Meld.make_chi(tiles_a, 1, mid_a, missing_called)
			"pon":
				src_a = Meld.make_pon(tiles_a, 1, mid_a, missing_called)
			_:
				src_a = Meld.make_minkan(tiles_a, 2, mid_a, missing_called)
		assert_eq(src_a.called_tile_instance_id, 999,
			"%s A: 源保留 missing called instance" % kind_label)
		assert_null(src_a.called_tile,
			"%s A: 源 called 不在 tiles" % kind_label)
		assert_null(PlayableTable._clone_result_meld(src_a),
			"%s A: called 不在 tiles 必须 fail-closed 返回 null" % kind_label)

		# --- B) 合法 called 但 meld_id INVALID → null ---
		var called_b: Tile
		var tiles_b: Array[Tile]
		match factory:
			"chi":
				called_b = Tile.new(TileId.W2, false, 1, 11)
				tiles_b = [
					Tile.new(TileId.W1, false, 0, 10),
					called_b,
					Tile.new(TileId.W3, false, 0, 12),
				]
			"pon":
				called_b = Tile.new(TileId.W5, true, 1, 30)
				tiles_b = [
					called_b,
					Tile.new(TileId.W5, false, 0, 31),
					Tile.new(TileId.W5, false, 0, 32),
				]
			_:
				called_b = Tile.new(TileId.S1, false, 2, 40)
				tiles_b = [
					called_b,
					Tile.new(TileId.S1, false, 0, 41),
					Tile.new(TileId.S1, false, 0, 42),
					Tile.new(TileId.S1, false, 0, 43),
				]
		var src_b: Meld
		match factory:
			"chi":
				src_b = Meld.make_chi(tiles_b, 1, Tile.INVALID_INSTANCE_ID, called_b)
			"pon":
				src_b = Meld.make_pon(tiles_b, 1, Tile.INVALID_INSTANCE_ID, called_b)
			_:
				src_b = Meld.make_minkan(tiles_b, 2, Tile.INVALID_INSTANCE_ID, called_b)
		assert_eq(src_b.meld_id, Tile.INVALID_INSTANCE_ID,
			"%s B: 源 meld_id 为 INVALID" % kind_label)
		assert_not_null(src_b.called_tile,
			"%s B: called 合法在 tiles 中" % kind_label)
		assert_null(PlayableTable._clone_result_meld(src_b),
			"%s B: meld_id INVALID 必须 fail-closed 返回 null" % kind_label)


# ANKAN：合法 meld_id 但 from_seat 不是 NO_SOURCE → null
func test_clone_result_meld_ankan_fail_closed_from_seat_not_no_source() -> void:
	var tiles: Array[Tile] = [
		Tile.new(TileId.W5, false, 0, 61),
		Tile.new(TileId.W5, false, 0, 62),
		Tile.new(TileId.W5, false, 0, 63),
		Tile.new(TileId.W5, false, 0, 64),
	]
	# 故意 from_seat=1（非 NO_SOURCE）；新签名 meld_id=int
	var src := Meld.new(Meld.Kind.ANKAN, tiles, 1, 17, null)
	assert_eq(src.kind, Meld.Kind.ANKAN)
	assert_eq(src.meld_id, 17)
	assert_ne(src.from_seat, Meld.NO_SOURCE_SEAT)
	assert_null(PlayableTable._clone_result_meld(src),
		"ANKAN: from_seat 非 NO_SOURCE 必须 fail-closed 返回 null")


# ANKAN：合法 meld_id / NO_SOURCE 但带 called → null
func test_clone_result_meld_ankan_fail_closed_with_called() -> void:
	var called := Tile.new(TileId.W5, false, 0, 71)
	var tiles: Array[Tile] = [
		called,
		Tile.new(TileId.W5, false, 0, 72),
		Tile.new(TileId.W5, false, 0, 73),
		Tile.new(TileId.W5, false, 0, 74),
	]
	var src := Meld.new(Meld.Kind.ANKAN, tiles, Meld.NO_SOURCE_SEAT, 18, called)
	assert_eq(src.kind, Meld.Kind.ANKAN)
	assert_eq(src.meld_id, 18)
	assert_eq(src.from_seat, Meld.NO_SOURCE_SEAT)
	assert_eq(src.called_tile_instance_id, 71)
	assert_not_null(src.called_tile)
	assert_null(PlayableTable._clone_result_meld(src),
		"ANKAN: 带 called 必须 fail-closed 返回 null")


# ANKAN 正向：合法 meld_id + NO_SOURCE + 无 called → 保留 kind/meld_id/4 tiles，called 空
func test_clone_result_meld_ankan_preserves_identity_when_valid() -> void:
	var tiles: Array[Tile] = [
		Tile.new(TileId.T1, false, 0, 81),
		Tile.new(TileId.T1, false, 0, 82),
		Tile.new(TileId.T1, false, 0, 83),
		Tile.new(TileId.T1, false, 0, 84),
	]
	var src := Meld.make_ankan(tiles, 19)
	assert_eq(src.kind, Meld.Kind.ANKAN)
	assert_eq(src.meld_id, 19)
	assert_eq(src.from_seat, Meld.NO_SOURCE_SEAT)
	assert_eq(src.called_tile_instance_id, Tile.INVALID_INSTANCE_ID)

	var cloned: Meld = PlayableTable._clone_result_meld(src)
	assert_not_null(cloned, "合法 ANKAN 必须可 clone")
	assert_ne(cloned, src)
	assert_eq(cloned.kind, Meld.Kind.ANKAN)
	assert_eq(cloned.meld_id, 19)
	assert_eq(cloned.tiles.size(), 4)
	assert_eq(cloned.called_tile_instance_id, Tile.INVALID_INSTANCE_ID)
	assert_null(cloned.called_tile, "合法 ANKAN called 必须为空")
	var cloned_iids: Array = []
	for t in cloned.tiles:
		cloned_iids.append(t.instance_id)
	cloned_iids.sort()
	assert_eq(cloned_iids, [81, 82, 83, 84])
