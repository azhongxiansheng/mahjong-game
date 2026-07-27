extends GutTest

# Issue #348：宝络绯必须从真实 config/slot 武装进入 Action.tsumo / Action.ron，
# 再经 WIN_DECLARED_PRE → ScoreCalc → 权威事件与结算归因；不得只直调 hook。

const CHARACTERS := [&"qiu_jue", &"hua_ling", &"lin_yeche", &"bai_touli"]
const PARTICIPANTS := [&"HUMAN", &"HUMAN", &"HUMAN", &"HUMAN"]


func _make_config(bao_seat: int) -> GameSessionConfig:
	var characters := CHARACTERS.duplicate()
	characters[bao_seat] = &"bao_luo"
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PUBLIC_CASUAL,
		GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK,
		PARTICIPANTS,
		characters,
		348,
		"issue-348-bao-luo-%d" % bao_seat,
		"issue-348-v1"
	)


func _bind_bao_slot(bc: BattleController, bao_seat: int, armed: bool) -> ModeModuleBundle:
	var config := _make_config(bao_seat)
	assert_not_null(config, "真实 GameSessionConfig 必须接受宝络绯席位")
	var bundle := ModeModuleBundle.from_config(config)
	assert_not_null(bundle)
	var slot := bundle.character_ability_slots[bao_seat] as CharacterAbilitySlot
	assert_not_null(slot)
	assert_eq(slot.character_id, &"bao_luo")
	assert_eq(slot.ability_id, &"char_kuro_passive_v1")
	assert_not_null(slot.skill, "真实 factory 必须构造宝络绯 hook")
	assert_true(String(CharacterPool.find(&"bao_luo").description).contains("能力赤 Dora"),
		"角色规则说明必须与独立赤宝桶一致")
	assert_true(String(slot.skill.description).contains("能力赤 Dora"),
		"factory 构造的能力说明必须与独立赤宝桶一致")
	assert_false(slot.armed, "角色槽首窗必须保持未武装")
	if not armed:
		return bundle
	var inv := bundle.item_inventory
	inv.set_match_namespace("issue-348")
	assert_true(bool(inv.grant_for_seat({
		"seat": bao_seat,
		"item_id": "iron_shield_v1",
		"window_id": "w0",
		"hand_seq": 0,
		"score": 0,
		"rule_version": "issue-348-v1",
		"assignment_version": "assign-v1",
		"matched_rule_ids": [],
		"affinity_match": true,
		"next_window_id": "w1",
		"match_namespace": "issue-348",
	}).get("ok", false)))
	var arm := ItemAuthority.arm_seats_on_open(
		bc, inv, bundle.character_ability_slots, "w1")
	assert_true(bool(arm.get("ok", false)), str(arm))
	assert_true(slot.armed)
	assert_true(slot.registry_registered)
	return bundle


func _make_t1_tanki_hand() -> Hand:
	var hand := Hand.new()
	var serial := 0
	for tile_id in [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T1, TileId.T1,
	]:
		hand.add(Tile.new(tile_id, tile_id == TileId.T5, Tile.NO_OWNER, serial))
		serial += 1
	return hand


func _settle_tsumo(
	bao_seat: int = -1,
	armed: bool = false,
	with_hua_ling: bool = false,
	with_non_ability_dora: bool = false
) -> BattleController:
	var bc := BattleController.new(42, 0, false, TileId.E)
	if bao_seat >= 0:
		_bind_bao_slot(bc, bao_seat, armed)
	if with_hua_ling:
		assert_true(BossAbilityFactory.inject(
			bc.registry, &"char_saki_passive_v1", 0))
	if with_non_ability_dora:
		assert_true(TileSkillFactory.inject_one(
			bc.registry, &"man6_treasure_v1", 0))
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.state.seats[0].hand = _make_t1_tanki_hand()
	var tiles: Array[Tile] = bc.state.seats[0].hand.tiles()
	var drawn: Tile = tiles[-1]
	bc.state.seats[0].last_drawn_instance_id = drawn.instance_id
	var checked := bc._check_tsumo(drawn)
	assert_true(bool(checked.get("is_winning", false)), "夹具必须是真实合法自摸")
	var ctx := bc.decision_context_for_seat(0)
	assert_not_null(ctx)
	assert_true(ctx.has_kind("TSUMO"))
	var applied := bc.apply_action(Action.tsumo(
		0, "local", "550e8400-e29b-41d4-a716-000000000348",
		ctx.decision_id, 0, 1
	), ActionSource.HUMAN)
	assert_true(applied.accepted, String(applied.error_code))
	return bc


func _make_t1_tanki_ron_hand() -> Hand:
	var hand := Hand.new()
	var serial := 10
	for tile_id in [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T1,
	]:
		hand.add(Tile.new(tile_id, tile_id == TileId.T5, Tile.NO_OWNER, serial))
		serial += 1
	return hand


