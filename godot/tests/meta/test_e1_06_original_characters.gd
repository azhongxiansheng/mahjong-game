extends GutTest

# E1-06 / #230：12 原创角色池、工厂 12 通、GAME_BEGIN 身份锁、portrait 序列化、旧 IP 负向。

const EXPECTED_MAP: Array = [
	{"id": &"lin_yeche", "name": "林夜彻", "ability": &"char_akagi_passive_v1",
		"title": "林夜彻·脊读鬼神", "primary": &"CUNNING", "secondary": &"MYSTIC",
		"triggers": [&"TILE_DRAWN"]},
	{"id": &"qiu_jue", "name": "裘绝", "ability": &"char_kaiji_passive_v1",
		"title": "裘绝·绝崖翻盘", "primary": &"PASSION", "secondary": &"DOMINATION",
		"triggers": [&"WIN_DECLARED_PRE"]},
	{"id": &"bai_touli", "name": "白透璃", "ability": &"char_washizu_passive_v1",
		"title": "白透璃·万透镜华", "primary": &"MYSTIC", "secondary": &"CUNNING",
		"triggers": [&"GAME_BEGIN"]},
	{"id": &"hua_ling", "name": "华岭澄", "ability": &"char_saki_passive_v1",
		"title": "华岭澄·宝华绽放", "primary": &"DOMINATION", "secondary": &"PASSION",
		"triggers": [&"WIN_DECLARED_PRE"]},
	{"id": &"lian_yao", "name": "连曜真", "ability": &"char_teru_passive_v1",
		"title": "连曜真·叠曜连斩", "primary": &"DOMINATION", "secondary": &"PASSION",
		"triggers": [&"WIN_DECLARED_PRE", &"EXHAUSTIVE_DRAW", &"ABORTIVE_DRAW"]},
	{"id": &"an_cheng", "name": "安澄青", "ability": &"char_awai_passive_v1",
		"title": "安澄青·无风净界", "primary": &"CALM", "secondary": &"MYSTIC",
		"triggers": [&"GAME_BEGIN"]},
	{"id": &"yuan_xi", "name": "渊汐", "ability": &"char_koromo_passive_v1",
		"title": "渊汐·底牌潮掌", "primary": &"MYSTIC", "secondary": &"CALM",
		"triggers": [&"HAITEI", &"HOUTEI", &"TILE_DRAWN"]},
	{"id": &"ji_shu", "name": "纪枢", "ability": &"char_nodoka_passive_v1",
		"title": "纪枢·概率圣裁", "primary": &"CALM", "secondary": &"CUNNING",
		"triggers": [&"WIN_DECLARED_PRE", &"TENPAI_ENTERED"]},
	{"id": &"xian_shi", "name": "先示", "ability": &"char_toki_passive_v1",
		"title": "先示·四席窥运", "primary": &"MYSTIC", "secondary": &"CALM",
		"triggers": [&"GAME_BEGIN"]},
	{"id": &"bao_luo", "name": "宝络绯", "ability": &"char_kuro_passive_v1",
		"title": "宝络绯·赤线缠宝", "primary": &"PASSION", "secondary": &"MYSTIC",
		"triggers": [&"WIN_DECLARED_PRE"]},
	{"id": &"ying_li", "name": "影立静", "ability": &"char_momoko_passive_v1",
		"title": "影立静·消影一发", "primary": &"CUNNING", "secondary": &"CALM",
		"triggers": [
			&"RIICHI_DECLARED", &"WIN_DECLARED_PRE", &"EXHAUSTIVE_DRAW", &"ABORTIVE_DRAW"]},
	{"id": &"ju_jin", "name": "局进吾", "ability": &"char_tetsuya_passive_v1",
		"title": "局进吾·阶升必杀", "primary": &"DOMINATION", "secondary": &"CUNNING",
		"triggers": [&"WIN_DECLARED_PRE"]},
]

const OLD_PRODUCTION_IDS: Array = [
	&"akagi", &"kaiji", &"washizu", &"saki", &"teru", &"awai",
	&"koromo", &"nodoka", &"toki", &"kuro", &"momoko", &"tetsuya",
]

const OLD_PRODUCTION_NAMES: Array = [
	"赤木", "开司", "鹲巣", "宫永咲", "宫永照", "大星淡",
	"天江衣", "原村和", "園城寺怜", "松実玄", "東横桃子", "哲也",
]

