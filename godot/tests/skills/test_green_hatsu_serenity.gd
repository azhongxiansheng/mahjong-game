extends GutTest

# 麻将王 — M6 内容生产：发·禅意（§8.1 增番系）

const Hook := preload("res://skills/hooks/green_hatsu_serenity_hook.gd")

func _make_skill() -> SkillResource:
	var s := SkillResource.new()
	s.id = &"green_hatsu_serenity_v1"
	s.attached_tile = TileId.HATSU
	s.rarity = Rarity.Kind.UNCOMMON
	var ht: Array[StringName] = [&"WIN_DECLARED"]
	s.holder_triggers = ht
	s.hook_script = Hook
	return s

func _setup() -> Array:
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	return [reg, st, sched]

func test_serenity_adds_1_han_when_holder_is_winner():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_skill()
	var ti := TileInstance.make(Tile.new(TileId.HATSU), 1, sk)
	ti.holder_seat = 1
	reg.register(sk, ti)
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 1))
	assert_eq(int(out_ctx.han_deltas.get(1, 0)), 1, "holder=1 自胡 → +1 番")

func test_serenity_no_han_when_other_seat_wins():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_skill()
	var ti := TileInstance.make(Tile.new(TileId.HATSU), 0, sk)
	ti.holder_seat = 1
	reg.register(sk, ti)
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 3))
	assert_eq(int(out_ctx.han_deltas.get(3, 0)), 0, "actor=3 ≠ holder=1 不触发")
	assert_eq(int(out_ctx.han_deltas.get(1, 0)), 0)

func test_serenity_no_holder_no_trigger():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_skill()
	var ti := TileInstance.make(Tile.new(TileId.HATSU), 0, sk)
	ti.holder_seat = -1
	reg.register(sk, ti)
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(int(out_ctx.han_deltas.get(0, 0)), 0, "无 holder 时 holder_trigger 不触发")
