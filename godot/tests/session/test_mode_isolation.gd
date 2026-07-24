extends GutTest

# E2-04（#234）：标准场与欢乐场构造期硬隔离。
# 由 GameSessionConfig.game_mode 在构造边界决定模块；
# STANDARD 四零；TRASH_TALK 最小生产模块 + 首窗 unarmed；运行中不可切模式。

const CONFIG_SCRIPT := "res://session/game_session_config.gd"
const BUNDLE_SCRIPT := "res://session/mode_module_bundle.gd"
const LAUNCHER_SCRIPT := "res://session/practice_session_launcher.gd"
const LOOPBACK_SCRIPT := "res://server/local_loopback_server.gd"

const STANDARD_COMBOS := [
	[&"PRACTICE", &"EAST", &"STANDARD"],
	[&"PRACTICE", &"HANCHAN", &"STANDARD"],
	[&"PUBLIC_CASUAL", &"EAST", &"STANDARD"],
	[&"PUBLIC_CASUAL", &"HANCHAN", &"STANDARD"],
]

const TRASH_TALK_EVENT_KINDS := [
	"REWARD_WINDOW_OPENED",
	"REWARD_WINDOW_CLOSING",
	"REWARD_WINDOW_SETTLED",
	"REWARD_WINDOW_CANCELLED",
	"ITEM_GRANTED",
	"ITEM_CONSUMED",
	"ITEM_APPLIED",
	"CHARACTER_ABILITY_ARMED",
	"CHARACTER_ABILITY_DISARMED",
]

const PARTS_PRACTICE := [&"HUMAN", &"AI", &"AI", &"AI"]
const CHARS := [&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"]


func _config_script() -> GDScript:
	if not ResourceLoader.exists(CONFIG_SCRIPT):
		return null
	return load(CONFIG_SCRIPT) as GDScript


func _bundle_script() -> GDScript:
	if not ResourceLoader.exists(BUNDLE_SCRIPT):
		return null
	return load(BUNDLE_SCRIPT) as GDScript


func _make_config(
	room: StringName,
	round_kind: StringName,
	mode: StringName,
	p_seed: int = 42
) -> GameSessionConfig:
	if room == &"PRACTICE":
		return GameSessionConfig.create_validated(
			GameSessionConfig.ROOM_PRACTICE,
			round_kind,
			mode,
			PARTS_PRACTICE,
			CHARS,
			p_seed,
			"sid-e2-04-%s-%s-%s" % [room, round_kind, mode],
			"rv-e2-04"
		)
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PUBLIC_CASUAL,
		round_kind,
		mode,
		PARTS_PRACTICE,
		CHARS,
		p_seed,
		"sid-e2-04-%s-%s-%s" % [room, round_kind, mode],
		"rv-e2-04"
	)


func test_mode_module_bundle_script_exists() -> void:
	assert_true(
		ResourceLoader.exists(BUNDLE_SCRIPT),
		"#234 应新增 ModeModuleBundle 构造边界"
	)
	var script := _bundle_script()
	assert_not_null(script, "ModeModuleBundle 脚本应可加载")
	if script == null:
		return
	assert_true(
		String(script.source_code).contains("class_name ModeModuleBundle"),
		"必须暴露 class_name ModeModuleBundle"
	)


func test_standard_four_combos_zero_modules() -> void:
	var script := _bundle_script()
	assert_not_null(script, "依赖 ModeModuleBundle")
	if script == null:
		return

	for row in STANDARD_COMBOS:
		var cfg: GameSessionConfig = _make_config(row[0], row[1], row[2])
		assert_not_null(cfg, "STANDARD 组合应可构造 Config: %s" % [row])
		if cfg == null:
			continue
		var modules: Variant = script.call("from_config", cfg)
		assert_not_null(modules, "STANDARD 应返回 ModeModuleBundle: %s" % [row])
		if modules == null:
			continue
		assert_eq(modules.game_mode, GameSessionConfig.MODE_STANDARD)
		assert_true(modules.is_standard(), "应判定为 STANDARD")
		assert_false(modules.is_trash_talk())

		# 四零：零 RewardWindow / 零库存 / 零角色能力武装路径 / 零语音
		assert_null(modules.reward_window, "STANDARD 零 RewardWindow: %s" % [row])
		assert_null(modules.item_inventory, "STANDARD 零库存: %s" % [row])
		assert_eq(
			modules.character_ability_slots.size(), 0,
			"STANDARD 零角色能力对象: %s" % [row]
		)
		assert_null(modules.momentum, "STANDARD 零 Momentum 生产模块: %s" % [row])
		assert_null(modules.text_analyzer, "STANDARD 零 TextAnalyzer: %s" % [row])
		assert_null(modules.voice_port, "STANDARD 零语音节点: %s" % [row])
		assert_false(
			modules.voice_port != null and modules.voice_port.microphone_requested,
			"STANDARD 不得请求麦克风"
		)


