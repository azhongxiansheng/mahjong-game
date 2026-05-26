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

	var koromo := Character.new(&"koromo")
	koromo.display_name = "天江衣"
	koromo.description = "海底支配。海底/河底胡牌 +3 番 + 摸牌時残り 3 枚透視。"
	koromo.ability_id = &"char_koromo_passive_v1"
	koromo.starting_hp = 4
	koromo.starting_gold = 30
	koromo.recommended_pack = &"starter_control"
	koromo.unlock_renown = 300
	pool.append(koromo)

	var nodoka := Character.new(&"nodoka")
	nodoka.display_name = "原村和"
	nodoka.description = "デジタル。胡牌 +1 番 + 対手聴牌時に手牌 1 枚透視。"
	nodoka.ability_id = &"char_nodoka_passive_v1"
	nodoka.starting_hp = 5
	nodoka.starting_gold = 10
	nodoka.recommended_pack = &"starter_control"
	nodoka.unlock_renown = 300
	pool.append(nodoka)

	var toki := Character.new(&"toki")
	toki.display_name = "園城寺怜"
	toki.description = "一巡先見。開局時に全 4 席の次の摸牌を透視。"
	toki.ability_id = &"char_toki_passive_v1"
	toki.starting_hp = 4
	toki.starting_gold = 20
	toki.recommended_pack = &"starter_fast"
	toki.unlock_renown = 400
	pool.append(toki)

	var kuro := Character.new(&"kuro")
	kuro.display_name = "松実玄"
	kuro.description = "ドラの愛。胡牌時に +2 extra Dora。"
	kuro.ability_id = &"char_kuro_passive_v1"
	kuro.starting_hp = 5
	kuro.starting_gold = 0
	kuro.recommended_pack = &"starter_aggro"
	kuro.unlock_renown = 400
	pool.append(kuro)

	var momoko := Character.new(&"momoko")
	momoko.display_name = "東横桃子"
	momoko.description = "ステルス。立直後の胡牌 +1 番。"
	momoko.ability_id = &"char_momoko_passive_v1"
	momoko.starting_hp = 5
	momoko.starting_gold = 10
	momoko.recommended_pack = &"starter_fast"
	momoko.unlock_renown = 500
	pool.append(momoko)

	var tetsuya := Character.new(&"tetsuya")
	tetsuya.display_name = "哲也"
	tetsuya.description = "玄人技。胡牌每回 +1 番累積（初回 +1、2 回目 +2…）。"
	tetsuya.ability_id = &"char_tetsuya_passive_v1"
	tetsuya.starting_hp = 4
	tetsuya.starting_gold = 40
	tetsuya.recommended_pack = &"starter_aggro"
	tetsuya.unlock_renown = 500
	pool.append(tetsuya)

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
