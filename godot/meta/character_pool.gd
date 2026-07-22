class_name CharacterPool

# E1-06：12 名虚席馆原创角色；ability_id 1:1 映射既有 char_*_passive_v1 语义。
# 最终 portrait 路径已写入契约；资源文件待 Gate B 批量入库后才存在。

static func _mk(
	p_id: StringName,
	p_name: String,
	p_desc: String,
	p_ability: StringName,
	p_primary: StringName,
	p_secondary: StringName,
	p_hp: int,
	p_gold: int,
	p_pack: StringName,
	p_renown: int
) -> Character:
	var c := Character.new(p_id)
	c.display_name = p_name
	c.description = p_desc
	c.ability_id = p_ability
	c.affinity_primary = Character.normalize_affinity(p_primary)
	c.affinity_secondary = Character.normalize_affinity(p_secondary)
	c.starting_hp = p_hp
	c.starting_gold = p_gold
	c.recommended_pack = p_pack
	c.unlock_renown = p_renown
	c.portrait_path = "res://assets/roguelike/characters/char_%s.png" % String(p_id)
	return c

static func all() -> Array:
	var pool: Array = []

	# 解锁 0
	pool.append(_mk(&"lin_yeche", "林夜彻",
		"虚席馆「读脊」席。每次摸牌后透视下家 1 张手牌。寡言，专吃信息差。",
		&"char_akagi_passive_v1", &"CUNNING", &"MYSTIC",
		4, 50, &"starter_aggro", 0))
	pool.append(_mk(&"qiu_jue", "裘绝",
		"虚席馆「绝崖」席。分数低于 15000 时胡牌 +2 番。点棒见底反而更危险。",
		&"char_kaiji_passive_v1", &"PASSION", &"DOMINATION",
		5, 0, &"starter_control", 0))
	pool.append(_mk(&"bai_touli", "白透璃",
		"虚席馆「透璃」席。开局透视所有对手各 2 张手牌。礼貌，信息压迫。",
		&"char_washizu_passive_v1", &"MYSTIC", &"CUNNING",
		6, 0, &"starter_fast", 0))

	# 解锁 50 / 100 / 200
	pool.append(_mk(&"hua_ling", "华岭澄",
		"虚席馆「岭华」席。胡牌时额外 +2 Dora。强运像跟着她走。",
		&"char_saki_passive_v1", &"DOMINATION", &"PASSION",
		5, 0, &"starter_aggro", 50))
	pool.append(_mk(&"lian_yao", "连曜真",
		"虚席馆「连曜」席。连续胡牌时每次 +N 番（N=连胡次数）。越和越重。",
		&"char_teru_passive_v1", &"DOMINATION", &"PASSION",
		4, 30, &"starter_aggro", 100))
	pool.append(_mk(&"an_cheng", "安澄青",
		"虚席馆「澄安」席。开局清振听，并预知自己下一张摸牌。安全先于进攻。",
		&"char_awai_passive_v1", &"CALM", &"MYSTIC",
		5, 20, &"starter_fast", 200))

	# 解锁 300
	pool.append(_mk(&"yuan_xi", "渊汐",
		"虚席馆「渊掌」席。海底/河底胡牌 +3 番；摸牌时透视牌墙顶 3 张。",
		&"char_koromo_passive_v1", &"MYSTIC", &"CALM",
		4, 30, &"starter_control", 300))
	pool.append(_mk(&"ji_shu", "纪枢",
		"虚席馆「算枢」席。胡牌 +1 番；对手听牌成型时透视其手牌 1 张。",
		&"char_nodoka_passive_v1", &"CALM", &"CUNNING",
		5, 10, &"starter_control", 300))

	# 解锁 400
	pool.append(_mk(&"xian_shi", "先示",
		"虚席馆「先示」席。开局透视全 4 席各自下一张摸牌。",
		&"char_toki_passive_v1", &"MYSTIC", &"CALM",
		4, 20, &"starter_fast", 400))
	pool.append(_mk(&"bao_luo", "宝络绯",
		"虚席馆「宝络」席。胡牌时 +2 extra Dora。宝牌像红线缠上手腕。",
		&"char_kuro_passive_v1", &"PASSION", &"MYSTIC",
		5, 0, &"starter_aggro", 400))

	# 解锁 500
	pool.append(_mk(&"ying_li", "影立静",
		"虚席馆「影立」席。立直后进入 primed；下一次自胡 +1 番。",
		&"char_momoko_passive_v1", &"CUNNING", &"CALM",
		5, 10, &"starter_fast", 500))
	pool.append(_mk(&"ju_jin", "局进吾",
		"虚席馆「局进」席。每回胡牌累加加番（初回 +1、第 2 回 +2…）。",
		&"char_tetsuya_passive_v1", &"DOMINATION", &"CUNNING",
		4, 40, &"starter_aggro", 500))

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