func test_standard_rejects_trash_talk_commands_and_events() -> void:
	var script := _bundle_script()
	assert_not_null(script)
	if script == null:
		return
	var cfg: GameSessionConfig = _make_config(&"PRACTICE", &"EAST", &"STANDARD")
	var modules: Variant = script.call("from_config", cfg)
	assert_not_null(modules)
	if modules == null:
		return

	assert_false(
		modules.accepts_command_kind("ITEM_USE"),
		"STANDARD 必须拒绝 ITEM_USE 命令"
	)
	for kind in TRASH_TALK_EVENT_KINDS:
		assert_false(
			modules.accepts_event_kind(kind),
			"STANDARD 必须拒绝事件 kind=%s" % kind
		)
	# 日麻基础命令/事件仍允许
	assert_true(modules.accepts_command_kind("DISCARD"))
	assert_true(modules.accepts_event_kind("ACTION_APPLIED"))
	assert_true(modules.accepts_event_kind("ROOM_SNAPSHOT"))


func test_trash_talk_creates_minimal_production_modules() -> void:
	var script := _bundle_script()
	assert_not_null(script)
	if script == null:
		return
	var cfg: GameSessionConfig = _make_config(&"PRACTICE", &"EAST", &"TRASH_TALK", 7)
	var modules: Variant = script.call("from_config", cfg)
	assert_not_null(modules, "TRASH_TALK 应构造 ModeModuleBundle")
	if modules == null:
		return

	assert_eq(modules.game_mode, GameSessionConfig.MODE_TRASH_TALK)
	assert_true(modules.is_trash_talk())
	assert_false(modules.is_standard())

	assert_not_null(modules.reward_window, "TRASH_TALK 须创建 RewardWindow 生产模块")
	assert_not_null(modules.item_inventory, "TRASH_TALK 须创建库存生产模块")
	assert_not_null(modules.momentum, "TRASH_TALK 须创建 Momentum")
	assert_true(modules.momentum is Momentum)
	assert_not_null(modules.text_analyzer, "TRASH_TALK 须创建 TextAnalyzer 接口对象")
	assert_not_null(modules.voice_port, "TRASH_TALK 须创建语音接口对象")
	assert_false(
		bool(modules.voice_port.get("microphone_requested")),
		"E2-04 不实现采麦业务；默认不得已申请麦克风"
	)

	assert_eq(modules.character_ability_slots.size(), 4, "四席角色能力槽")
	for i in range(4):
		var slot: Variant = modules.character_ability_slots[i]
		assert_not_null(slot, "seat %d 能力槽" % i)
		assert_eq(int(slot.seat), i)
		assert_eq(StringName(slot.character_id), CHARS[i])
		assert_false(bool(slot.armed), "首窗被动必须 unarmed")
		assert_not_null(slot.skill, "能力对象须已创建（冷启动）")
		assert_false(
			bool(slot.can_receive_hooks()),
			"对象已创建也不得接收 hook（首窗 unarmed）"
		)

	# 门控：TT 模式允许欢乐 kind（业务副作用归 E5，此处仅门控）
	assert_true(modules.accepts_command_kind("ITEM_USE"))
	for kind in TRASH_TALK_EVENT_KINDS:
		assert_true(
			modules.accepts_event_kind(kind),
			"TRASH_TALK 门控应接受 kind=%s" % kind
		)


