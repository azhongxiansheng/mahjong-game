class_name PracticeSessionLauncher extends RefCounted

# E2-01（#231）：练习场启动器。
# 只消费已验证 GameSessionConfig；拒绝 PUBLIC_CASUAL 与非法配置。
# 返回配置好的 GameDriver，不绑定 UI、不跑业务循环、不复用 Run 路径。

const HANDS_PER_ROUND: int = 4
const EAST_TOTAL_HANDS: int = 4
const HANCHAN_TOTAL_HANDS: int = 8


func launch(config: GameSessionConfig) -> GameDriver:
	if config == null:
		return null
	if config.room_kind != GameSessionConfig.ROOM_PRACTICE:
		return null
	# 再过一遍正式校验，拒绝残缺/非法 Config
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

	var driver := GameDriver.new(verified.seed, total_hands, HANDS_PER_ROUND)
	# 练习玩家席语义：PlayableBattleController；不绑定 UI、不进入 run 循环
	driver.bc_factory = func(
		hand_seed: int,
		dealer: int,
		use_heuristic: bool,
		round_wind: int
	) -> PlayableBattleController:
		return PlayableBattleController.new(hand_seed, dealer, use_heuristic, round_wind)
	return driver
