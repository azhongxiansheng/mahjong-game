class_name CharacterPool

# 3 初始角色 + 未来解锁角色。

static func all() -> Array:
	var pool: Array = []

	var akagi := Character.new(&"akagi")
	akagi.display_name = "赤木"
	akagi.description = "攻击型。每次胡牌额外 +1 番。起始 HP 较低但起始金币多。"
	akagi.ability_id = &"char_akagi_passive_v1"
	akagi.starting_hp = 4
	akagi.starting_gold = 50
	akagi.recommended_pack = &"starter_aggro"
	akagi.unlock_renown = 0
	pool.append(akagi)

	var kaiji := Character.new(&"kaiji")
	kaiji.display_name = "开司"
	kaiji.description = "防御型。被荣胡时 50% 概率取消（每局最多 1 次）。标准起始。"
	kaiji.ability_id = &"char_kaiji_passive_v1"
	kaiji.starting_hp = 5
	kaiji.starting_gold = 0
	kaiji.recommended_pack = &"starter_control"
	kaiji.unlock_renown = 0
	pool.append(kaiji)

	var washizu := Character.new(&"washizu")
	washizu.display_name = "鹲巣"
	washizu.description = "信息型。每局开始看牌墙顶 3 张。起始 HP 高但无金币。"
	washizu.ability_id = &"char_washizu_passive_v1"
	washizu.starting_hp = 6
	washizu.starting_gold = 0
	washizu.recommended_pack = &"starter_fast"
	washizu.unlock_renown = 0
	pool.append(washizu)

	return pool

static func find(char_id: StringName) -> Character:
	for c in all():
		if c.id == char_id:
			return c
	return null

static func unlocked(renown: int) -> Array:
	var result: Array = []
	for c in all():
		if c.is_unlocked(renown):
			result.append(c)
	return result
