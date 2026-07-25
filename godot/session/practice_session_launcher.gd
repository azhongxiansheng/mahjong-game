class_name PracticeSessionLauncher extends RefCounted

# E2-01（#231）+ #253：练习场启动器。
# 只消费已验证 GameSessionConfig；拒绝 PUBLIC_CASUAL 与非法配置。
# TRASH_TALK：每局 PBC 仅以 meta local_authority 持有对应 LocalLoopback（无 bundle 双权威）。
# STANDARD：无道具/奖励权威，仅 PBC。

const HANDS_PER_ROUND: int = 4
const EAST_TOTAL_HANDS: int = 4
const HANCHAN_TOTAL_HANDS: int = 8


func launch(config: GameSessionConfig) -> GameDriver:
	if config == null:
		return null
	if config.room_kind != GameSessionConfig.ROOM_PRACTICE:
		return null
	var verified := GameSessionConfig.create_validated(
		config.room_kind,
		config.round_kind,
		config.game_mode,
		config.participants,
		config.character_ids,
		config.seed,
		config.session_id,
		config.rule_version
	)
	if verified == null:
		return null

	var total_hands: int = EAST_TOTAL_HANDS
	if verified.round_kind == GameSessionConfig.ROUND_HANCHAN:
		total_hands = HANCHAN_TOTAL_HANDS
	elif verified.round_kind != GameSessionConfig.ROUND_EAST:
		return null

	var modules: ModeModuleBundle = ModeModuleBundle.from_config(verified)
	if modules == null:
		return null
	if modules.is_trash_talk() and modules.item_inventory != null:
		modules.item_inventory.set_match_namespace(str(verified.session_id))

	var driver := GameDriver.new(verified.seed, total_hands, HANDS_PER_ROUND)
	driver.mode_modules = modules
	var cfg_ref: GameSessionConfig = verified
	var mods_ref: ModeModuleBundle = modules
	driver.bc_factory = func(
		hand_seed: int,
		dealer: int,
		use_heuristic: bool,
		round_wind: int,
		hand_seq: int
	) -> PlayableBattleController:
		var pbc := PlayableBattleController.new(
			hand_seed, dealer, use_heuristic, round_wind, hand_seq
		)
		pbc.bind_mode_modules(mods_ref)
		if mods_ref.is_trash_talk():
			# 注入 PBC：LocalLoopback 弱引用持有；权威只挂本局 meta
			var auth := LocalLoopbackServer.new(cfg_ref, dealer, pbc, mods_ref)
			pbc.set_meta("local_authority", auth)
			if not auth.start():
				pbc.remove_meta("local_authority")
				return null
		return pbc
	return driver
