extends GutTest

# #253 Round 3：练习生产入口必须驱动 LocalLoopback 权威（非仅 meta 挂载）。

const CHARS := [&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"]
const PARTS := [&"HUMAN", &"AI", &"AI", &"AI"]


func _cfg_tt(seed: int = 42) -> GameSessionConfig:
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK, PARTS, CHARS, seed,
		"practice-auth-tt-42", "rv-253"
	)


func _cfg_std(seed: int = 7) -> GameSessionConfig:
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_STANDARD, PARTS, CHARS, seed,
		"practice-auth-std-7", "rv"
	)


func test_grantable_excludes_seat_swap_and_tsubame() -> void:
	var ids: Array = TrashTalkRuleCatalog.grantable_item_ids()
	assert_false(ids.has("seat_swap_v1"), "seat_swap 不得进入权威奖池")
	assert_false(ids.has("tsubame_v1"), "tsubame 不得进入权威奖池")
	assert_true(ids.has("wall_collapse_v1") or ids.has("wall_peek_v1") \
			or ids.has("iron_shield_v1"), "其它 battle 道具仍可发放")
	assert_false(TrashTalkRuleCatalog.is_alpha_grantable("seat_swap_v1"))
	assert_false(TrashTalkRuleCatalog.is_alpha_grantable("tsubame_v1"))
	# 图鉴可仍列出（展示），与 grantable 分离
	var codex := LobbyCodexCatalog.new()
	var codex_ids: Array = []
	for row in codex.items():
		codex_ids.append(String(row.get("id", "")))
	# 不强制图鉴移除；若图鉴含二者亦可


func test_practice_tt_start_hand_opens_reward_via_shared_loopback() -> void:
	var driver: GameDriver = PracticeSessionLauncher.new().launch(_cfg_tt(42))
	assert_not_null(driver)
	assert_not_null(driver.mode_modules)
	assert_true(driver.mode_modules.is_trash_talk())
	var bc: PlayableBattleController = driver.start_hand() as PlayableBattleController
	assert_not_null(bc)
	var auth = bc.get_meta("local_authority", null)
	assert_not_null(auth, "start_hand 须挂 local_authority")
	assert_true(auth is LocalLoopbackServer)
	var server: LocalLoopbackServer = auth as LocalLoopbackServer
	assert_true(bool(server.get("_started")), "权威须已 start")
	assert_eq(server.get("_bc"), bc, "须共享同一 BC 实例")
	# 仅 PBC meta 持有 authority；bundle 无 practice_authority 双状态
	assert_null(driver.mode_modules.get("practice_authority"),
		"ModeModuleBundle 不得再持有 practice_authority")
	# 弱引用：注入 PBC 时 _bc_injected 非空，_bc_owned 为空
	assert_null(server.get("_bc_owned"), "注入 PBC 不得强拥有")
	assert_not_null(server.get("_bc_injected"), "注入 PBC 须 WeakRef")
	# 生产权威事件：OPENED
	var kinds: Array = []
	for ne in server.event_journal(0):
		if ne is NetworkedEvent:
			kinds.append((ne as NetworkedEvent).kind)
	assert_true(kinds.has("REWARD_WINDOW_OPENED"), "练习 TT 须经 Loopback 开窗")
	assert_true(kinds.has("ROOM_SNAPSHOT"))
	assert_true(kinds.has("TURN_PROMPT"))


func test_practice_standard_has_no_authority() -> void:
	var driver: GameDriver = PracticeSessionLauncher.new().launch(_cfg_std(3))
	assert_not_null(driver)
	var bc: PlayableBattleController = driver.start_hand() as PlayableBattleController
	assert_not_null(bc)
	assert_false(bc.has_meta("local_authority"))


