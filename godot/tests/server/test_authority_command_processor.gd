extends GutTest

# ARCH-02 #392：AuthorityCommandProcessor —— 命令业务指纹、幂等命中/冲突、
# 首次结果缓存与事务 capture/restore。LLS 行为不变由 e3_07 / LLS 套件回归证明。

const SID := "sess-acp-1"


func _cr(n: int) -> CommandResult:
	return CommandResult.from_dict({
		"protocol_version": ProtocolConstants.PROTOCOL_VERSION,
		"command_id": "550e8400-e29b-41d4-a716-%012d" % n,
		"status": "REJECTED",
		"server_seq": 0,
		"error_code": "INVALID_ACTION",
	})


func _action(n: int, seat: int = 0) -> Action:
	return Action.discard(
		seat, 100 + n, "room-acp",
		"550e8400-e29b-41d4-a716-%012d" % n,
		"550e8400-e29b-41d4-a716-%012d" % (900000 + n), 0, n
	)


func test_business_fingerprint_stable_and_sensitive():
	var a := _action(1)
	var fp1: String = AuthorityCommandProcessor.business_fingerprint(a, SID)
	var fp2: String = AuthorityCommandProcessor.business_fingerprint(_action(1), SID)
	assert_eq(fp1.length(), 64)
	assert_eq(fp1, fp2, "同 payload 同会话指纹稳定")
	assert_ne(fp1, AuthorityCommandProcessor.business_fingerprint(_action(2), SID),
		"payload 变化指纹必变")
	assert_ne(fp1, AuthorityCommandProcessor.business_fingerprint(a, "sess-other"),
		"会话变化指纹必变")
	assert_eq(AuthorityCommandProcessor.business_fingerprint(a, ""), "",
		"无 session 兜底 → 空指纹拒绝")
	assert_eq(AuthorityCommandProcessor.business_fingerprint(null, SID), "")


func test_bound_session_id_overrides_fallback():
	var a := _action(3)
	var bound: String = AuthorityCommandProcessor.business_fingerprint(a, SID, "sess-bound")
	assert_eq(bound, AuthorityCommandProcessor.business_fingerprint(a, "ignored", "sess-bound"),
		"显式 bound_session_id 优先于兜底")
	assert_ne(bound, AuthorityCommandProcessor.business_fingerprint(a, SID))


func test_lookup_miss_hit_conflict_and_store():
	var proc := AuthorityCommandProcessor.new()
	var cr := _cr(1)
	assert_eq(str(proc.lookup("cmd-1", "fp-a").get("status", "")),
		AuthorityCommandProcessor.STATUS_MISS)
	proc.store("cmd-1", "fp-a", cr)
	var hit: Dictionary = proc.lookup("cmd-1", "fp-a")
	assert_eq(str(hit.get("status", "")), AuthorityCommandProcessor.STATUS_HIT)
	assert_same(hit.get("result"), cr, "命中返回原缓存结果")
	assert_eq(str(proc.lookup("cmd-1", "fp-b").get("status", "")),
		AuthorityCommandProcessor.STATUS_CONFLICT, "同 command_id 异指纹 → 冲突")
	assert_eq(proc.size(), 1)


func test_capture_restore_roundtrip_and_clear():
	var proc := AuthorityCommandProcessor.new()
	proc.store("cmd-1", "fp-a", _cr(2))
	var snap: Dictionary = proc.capture()
	proc.store("cmd-2", "fp-b", _cr(3))
	assert_eq(proc.size(), 2)
	proc.restore(snap)
	assert_eq(proc.size(), 1, "restore 回滚到 capture 时刻")
	assert_eq(str(proc.lookup("cmd-1", "fp-a").get("status", "")),
		AuthorityCommandProcessor.STATUS_HIT)
	proc.clear()
	assert_eq(proc.size(), 0)


func test_lls_exposes_readonly_cache_introspection():
	# characterization 测试兼容面：get("_command_cache") 仍返回 Dictionary 快照
	var cfg := GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_STANDARD,
		[&"HUMAN", &"AI", &"AI", &"AI"],
		[&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"],
		7, "sess-acp-lls", "rv-acp"
	)
	var server := LocalLoopbackServer.new(cfg, 0)
	assert_not_null(server)
	var c: Variant = server.get("_command_cache")
	assert_eq(typeof(c), TYPE_DICTIONARY)
	assert_eq((c as Dictionary).size(), 0)
