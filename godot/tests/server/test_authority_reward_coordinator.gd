extends GutTest

# ARCH-02 #392：AuthorityRewardCoordinator —— 奖励窗运行时标量状态所有权
#（权威时钟 / CLAIM 可见性 / 延迟 HAND_SETTLED / 终场三态）、只读屏障判定
# 与同事务 capture/restore。LLS 行为不变由 reward/item/skills 套件回归。


func _svc() -> AuthorityRewardCoordinator:
	return AuthorityRewardCoordinator.new()


func test_initial_state_owns_clock_and_flags():
	var svc := _svc()
	assert_eq(svc.now_ms, AuthorityRewardCoordinator.CLOCK_BASE_MS)
	assert_false(svc.claim_seen_open)
	assert_false(svc.hand_settled_deferred)
	assert_null(svc.match_ended, "终场初始为未判定（null），不得为 false")


func test_is_int_ms_rejects_non_int():
	assert_true(AuthorityRewardCoordinator.is_int_ms(0))
	assert_true(AuthorityRewardCoordinator.is_int_ms(1_700_000_000_001))
	assert_false(AuthorityRewardCoordinator.is_int_ms(1.5))
	assert_false(AuthorityRewardCoordinator.is_int_ms("1700"))
	assert_false(AuthorityRewardCoordinator.is_int_ms(null))
	assert_false(AuthorityRewardCoordinator.is_int_ms(true),
		"bool 不是合法权威毫秒")


func test_barrier_fail_open_when_no_reward_module():
	# 标准场无 RewardWindow：屏障不得阻塞普通推进
	var svc := _svc()
	assert_true(svc.allows_normal_progress(null))
	assert_false(svc.is_closing(null))


func test_note_claim_visibility_requires_closing_and_open_window():
	var svc := _svc()
	# 无 rw（非 CLOSING）→ 即使窗开着也不记账
	svc.note_claim_visibility(null, true)
	assert_false(svc.claim_seen_open, "非 CLOSING 不得记 claim 可见")


func test_match_ended_tri_state_semantics():
	var svc := _svc()
	assert_false(svc.match_ended_decided(), "null = 未判定")
	assert_false(svc.match_ended_is_true())
	svc.match_ended = false
	assert_true(svc.match_ended_decided(), "显式 false 也算已判定")
	assert_false(svc.match_ended_is_true())
	svc.match_ended = true
	assert_true(svc.match_ended_decided())
	assert_true(svc.match_ended_is_true())


func test_reset_for_new_hand_keeps_clock_monotonic():
	var svc := _svc()
	svc.now_ms = 1_700_000_020_000
	svc.claim_seen_open = true
	svc.hand_settled_deferred = true
	svc.match_ended = true
	svc.reset_for_new_hand()
	assert_eq(svc.now_ms, 1_700_000_020_000, "跨局保留权威时钟（单调）")
	assert_false(svc.claim_seen_open)
	assert_false(svc.hand_settled_deferred)
	assert_null(svc.match_ended, "跨局回到未判定")


func test_hard_reset_returns_clock_to_base():
	var svc := _svc()
	svc.now_ms = 1_700_000_030_000
	svc.claim_seen_open = true
	svc.hand_settled_deferred = true
	svc.hard_reset(null)
	assert_eq(svc.now_ms, AuthorityRewardCoordinator.CLOCK_BASE_MS)
	assert_false(svc.claim_seen_open)
	assert_false(svc.hand_settled_deferred)


func test_public_has_aa_seq_without_module_is_false():
	assert_false(_svc().public_has_aa_seq(null, 5))


## LLS 兼容面：外部（headless_room_session / 测试）读 REWARD_CLOCK_BASE_MS
## 与内省 _reward_* 字段的路径必须保持不变。
func test_lls_clock_const_and_introspection_still_work():
	assert_eq(LocalLoopbackServer.REWARD_CLOCK_BASE_MS,
		AuthorityRewardCoordinator.CLOCK_BASE_MS,
		"LLS 常量须与组件同源")
	var cfg := GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_STANDARD,
		[&"HUMAN", &"AI", &"AI", &"AI"],
		[&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"],
		7, "sess-reward-lls", "rv-reward"
	)
	var server := LocalLoopbackServer.new(cfg, 0)
	assert_true(server.start())
	assert_eq(int(server.get("_reward_authority_now_ms")),
		LocalLoopbackServer.REWARD_CLOCK_BASE_MS, "时钟内省面保留")
	assert_false(bool(server.get("_reward_hand_settled_deferred")),
		"延迟标记内省面保留")
	assert_eq(server.reward_authority_now_ms(),
		LocalLoopbackServer.REWARD_CLOCK_BASE_MS, "公开只读时钟不变")