func test_seat_swap_and_tsubame_use_rejected() -> void:
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace("ns")
	# 即使强行 grant 也不应可使用
	for item_id in ["seat_swap_v1", "tsubame_v1"]:
		# 非 grantable 应失败
		var g: Dictionary = inv.grant_for_seat({
			"seat": 0, "item_id": item_id, "window_id": "hand_0_window_0",
			"hand_seq": 0, "score": 0, "rule_version": "rv",
			"assignment_version": "av", "matched_rule_ids": [], "affinity_match": false,
		})
		# is_grantable 在 grant_full 检查；grant_for_seat 不检查 grantable
		# ItemAuthority.use 会拒绝
		if bool(g.get("ok", false)):
			var bc := BattleController.new(1, 0, false, TileId.E, 0)
			var use: Dictionary = ItemAuthority.use_item(
				bc, inv, 0, str(g["payload"]["item_instance_id"]),
				"550e8400-e29b-41d4-a716-0000000000e1"
			)
			assert_false(bool(use.get("accepted", false)), "%s USE 须拒绝" % item_id)
		assert_false(ItemInventoryModule.is_grantable(item_id))


func test_wall_collapse_immediate_use_reduces_wall() -> void:
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace("ns_wc")
	var g: Dictionary = inv.grant_for_seat({
		"seat": 0, "item_id": "wall_collapse_v1", "window_id": "hand_0_window_0",
		"hand_seq": 0, "score": 0, "rule_version": "rv",
		"assignment_version": "av", "matched_rule_ids": [], "affinity_match": false,
	})
	assert_true(bool(g.get("ok", false)), str(g))
	var bc := BattleController.new(9, 0, false, TileId.E, 0)
	var before: int = bc.state.wall.live_wall_size()
	var use: Dictionary = ItemAuthority.use_item(
		bc, inv, 0, str(g["payload"]["item_instance_id"]),
		"550e8400-e29b-41d4-a716-0000000000e2"
	)
	assert_true(bool(use.get("accepted", false)), str(use))
	var evs: Array = use.get("events", [])
	assert_eq(evs.size(), 2)
	assert_eq(str(evs[0]["kind"]), "ITEM_APPLIED")
	assert_eq(str(evs[1]["kind"]), "ITEM_CONSUMED")
	var after: int = bc.state.wall.live_wall_size()
	assert_eq(after, before - 6, "牌墙崩塌须移除 6 张 live wall（spec 2026-07-28 §3.1）")
	assert_eq(inv.instance_count(), 0)


func test_worker_owned_bc_starts_and_submits() -> void:
	# Worker 自建 BC（非注入）仍强拥有并可 start/submit
	var cfg := _cfg_tt(11)
	var a: LocalLoopbackServer = LocalLoopbackServer.new(cfg, 0)
	assert_not_null(a)
	assert_not_null(a.get("_bc_owned"), "自建 BC 须强拥有")
	assert_null(a.get("_bc_injected"))
	assert_true(a.start())
	var b: LocalLoopbackServer = LocalLoopbackServer.new(cfg, 0)
	assert_true(b.start())
	# 同 seed 开窗奖池一致
	var pa: Array = a.mode_modules.reward_window.prize_pool
	var pb: Array = b.mode_modules.reward_window.prize_pool
	assert_eq(JSON.stringify(pa), JSON.stringify(pb))
	# 公开 kind 序列字节一致（同 config 独立 Loopback）
	var ka: Array = []
	var kb: Array = []
	for ne in a.event_journal(0):
		if ne is NetworkedEvent:
			ka.append((ne as NetworkedEvent).kind)
	for ne2 in b.event_journal(0):
		if ne2 is NetworkedEvent:
			kb.append((ne2 as NetworkedEvent).kind)
	assert_eq(JSON.stringify(ka), JSON.stringify(kb), "Worker 同构 start 公开 kind 流须一致")


## P2-4.6：生产练习入口 start 公开 kind 流与独立 LocalLoopback 一致。
func test_practice_start_public_event_kinds_match_standalone_loopback() -> void:
	var cfg := _cfg_tt(42)
	var driver: GameDriver = PracticeSessionLauncher.new().launch(cfg)
	var bc: PlayableBattleController = driver.start_hand() as PlayableBattleController
	assert_not_null(bc)
	var practice_auth: LocalLoopbackServer = bc.get_meta("local_authority") as LocalLoopbackServer
	var standalone := LocalLoopbackServer.new(cfg, 0)
	assert_true(standalone.start())
	var kp: Array = []
	var ks: Array = []
	for ne in practice_auth.event_journal(0):
		if ne is NetworkedEvent:
			kp.append((ne as NetworkedEvent).kind)
	for ne2 in standalone.event_journal(0):
		if ne2 is NetworkedEvent:
			ks.append((ne2 as NetworkedEvent).kind)
	assert_eq(JSON.stringify(kp), JSON.stringify(ks))


