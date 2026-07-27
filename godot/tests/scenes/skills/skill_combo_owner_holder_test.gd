extends SkillTestSceneBase

# 复合场景 — 两张技能挂同一事件 WIN_DECLARED，验证 SkillScheduler 在同事件
# 中按 (group asc, rarity desc, reg_order asc) 调度两组（owner / holder）的能力。
#
# 注册：
#   - thunder_5w_v1     owner_seat=0, rarity=2, owner_trigger=WIN_DECLARED   (+1 han to owner)
#   - soul_drain_v1     owner_seat=3, holder_seat=2, rarity=3, holder_trigger=WIN_DECLARED  (转 30% 给 holder)
#
# 三个按钮覆盖三种归属模式（actor 与 owner/holder 的关系）：
#   A) actor=0 (= thunder.owner, ≠ soul_drain.holder)：两张都触发
#   B) actor=2 (≠ thunder.owner, = soul_drain.holder 自胡)：均不触发
#   C) actor=1 (≠ thunder.owner, ≠ soul_drain.holder)：仅 soul_drain 触发

const ThunderHook := preload("res://skills/hooks/thunder_5w_hook.gd")
const SoulDrainHook := preload("res://skills/hooks/soul_drain_hatsu_hook.gd")

var _thunder: SkillResource
var _soul_drain: SkillResource

func _scene_title() -> String:
	return "复合 — thunder_5w(owner=0) + soul_drain_hatsu(owner=3, holder=2) 同 WIN_DECLARED"

func _trigger_buttons() -> Array:
	return [
		{"id": &"actor_0_owner_self_win", "label": "A) actor=0 自胡 points=8000 (两张都触发)"},
		{"id": &"actor_2_holder_self_win", "label": "B) actor=2 自胡 (均不触发)"},
		{"id": &"actor_1_third_party_win", "label": "C) actor=1 对手胡 points=8000 (仅 soul_drain 触发)"},
	]

func _register_skill() -> void:
	# thunder 5万·闪电 — owner_seat=0
	_thunder = SkillResource.new()
	_thunder.id = &"thunder_5w_v1"
	_thunder.attached_tile = TileId.W5
	_thunder.rarity = 2
	var ot: Array[StringName] = [&"WIN_DECLARED"]
	_thunder.owner_triggers = ot
	_thunder.hook_script = ThunderHook
	var ti_thunder := TileSkillAnchor.make(Tile.new(TileId.W5), 0, _thunder)
	ti_thunder.holder_seat = 0
	_registry.register(_thunder, ti_thunder)

	# soul drain 发·吸魂 — owner=3 持牌 holder=2
	_soul_drain = SkillResource.new()
	_soul_drain.id = &"soul_drain_hatsu_v1"
	_soul_drain.attached_tile = TileId.HATSU
	_soul_drain.rarity = 3
	var ht: Array[StringName] = [&"WIN_DECLARED"]
	_soul_drain.holder_triggers = ht
	_soul_drain.hook_script = SoulDrainHook
	var ti_drain := TileSkillAnchor.make(Tile.new(TileId.HATSU), 3, _soul_drain)
	ti_drain.holder_seat = 2
	_registry.register(_soul_drain, ti_drain)

func _on_trigger(trigger_id: StringName) -> SkillCtx:
	var actor := 0
	match trigger_id:
		&"actor_0_owner_self_win":
			actor = 0
		&"actor_2_holder_self_win":
			actor = 2
		&"actor_1_third_party_win":
			actor = 1
	return _scheduler.emit_event(
		BattleEvent.make(&"WIN_DECLARED", actor, null, {"points_won": 8000})
	)

func _evaluate(ctx: SkillCtx) -> String:
	var actor := ctx.get_event().actor_seat
	var han_owner := int(ctx.han_deltas.get(0, 0))
	var s := _state.scores
	var starting := BattleState.STARTING_SCORE
	var transferred := int(8000 * 0.3)  # 2400

	match actor:
		0:
			# A: 两张都触发
			var thunder_ok := han_owner == 1
			# soul_drain: actor=0 ≠ holder=2 → 转账
			var drain_ok := s[0] == starting - transferred and s[2] == starting + transferred
			if thunder_ok and drain_ok:
				return "PASS: thunder +1 han to seat 0, soul_drain 0 → 2 转 %d" % transferred
			return "FAIL: thunder=%s drain=%s han_deltas[0]=%d scores=%s" % [
				thunder_ok, drain_ok, han_owner, str(s)
			]
		2:
			# B: 均不触发
			if han_owner == 0 and s[0] == starting and s[2] == starting:
				return "PASS: actor=2 = soul_drain.holder 自胡，两张技能均未触发"
			return "FAIL: 期望均不触发，实际 han_deltas[0]=%d scores=%s" % [han_owner, str(s)]
		_:
			# C: 仅 soul_drain
			var thunder_silent := han_owner == 0
			var drain_only := s[1] == starting - transferred and s[2] == starting + transferred and s[0] == starting
			if thunder_silent and drain_only:
				return "PASS: thunder 静默, soul_drain 1 → 2 转 %d" % transferred
			return "FAIL: thunder_silent=%s drain_only=%s han_deltas[0]=%d scores=%s" % [
				thunder_silent, drain_only, han_owner, str(s)
			]
