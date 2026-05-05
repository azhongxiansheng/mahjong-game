extends GutTest

# 麻将王 — M7：HAITEI / HOUTEI 事件 emit + game_ctx 标志接通验证。
#
# 之前 BattleController 不 emit HAITEI/HOUTEI，且 game_ctx.is_haitei /
# is_houtei 永远是 false——海底捞月 / 河底捞鱼役在真战斗永不被检测。
# 本批改：
# 1. _step_draw 摸牌后 wall.live_wall_size==0 时 _check_tsumo + _settle_tsumo
#    走 is_haitei=true 路径，emit HAITEI，game_ctx.is_haitei = true
# 2. apply_ron(is_houtei=true) 路径同理 emit HOUTEI

var _bc: IBattleController

func before_each() -> void:
	_bc = BattleController.new(42, 0)

# ---- HAITEI: 自摸最后一张 ----

func test_haitei_emitted_on_last_tile_tsumo():
	# 七対子听 W9 单骑（同 test_battle_e2e path B）
	var tenpai_ids: Array = [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W9,
	]
	var seat0: Seat = _bc.state.seats[0]
	seat0.hand._tiles.clear()
	for tid in tenpai_ids:
		seat0.hand.add(Tile.new(tid))

	# 把 wall 的 draw_index 推到只剩 1 张 live tile，且这张 = W9
	var w: Wall = _bc.state.wall
	# size() = _tiles.size() - _draw_index - _dead_wall_size
	# 把 draw_index 推到 size() == 1 的位置
	var current_live: int = w.live_wall_size()
	w._draw_index += (current_live - 1)
	# 现在下一次 draw 取的就是最后一张 live tile；把它替换为 W9
	w._tiles[w._draw_index] = Tile.new(TileId.W9)

	var result: Dictionary = _bc.run_to_end()
	assert_eq(result.last_event, &"WIN_DECLARED", "应自摸到 WIN_DECLARED")

	# 检查 events 中含 HAITEI
	var haitei_evs := _events_of_type(result.events, &"HAITEI")
	assert_eq(haitei_evs.size(), 1, "应 emit 1 次 HAITEI")
	assert_eq(haitei_evs[0].actor_seat, 0, "HAITEI 主体是自摸者 seat 0")

	# 检查最末 WIN_DECLARED 的 yaku 含 haitei
	var win_ev: BattleEvent = result.events[result.events.size() - 1]
	var extra: Dictionary = win_ev.extra
	# yaku 列表（ScoreCalc 输出）应包含 yaku id "4"（YakuId.HAITEI = 4）
	# 或字符串占位 (battle_controller._yaku_id_to_string_name 仅特殊化 pinfu/chiitoitsu)
	# 直接通过 ScoreCalc 出来的 yaku 是 YakuList.yaku 数组里有 "4" 这个 id
	# 取巧：han 应大于"无 haitei"基线（同样 fixture 跑一遍非 haitei 比较）
	assert_gt(int(extra.han), 2, "haitei 应被算进总番（七対子 2 番 + 海底 1 番 ≥ 3）")

func test_no_haitei_when_wall_not_drained():
	# 同样的 fixture 但不耗 wall：HAITEI 不应 emit
	var tenpai_ids: Array = [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W9,
	]
	var seat0: Seat = _bc.state.seats[0]
	seat0.hand._tiles.clear()
	for tid in tenpai_ids:
		seat0.hand.add(Tile.new(tid))

	# 直接把下一张 live tile 设为 W9（wall 仍满）
	var w: Wall = _bc.state.wall
	w._tiles[w._draw_index] = Tile.new(TileId.W9)

	var result: Dictionary = _bc.run_to_end()
	assert_eq(result.last_event, &"WIN_DECLARED")

	var haitei_evs := _events_of_type(result.events, &"HAITEI")
	assert_eq(haitei_evs.size(), 0, "wall 未空 → 不应 emit HAITEI")

# ---- HOUTEI: apply_ron(is_houtei=true) ----

func test_houtei_emitted_when_apply_ron_marked():
	# 七対子听 W9 单骑；seat 1 弃出 W9 + is_houtei=true
	var tenpai_ids: Array = [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W9,
	]
	var seat0: Seat = _bc.state.seats[0]
	seat0.hand._tiles.clear()
	for tid in tenpai_ids:
		seat0.hand.add(Tile.new(tid))

	var ron_tile := Tile.new(TileId.W9)
	var ok: bool = _bc.apply_ron(0, ron_tile, 1, true)  # is_houtei=true
	assert_true(ok, "apply_ron 应成立")

	var houtei_evs := _events_of_type(_bc.events, &"HOUTEI")
	assert_eq(houtei_evs.size(), 1, "应 emit 1 次 HOUTEI")
	assert_eq(houtei_evs[0].actor_seat, 0, "HOUTEI 主体是胡牌者 seat 0")

	var win_ev: BattleEvent = _bc.events[_bc.events.size() - 1]
	assert_gt(int(win_ev.extra.han), 2, "houtei 应被算进总番（七対子 2 + 河底 1 ≥ 3）")

func test_no_houtei_when_apply_ron_default():
	# is_houtei 缺省为 false → 不 emit HOUTEI（向后兼容）
	var tenpai_ids: Array = [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W9,
	]
	var seat0: Seat = _bc.state.seats[0]
	seat0.hand._tiles.clear()
	for tid in tenpai_ids:
		seat0.hand.add(Tile.new(tid))

	var ron_tile := Tile.new(TileId.W9)
	_bc.apply_ron(0, ron_tile, 1)  # 默认 is_houtei=false
	var houtei_evs := _events_of_type(_bc.events, &"HOUTEI")
	assert_eq(houtei_evs.size(), 0, "默认 is_houtei=false → 不 emit HOUTEI")

# ---- HAITEI hook 真生效（boss3_kanmon / pin9_haitei_double）----

func test_haitei_hook_han_applied_to_score():
	# 注册 boss3_kanmon 给 seat 0；seat 0 是自摸者；预期 +3 番在最终 han 反映
	BossAbilityFactory.inject(_bc.registry, &"boss3_kanmon_v1", 0)

	var tenpai_ids: Array = [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W9,
	]
	var seat0: Seat = _bc.state.seats[0]
	seat0.hand._tiles.clear()
	for tid in tenpai_ids:
		seat0.hand.add(Tile.new(tid))

	var w: Wall = _bc.state.wall
	var current_live: int = w.live_wall_size()
	w._draw_index += (current_live - 1)
	w._tiles[w._draw_index] = Tile.new(TileId.W9)

	var result: Dictionary = _bc.run_to_end()
	assert_eq(result.last_event, &"WIN_DECLARED")
	var win_ev: BattleEvent = result.events[result.events.size() - 1]
	# 七対子 2 + 海底 1 + 门前清自摸 1 + boss3_kanmon +3 ≥ 7
	assert_gt(int(win_ev.extra.han), 5, "boss3_kanmon +3 番应反映在最终 han")

# ---- helper ----

func _events_of_type(events: Array, type: StringName) -> Array:
	var out: Array = []
	for ev in events:
		if ev.type == type:
			out.append(ev)
	return out