func test_trash_talk_cold_start_does_not_register_hooks_on_battle() -> void:
	# 能力对象在 bundle 创建，但不得注入 SkillRegistry 接收 hook
	assert_true(ResourceLoader.exists(LAUNCHER_SCRIPT))
	var launcher_script: GDScript = load(LAUNCHER_SCRIPT) as GDScript
	assert_not_null(launcher_script)
	if launcher_script == null:
		return
	var cfg: GameSessionConfig = _make_config(&"PRACTICE", &"EAST", &"TRASH_TALK", 11)
	var launcher: Variant = launcher_script.new()
	var driver: Variant = launcher.launch(cfg)
	assert_not_null(driver, "练习 TRASH_TALK 应返回 GameDriver")
	if driver == null:
		return
	assert_not_null(driver.mode_modules, "launcher 须在构造边界注入 mode_modules")
	if driver.mode_modules == null:
		return
	assert_true(driver.mode_modules.is_trash_talk())
	assert_eq(driver.mode_modules.character_ability_slots.size(), 4)

	var bc: Variant = driver.start_hand()
	assert_not_null(bc)
	if bc == null:
		return
	assert_not_null(bc.registry)
	assert_eq(
		bc.registry.get_all_entries().size(), 0,
		"首窗 unarmed：能力不得注册进 SkillRegistry，故不能接收 hook"
	)


func test_mode_cannot_switch_at_runtime_or_via_payload() -> void:
	var script := _bundle_script()
	assert_not_null(script)
	if script == null:
		return
	var cfg: GameSessionConfig = _make_config(&"PRACTICE", &"EAST", &"STANDARD")
	var modules: Variant = script.call("from_config", cfg)
	assert_not_null(modules)
	if modules == null:
		return

	assert_false(
		modules.try_switch_mode(GameSessionConfig.MODE_TRASH_TALK),
		"运行中不可切换模式"
	)
	assert_eq(modules.game_mode, GameSessionConfig.MODE_STANDARD)
	assert_true(modules.is_standard())
	assert_null(modules.reward_window)

	# 客户端伪造 payload 不得改模式
	assert_false(
		modules.apply_client_mode_override({"game_mode": "TRASH_TALK"}),
		"不得用客户端 payload 伪造切换"
	)
	assert_eq(modules.game_mode, GameSessionConfig.MODE_STANDARD)
	assert_false(modules.accepts_event_kind("REWARD_WINDOW_OPENED"))

	# P1-3：直接赋值 game_mode 也不得改写（非仅 helper）
	modules.game_mode = GameSessionConfig.MODE_TRASH_TALK
	assert_eq(
		modules.game_mode, GameSessionConfig.MODE_STANDARD,
		"冻结后直接赋值不得改变 game_mode"
	)
	assert_true(modules.is_standard())
	assert_null(modules.reward_window, "直接赋值不得造成模块/模式不一致")
	assert_false(modules.accepts_command_kind("ITEM_USE"))


## P1-1：真实 launcher → start_hand → BattleState.momentum 按模式
func test_launcher_start_hand_momentum_isolation() -> void:
	var launcher_script: GDScript = load(LAUNCHER_SCRIPT) as GDScript
	assert_not_null(launcher_script)
	if launcher_script == null:
		return
	var launcher: Variant = launcher_script.new()

	var std_cfg: GameSessionConfig = _make_config(&"PRACTICE", &"EAST", &"STANDARD", 17)
	var std_driver: Variant = launcher.launch(std_cfg)
	assert_not_null(std_driver)
	if std_driver == null:
		return
	var std_bc: Variant = std_driver.start_hand()
	assert_not_null(std_bc)
	assert_not_null(std_bc.state)
	assert_null(
		std_bc.state.momentum,
		"STANDARD 真实 BattleState.momentum 必须为 null"
	)
	assert_not_null(std_bc.mode_modules)
	assert_true(std_bc.mode_modules.is_standard())

	var tt_cfg: GameSessionConfig = _make_config(&"PRACTICE", &"EAST", &"TRASH_TALK", 17)
	var tt_driver: Variant = launcher.launch(tt_cfg)
	assert_not_null(tt_driver)
	if tt_driver == null:
		return
	var tt_bc: Variant = tt_driver.start_hand()
	assert_not_null(tt_bc)
	assert_not_null(tt_bc.state)
	assert_not_null(
		tt_bc.state.momentum,
		"TRASH_TALK 真实 BattleState.momentum 必须创建"
	)
	assert_true(tt_bc.state.momentum is Momentum)
	assert_not_null(tt_bc.mode_modules)
	assert_true(tt_bc.mode_modules.is_trash_talk())