# 姓名拆字式旧称号（不得再出现）
const BANNED_TITLE_FRAGMENTS: Array = [
	"白透璃·透璃", "连曜真·连曜", "安澄青·澄安", "先示·先示",
	"宝络绯·宝络", "影立静·影立", "局进吾·局进", "华岭澄·岭华",
	"渊汐·渊掌", "纪枢·算枢",
]

const GAME_BEGIN_LOCKED: Array = [
	&"char_washizu_passive_v1",
	&"char_awai_passive_v1",
	&"char_toki_passive_v1",
]

func test_pool_has_exactly_12_original_characters():
	var pool: Array = CharacterPool.all()
	assert_eq(pool.size(), 12)
	var seen: Dictionary = {}
	for c in pool:
		assert_false(seen.has(c.id), "角色 id 不得重复: %s" % c.id)
		seen[c.id] = true
	for row in EXPECTED_MAP:
		assert_true(seen.has(row.id), "缺席: %s" % row.id)

func test_pool_maps_ability_and_affinity_1_to_1():
	for row in EXPECTED_MAP:
		var c: Character = CharacterPool.find(row.id)
		assert_not_null(c, "find %s" % row.id)
		assert_eq(c.display_name, row.name)
		assert_eq(c.ability_id, row.ability)
		assert_eq(c.affinity_primary, row.primary)
		assert_eq(c.affinity_secondary, row.secondary)
		assert_true(c.description.length() > 0, "%s 需人设文案" % row.id)
		assert_eq(
			c.portrait_path,
			"res://assets/roguelike/characters/char_%s.png" % String(row.id),
			"%s 最终 portrait_path 契约" % row.id
		)

func test_old_production_character_ids_absent_from_pool():
	for old_id in OLD_PRODUCTION_IDS:
		assert_null(CharacterPool.find(old_id), "旧 id 不得仍在池: %s" % old_id)

func test_old_production_display_names_absent_from_pool():
	for c in CharacterPool.all():
		assert_false(OLD_PRODUCTION_NAMES.has(c.display_name),
			"旧显示名不得残留: %s" % c.display_name)
		for bad in OLD_PRODUCTION_NAMES:
			assert_false(c.description.find(bad) >= 0,
				"描述不得含旧名 %s（角色 %s）" % [bad, c.id])

func test_all_12_ability_ids_build_and_inject_via_factory():
	for row in EXPECTED_MAP:
		var sk: SkillResource = BossAbilityFactory.build(row.ability)
		assert_not_null(sk, "build 失败: %s" % row.ability)
		assert_eq(sk.id, row.ability)
		assert_not_null(sk.hook_script)
		for t in row.triggers:
			assert_true(sk.owner_triggers.has(t),
				"%s 缺 trigger %s" % [row.ability, t])
		assert_eq(sk.owner_triggers.size(), row.triggers.size(),
			"%s triggers 数量应与 hook 分支一致" % row.ability)
		var reg := SkillRegistry.new()
		assert_true(BossAbilityFactory.inject(reg, row.ability, 0),
			"inject 失败: %s" % row.ability)

func test_game_begin_locked_abilities_only_listen_game_begin():
	for ab_id in GAME_BEGIN_LOCKED:
		var sk: SkillResource = BossAbilityFactory.build(ab_id)
		assert_not_null(sk, "GAME_BEGIN 锁 ability 必须可 build: %s" % ab_id)
		assert_eq(sk.owner_triggers.size(), 1)
		assert_true(sk.owner_triggers.has(&"GAME_BEGIN"))
		assert_ne(ab_id, &"yamagan_v1")
		assert_ne(ab_id, &"toki_foresight_v1")

func test_character_to_dict_from_dict_roundtrips_portrait_path():
	for row in EXPECTED_MAP:
		var c: Character = CharacterPool.find(row.id)
		var d := c.to_dict()
		assert_true(d.has("portrait_path"), "to_dict 必须含 portrait_path")
		assert_eq(String(d["portrait_path"]), c.portrait_path)
		var restored := Character.from_dict(d)
		assert_not_null(restored)
		assert_eq(restored.id, c.id)
		assert_eq(restored.portrait_path, c.portrait_path)
		assert_eq(restored.ability_id, c.ability_id)
		assert_eq(restored.display_name, c.display_name)
		assert_eq(restored.affinity_primary, c.affinity_primary)
		assert_eq(restored.affinity_secondary, c.affinity_secondary)

