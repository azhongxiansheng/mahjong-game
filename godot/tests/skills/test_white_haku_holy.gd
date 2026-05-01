extends GutTest

# 麻将王 — M6 内容生产示范：白板·圣光（§8.1 增番系）

const Hook := preload("res://skills/hooks/white_haku_holy_hook.gd")

func _make_skill() -> SkillResource:
	var s := SkillResource.new()
	s.id = &"white_haku_holy_v1"
	s.attached_tile = TileId.HAKU
	s.rarity = Rarity.Kind.UNCOMMON
	# holder_trigger 模式：胡牌者 = 持牌者时 +1 番
	var ht: Array[StringName] = [&"WIN_DECLARED"]
	s.holder_triggers = ht
	s.hook_script = Hook
	return s

func _setup() -> Array:
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	return [reg, st, sched]

func test_holy_adds_1_han_when_holder_is_winner():
	# seat 2 是 holder 也是 actor（自胡）→ +1 番
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_skill()
	var ti := TileInstance.make(Tile.new(TileId.HAKU), 0, sk)
	ti.holder_seat = 2
	reg.register(sk, ti)
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 2))
	assert_eq(int(out_ctx.han_deltas.get(2, 0)), 1, "holder=2 自胡 → +1 番")

func test_holy_no_han_when_holder_not_winner():
	# seat 2 是 holder，但 seat 0 是胡牌者 → 不加番
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_skill()
	var ti := TileInstance.make(Tile.new(TileId.HAKU), 0, sk)
	ti.holder_seat = 2
	reg.register(sk, ti)
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(int(out_ctx.han_deltas.get(0, 0)), 0, "actor != holder 时不触发")
	assert_eq(int(out_ctx.han_deltas.get(2, 0)), 0, "holder 也不会被加番")

func test_holy_no_han_when_no_holder_set():
	# 牌没人持（holder_seat = -1）→ trigger 不触发
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_skill()
	var ti := TileInstance.make(Tile.new(TileId.HAKU), 0, sk)
	ti.holder_seat = -1  # 没人持
	reg.register(sk, ti)
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(int(out_ctx.han_deltas.get(0, 0)), 0, "无 holder 时 holder_trigger 不触发")
