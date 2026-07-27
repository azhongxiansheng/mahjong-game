extends SkillTestSceneBase

const Hook := preload("res://skills/hooks/thunder_5w_hook.gd")

var _skill: SkillResource

func _scene_title() -> String:
	return "5万·闪电 — §8.1 增番系 Demo"

func _trigger_buttons() -> Array:
	return [
		{"id": &"win_actor_0", "label": "Trigger WIN_DECLARED actor=0(owner)"},
		{"id": &"win_actor_1", "label": "Trigger WIN_DECLARED actor=1(non-owner)"},
	]

func _register_skill() -> void:
	_skill = SkillResource.new()
	_skill.id = &"thunder_5w_v1"
	_skill.attached_tile = TileId.W5
	_skill.rarity = 2
	var ot: Array[StringName] = [&"WIN_DECLARED"]
	_skill.owner_triggers = ot
	_skill.hook_script = Hook
	var ti := TileSkillAnchor.make(Tile.new(TileId.W5), 0, _skill)
	ti.holder_seat = 0
	_registry.register(_skill, ti)

func _on_trigger(trigger_id: StringName) -> SkillCtx:
	var actor := 0 if trigger_id == &"win_actor_0" else 1
	return _scheduler.emit_event(BattleEvent.make(&"WIN_DECLARED", actor))

func _evaluate(ctx: SkillCtx) -> String:
	var delta_0 := int(ctx.han_deltas.get(0, 0))
	if ctx.get_event().actor_seat == 0:
		if delta_0 == 1:
			return "PASS: owner 自胡 → han_deltas[0] = +1"
		return "FAIL: 期望 +1,实际 %d" % delta_0
	else:
		if delta_0 == 0:
			return "PASS: 非 owner 胡 → han_deltas[0] = 0"
		return "FAIL: 期望 0,实际 %d" % delta_0
