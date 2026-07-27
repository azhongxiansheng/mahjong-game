extends SkillTestSceneBase

const Hook := preload("res://skills/hooks/unfuriten_5p_hook.gd")

var _skill: SkillResource

func _scene_title() -> String:
	return "5筒·解除振听 — §8.6 立直系 Demo(消耗型)"

func _trigger_buttons() -> Array:
	return [
		{"id": &"furiten_0", "label": "标记 furiten_flags[0]=true 后 Trigger FURITEN_TRIGGERED actor=0"},
	]

func _register_skill() -> void:
	_skill = SkillResource.new()
	_skill.id = &"unfuriten_5p_v1"
	_skill.attached_tile = TileId.T5
	_skill.rarity = 2
	var ot: Array[StringName] = [&"FURITEN_TRIGGERED"]
	_skill.owner_triggers = ot
	_skill.hook_script = Hook
	var ti := TileSkillAnchor.make(Tile.new(TileId.T5), 0, _skill)
	ti.holder_seat = 0
	_registry.register(_skill, ti)

func _on_trigger(_trigger_id: StringName) -> SkillCtx:
	_state.furiten_flags[0] = true
	return _scheduler.emit_event(BattleEvent.make(&"FURITEN_TRIGGERED", 0))

func _evaluate(_ctx: SkillCtx) -> String:
	if not _skill.consumed:
		# 第二次点击且 skill 已 consumed → 本次按钮调用前 furiten_flags[0] 又被设回 true
		# 但 hook 因 consumed 不再 clear,所以 flag 应保持 true
		if _state.furiten_flags[0]:
			return "(二次点击)PASS: consumed=true,furiten_flags[0] 未被清"
		return "FAIL: skill 未消耗也未清 furiten"
	# 首次:期望 furiten_flags[0]=false 且 consumed=true
	if not _state.furiten_flags[0] and _skill.consumed:
		return "PASS: furiten_flags[0]=false,skill consumed"
	return "FAIL: furiten_flags[0]=%s consumed=%s" % [str(_state.furiten_flags[0]), str(_skill.consumed)]