func _settle_chankan_ron(bao_seat: int = -1, armed: bool = false) -> BattleController:
	var bc := BattleController.new(42, 0, false, TileId.E)
	if bao_seat >= 0:
		_bind_bao_slot(bc, bao_seat, armed)
	bc.state.seats[1].hand = _make_t1_tanki_ron_hand()
	bc.state.seats[1].furiten = FuritenState.new()
	bc.state.seats[0].hand = Hand.new()
	var added := Tile.new(TileId.T1, false, Tile.NO_OWNER, 100)
	bc.state.seats[0].hand.add(added)
	for tile_id in [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.W7, TileId.W8, TileId.W9,
		TileId.E, TileId.E, TileId.S_WIND,
	]:
		bc.state.seats[0].hand.add(Tile.new(
			tile_id, false, Tile.NO_OWNER, 101 + bc.state.seats[0].hand.size()))
	var pon := Meld.make_pon([
		Tile.new(TileId.T1, false, 0, 1),
		Tile.new(TileId.T1, false, 0, 2),
		Tile.new(TileId.T1, false, 0, 3),
	], 2, 0)
	bc.state.seats[0].melds.restore([pon], 1)
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.state.seats[0].last_drawn_instance_id = added.instance_id
	var kan_ctx := bc.decision_context_for_seat(0)
	assert_not_null(kan_ctx)
	var added_kan_payload: Dictionary = {}
	for offer in kan_ctx.allowed_actions:
		if str(offer.get("kind", "")) != "KAN":
			continue
		for option in offer.get("payload_options", []):
			if str(option.get("kan_kind", "")) == "ADDED_KAN":
				added_kan_payload = option
	assert_false(added_kan_payload.is_empty(), "夹具必须提供加杠")
	assert_true(bc.apply_action(Action.kan(
		0, added_kan_payload, "local",
		"550e8400-e29b-41d4-a716-000000000340",
		kan_ctx.decision_id, 0, 1
	), ActionSource.HUMAN).accepted)
	for seat in [1, 2, 3]:
		var ron_ctx := bc.decision_context_for_seat(seat)
		assert_not_null(ron_ctx)
		var action: Action
		if seat == 1:
			assert_true(ron_ctx.has_kind("RON"), "宝络绯必须获得真实 RON offer")
			action = Action.ron(
				seat, "local", "550e8400-e29b-41d4-a716-00000000034%d" % seat,
				ron_ctx.decision_id, 0, seat + 1)
		else:
			action = Action.make_pass(
				seat, "local", "550e8400-e29b-41d4-a716-00000000034%d" % seat,
				ron_ctx.decision_id, 0, seat + 1)
		assert_true(bc.apply_action(action, ActionSource.HUMAN).accepted)
	return bc


func _last_event(bc: BattleController, type: StringName) -> BattleEvent:
	for index in range(bc.events.size() - 1, -1, -1):
		var event := bc.events[index] as BattleEvent
		if event.type == type:
			return event
	return null


func _skill_event(bc: BattleController, skill_id: StringName) -> BattleEvent:
	for event_value in bc.events:
		var event := event_value as BattleEvent
		if event.type == &"SKILL_TRIGGERED" \
				and StringName(String(event.extra.get("skill_id", ""))) == skill_id:
			return event
	return null


func _event_index(bc: BattleController, event: BattleEvent) -> int:
	return bc.events.find(event)


func test_bao_luo_owner_tsumo_uses_red_bucket_in_real_score_and_events() -> void:
	var baseline := _settle_tsumo()
	var powered := _settle_tsumo(0, true)
	var base_win := _last_event(baseline, &"WIN_DECLARED")
	var win := _last_event(powered, &"WIN_DECLARED")
	assert_not_null(base_win)
	assert_not_null(win)
	assert_gte(int(base_win.extra.get("dora_count", 0)), 1,
		"真实手牌必须包含至少一张实体赤五")
	assert_eq(powered.state.extra_dora_count, [0, 0, 0, 0],
		"宝络绯不得冒充华岭澄的普通能力 Dora")
	assert_eq(powered.state.extra_red_dora_count, [2, 0, 0, 0])
	assert_eq(int(win.extra.get("ability_extra_dora_count", -1)), 0)
	assert_eq(int(win.extra.get("ability_extra_red_dora_count", -1)), 2)
	assert_eq(int(win.extra.get("dora_count", -1)),
		int(base_win.extra.get("dora_count", -1)) + 2)
	assert_eq(int(win.extra.get("han", 0)), int(base_win.extra.get("han", 0)) + 2)
	assert_gt(int(win.extra.get("winner_total", 0)), int(base_win.extra.get("winner_total", 0)))
	var skill := _skill_event(powered, &"char_kuro_passive_v1")
	assert_not_null(skill)
	if skill == null:
		return
	assert_eq(int(skill.extra.get("extra_red_dora_delta", 0)), 2)
	assert_false(skill.extra.has("extra_dora_delta"))
	assert_lt(_event_index(powered, skill), _event_index(powered, win),
		"能力事件必须先于最终确认结算")