## P1-1：legacy 裸 BC（mode_modules==null）仍创建 Momentum 兼容
func test_legacy_bare_bc_keeps_momentum() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E, 0)
	assert_not_null(bc.state)
	assert_null(bc.mode_modules)
	assert_not_null(bc.state.momentum, "无 mode_modules 的 legacy 路径保留 Momentum")


## P1-1：ARS 对两模式真实 capture/hash/restore（无 mock）
func test_ars_capture_restore_both_modes() -> void:
	var launcher_script: GDScript = load(LAUNCHER_SCRIPT) as GDScript
	assert_not_null(launcher_script)
	if launcher_script == null:
		return
	var launcher: Variant = launcher_script.new()

	for mode in [&"STANDARD", &"TRASH_TALK"]:
		var cfg: GameSessionConfig = _make_config(&"PRACTICE", &"EAST", mode, 31)
		var driver: Variant = launcher.launch(cfg)
		assert_not_null(driver, "mode=%s" % mode)
		if driver == null:
			continue
		var bc: Variant = driver.start_hand()
		assert_not_null(bc)
		if bc == null:
			continue
		if mode == &"STANDARD":
			assert_null(bc.state.momentum)
		else:
			assert_not_null(bc.state.momentum)

		var snap: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(bc)
		assert_not_null(snap, "ARS capture 须支持 mode=%s" % mode)
		if snap == null:
			continue
		var h1: String = snap.sha256()
		assert_eq(h1.length(), 64, "hash mode=%s" % mode)
		assert_true(snap.can_restore(), "can_restore mode=%s" % mode)
		assert_true(snap.restore_into(bc), "restore_into mode=%s" % mode)
		if mode == &"STANDARD":
			assert_null(bc.state.momentum, "STANDARD restore 后 momentum 仍为 null")
		else:
			assert_not_null(bc.state.momentum, "TRASH_TALK restore 后保留 Momentum")
		var snap2: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(bc)
		assert_not_null(snap2)
		if snap2 != null:
			assert_eq(snap2.sha256(), h1, "round-trip hash 稳定 mode=%s" % mode)


## P1-2：真实 PBC.apply_action 模式门控 → MODE_FORBIDDEN（非仅 NOT_ENABLED）
func test_pbc_standard_item_use_mode_forbidden() -> void:
	var launcher_script: GDScript = load(LAUNCHER_SCRIPT) as GDScript
	assert_not_null(launcher_script)
	if launcher_script == null:
		return
	var cfg: GameSessionConfig = _make_config(&"PRACTICE", &"EAST", &"STANDARD", 8)
	var driver: Variant = launcher_script.new().launch(cfg)
	assert_not_null(driver)
	if driver == null:
		return
	var bc: Variant = driver.start_hand()
	assert_not_null(bc)
	assert_true(bc is PlayableBattleController)
	assert_not_null(bc.mode_modules)
	assert_true(bc.mode_modules.is_standard())
	# 进入 TURN 以便构造合法 decision
	assert_true(bc.progress_server_draw())
	var ctx: DecisionContext = bc.decision_context_for_seat(bc.state.current_seat)
	assert_not_null(ctx)
	var act: Action = Action.item_use(
		bc.state.current_seat, "item_inst_std",
		cfg.session_id,
		"550e8400-e29b-41d4-a716-446655440030",
		ctx.decision_id, bc.state.hand_seq, 1
	)
	assert_not_null(act)
	var resp: ActionResolution = bc.apply_action(act, ActionSource.HUMAN)
	assert_not_null(resp)
	assert_false(resp.accepted)
	assert_eq(
		resp.error_code, ActionResolution.MODE_FORBIDDEN,
		"STANDARD 须由模式门控拒绝，错误码 MODE_FORBIDDEN"
	)
	assert_ne(resp.error_code, ActionResolution.NOT_ENABLED)


