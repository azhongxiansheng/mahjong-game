extends GutTest

# StatsManager — 验证终身统计累计 + 成就解锁。
# 用专门 "scratch" 副本测,避免污染实际玩家存档(autoload 实例直接操作就行 —
# 测试结束 GUT 不会持久化变化到 user://stats.json 之外)。


func _sm() -> Node:
	return get_tree().root.get_node("/root/StatsManager")


func before_each() -> void:
	# 每个测试前重置 stats 内存状态(不动磁盘),让断言可重复
	var sm = _sm()
	if sm == null:
		return
	sm.hands_played = 0
	sm.hands_won = 0
	sm.hands_lost_by_deal_in = 0
	sm.tsumo_count = 0
	sm.ron_count = 0
	sm.yakuman_count = 0
	sm.double_yakuman_count = 0
	sm.riichi_count = 0
	sm.double_riichi_count = 0
	sm.ippatsu_count = 0
	sm.haitei_count = 0
	sm.rinshan_count = 0
	sm.runs_started = 0
	sm.runs_won = 0
	sm.runs_failed = 0
	sm.highest_single_hand_score = 0
	sm.total_points_won = 0
	sm.unlocked_achievements = {}


# ---- autoload 注册 ----

func test_autoload_registered() -> void:
	assert_not_null(_sm(), "/root/StatsManager autoload 应已挂载")


# ---- record_hand_end ----

func test_record_hand_loss_increments_played() -> void:
	var sm = _sm()
	sm.record_hand_end(null, false, false)
	assert_eq(sm.hands_played, 1)
	assert_eq(sm.hands_won, 0)


func test_record_hand_win_tsumo() -> void:
	var sm = _sm()
	var ev := BattleEvent.new()
	ev.actor_seat = 0
	ev.extra = {"yakuman_multiplier": 0, "han": 3, "winner_total": 5200,
		"yaku_names": [], "discarder_seat": -1}  # discarder<0 = tsumo
	sm.record_hand_end(ev, true, false)
	assert_eq(sm.hands_played, 1)
	assert_eq(sm.hands_won, 1)
	assert_eq(sm.tsumo_count, 1)
	assert_eq(sm.ron_count, 0)
	assert_eq(sm.highest_single_hand_score, 5200)
	assert_eq(sm.total_points_won, 5200)


func test_record_hand_win_ron() -> void:
	var sm = _sm()
	var ev := BattleEvent.new()
	ev.actor_seat = 0
	ev.extra = {"yakuman_multiplier": 0, "han": 4, "winner_total": 8000,
		"discarder_seat": 2}
	sm.record_hand_end(ev, true, false)
	assert_eq(sm.ron_count, 1)
	assert_eq(sm.tsumo_count, 0)


func test_record_yakuman_increments_count() -> void:
	var sm = _sm()
	var ev := BattleEvent.new()
	ev.actor_seat = 0
	ev.extra = {"yakuman_multiplier": 1, "han": 0, "winner_total": 32000,
		"discarder_seat": -1}
	sm.record_hand_end(ev, true, false)
	assert_eq(sm.yakuman_count, 1)
	assert_eq(sm.double_yakuman_count, 0)


func test_record_double_yakuman() -> void:
	var sm = _sm()
	var ev := BattleEvent.new()
	ev.extra = {"yakuman_multiplier": 2, "han": 0, "winner_total": 64000,
		"discarder_seat": -1}
	sm.record_hand_end(ev, true, false)
	assert_eq(sm.yakuman_count, 1)
	assert_eq(sm.double_yakuman_count, 1)


# 特殊役命中(一発/海底/岭上)从 yaku_names 抽取
func test_ippatsu_counted_from_yaku_names() -> void:
	var sm = _sm()
	var ev := BattleEvent.new()
	ev.extra = {"yakuman_multiplier": 0, "han": 2,
		"yaku_names": [{"name": "立直", "han": 1}, {"name": "一発", "han": 1}],
		"discarder_seat": -1}
	sm.record_hand_end(ev, true, false)
	assert_eq(sm.ippatsu_count, 1)


