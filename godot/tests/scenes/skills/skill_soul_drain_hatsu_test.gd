extends SkillTestSceneBase

const Hook := preload("res://skills/hooks/soul_drain_hatsu_hook.gd")

var _skill: SkillResource

func _scene_title() -> String:
	return "发·吸魂 — §8.4 抓马反向得分系 Demo(holder 触发)"

func _trigger_buttons() -> Array:
	return [
		{"id": &"opponent_win_8000", "label": "Trigger WIN_DECLARED actor=1 points_won=8000"},
		{"id": &"holder_self_win", "label": "Trigger WIN_DECLARED actor=0 (holder 自胡 — 不应触发)"},
	]

func _register_skill() -> void:
	_skill = SkillResource.new()
	_skill.id = &"soul_drain_hatsu_v1"
	_skill.attached_tile = TileId.HATSU
	_skill.rarity = 3
	var ht: Array[StringName] = [&"WIN_DECLARED"]
	_skill.holder_triggers = ht
	_skill.hook_script = Hook
	# owner 与 holder 分离:owner=2 持牌人=0
	var ti := TileSkillAnchor.make(Tile.new(TileId.HATSU), 2, _skill)
	ti.holder_seat = 0
	_registry.register(_skill, ti)

func _on_trigger(trigger_id: StringName) -> SkillCtx:
	var actor := 1 if trigger_id == &"opponent_win_8000" else 0
	return _scheduler.emit_event(
		BattleEvent.make(&"WIN_DECLARED", actor, null, {"points_won": 8000})
	)

func _evaluate(ctx: SkillCtx) -> String:
	var actor := ctx.get_event().actor_seat
	if actor == 0:
		if _state.scores[0] == BattleState.STARTING_SCORE:
			return "PASS: holder 自胡不触发,scores[0] 不变"
		return "FAIL: holder 自胡时 scores 应不变"
	# opponent 胜
	var expected := BattleState.STARTING_SCORE + 2400
	if _state.scores[0] == expected and _state.scores[1] == BattleState.STARTING_SCORE - 2400:
		return "PASS: scores[0]=%d (+2400), scores[1]=%d (-2400)" % [_state.scores[0], _state.scores[1]]
	return "FAIL: 期望 +/-2400,实际 scores[0]=%d scores[1]=%d" % [_state.scores[0], _state.scores[1]]