## P1-2：TRASH_TALK PBC 门控放行 ITEM_USE，E5 未实现仍 NOT_ENABLED
func test_pbc_trash_talk_item_use_not_enabled_after_mode_gate() -> void:
	var launcher_script: GDScript = load(LAUNCHER_SCRIPT) as GDScript
	assert_not_null(launcher_script)
	if launcher_script == null:
		return
	var cfg: GameSessionConfig = _make_config(&"PRACTICE", &"EAST", &"TRASH_TALK", 8)
	var driver: Variant = launcher_script.new().launch(cfg)
	assert_not_null(driver)
	if driver == null:
		return
	var bc: Variant = driver.start_hand()
	assert_not_null(bc)
	assert_not_null(bc.mode_modules)
	assert_true(bc.mode_modules.accepts_command_kind("ITEM_USE"))
	assert_true(bc.progress_server_draw())
	var ctx: DecisionContext = bc.decision_context_for_seat(bc.state.current_seat)
	assert_not_null(ctx)
	var inv_before: int = bc.mode_modules.item_inventory.instance_count()
	var act: Action = Action.item_use(
		bc.state.current_seat, "item_inst_tt",
		cfg.session_id,
		"550e8400-e29b-41d4-a716-446655440031",
		ctx.decision_id, bc.state.hand_seq, 1
	)
	var resp: ActionResolution = bc.apply_action(act, ActionSource.HUMAN)
	assert_not_null(resp)
	assert_false(resp.accepted)
	assert_eq(
		resp.error_code, ActionResolution.NOT_ENABLED,
		"TT 过模式门控后 E5 未实现 → NOT_ENABLED"
	)
	assert_ne(resp.error_code, ActionResolution.MODE_FORBIDDEN)
	assert_eq(bc.mode_modules.item_inventory.instance_count(), inv_before)


func test_both_modes_share_same_mahjong_driver_rules() -> void:
	assert_true(ResourceLoader.exists(LAUNCHER_SCRIPT))
	var launcher_script: GDScript = load(LAUNCHER_SCRIPT) as GDScript
	assert_not_null(launcher_script)
	if launcher_script == null:
		return
	var launcher: Variant = launcher_script.new()

	var std_cfg: GameSessionConfig = _make_config(&"PRACTICE", &"HANCHAN", &"STANDARD", 99)
	var tt_cfg: GameSessionConfig = _make_config(&"PRACTICE", &"HANCHAN", &"TRASH_TALK", 99)
	var std_driver: Variant = launcher.launch(std_cfg)
	var tt_driver: Variant = launcher.launch(tt_cfg)
	assert_not_null(std_driver)
	assert_not_null(tt_driver)
	if std_driver == null or tt_driver == null:
		return

	assert_true(std_driver is GameDriver)
	assert_true(tt_driver is GameDriver)
	assert_eq(std_driver.total_hands, tt_driver.total_hands)
	assert_eq(std_driver.hands_per_round, tt_driver.hands_per_round)
	assert_eq(std_driver.seed, tt_driver.seed)
	assert_eq(std_driver.cumulative_scores, tt_driver.cumulative_scores)

	# 相同 seed 开局应产出可运行 BC（日麻基础路径共享）
	var std_bc: Variant = std_driver.start_hand()
	var tt_bc: Variant = tt_driver.start_hand()
	assert_not_null(std_bc)
	assert_not_null(tt_bc)
	assert_not_null(std_bc.state)
	assert_not_null(tt_bc.state)
	assert_eq(std_bc.state.hand_seq, tt_bc.state.hand_seq)
	assert_eq(std_bc.state.seats.size(), 4)
	assert_eq(tt_bc.state.seats.size(), 4)


func test_skill_effect_multiplier_not_in_production_settlement() -> void:
	# 旧 multiplier 仅保留于 Momentum 单元语义；生产结算路径不得引用
	var gd_src: String = (load("res://battle/game_driver.gd") as GDScript).source_code
	var bundle_src: String = ""
	if ResourceLoader.exists(BUNDLE_SCRIPT):
		bundle_src = (_bundle_script() as GDScript).source_code
	assert_false(
		gd_src.contains("skill_effect_multiplier"),
		"GameDriver 生产结算不得使用 skill_effect_multiplier"
	)
	if not bundle_src.is_empty():
		assert_false(
			bundle_src.contains("skill_effect_multiplier"),
			"ModeModuleBundle 不得把 skill_effect_multiplier 接入生产"
		)


