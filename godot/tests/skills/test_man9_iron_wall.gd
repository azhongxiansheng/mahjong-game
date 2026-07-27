extends GutTest

# 麻将王 — M6 内容生产：9 万·铁壁（§8.3 阻胡系）

const Hook := preload("res://skills/hooks/man9_iron_wall_hook.gd")

func _make_skill() -> SkillResource:
	var s := SkillResource.new()
	s.id = &"man9_iron_wall_v1"
	s.attached_tile = TileId.W9
	s.rarity = Rarity.Kind.UNCOMMON
	# owner_trigger 模式：owner 被荣胡时 -1 番
	var ot: Array[StringName] = [&"RON_DECLARED"]
	s.owner_triggers = ot
	s.hook_script = Hook
	return s

func _setup() -> Array:
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	return [reg, st, sched]

func test_iron_wall_subtracts_1_han_when_owner_is_discarder():
	# seat 0 是 owner，也是出铳方；seat 1 荣胡 → seat 1 -1 番
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var sched: SkillScheduler = arr[2]
	var sk := _make_skill()
	var ti := TileSkillAnchor.make(Tile.new(TileId.W9), 0, sk)
	reg.register(sk, ti)
	var out_ctx := sched.emit_event(
		BattleEvent.make(&"RON_DECLARED", 1, ti, {"discarder_seat": 0})
	)
	assert_eq(int(out_ctx.han_deltas.get(1, 0)), -1, "owner 出铳被 RON → 胡牌方 -1 番")

func test_iron_wall_does_nothing_when_owner_is_not_discarder():
	# seat 0 是 owner；seat 2 出铳；seat 1 荣胡 → 不触发
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var sched: SkillScheduler = arr[2]
	var sk := _make_skill()
	var ti := TileSkillAnchor.make(Tile.new(TileId.W9), 0, sk)
	reg.register(sk, ti)
	var out_ctx := sched.emit_event(
		BattleEvent.make(&"RON_DECLARED", 1, ti, {"discarder_seat": 2})
	)
	assert_eq(int(out_ctx.han_deltas.get(1, 0)), 0, "owner 不是出铳方 → 不减番")

func test_iron_wall_does_nothing_when_discarder_seat_missing():
	# event.extra 没有 discarder_seat 字段（异常路径）→ 不触发，不崩
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var sched: SkillScheduler = arr[2]
	var sk := _make_skill()
	var ti := TileSkillAnchor.make(Tile.new(TileId.W9), 0, sk)
	reg.register(sk, ti)
	var out_ctx := sched.emit_event(BattleEvent.make(&"RON_DECLARED", 1, ti))
	assert_eq(int(out_ctx.han_deltas.get(1, 0)), 0, "缺 discarder_seat → 当不触发处理")