# 玩家放铳计数
func test_loser_was_player_counted() -> void:
	var sm = _sm()
	var ev := BattleEvent.new()
	ev.actor_seat = 2
	ev.extra = {"discarder_seat": 0}
	sm.record_hand_end(ev, false, true)
	assert_eq(sm.hands_lost_by_deal_in, 1)


# ---- record_riichi ----

func test_record_riichi() -> void:
	var sm = _sm()
	sm.record_riichi(false)
	assert_eq(sm.riichi_count, 1)
	assert_eq(sm.double_riichi_count, 0)
	sm.record_riichi(true)
	assert_eq(sm.riichi_count, 2)
	assert_eq(sm.double_riichi_count, 1)


# ---- record_run_* ----

func test_record_run_lifecycle() -> void:
	var sm = _sm()
	sm.record_run_started()
	assert_eq(sm.runs_started, 1)
	sm.record_run_ended(true)
	assert_eq(sm.runs_won, 1)
	assert_eq(sm.runs_failed, 0)
	sm.record_run_started()
	sm.record_run_ended(false)
	assert_eq(sm.runs_started, 2)
	assert_eq(sm.runs_failed, 1)


# ---- 成就解锁 ----

func test_first_win_unlocks() -> void:
	var sm = _sm()
	watch_signals(sm)
	var ev := BattleEvent.new()
	ev.extra = {"winner_total": 1000, "discarder_seat": -1, "han": 1,
		"yakuman_multiplier": 0}
	sm.record_hand_end(ev, true, false)
	assert_true(sm.unlocked_achievements.has("first_win"),
		"首胡应解锁")
	assert_signal_emitted(sm, "achievement_unlocked")


func test_first_yakuman_unlocks() -> void:
	var sm = _sm()
	var ev := BattleEvent.new()
	ev.extra = {"yakuman_multiplier": 1, "winner_total": 32000,
		"discarder_seat": -1}
	sm.record_hand_end(ev, true, false)
	assert_true(sm.unlocked_achievements.has("first_yakuman"))


func test_score_32000_unlocks() -> void:
	var sm = _sm()
	var ev := BattleEvent.new()
	ev.extra = {"winner_total": 32000, "discarder_seat": -1,
		"yakuman_multiplier": 1}
	sm.record_hand_end(ev, true, false)
	assert_true(sm.unlocked_achievements.has("score_32000"))
	assert_true(sm.unlocked_achievements.has("score_18000"),
		"18000 阈值同时也命中")


func test_achievement_not_re_emitted() -> void:
	var sm = _sm()
	watch_signals(sm)
	var ev := BattleEvent.new()
	ev.extra = {"winner_total": 1000, "discarder_seat": -1,
		"yakuman_multiplier": 0}
	sm.record_hand_end(ev, true, false)
	var first_emit_count: int = get_signal_emit_count(sm, "achievement_unlocked")
	# 再胡一次,first_win 已解锁不应再发
	sm.record_hand_end(ev, true, false)
	var second_emit_count: int = get_signal_emit_count(sm, "achievement_unlocked")
	# 再次胡牌只新解锁 0 个(first_win 已解锁,hands_won 没到 100)
	assert_eq(second_emit_count, first_emit_count,
		"已解锁成就不应重复 emit")


# ---- 持久化 round-trip ----

func test_round_trip_save_load() -> void:
	var sm = _sm()
	sm.hands_won = 42
	sm.yakuman_count = 3
	sm._save_to_disk()
	# 改内存值
	sm.hands_won = 0
	sm.yakuman_count = 0
	sm._load_from_disk()
	assert_eq(sm.hands_won, 42)
	assert_eq(sm.yakuman_count, 3)
