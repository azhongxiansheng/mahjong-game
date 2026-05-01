extends SkillTestSceneBase

const Hook := preload("res://skills/hooks/seal_chun_hook.gd")

var _skill: SkillResource
var _ti: TileInstance

func _scene_title() -> String:
	return "中·封印 — §8.3 阻胡系 Demo(消耗型)"

func _trigger_buttons() -> Array:
	return [
		{"id": &"ron_owner_discarded", "label": "Trigger RON_DECLARED actor=1(owner=0 出铳)"},
	]

func _register_skill() -> void:
	_skill = SkillResource.new()
	_skill.id = &"seal_chun_v1"
	_skill.attached_tile = TileId.CHUN
	_skill.rarity = 2
	var ot: Array[StringName] = [&"RON_DECLARED"]
	_skill.owner_triggers = ot
	_skill.hook_script = Hook
	_ti = TileInstance.make(Tile.new(TileId.CHUN), 0, _skill)
	_registry.register(_skill, _ti)

func _on_trigger(_trigger_id: StringName) -> SkillCtx:
	return _scheduler.emit_event(
		BattleEvent.make(&"RON_DECLARED", 1, _ti, {"discarder_seat": 0})
	)

func _evaluate(_ctx: SkillCtx) -> String:
	var lines: Array = []
	lines.append("ron_cancelled[1] = %s" % str(_state.ron_cancelled[1]))
	lines.append("skill.consumed   = %s" % str(_skill.consumed))
	if _state.ron_cancelled[1] and _skill.consumed:
		lines.append("PASS: 取消荣胡 + 技能消耗")
	elif _skill.consumed:
		lines.append("PASS(二次点击): consumed=true,本次不再触发")
	else:
		lines.append("FAIL: 未取消荣胡且未消耗")
	return "\n".join(lines)
