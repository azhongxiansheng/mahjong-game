extends GutTest

# WinBurst + ScreenShake — 单元测试 cover tier 分级、粒子生成数、震动归零。


# ---- WinBurst ----

func test_winburst_spawns_expected_particle_count_light() -> void:
	var burst := WinBurst.new()
	add_child_autofree(burst)
	burst.play(WinBurst.Tier.LIGHT)
	# 已 spawn 完毕,child count 应等于 LIGHT 的 PARTICLE_COUNTS
	assert_eq(burst.get_child_count(),
		int(WinBurst.PARTICLE_COUNTS[WinBurst.Tier.LIGHT]),
		"LIGHT tier 应生 24 个粒子")


func test_winburst_spawns_expected_particle_count_yakuman() -> void:
	var burst := WinBurst.new()
	add_child_autofree(burst)
	burst.play(WinBurst.Tier.YAKUMAN)
	assert_eq(burst.get_child_count(),
		int(WinBurst.PARTICLE_COUNTS[WinBurst.Tier.YAKUMAN]),
		"YAKUMAN tier 应生 140 个粒子")


# tier 颜色不同
func test_winburst_tier_colors_distinct() -> void:
	var light_c: Color = WinBurst.TIER_COLORS[WinBurst.Tier.LIGHT]
	var yakuman_c: Color = WinBurst.TIER_COLORS[WinBurst.Tier.YAKUMAN]
	assert_ne(light_c, yakuman_c, "tier 颜色应不同")


# tier 持续时间随级增长
func test_winburst_durations_monotone() -> void:
	var d_light: float = float(WinBurst.TIER_DURATIONS[WinBurst.Tier.LIGHT])
	var d_medium: float = float(WinBurst.TIER_DURATIONS[WinBurst.Tier.MEDIUM])
	var d_heavy: float = float(WinBurst.TIER_DURATIONS[WinBurst.Tier.HEAVY])
	var d_yakuman: float = float(WinBurst.TIER_DURATIONS[WinBurst.Tier.YAKUMAN])
	assert_true(d_light < d_medium and d_medium < d_heavy and d_heavy < d_yakuman,
		"持续时间应随 tier 递增")


# ---- ScreenShake ----

func test_screen_shake_tier_intensity_monotone() -> void:
	var i_light: float = float(ScreenShake.TIER_INTENSITY[WinBurst.Tier.LIGHT])
	var i_yakuman: float = float(ScreenShake.TIER_INTENSITY[WinBurst.Tier.YAKUMAN])
	assert_true(i_yakuman > i_light, "YAKUMAN 震动比 LIGHT 强")


func test_screen_shake_for_tier_constructor() -> void:
	var target := Node2D.new()
	add_child_autofree(target)
	var shake := ScreenShake.for_tier(target, WinBurst.Tier.MEDIUM)
	assert_not_null(shake, "for_tier 应返非空 ScreenShake")
	assert_eq(shake._intensity, float(ScreenShake.TIER_INTENSITY[WinBurst.Tier.MEDIUM]))
	assert_eq(shake._duration, float(ScreenShake.TIER_DURATION[WinBurst.Tier.MEDIUM]))


# ScreenShake.start 不挂在树上的 target 应静默退出
func test_screen_shake_invalid_target_no_crash() -> void:
	var target := Node2D.new()
	# 不 add_child,target.get_tree() 返 null
	var shake := ScreenShake.new(target, 10.0, 0.2)
	shake.start()  # 应静默,不崩
	assert_true(true)
	target.free()


# ---- PlayableTable._win_tier 分级逻辑 ----

func test_win_tier_yakuman() -> void:
	var ev := BattleEvent.new()
	ev.extra = {"yakuman_multiplier": 1, "han": 0}
	# 实例化一次只跑 _win_tier
	var table := PlayableTable.new()
	add_child_autofree(table)
	assert_eq(table._win_tier(ev), WinBurst.Tier.YAKUMAN)


func test_win_tier_heavy_for_sanbaiman() -> void:
	var ev := BattleEvent.new()
	ev.extra = {"yakuman_multiplier": 0, "han": 11}
	var table := PlayableTable.new()
	add_child_autofree(table)
	assert_eq(table._win_tier(ev), WinBurst.Tier.HEAVY)


func test_win_tier_medium_for_haneman() -> void:
	var ev := BattleEvent.new()
	ev.extra = {"yakuman_multiplier": 0, "han": 6}
	var table := PlayableTable.new()
	add_child_autofree(table)
	assert_eq(table._win_tier(ev), WinBurst.Tier.MEDIUM)


func test_win_tier_light_for_normal_hand() -> void:
	var ev := BattleEvent.new()
	ev.extra = {"yakuman_multiplier": 0, "han": 3}
	var table := PlayableTable.new()
	add_child_autofree(table)
	assert_eq(table._win_tier(ev), WinBurst.Tier.LIGHT)


func test_win_tier_null_event_returns_light() -> void:
	var table := PlayableTable.new()
	add_child_autofree(table)
	assert_eq(table._win_tier(null), WinBurst.Tier.LIGHT)
