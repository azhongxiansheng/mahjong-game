extends GutTest

# 麻将王 — M6 内容生产：西风·镜像（§8.3 阻胡系）

const Hook := preload("res://skills/hooks/west_mirror_hook.gd")

func _make_skill() -> SkillResource:
	var s := SkillResource.new()
	s.id = &"west_mirror_v1"
	s.attached_tile = TileId.W_WIND
	s.rarity = Rarity.Kind.EPIC
	var ot: Array[StringName] = [&"RIICHI_DECLARED"]
	s.owner_triggers = ot
	s.hook_script = Hook
	return s

func _setup() -> Array:
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	# 让 owner=2 处于振听
	st.furiten_flags[2] = true
	var sched := SkillScheduler.new(reg, st)
	return [reg, st, sched]

func test_mirror_clears_furiten_when_owner_riichis():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_skill()
	var ti := TileSkillAnchor.make(Tile.new(TileId.W_WIND), 2, sk)
	reg.register(sk, ti)
	assert_true(st.furiten_flags[2], "前置：owner 振听中")
	sched.emit_event(BattleEvent.make(&"RIICHI_DECLARED", 2))
	assert_false(st.furiten_flags[2], "owner 立直触发后振听被清除")

func test_mirror_no_effect_when_other_seat_riichis():
	# owner=2 在振听；seat 1 立直 → owner_trigger 不为 owner=2 触发，不清除
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_skill()
	var ti := TileSkillAnchor.make(Tile.new(TileId.W_WIND), 2, sk)
	reg.register(sk, ti)
	sched.emit_event(BattleEvent.make(&"RIICHI_DECLARED", 1))
	assert_true(st.furiten_flags[2], "别人立直时 owner 振听不应被清除")

func test_mirror_safe_when_owner_not_in_furiten():
	# owner=2 不在振听；立直触发 hook 仍调 clear_furiten 但 idempotent
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	st.furiten_flags[2] = false  # 重置
	var sk := _make_skill()
	var ti := TileSkillAnchor.make(Tile.new(TileId.W_WIND), 2, sk)
	reg.register(sk, ti)
	sched.emit_event(BattleEvent.make(&"RIICHI_DECLARED", 2))
	assert_false(st.furiten_flags[2], "本来就非振听，调用后仍非振听")