func test_bao_luo_owner_ron_uses_red_bucket_in_real_payment() -> void:
	var baseline := _settle_chankan_ron()
	var powered := _settle_chankan_ron(1, true)
	var base_win := _last_event(baseline, &"WIN_DECLARED")
	var win := _last_event(powered, &"WIN_DECLARED")
	assert_not_null(base_win)
	assert_not_null(win)
	assert_false(bool(win.extra.get("is_tsumo", true)))
	assert_eq(int(win.extra.get("ability_extra_red_dora_count", -1)), 2)
	assert_eq(int(win.extra.get("dora_count", -1)),
		int(base_win.extra.get("dora_count", -1)) + 2)
	assert_eq(int(win.extra.get("han", 0)), int(base_win.extra.get("han", 0)) + 2)
	assert_gt(int(win.extra.get("winner_total", 0)), int(base_win.extra.get("winner_total", 0)))
	var skill := _skill_event(powered, &"char_kuro_passive_v1")
	assert_not_null(skill)
	if skill != null:
		assert_eq(int(skill.extra.get("extra_red_dora_delta", 0)), 2)
		assert_lt(_event_index(powered, skill), _event_index(powered, win),
			"RON 能力事件必须先于最终确认结算")


func test_bao_luo_non_owner_and_unarmed_slots_do_not_trigger() -> void:
	for bc in [_settle_tsumo(1, true), _settle_tsumo(0, false)]:
		var win := _last_event(bc, &"WIN_DECLARED")
		assert_not_null(win)
		assert_eq(bc.state.extra_red_dora_count, [0, 0, 0, 0])
		assert_eq(int(win.extra.get("ability_extra_red_dora_count", -1)), 0)
		assert_null(_skill_event(bc, &"char_kuro_passive_v1"),
			"非 owner 或未武装不得产生空技能反馈/语音")


func test_bao_luo_armed_without_win_event_does_not_trigger() -> void:
	var bc := BattleController.new(348, 0, false, TileId.E)
	_bind_bao_slot(bc, 0, true)
	bc._emit(&"TILE_DRAWN", 0, null, {})
	assert_eq(bc.state.extra_red_dora_count, [0, 0, 0, 0])
	assert_null(_skill_event(bc, &"char_kuro_passive_v1"),
		"已武装但未进入合法和牌前事件时不得触发")


func test_red_ability_stacks_with_hua_ling_and_ordinary_dora_without_mixing_attribution() -> void:
	var baseline := _settle_tsumo()
	var stacked := _settle_tsumo(0, true, true, true)
	var base_win := _last_event(baseline, &"WIN_DECLARED")
	var win := _last_event(stacked, &"WIN_DECLARED")
	assert_eq(int(win.extra.get("dora_count", -1)),
		int(base_win.extra.get("dora_count", -1)) + 5,
		"宝络绯 +2 赤、华岭澄 +2 普通、牌技能 +1 必须加法叠加")
	assert_eq(int(win.extra.get("ability_extra_dora_count", -1)), 2)
	assert_eq(int(win.extra.get("ability_extra_red_dora_count", -1)), 2)
	var hua_skill := _skill_event(stacked, &"char_saki_passive_v1")
	var bao_skill := _skill_event(stacked, &"char_kuro_passive_v1")
	assert_not_null(hua_skill)
	assert_not_null(bao_skill)
	if hua_skill != null:
		assert_eq(int(hua_skill.extra.get("extra_dora_delta", 0)), 2)
	if bao_skill != null:
		assert_eq(int(bao_skill.extra.get("extra_red_dora_delta", 0)), 2)


func test_bao_luo_red_state_and_events_survive_restore_then_reset() -> void:
	var settled := _settle_tsumo(0, true)
	var source := BattleController.new(42, 0, false, TileId.E)
	_bind_bao_slot(source, 0, true)
	source._emit(&"WIN_DECLARED_PRE", 0, null, {"is_tsumo": true})
	for event_type in [&"SKILL_TRIGGERED", &"WIN_DECLARED"]:
		var produced := _last_event(settled, event_type)
		assert_not_null(produced)
		if produced != null:
			source.events.append(BattleEvent.make(
				produced.type, produced.actor_seat, null, produced.extra.duplicate(true)))
	assert_eq(source.state.extra_red_dora_count, [2, 0, 0, 0])
	var snapshot := AuthorityReplaySnapshot.capture(source)
	assert_not_null(snapshot)
	var restored := BattleController.new(99, 0, false, TileId.E)
	assert_true(snapshot.restore_into(restored))
	assert_eq(restored.state.extra_dora_count, [0, 0, 0, 0])
	assert_eq(restored.state.extra_red_dora_count, [2, 0, 0, 0])
	var restored_skill := _skill_event(restored, &"char_kuro_passive_v1")
	var restored_win := _last_event(restored, &"WIN_DECLARED")
	assert_not_null(restored_skill)
	assert_not_null(restored_win)
	if restored_skill != null:
		assert_eq(int(restored_skill.extra.get("extra_red_dora_delta", 0)), 2)
	if restored_win != null:
		assert_eq(int(restored_win.extra.get("ability_extra_red_dora_count", 0)), 2)
	var next_hand := BattleController.new(100, 0, false, TileId.E)
	assert_eq(next_hand.state.extra_red_dora_count, [0, 0, 0, 0],
		"新一局权威状态不得残留上一局能力赤 Dora")