func test_character_pool_ability_ids_not_bound_to_near_miss_gacha_cards():
	var c_yuan: Character = CharacterPool.find(&"yuan_xi")
	assert_eq(c_yuan.ability_id, &"char_koromo_passive_v1")
	assert_ne(c_yuan.ability_id, &"koromo_haitei_ability_v1")
	var c_xian: Character = CharacterPool.find(&"xian_shi")
	assert_eq(c_xian.ability_id, &"char_toki_passive_v1")
	assert_ne(c_xian.ability_id, &"toki_foresight_v1")
	var c_bao: Character = CharacterPool.find(&"bao_luo")
	assert_eq(c_bao.ability_id, &"char_kuro_passive_v1")
	assert_ne(c_bao.ability_id, &"kuro_dora_love_v1")
	var c_ying: Character = CharacterPool.find(&"ying_li")
	assert_eq(c_ying.ability_id, &"char_momoko_passive_v1")
	assert_ne(c_ying.ability_id, &"momoko_stealth_ability_v1")

func test_card_pool_char_passives_have_original_titles_not_name_splits():
	for row in EXPECTED_MAP:
		var card: AbilityCard = null
		for a in CardPool.all_abilities():
			if a.id == row.ability:
				card = a
				break
		assert_not_null(card, "缺 AbilityCard: %s" % row.ability)
		assert_eq(card.display_name, row.title,
			"%s 显示称号应为独立中二技名" % row.ability)
		for banned in BANNED_TITLE_FRAGMENTS:
			assert_ne(card.display_name, banned)
			assert_false(card.display_name == banned)

# 人类可读旧 IP 标记（不含稳定 ability_id / 文件名中的 char_akagi 等身份锁）
const OLD_IP_HUMAN_MARKERS: Array = [
	"赤木", "开司", "鹲巣", "宫永咲", "宫永照", "大星淡",
	"天江衣", "原村和", "園城寺怜", "松実玄", "東横桃子", "哲也",
	"久・悪待ち", "アカギ", "原著",
]

func test_card_pool_and_hooks_have_no_old_ip_person_names():
	for a in CardPool.all_abilities():
		for bad in OLD_IP_HUMAN_MARKERS:
			assert_false(a.display_name.find(bad) >= 0,
				"AbilityCard 显示名含旧 IP: %s / %s" % [a.id, a.display_name])
			assert_false(a.description.find(bad) >= 0,
				"AbilityCard 描述含旧 IP: %s" % a.id)
	# 从 CardPool 真实 hook_resource_path 动态收集全部生产 ability hook
	var hook_paths: Dictionary = {}  # path -> true
	for a in CardPool.all_abilities():
		var path: String = a.hook_resource_path
		if path == "":
			continue
		hook_paths[path] = true
	assert_gt(hook_paths.size(), 10, "CardPool 应提供多条 hook 路径")
	for path in hook_paths.keys():
		assert_true(FileAccess.file_exists(path), "hook 文件应存在: %s" % path)
		var f := FileAccess.open(path, FileAccess.READ)
		assert_not_null(f)
		var text := f.get_as_text()
		for bad in OLD_IP_HUMAN_MARKERS:
			assert_false(text.find(bad) >= 0,
				"hook 人类可读文案含旧 IP「%s」: %s" % [bad, path])

