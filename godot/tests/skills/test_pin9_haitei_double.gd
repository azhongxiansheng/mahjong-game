extends GutTest

# 麻将王 — M6 内容生产：9 筒·龙断（§8.9 终局系）

const Hook := preload("res://skills/hooks/pin9_haitei_double_hook.gd")

func _make_skill() -> SkillResource:
	var s := SkillResource.new()
	s.id = &"pin9_haitei_double_v1"
	s.attached_tile = TileId.T9
	s.rarity = Rarity.Kind.LEGENDARY
	# HAITEI（海底自摸）+ HOUTEI（河底荣胡）— holder_trigger
	var ht: Array[StringName] = [&"HAITEI", &"HOUTEI"]
	s.holder_triggers = ht
	s.hook_script = Hook
	return s

func _setup() -> Array:
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	return [reg, st, sched]

func test_haitei_doubles_han_when_holder_self_tsumos():
	# M7 B3-mini 升级：v1 +1 番 → v2 ×2 真效果
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_skill()
	var ti := TileSkillAnchor.make(Tile.new(TileId.T9), 0, sk)
	ti.holder_seat = 0
	reg.register(sk, ti)
	var out_ctx := sched.emit_event(BattleEvent.make(&"HAITEI", 0))
	assert_eq(float(out_ctx.han_multipliers.get(0, 1.0)), 2.0, "HAITEI 时 holder 自摸 ×2")

func test_houtei_also_triggers():
	# HOUTEI 也在 holder_triggers 列表中
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_skill()
	var ti := TileSkillAnchor.make(Tile.new(TileId.T9), 1, sk)
	ti.holder_seat = 1
	reg.register(sk, ti)
	var out_ctx := sched.emit_event(BattleEvent.make(&"HOUTEI", 1))
	assert_eq(float(out_ctx.han_multipliers.get(1, 1.0)), 2.0, "HOUTEI 也 ×2")

func test_no_effect_when_actor_is_not_holder():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_skill()
	var ti := TileSkillAnchor.make(Tile.new(TileId.T9), 0, sk)
	ti.holder_seat = 0
	reg.register(sk, ti)
	var out_ctx := sched.emit_event(BattleEvent.make(&"HAITEI", 2))
	assert_eq(float(out_ctx.han_multipliers.get(0, 1.0)), 1.0, "actor=2 ≠ holder=0 不触发")
	assert_eq(float(out_ctx.han_multipliers.get(2, 1.0)), 1.0)