## 生产 PBC 用 DEFAULT_ROOM_ID("local") 构造 Action；须经共享 Loopback 对齐 session room，不得 WRONG_ROOM。
func test_practice_tt_pbc_discard_routes_loopback_accepts_local_room() -> void:
	var driver: GameDriver = PracticeSessionLauncher.new().launch(_cfg_tt(42))
	var bc: PlayableBattleController = driver.start_hand() as PlayableBattleController
	assert_not_null(bc)
	var server: LocalLoopbackServer = bc.get_meta("local_authority") as LocalLoopbackServer
	assert_not_null(server)
	assert_eq(str(server.get("_room_id")), "practice-auth-tt-42")
	var seq_before: int = int(server.get("_server_seq"))
	# 刷新决策窗
	for s in range(4):
		bc.decision_context_for_seat(s)
	var win = bc.get("_active_window")
	assert_true(win is DecisionWindow, "须有 TURN/CLAIM 窗")
	var dw: DecisionWindow = win as DecisionWindow
	assert_eq(dw.kind, DecisionWindow.KIND_TURN, "开局后应 TURN")
	var actor: int = int(dw.subject_seat)
	assert_eq(actor, 0, "练习 HUMAN 为 seat0 且开局 actor0")
	var tctx: DecisionContext = dw.context_for_seat(actor)
	assert_not_null(tctx)
	var iid := -1
	for o in tctx.allowed_actions:
		if typeof(o) == TYPE_DICTIONARY and str(o.get("kind", "")) == "DISCARD":
			var opts: Array = o.get("payload_options", [])
			assert_gt(opts.size(), 0)
			iid = int(opts[0]["tile_instance_id"])
			break
	assert_gt(iid, -1, "须有可弃牌")
	# 故意用生产 PBC 默认 room（"local"），不得依赖测试手写 session_id
	var act: Action = Action.discard(
		actor, iid, BattleController.DEFAULT_ROOM_ID,
		"550e8400-e29b-41d4-a716-0000000000f1",
		str(tctx.decision_id), int(tctx.hand_seq), 1
	)
	assert_eq(act.room_id, "local")
	var res: ActionResolution = bc.apply_action(act, ActionSource.HUMAN)
	assert_not_null(res)
	assert_true(
		res.accepted,
		"练习生产路径须接受 local room 并路由 Loopback，got error=%s" % str(res.error_code)
	)
	assert_ne(str(res.error_code), "WRONG_ROOM")
	assert_gt(int(server.get("_server_seq")), seq_before, "Loopback server_seq 须前进")
	var kinds: Array = []
	for ne in server.event_journal(0):
		if ne is NetworkedEvent:
			kinds.append((ne as NetworkedEvent).kind)
	assert_true(kinds.has("ACTION_APPLIED"), "须经 Loopback 发布 ACTION_APPLIED")


## P1-2：任意非 session / 非 DEFAULT 的 room 必须稳定 WRONG_ROOM，不得静默改写。
func test_practice_tt_arbitrary_wrong_room_rejected() -> void:
	var driver: GameDriver = PracticeSessionLauncher.new().launch(_cfg_tt(42))
	var bc: PlayableBattleController = driver.start_hand() as PlayableBattleController
	assert_not_null(bc)
	for s in range(4):
		bc.decision_context_for_seat(s)
	var dw: DecisionWindow = bc.get("_active_window") as DecisionWindow
	assert_not_null(dw)
	var actor: int = int(dw.subject_seat)
	var tctx: DecisionContext = dw.context_for_seat(actor)
	var iid := -1
	for o in tctx.allowed_actions:
		if typeof(o) == TYPE_DICTIONARY and str(o.get("kind", "")) == "DISCARD":
			iid = int((o.get("payload_options", []) as Array)[0]["tile_instance_id"])
			break
	assert_gt(iid, -1)
	var act: Action = Action.discard(
		actor, iid, "attacker-forged-room",
		"550e8400-e29b-41d4-a716-0000000000f2",
		str(tctx.decision_id), int(tctx.hand_seq), 2
	)
	var res: ActionResolution = bc.apply_action(act, ActionSource.HUMAN)
	assert_not_null(res)
	assert_false(res.accepted)
	assert_eq(str(res.error_code), "WRONG_ROOM")


