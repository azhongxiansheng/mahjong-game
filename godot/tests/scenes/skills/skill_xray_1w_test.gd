extends SkillTestSceneBase

const Hook := preload("res://skills/hooks/xray_1w_hook.gd")

var _skill: SkillResource

func _scene_title() -> String:
	return "1万·透视 — §8.5 透明牌 / 信息系 Demo"

func _trigger_buttons() -> Array:
	return [
		{"id": &"draw_actor_0", "label": "Trigger TILE_DRAWN actor=0(owner)"},
		{"id": &"draw_actor_2", "label": "Trigger TILE_DRAWN actor=2(non-owner)"},
	]

func _register_skill() -> void:
	_skill = SkillResource.new()
	_skill.id = &"xray_1w_v1"
	_skill.attached_tile = TileId.W1
	_skill.rarity = 1
	var ot: Array[StringName] = [&"TILE_DRAWN"]
	_skill.owner_triggers = ot
	_skill.hook_script = Hook
	var ti := TileInstance.make(Tile.new(TileId.W1), 0, _skill)
	ti.holder_seat = 0
	_registry.register(_skill, ti)

func _on_trigger(trigger_id: StringName) -> SkillCtx:
	var actor := 0 if trigger_id == &"draw_actor_0" else 2
	return _scheduler.emit_event(BattleEvent.make(&"TILE_DRAWN", actor))

func _evaluate(ctx: SkillCtx) -> String:
	var actor := ctx.get_event().actor_seat
	if actor == 0:
		if _state.revealed_tiles.size() == 1 and _state.revealed_tiles[0]["visible_to"].has(0):
			return "PASS: revealed_tiles 有 1 项,visible_to 包含座位 0"
		return "FAIL: 期望 1 项 visible_to=[0],实际 %s" % str(_state.revealed_tiles)
	if _state.revealed_tiles.size() == 0:
		return "PASS: 非 owner 摸牌不触发,revealed_tiles 为空"
	return "FAIL: 非 owner 摸牌不应产生 reveal 项"
