extends SkillTestSceneBase

const Hook := preload("res://skills/hooks/seabed_hunter_hook.gd")

var _skill: SkillResource

func _scene_title() -> String:
	return "海底狩人 — §8.10 #2 角色能力 Demo(ability + 消耗)"

func _trigger_buttons() -> Array:
	return [
		{"id": &"haitei_actor_1", "label": "Trigger HAITEI actor=1(对手摸最后一张)"},
	]

func _register_skill() -> void:
	_skill = SkillResource.new()
	_skill.id = &"seabed_hunter_v1"
	_skill.is_ability = true
	_skill.rarity = 3
	# 同时挂 owner / holder triggers 验证 dedup 路径仍只触发 1 次
	var ot: Array[StringName] = [&"HAITEI"]
	var ht: Array[StringName] = [&"HAITEI"]
	_skill.owner_triggers = ot
	_skill.holder_triggers = ht
	_skill.hook_script = Hook
	_registry.register(_skill, 0)  # ability 锚点 = 座位 0

func _on_trigger(_trigger_id: StringName) -> SkillCtx:
	return _scheduler.emit_event(BattleEvent.make(&"HAITEI", 1))

func _evaluate(_ctx: SkillCtx) -> String:
	if not _skill.consumed:
		return "FAIL: ability 未触发"
	if _state.haitei_forced_seat == 0:
		return "PASS: haitei_forced_seat=0,ability consumed"
	if _state.haitei_forced_seat == -1:
		return "(二次点击)PASS: consumed,本次不再 force_tsumo"
	return "FAIL: haitei_forced_seat=%d 异常" % _state.haitei_forced_seat