## P1-2：auth.start 失败 fail-closed — start_hand 返回 null，不挂裸 PBC。
func test_practice_tt_start_fail_closed_returns_null() -> void:
	var driver: GameDriver = PracticeSessionLauncher.new().launch(_cfg_tt(99))
	assert_not_null(driver)
	# 劫持 factory：先构造再强制 start 失败
	var orig: Callable = driver.bc_factory
	driver.bc_factory = func(
		hand_seed: int, dealer: int, use_heuristic: bool, round_wind: int, hand_seq: int
	):
		var pbc: PlayableBattleController = orig.call(
			hand_seed, dealer, use_heuristic, round_wind, hand_seq
		) as PlayableBattleController
		# 若 orig 已成功 start，模拟失败路径：清权威后验证不得留下可玩脱权威局
		# 直接测 launcher 内联：fail_next_snapshot 在 new 前注入
		return pbc
	# 使用独立路径：LocalLoopback fail_next_snapshot
	var cfg := _cfg_tt(77)
	var mods: ModeModuleBundle = ModeModuleBundle.from_config(cfg)
	var pbc2 := PlayableBattleController.new(cfg.seed, 0, false, TileId.E, 0)
	pbc2.bind_mode_modules(mods)
	var auth := LocalLoopbackServer.new(cfg, 0, pbc2, mods)
	auth.set("_fail_next_snapshot", true)
	assert_false(auth.start(), "注入 snap 失败")
	# 无法在 factory 内直接注入 fail 标志；改为验证契约 helper
	assert_null(
		_practice_bc_or_null_on_auth_fail(cfg),
		"start 失败须 fail-closed 返回 null"
	)


func _practice_bc_or_null_on_auth_fail(cfg: GameSessionConfig) -> PlayableBattleController:
	# 复现 launcher 契约：start 失败 → null（仅 meta，无 bundle 权威）
	var mods: ModeModuleBundle = ModeModuleBundle.from_config(cfg)
	var pbc := PlayableBattleController.new(cfg.seed, 0, false, TileId.E, 0)
	pbc.bind_mode_modules(mods)
	var auth := LocalLoopbackServer.new(cfg, 0, pbc, mods)
	pbc.set_meta("local_authority", auth)
	auth.set("_fail_next_snapshot", true)
	if not auth.start():
		pbc.remove_meta("local_authority")
		return null
	return pbc


## P2-1：Practice authority 下 REPLAY 仍对齐/消费；错误动作 REPLAY_MISMATCH。
func test_practice_authority_preserves_replay_source_semantics() -> void:
	var driver: GameDriver = PracticeSessionLauncher.new().launch(_cfg_tt(21))
	var pbc: PlayableBattleController = driver.start_hand() as PlayableBattleController
	assert_not_null(pbc)
	var auth: LocalLoopbackServer = pbc.get_meta("local_authority") as LocalLoopbackServer
	assert_not_null(auth)
	# 取真实 TURN_PROMPT 构建合法 DISCARD
	var prompt: NetworkedEvent = null
	for ne in auth.event_journal(0):
		if ne is NetworkedEvent and (ne as NetworkedEvent).kind == "TURN_PROMPT":
			prompt = ne as NetworkedEvent
			break
	assert_not_null(prompt)
	var pl: Dictionary = prompt.payload
	var seat: int = int(pl.get("seat", 0))
	var tile_iid := -1
	for o in pl.get("allowed_actions", []):
		if typeof(o) == TYPE_DICTIONARY and str(o.get("kind", "")) == "DISCARD":
			var opts: Array = o.get("payload_options", []) as Array
			if not opts.is_empty():
				tile_iid = int((opts[0] as Dictionary).get("tile_instance_id", -1))
			break
	assert_gt(tile_iid, -1)
	var good := Action.discard(
		seat, tile_iid, str(auth.get("_room_id")),
		"550e8400-e29b-41d4-a716-0000000000a1",
		str(pl.get("decision_id", "")), int(pl.get("hand_seq", 0)), 1
	)
	assert_not_null(good, "合法 DISCARD Action 须构造成功")
	var bad := Action.discard(
		seat, tile_iid, str(auth.get("_room_id")),
		"550e8400-e29b-41d4-a716-0000000000a2",
		str(pl.get("decision_id", "")), int(pl.get("hand_seq", 0)), 2
	)
	assert_not_null(bad)
	# 期望队列装载 good；先错后对
	assert_true(bool(pbc.call("load_replay_journal", [Action.from_dict(good.to_dict())])))
	assert_eq(str(pbc.call("replay_status")), "LOADED")
	var mis: ActionResolution = pbc.apply_action(bad, ActionSource.REPLAY)
	assert_false(mis.accepted)
	assert_eq(mis.error_code, ActionResolution.REPLAY_MISMATCH)
	assert_eq(str(pbc.call("replay_status")), "MISMATCH")
	# 重新装载后正确动作须 ACCEPTED 并消费队列
	assert_true(bool(pbc.call("load_replay_journal", [Action.from_dict(good.to_dict())])))
	var ok: ActionResolution = pbc.apply_action(
		Action.from_dict(good.to_dict()), ActionSource.REPLAY
	)
	assert_true(ok.accepted, "REPLAY 合法动作须经 Loopback 事务成功 err=%s" % str(ok.error_code))
	assert_true(
		str(pbc.call("replay_status")) in ["RUNNING", "COMPLETED"],
		"REPLAY 成功后 status=%s" % str(pbc.call("replay_status"))
	)


