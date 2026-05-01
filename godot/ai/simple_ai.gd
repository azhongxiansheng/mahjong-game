class_name SimpleAi

# 里程碑 2 最小日麻 AI：随机弃手牌一张。
# 不立直、不鸣牌、不暗杠、不主动宣告自摸/荣胡（结算由 BattleController 自动判定命中）。
# 故意做最弱 — 本里程碑只验证 pipeline，不验证 AI 智能。

var _rng: RandomNumberGenerator

func _init(seed: int = 0) -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed

# 在 seat 的手牌里随机挑一张返回。手牌为空时返 null（异常路径，不应在正常流程触发）。
func decide_discard(seat: Seat) -> Tile:
	var hand_tiles: Array = seat.hand._tiles
	if hand_tiles.is_empty():
		return null
	var idx: int = _rng.randi_range(0, hand_tiles.size() - 1)
	return hand_tiles[idx]
