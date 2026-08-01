extends GutTest

# ARCH-02 #392：AuthorityEventPublisher —— server_seq 与四席 journal 的所有权、
# recipient 事件构造（严格 wire roundtrip）与事件克隆。
# LLS 行为不变由 e3_07 / LLS / loopback 套件回归证明。

const VH := "0000000000000000000000000000000000000000000000000000000000000000"


func test_initial_state_owns_seq_and_four_journals():
	var pub := AuthorityEventPublisher.new()
	assert_eq(pub.server_seq, 0)
	assert_eq(pub.journals.size(), 4)
	for j in pub.journals:
		assert_eq((j as Array).size(), 0)


func test_journals_are_live_references_for_atomic_commit():
	# LLS 的"预构造 → 抢占 seq → 逐席 append"提交模式依赖 journal 为活引用
	var pub := AuthorityEventPublisher.new()
	var ne: NetworkedEvent = pub.build_recipient_event(
		"PLAYER_JOINED", 1, "room-pub", {
			"seat": 0, "participant_kind": "AI", "display_name": "测试", "connected": true,
		}, VH)
	assert_not_null(ne)
	(pub.journals[2] as Array).append(ne)
	assert_eq((pub.journals[2] as Array).size(), 1, "外部 append 必须写入权威 journal")
	pub.server_seq = 7
	assert_eq(pub.server_seq, 7)


func test_build_recipient_event_strict_roundtrip_and_rejects():
	var pub := AuthorityEventPublisher.new()
	assert_null(pub.build_recipient_event("ERROR", 1, "room-pub", {}, VH),
		"控制类 kind 拒绝")
	assert_null(pub.build_recipient_event("PLAYER_JOINED", 1, "room-pub",
		{"seat": 9}, VH), "非法 payload 拒绝")
	var ne: NetworkedEvent = pub.build_recipient_event(
		"PLAYER_JOINED", 3, "room-pub", {
			"seat": 1, "participant_kind": "HUMAN", "display_name": "n", "connected": false,
		}, VH)
	assert_not_null(ne)
	assert_eq(ne.server_seq, 3)
	assert_eq(ne.room_id, "room-pub")


func test_clone_events_deep_copies_wire_events():
	var pub := AuthorityEventPublisher.new()
	var ne: NetworkedEvent = pub.build_recipient_event(
		"PLAYER_JOINED", 1, "room-pub", {
			"seat": 0, "participant_kind": "AI", "display_name": "n", "connected": true,
		}, VH)
	var cloned: Array = AuthorityEventPublisher.clone_events([ne, null, "junk"])
	assert_eq(cloned.size(), 1, "仅克隆合法 NetworkedEvent")
	assert_ne(cloned[0], ne, "必须是新实例")
	assert_eq((cloned[0] as NetworkedEvent).to_dict(), ne.to_dict(), "wire 内容一致")


func test_lls_seq_and_journal_introspection_still_works():
	var cfg := GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_STANDARD,
		[&"HUMAN", &"AI", &"AI", &"AI"],
		[&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"],
		7, "sess-pub-lls", "rv-pub"
	)
	var server := LocalLoopbackServer.new(cfg, 0)
	assert_not_null(server)
	assert_eq(int(server.get("_server_seq")), 0, "seq 内省兼容面保留")
	var js: Variant = server.get("_journals")
	assert_eq(typeof(js), TYPE_ARRAY)
	assert_eq((js as Array).size(), 4, "journal 内省兼容面保留")