func test_affinity_keys_contract_matches_momentum_attribute_enum():
	# 完整契约：数量 + 每个索引键名与 Momentum.Attribute 一致
	var enum_keys: Array = Momentum.Attribute.keys()
	var char_keys: Array[StringName] = Character.affinity_keys()
	assert_eq(char_keys.size(), enum_keys.size(),
		"affinity_keys 数量必须等于 Momentum.Attribute")
	assert_eq(char_keys.size(), 5, "五类 affinity")
	# 生产侧不得再保留未使用手写 AFFINITY_KEYS 双源
	var char_src := FileAccess.get_file_as_string("res://meta/character.gd")
	assert_false(char_src.find("AFFINITY_KEYS") >= 0,
		"character.gd 不得再定义手写 AFFINITY_KEYS")
	for i in range(enum_keys.size()):
		assert_eq(String(char_keys[i]), String(enum_keys[i]),
			"索引 %d 键名漂移: Character=%s Momentum=%s" % [i, char_keys[i], enum_keys[i]])
		# 0..4 int 归一化覆盖全部枚举值
		var as_int: int = int(Momentum.Attribute[enum_keys[i]])
		assert_eq(as_int, i, "Momentum.Attribute.%s 应为 %d" % [enum_keys[i], i])
		assert_eq(Character.normalize_affinity(as_int), char_keys[i],
			"int %d 应归一化为 %s" % [as_int, char_keys[i]])
		assert_eq(Character.normalize_affinity(char_keys[i]), char_keys[i])
		assert_eq(Character.normalize_affinity(String(char_keys[i]).to_lower()), char_keys[i])
	# 越界 int / 非法串 → 空；合法串稳定序列化
	assert_eq(Character.normalize_affinity(-1), &"")
	assert_eq(Character.normalize_affinity(5), &"")
	assert_eq(Character.normalize_affinity(99), &"")
	assert_eq(Character.normalize_affinity(&"not_a_real_affinity"), &"")
	assert_eq(Character.normalize_affinity(&""), &"")
	var bad := Character.from_dict({
		"id": "tmp",
		"affinity_primary": "FIRE",
		"affinity_secondary": "calm",
	})
	assert_eq(bad.affinity_primary, &"")
	assert_eq(bad.affinity_secondary, &"CALM")
	for c in CharacterPool.all():
		assert_true(Character.is_valid_affinity(c.affinity_primary),
			"%s primary affinity 非法" % c.id)
		assert_true(Character.is_valid_affinity(c.affinity_secondary),
			"%s secondary affinity 非法" % c.id)
	var c0: Character = CharacterPool.find(&"lin_yeche")
	var d := c0.to_dict()
	assert_eq(String(d["affinity_primary"]), "CUNNING")
	var r := Character.from_dict(d)
	assert_eq(r.affinity_primary, &"CUNNING")
	assert_eq(r.affinity_secondary, &"MYSTIC")

func test_all_portrait_paths_load_from_original_production_assets():
	# Gate B 已通过：
	# 1) 不得绑定旧 IP / AI 旁路图
	# 2) 不得把 staging 路径写进生产 Character.portrait_path
	# 3) 12 条最终契约 path 必须可由 ResourceLoader 加载
	var old_or_bypass := [
		"res://assets/roguelike/characters/char_akagi.png",
		"res://assets/roguelike/characters/char_kaiji.png",
		"res://assets/roguelike/characters/char_washizu.png",
		"res://assets/roguelike/characters/char_lingye.png",
		"res://assets/roguelike/characters/char_alie.png",
		"res://assets/roguelike/characters/char_jinlao.png",
		"res://assets/roguelike/characters/char_qingluan.png",
	]
	for row in EXPECTED_MAP:
		var c: Character = CharacterPool.find(row.id)
		assert_not_null(c)
		var path := c.portrait_path
		assert_false(old_or_bypass.has(path),
			"不得把旧 IP/旁路图绑到新角色: %s" % c.id)
		assert_false(path.find("_staging") >= 0,
			"生产 portrait_path 不得指向 staging: %s" % c.id)
		assert_false(path.find("tools/asset_gen") >= 0,
			"生产 portrait_path 不得指向 asset_gen: %s" % c.id)
		assert_eq(
			path,
			"res://assets/roguelike/characters/char_%s.png" % String(row.id)
		)
		assert_true(
			ResourceLoader.exists(path),
			"Gate B 后最终 portrait 必须存在于生产资源树: %s" % path
		)


func test_ying_li_three_existing_visual_assets_load_with_frozen_dimensions() -> void:
	var expected := {
		"res://assets/roguelike/characters/char_ying_li.png": Vector2i(1024, 1536),
		"res://assets/roguelike/characters/char_ying_li_cutout.png": Vector2i(1024, 1536),
		"res://assets/roguelike/characters/char_ying_li_avatar.png": Vector2i(512, 512),
	}
	for path_value in expected:
		var path := String(path_value)
		assert_true(ResourceLoader.exists(path), "%s 必须是既有生产资源" % path)
		var texture := load(path) as Texture2D
		assert_not_null(texture)
		if texture != null:
			assert_eq(Vector2i(texture.get_width(), texture.get_height()), expected[path])
