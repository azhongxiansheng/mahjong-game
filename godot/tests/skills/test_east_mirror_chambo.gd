extends GutTest

# 麻将王 — M6 内容生产：东·镜抓（§8.4 抓马反向得分系）

const Hook := preload("res://skills/hooks/east_mirror_chambo_hook.gd")

func _make_skill() -> SkillResource:
	var s := SkillResource.new()
	s.id = &"east_mirror_chambo_v1"
	s.attached_tile = TileId.E
	s.rarity = Rarity.Kind.EPIC
	# owner_trigger 模式：owner 出铳时反向 50% 得分
	var ot: Array[StringName] = [&"RON_DECLARED"]
	s.owner_triggers = ot
	s.hook_script = Hook
	return s

func _setup() -> Array:
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	return [reg, st, sched]

func test_chambo_refunds_50_percent_when_owner_is_discarder():
	# seat 0 是 owner（出铳方）；seat 1 荣胡 8000 → seat 0 拿回 4000
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var st: BattleState = arr[1]
	var sched: SkillScheduler = arr[2]
	var sk := _make_skill()
	var ti := TileInstance.make(Tile.new(TileId.E), 0, sk)
	reg.register(sk, ti)
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 1, ti,
		{"discarder_seat": 0, "points_won": 8000}))
	assert_eq(st.scores[0], 25000 + 4000, "owner 拿回 50%")
	assert_eq(st.scores[1], 25000 - 4000, "胡牌方扣 50%")

func test_chambo_no_refund_when_owner_is_not_discarder():
	# seat 0 是 owner；seat 2 出铳；seat 1 荣胡 → 不触发
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var st: BattleState = arr[1]
	var sched: SkillScheduler = arr[2]
	var sk := _make_skill()
	var ti := TileInstance.make(Tile.new(TileId.E), 0, sk)
	reg.register(sk, ti)
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 1, ti,
		{"discarder_seat": 2, "points_won": 8000}))
	assert_eq(st.scores[0], 25000, "owner 不是出铳方时分数不变")
	assert_eq(st.scores[1], 25000, "胡牌方分数不变")

func test_chambo_no_refund_when_points_won_zero_or_missing():
	# 边界：event.extra 缺 points_won 或为 0 → 不触发不崩
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var st: BattleState = arr[1]
	var sched: SkillScheduler = arr[2]
	var sk := _make_skill()
	var ti := TileInstance.make(Tile.new(TileId.E), 0, sk)
	reg.register(sk, ti)
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 1, ti,
		{"discarder_seat": 0}))  # 无 points_won
	assert_eq(st.scores[0], 25000, "缺 points_won → 不动分")
	assert_eq(st.scores[1], 25000)