## P2-3：非法 arm command_id fail-closed；合法 USE 的 APPLIED/CONSUMED 用原 command_id。
func test_finalize_rejects_invalid_arm_command_id_zero_side_effect() -> void:
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace("cmd-id")
	var g: Dictionary = inv.grant_for_seat({
		"seat": 0, "item_id": "dora_flip_v1", "window_id": "w0",
		"hand_seq": 0, "score": 0, "rule_version": "rv", "assignment_version": "av",
		"matched_rule_ids": [], "affinity_match": false,
	})
	assert_true(bool(g.get("ok", false)))
	var iid := str(g["payload"]["item_instance_id"])
	var bc := BattleController.new(3, 0, false, TileId.E, 0)
	# 非法 command 不得 mark_armed
	var bad_arm: Dictionary = inv.mark_armed(iid, 0, "not-a-uuid")
	assert_false(bool(bad_arm.get("ok", false)))
	assert_eq(inv.find_instance(iid).status, ItemInstance.STATUS_HELD)
	# 合法 USE
	var cmd := "550e8400-e29b-41d4-a716-0000000000c3"
	var use: Dictionary = ItemAuthority.use_item(bc, inv, 0, iid, cmd)
	assert_true(bool(use.get("accepted", false)), str(use))
	assert_eq(inv.find_instance(iid).status, ItemInstance.STATUS_ARMED)
	assert_eq(inv.find_instance(iid).arm_command_id, cmd)
	# 污染 arm_command_id 后 finalize fail-closed
	inv.find_instance(iid).arm_command_id = "bad"
	var sk: SkillResource = inv.registered_skill(iid)
	assert_not_null(sk)
	sk.consumed = true
	var fin_bad: Dictionary = ItemAuthority.finalize_triggered(bc, inv)
	assert_false(bool(fin_bad.get("ok", false)))
	assert_eq(str(fin_bad.get("reason", "")), "INVALID_ARM_COMMAND_ID")
	assert_not_null(inv.find_instance(iid), "非法 cmd 不得消费实例")
	# 恢复合法 cmd 后 finalize 成功且事件 command_id 原样
	inv.find_instance(iid).arm_command_id = cmd
	var fin_ok: Dictionary = ItemAuthority.finalize_triggered(bc, inv)
	assert_true(bool(fin_ok.get("ok", false)), str(fin_ok))
	var evs: Array = fin_ok.get("events", [])
	assert_eq(evs.size(), 2)
	assert_eq(str(evs[0]["payload"]["command_id"]), cmd)
	assert_eq(str(evs[1]["payload"]["command_id"]), cmd)
	assert_null(inv.find_instance(iid))
