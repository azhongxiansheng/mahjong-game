class_name CharacterPool

# 3 初始角色 + 未来解锁角色。

static func all() -> Array:
	var pool: Array = []

	var akagi := Character.new(&"akagi")
	akagi.display_name = "赤木"
	akagi.description = "鬼読み。每次摸牌后透视下家 1 张手牌。起始 HP 低但金币多。"
	akagi.ability_id = &"char_akagi_passive_v1"
	akagi.starting_hp = 4
	akagi.starting_gold = 50
	akagi.recommended_pack = &"starter_aggro"
	akagi.unlock_renown = 0
	akagi.portrait_path = "res://assets/roguelike/characters/char_akagi.png"
	pool.append(akagi)

	var kaiji := Character.new(&"kaiji")
	kaiji.display_name = "开司"
	kaiji.description = "逆境覚醒。分数低于 15000 时胡牌 +2 番。标准起始。"
	kaiji.ability_id = &"char_kaiji_passive_v1"
	kaiji.starting_hp = 5
	kaiji.starting_gold = 0
	kaiji.recommended_pack = &"starter_control"
	kaiji.unlock_renown = 0
	kaiji.portrait_path = "res://assets/roguelike/characters/char_kaiji.png"
	pool.append(kaiji)

	var washizu := Character.new(&"washizu")
	washizu.display_name = "鹲巣"
	washizu.description = "鷲巣麻雀。开局透视所有对手各 2 张手牌。起始 HP 高。"
	washizu.ability_id = &"char_washizu_passive_v1"
	washizu.starting_hp = 6
	washizu.starting_gold = 0
	washizu.recommended_pack = &"starter_fast"
	washizu.unlock_renown = 0
	washizu.portrait_path = "res://assets/roguelike/characters/char_washizu.png"
	pool.append(washizu)

	var saki := Character.new(&"saki")
	saki.display_name = "宫永咲"
	saki.description = "嶺上の華。胡牌时额外 +2 Dora。起始标准。"
	saki.ability_id = &"char_saki_passive_v1"
	saki.starting_hp = 5
	saki.starting_gold = 0
	saki.recommended_pack = &"starter_aggro"
	saki.unlock_renown = 50
	pool.append(saki)

	var teru := Character.new(&"teru")
	teru.display_name = "宫永照"
	teru.description = "照魔鏡。连续胡牌时每次 +N 番累积（N=连胡次数）。"
	teru.ability_id = &"char_teru_passive_v1"
	teru.starting_hp = 4
	teru.starting_gold = 30
	teru.recommended_pack = &"starter_aggro"
	teru.unlock_renown = 100
	pool.append(teru)

	var awai := Character.new(&"awai")
	awai.display_name = "大星淡"
	awai.description = "絶対安全圏。开局清振听 + 预知下张摸牌。"
	awai.ability_id = &"char_awai_passive_v1"
	awai.starting_hp = 5
	awai.starting_gold = 20
	awai.recommended_pack = &"starter_fast"
	awai.unlock_renown = 200
	pool.append(awai)

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