func test_loopback_standard_rejects_item_use_and_exposes_zero_modules() -> void:
	assert_true(ResourceLoader.exists(LOOPBACK_SCRIPT))
	var cfg: GameSessionConfig = _make_config(&"PRACTICE", &"EAST", &"STANDARD", 42)
	var server: LocalLoopbackServer = LocalLoopbackServer.new(cfg, 0)
	assert_not_null(server)
	assert_not_null(server.mode_modules, "loopback 须在构造边界挂 mode_modules")
	if server.mode_modules == null:
		return
	assert_true(server.mode_modules.is_standard())
	assert_null(server.mode_modules.reward_window)
	assert_null(server.mode_modules.item_inventory)
	assert_eq(server.mode_modules.character_ability_slots.size(), 0)
	assert_null(server.mode_modules.voice_port)

	assert_true(server.start(), "STANDARD loopback 应可 start")
	var act: Action = Action.item_use(
		0, "item_inst_1", cfg.session_id,
		"550e8400-e29b-41d4-a716-446655440010",
		"550e8400-e29b-41d4-a716-446655440011",
		0, 1
	)
	assert_not_null(act)
	var cr: CommandResult = server.submit_action(act)
	assert_not_null(cr)
	assert_eq(cr.status, "REJECTED")
	assert_eq(
		cr.error_code, "MODE_FORBIDDEN",
		"loopback STANDARD ITEM_USE 须为模式门控 MODE_FORBIDDEN"
	)


func test_loopback_trash_talk_has_modules_but_item_use_still_no_e5_business() -> void:
	var cfg: GameSessionConfig = _make_config(&"PRACTICE", &"EAST", &"TRASH_TALK", 42)
	var server: LocalLoopbackServer = LocalLoopbackServer.new(cfg, 0)
	assert_not_null(server.mode_modules)
	if server.mode_modules == null:
		return
	assert_true(server.mode_modules.is_trash_talk())
	assert_not_null(server.mode_modules.reward_window)
	assert_not_null(server.mode_modules.item_inventory)
	assert_eq(server.mode_modules.character_ability_slots.size(), 4)

	assert_true(server.start())
	# E5 业务未实现：即便 TT 模块存在，ITEM_USE 仍不得产生库存副作用
	var inv_before: int = server.mode_modules.item_inventory.instance_count()
	var act: Action = Action.item_use(
		0, "item_inst_1", cfg.session_id,
		"550e8400-e29b-41d4-a716-446655440020",
		"550e8400-e29b-41d4-a716-446655440021",
		0, 1
	)
	var cr: CommandResult = server.submit_action(act)
	assert_not_null(cr)
	assert_eq(cr.status, "REJECTED", "E2-04 不实现 E5 ITEM_USE 业务")
	assert_eq(server.mode_modules.item_inventory.instance_count(), inv_before)


func test_e2_02_fixtures_remain_independent_of_mode_gate() -> void:
	# 纯协议 fixture 可独立存在（E2-02）；真实会话路径见 try_publish 测试
	assert_true(NetworkedEvent.EVENT_KINDS.has("REWARD_WINDOW_OPENED"))
	assert_true(NetworkedEvent.EVENT_KINDS.has("ITEM_GRANTED"))
	assert_true(NetworkedEvent.EVENT_KINDS.has("CHARACTER_ABILITY_ARMED"))
	var payload := {
		"window_id": "hand_0_window_1",
		"hand_seq": 0,
		"window_index": 0,
		"prize_pool": ["item_a", "item_b", "item_c", "item_d"],
		"rule_version": "reward_v2",
		"phase": "OPEN",
		"window_exit": null,
	}
	var vh: String = ProtocolViewCodec.compute_view_hash(payload)
	var ne: NetworkedEvent = NetworkedEvent.make(
		"REWARD_WINDOW_OPENED", 1, "fixture-room", payload, vh
	)
	assert_not_null(ne, "E2-02 schema fixture 不依赖 ModeModuleBundle")
	if ne != null:
		assert_eq(ne.kind, "REWARD_WINDOW_OPENED")


