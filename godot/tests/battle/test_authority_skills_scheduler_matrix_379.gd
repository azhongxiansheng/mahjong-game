extends GutTest

# Issue #379 Round 7 P2-1 / Round 8：12 角色真实 factory → registry → SkillScheduler 矩阵
# CharacterPool.find → BossAbilityFactory.build/inject → SkillScheduler.emit_event
# 禁止自造 SkillResource / 直调 hook / 只做映射文案

const SeatDrawForecastCoordinator := preload("res://battle/seat_draw_forecast_coordinator.gd")

const ROWS := [
	# char_id, ability, primary_trigger, mutation_key
	["lin_yeche", "char_akagi_passive_v1", "TILE_DRAWN", "reveal"],
	["qiu_jue", "char_kaiji_passive_v1", "WIN_DECLARED_PRE", "han2"],
	["bai_touli", "char_washizu_passive_v1", "GAME_BEGIN", "reveal6"],
	["hua_ling", "char_saki_passive_v1", "WIN_DECLARED_PRE", "dora2"],
	["lian_yao", "char_teru_passive_v1", "WIN_DECLARED_PRE", "streak1"],
	["an_cheng", "char_awai_passive_v1", "GAME_BEGIN", "forecast"],
	["yuan_xi", "char_koromo_passive_v1", "TILE_DRAWN", "wall_top"],
	["ji_shu", "char_nodoka_passive_v1", "WIN_DECLARED_PRE", "han1"],
	["xian_shi", "char_toki_passive_v1", "GAME_BEGIN", "forecast4"],
	["bao_luo", "char_kuro_passive_v1", "WIN_DECLARED_PRE", "red_dora2"],
	["ying_li", "char_momoko_passive_v1", "RIICHI_DECLARED", "prime_then_win"],
	["ju_jin", "char_tetsuya_passive_v1", "WIN_DECLARED_PRE", "step_han"],
]


func _handed_state(seed: int = 42) -> BattleState:
	var st := BattleState.new()
	st.wall = Wall.new_full_set()
	st.wall.shuffle(seed)
	st.wall.reserve_dead_wall(14)
	st.seats.clear()
	for i in range(4):
		var seat := Seat.new(i, TileId.E)
		for _j in range(13):
			var t: Tile = st.wall.draw()
			if t != null:
				seat.add_to_hand(t)
		st.seats.append(seat)
	st.scores = [25000, 25000, 25000, 25000]
	return st


func _arm(char_id: String, owner: int, st: BattleState) -> Dictionary:
	var ch: Character = CharacterPool.find(StringName(char_id))
	assert_not_null(ch, char_id)
	var ab := String(ch.ability_id)
	var built: SkillResource = BossAbilityFactory.build(StringName(ab))
	assert_not_null(built, ab)
	assert_false(built.owner_triggers.is_empty(), ab)
	var reg := SkillRegistry.new()
	assert_true(BossAbilityFactory.inject(reg, StringName(ab), owner), "inject %s" % ab)
	var sched := SkillScheduler.new(reg, st)
	return {"ch": ch, "ability": ab, "reg": reg, "sched": sched, "skill": built}


func _has_triggered(ctx: SkillCtx, ability: String, seat: int) -> bool:
	for t in ctx.triggered_skills:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		if str(t.get("skill_id", "")) == ability and int(t.get("beneficiary_seat", -1)) == seat:
			return true
	return false


func _skill_from_reg(reg: SkillRegistry, ability: String) -> SkillResource:
	for entry_v in reg.get_all_entries():
		var entry: Dictionary = entry_v
		var sk: SkillResource = entry.get("skill") as SkillResource
		if sk != null and String(sk.id) == ability:
			return sk
	return null


func test_twelve_characters_real_factory_scheduler_matrix() -> void:
	assert_eq(ROWS.size(), 12)
	for row_v in ROWS:
		var row: Array = row_v
		var cid := str(row[0])
		var expected_ab := str(row[1])
		var trigger := str(row[2])
		var mut_key := str(row[3])
		var owner := 0
		var st := _handed_state(hash(cid) % 1000 + 10)
		var pack: Dictionary = _arm(cid, owner, st)
		assert_eq(str(pack.ability), expected_ab, cid)
		var sched: SkillScheduler = pack.sched
		var ab: String = pack.ability
		var reg: SkillRegistry = pack.reg

		# --- owner 正例 ---
		match mut_key:
			"reveal":
				var ctx: SkillCtx = sched.emit_event(BattleEvent.make(&"TILE_DRAWN", owner))
				assert_true(_has_triggered(ctx, ab, owner), "%s triggered" % cid)
				assert_gt(st.revealed_tiles.size(), 0, "%s reveal" % cid)
			"han2":
				st.scores[owner] = 10000
				var ctx2: SkillCtx = sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", owner))
				assert_true(_has_triggered(ctx2, ab, owner), "%s triggered" % cid)
				assert_eq(int(ctx2.han_deltas.get(owner, 0)), 2, "%s +2 han" % cid)
			"reveal6":
				var ctx3: SkillCtx = sched.emit_event(BattleEvent.make(&"GAME_BEGIN", owner))
				assert_true(_has_triggered(ctx3, ab, owner), "%s triggered" % cid)
				assert_eq(st.revealed_tiles.size(), 6, "%s 6 reveals" % cid)
			"dora2":
				var before_d := int(st.extra_dora_count[owner]) if owner < st.extra_dora_count.size() else 0
				var ctx4: SkillCtx = sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", owner))
				assert_true(_has_triggered(ctx4, ab, owner), "%s triggered" % cid)
				assert_eq(int(st.extra_dora_count[owner]), before_d + 2, "%s +2 dora" % cid)
			"streak1":
				var ctx5: SkillCtx = sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", owner))
				assert_true(_has_triggered(ctx5, ab, owner), "%s triggered" % cid)
				assert_eq(int(ctx5.han_deltas.get(owner, 0)), 1, "%s first streak +1" % cid)
				var sk5: SkillResource = _skill_from_reg(reg, ab)
				assert_eq(int(sk5.params.get("streak", 0)), 1)
			"forecast":
				st.furiten_flags[owner] = true
				st.seats[owner].furiten = FuritenState.new()
				st.seats[owner].furiten.temporary = true
				var rev_before6 := st.revealed_tiles.size()
				var ctx6: SkillCtx = sched.emit_event(BattleEvent.make(&"GAME_BEGIN", owner))
				assert_true(_has_triggered(ctx6, ab, owner), "%s triggered" % cid)
				assert_false(bool(st.furiten_flags[owner]), "%s clear furiten" % cid)
				assert_gt(st.revealed_tiles.size(), rev_before6, "%s next-draw reveal" % cid)
			"wall_top":
				var rev_before7 := st.revealed_tiles.size()
				var ctx7: SkillCtx = sched.emit_event(BattleEvent.make(&"TILE_DRAWN", owner))
				assert_true(_has_triggered(ctx7, ab, owner), "%s triggered" % cid)
				assert_gt(st.revealed_tiles.size(), rev_before7, "%s wall top reveal" % cid)
			"han1":
				var ctx8: SkillCtx = sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", owner))
				assert_true(_has_triggered(ctx8, ab, owner), "%s triggered" % cid)
				assert_eq(int(ctx8.han_deltas.get(owner, 0)), 1, "%s +1 han" % cid)
			"forecast4":
				# 先示：只读 predictions_for_viewer 证明四席预测，禁止 OR 弱断言
				st.phase = BattlePhase.Kind.DRAW
				st.current_seat = owner
				var expected_top: Array[Tile] = st.wall.peek_top_n(4)
				assert_eq(expected_top.size(), 4, "%s live wall 顶至少 4 张" % cid)
				var ctx9: SkillCtx = sched.emit_event(BattleEvent.make(&"GAME_BEGIN", owner))
				assert_true(_has_triggered(ctx9, ab, owner), "%s triggered" % cid)
				var preds: Array = SeatDrawForecastCoordinator.predictions_for_viewer(st, owner)
				assert_eq(preds.size(), 4, "%s 须恰好 4 条预测" % cid)
				var expected_targets: Array = [
					owner, (owner + 1) % 4, (owner + 2) % 4, (owner + 3) % 4,
				]
				var seen_iid: Dictionary = {}
				for pi in range(4):
					var pred: Dictionary = preds[pi] as Dictionary
					assert_eq(int(pred.get("target_seat", -1)), int(expected_targets[pi]),
						"%s target_seat[%d]" % [cid, pi])
					var anchor: TileSkillAnchor = pred.get("tile", null) as TileSkillAnchor
					assert_not_null(anchor, "%s tile anchor[%d]" % [cid, pi])
					assert_eq(anchor.owner_seat, int(expected_targets[pi]))
					assert_eq(anchor.holder_seat, -1)
					assert_eq(anchor.tile.instance_id, expected_top[pi].instance_id,
						"%s 真实 wall-top tile[%d]" % [cid, pi])
					seen_iid[anchor.tile.instance_id] = true
				assert_eq(seen_iid.size(), 4, "%s 四席预测不得共享同一 iid" % cid)
				# 错误 viewer：不得看到任何预测
				var wrong_viewer := (owner + 1) % 4
				assert_eq(
					SeatDrawForecastCoordinator.predictions_for_viewer(st, wrong_viewer).size(),
					0, "%s 错误 viewer 预测须空" % cid)
				# 空 registry：无 forecast / 无 triggered
				var st_empty := _handed_state(91)
				st_empty.phase = BattlePhase.Kind.DRAW
				st_empty.current_seat = owner
				var sched_empty_toki := SkillScheduler.new(SkillRegistry.new(), st_empty)
				var ctx_empty: SkillCtx = sched_empty_toki.emit_event(
					BattleEvent.make(&"GAME_BEGIN", owner))
				assert_true(ctx_empty.triggered_skills.is_empty(), "%s 空 registry 不触发" % cid)
				assert_eq(
					SeatDrawForecastCoordinator.predictions_for_viewer(st_empty, owner).size(),
					0, "%s 空 registry 无 forecast" % cid)
			"red_dora2":
				var before_r := int(st.extra_red_dora_count[owner]) \
					if owner < st.extra_red_dora_count.size() else 0
				var ctx10: SkillCtx = sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", owner))
				assert_true(_has_triggered(ctx10, ab, owner), "%s triggered" % cid)
				assert_eq(int(st.extra_red_dora_count[owner]), before_r + 2, "%s red dora" % cid)
			"prime_then_win":
				# 前置 RIICHI 必须经 Scheduler，不得手写 primed
				sched.emit_event(BattleEvent.make(&"RIICHI_DECLARED", owner))
				var sk_m: SkillResource = _skill_from_reg(reg, ab)
				assert_true(bool(sk_m.params.get("primed", false)), "%s primed via RIICHI" % cid)
				var ctx11: SkillCtx = sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", owner))
				assert_true(_has_triggered(ctx11, ab, owner), "%s win after riichi" % cid)
				assert_eq(int(ctx11.han_deltas.get(owner, 0)), 1, "%s +1 after prime" % cid)
				assert_false(bool(sk_m.params.get("primed", false)))
			"step_han":
				var ctx12: SkillCtx = sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", owner))
				assert_true(_has_triggered(ctx12, ab, owner), "%s triggered" % cid)
				assert_eq(int(ctx12.han_deltas.get(owner, 0)), 1, "%s first win +1" % cid)
			_:
				assert_true(false, "unknown mut_key %s" % mut_key)

		# --- 错误 seat / 未武装负例（owner 类 trigger）---
		if trigger in ["TILE_DRAWN", "WIN_DECLARED_PRE", "RIICHI_DECLARED"]:
			var st_neg := _handed_state(77)
			st_neg.scores[0] = 10000
			var pack_neg: Dictionary = _arm(cid, 0, st_neg)
			var sched_neg: SkillScheduler = pack_neg.sched
			var wrong_seat := 2
			var tname := StringName(trigger)
			if mut_key == "prime_then_win":
				sched_neg.emit_event(BattleEvent.make(&"RIICHI_DECLARED", 0))
				var ctx_w: SkillCtx = sched_neg.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", wrong_seat))
				assert_eq(int(ctx_w.han_deltas.get(0, 0)), 0, "%s wrong seat no owner han" % cid)
				assert_false(_has_triggered(ctx_w, ab, 0) and int(ctx_w.han_deltas.get(0, 0)) > 0)
			else:
				var before_han := 0
				var ctx_w2: SkillCtx = sched_neg.emit_event(BattleEvent.make(tname, wrong_seat))
				assert_eq(int(ctx_w2.han_deltas.get(0, 0)), before_han,
					"%s wrong actor seat 不得给 owner 加番" % cid)
			# 未注册：空 registry
			var reg_empty := SkillRegistry.new()
			var sched_empty := SkillScheduler.new(reg_empty, st_neg)
			var ctx_u: SkillCtx = sched_empty.emit_event(BattleEvent.make(StringName(trigger), 0))
			assert_true(ctx_u.triggered_skills.is_empty(), "%s unarmed 不触发" % cid)