## P1-4：真实 loopback journal 发布边界 — STANDARD 拒绝且 seq/journal 零变化
func test_loopback_standard_rejects_trash_events_on_publish_boundary() -> void:
	var cfg: GameSessionConfig = _make_config(&"PRACTICE", &"EAST", &"STANDARD", 55)
	var server: LocalLoopbackServer = LocalLoopbackServer.new(cfg, 0)
	assert_true(server.start())
	var seq0: int = server.current_server_seq()
	var j0: int = server.event_journal(0).size()
	assert_true(seq0 >= 1, "start 后应有 snapshot 等事件")

	var kinds: Array = [
		"REWARD_WINDOW_OPENED",
		"ITEM_GRANTED",
		"CHARACTER_ABILITY_ARMED",
	]
	for kind in kinds:
		var payload: Dictionary = _valid_e5_payload(kind)
		assert_false(
			server.try_publish_business_event(kind, payload),
			"STANDARD 真实发布边界必须拒绝 %s" % kind
		)
		assert_eq(server.current_server_seq(), seq0, "拒绝后 server_seq 零变化 kind=%s" % kind)
		assert_eq(server.event_journal(0).size(), j0, "拒绝后 journal 零变化 kind=%s" % kind)
		# journal 中不得出现该 kind
		for ne in server.event_journal(0):
			assert_ne(str(ne.kind), kind, "STANDARD journal 不得含 %s" % kind)


## P1-4：TRASH_TALK 真实发布边界允许 schema 合法欢乐事件入 journal（无 E5 业务副作用）
func test_loopback_trash_talk_publish_boundary_accepts_schema_valid_events() -> void:
	var cfg: GameSessionConfig = _make_config(&"PRACTICE", &"EAST", &"TRASH_TALK", 55)
	var server: LocalLoopbackServer = LocalLoopbackServer.new(cfg, 0)
	assert_true(server.start())
	var seq0: int = server.current_server_seq()
	var j0: int = server.event_journal(0).size()

	var payload: Dictionary = _valid_e5_payload("REWARD_WINDOW_OPENED")
	assert_true(
		server.try_publish_business_event("REWARD_WINDOW_OPENED", payload),
		"TT 发布边界应允许 schema 合法 REWARD_WINDOW_OPENED 入 journal"
	)
	assert_eq(server.current_server_seq(), seq0 + 1)
	assert_eq(server.event_journal(0).size(), j0 + 1)
	var last: NetworkedEvent = server.event_journal(0).back() as NetworkedEvent
	assert_not_null(last)
	assert_eq(last.kind, "REWARD_WINDOW_OPENED")
	# 不实现 E5：库存仍空
	assert_eq(server.mode_modules.item_inventory.instance_count(), 0)


func _valid_e5_payload(kind: String) -> Dictionary:
	match kind:
		"REWARD_WINDOW_OPENED":
			return {
				"window_id": "hand_0_window_1",
				"hand_seq": 0,
				"window_index": 0,
				"prize_pool": ["item_a", "item_b", "item_c", "item_d"],
				"rule_version": "reward_v2",
				"phase": "OPEN",
				"window_exit": null,
			}
		"ITEM_GRANTED":
			return {
				"window_id": "hand_0_window_1",
				"rule_version": "reward_v2",
				"assignment_version": "assign_v1",
				"matched_rule_ids": ["stable_rule_id"],
				"item_id": "item_a",
				"item_instance_id": "inst_seat_0",
				"seat": 0,
				"hand_seq": 0,
				"score": 1000,
				"affinity_match": false,
				"armed_for_window_id": null,
			}
		"CHARACTER_ABILITY_ARMED":
			return {
				"seat": 0,
				"window_id": "hand_0_window_1",
				"character_id": "lin_yeche",
				"ability_id": "char_akagi_passive_v1",
				"active_window_id": "hand_0_window_1",
			}
		_:
			return {}


func test_launcher_standard_practice_has_zero_modules() -> void:
	var launcher_script: GDScript = load(LAUNCHER_SCRIPT) as GDScript
	assert_not_null(launcher_script)
	if launcher_script == null:
		return
	var cfg: GameSessionConfig = _make_config(&"PRACTICE", &"EAST", &"STANDARD", 5)
	var launcher: Variant = launcher_script.new()
	var driver: Variant = launcher.launch(cfg)
	assert_not_null(driver)
	if driver == null:
		return
	assert_not_null(driver.mode_modules)
	if driver.mode_modules == null:
		return
	assert_true(driver.mode_modules.is_standard())
	assert_null(driver.mode_modules.reward_window)
	assert_null(driver.mode_modules.item_inventory)
	assert_eq(driver.mode_modules.character_ability_slots.size(), 0)
	assert_null(driver.mode_modules.momentum)
	assert_null(driver.mode_modules.voice_port)
