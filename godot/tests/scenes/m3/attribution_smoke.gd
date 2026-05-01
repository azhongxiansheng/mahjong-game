extends Control

# 麻将王 — 里程碑 3 第 3 步：归属可视化 F6 烟测
#
# 视觉验证：
#   1. 4 owner 的牌背色块依次：金 / 红 / 绿 / 蓝（spec §10）
#   2. 透明牌：alpha=0.5，可见正面 tile name
#   3. 印章：4 档 rarity 色（灰/蓝/紫/金），鼠标悬停显示 tooltip

const CARD_TILE_BACK := preload("res://ui/four_player_table/card_tile_back.gd")
const TILE_STAMP := preload("res://ui/four_player_table/tile_stamp.gd")

func _ready() -> void:
	custom_minimum_size = Vector2(900, 720)

	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.16, 0.04, 1.0)
	bg.size = Vector2(900, 720)
	add_child(bg)

	# Section 1: 4 owner 牌背色块
	_add_section_label("Section 1 — 4 owner 牌背色块（金/红/绿/蓝）", Vector2(20, 20))
	for i in range(4):
		var back: CardTileBack = CARD_TILE_BACK.new()
		back.position = Vector2(20 + i * 100, 60)
		back.set_owner_seat(i)
		back.set_tile_id(TileId.W5)  # 给个 tile 让 reveal 模式有内容
		add_child(back)
		var lbl := Label.new()
		lbl.position = Vector2(20 + i * 100, 190)
		lbl.text = "owner=%d" % i
		add_child(lbl)

	# Section 2: 透明牌（reveal=true）
	_add_section_label("Section 2 — 透明牌：4 owner × revealed", Vector2(20, 230))
	var sample_tiles := [TileId.W3, TileId.T7, TileId.S2, TileId.HAKU]
	for i in range(4):
		var back: CardTileBack = CARD_TILE_BACK.new()
		back.position = Vector2(20 + i * 100, 270)
		back.set_owner_seat(i)
		back.set_tile_id(sample_tiles[i])
		back.set_revealed(true)
		add_child(back)
		var lbl := Label.new()
		lbl.position = Vector2(20 + i * 100, 400)
		lbl.text = "owner=%d, revealed" % i
		add_child(lbl)

	# Section 3: 4 档 rarity 印章（带 tooltip）
	_add_section_label("Section 3 — 4 档 rarity 印章（hover 看 tooltip）", Vector2(20, 440))
	var rarity_names := ["普通", "精良", "史诗", "神话"]
	for i in range(4):
		# 牌背做底
		var back: CardTileBack = CARD_TILE_BACK.new()
		back.position = Vector2(20 + i * 110, 480)
		back.set_owner_seat(0)
		back.set_tile_id(TileId.W5)
		add_child(back)
		# 印章挂在牌右下角
		var stamp: TileStamp = TILE_STAMP.new()
		stamp.position = Vector2(20 + i * 110 + 60, 480 + 100)
		var sk := SkillResource.new()
		sk.id = StringName("demo_r%d" % i)
		sk.display_name = "Demo %s" % rarity_names[i]
		sk.description = "rarity=%d 演示技能" % i
		sk.rarity = i
		var ot: Array[StringName] = [&"WIN_DECLARED"]
		sk.owner_triggers = ot
		stamp.set_skill(sk)
		add_child(stamp)
		var lbl := Label.new()
		lbl.position = Vector2(20 + i * 110, 620)
		lbl.text = "rarity=%d %s" % [i, rarity_names[i]]
		add_child(lbl)

	# Section 4: 角色能力印章
	_add_section_label("Section 4 — 角色能力印章（is_ability=true）", Vector2(500, 440))
	var ab_back: CardTileBack = CARD_TILE_BACK.new()
	ab_back.position = Vector2(500, 480)
	ab_back.set_owner_seat(0)
	ab_back.set_tile_id(TileId.HAKU)
	add_child(ab_back)
	var ab_stamp: TileStamp = TILE_STAMP.new()
	ab_stamp.position = Vector2(560, 580)
	var ab_sk := SkillResource.new()
	ab_sk.id = &"seabed_hunter"
	ab_sk.display_name = "海底狩人"
	ab_sk.description = "海底捞月时强制 owner 自摸"
	ab_sk.rarity = 3
	ab_sk.is_ability = true
	var aot: Array[StringName] = [&"HAITEI"]
	ab_sk.owner_triggers = aot
	ab_stamp.set_skill(ab_sk)
	add_child(ab_stamp)
	var ab_lbl := Label.new()
	ab_lbl.position = Vector2(500, 620)
	ab_lbl.text = "海底狩人 (角色能力)"
	add_child(ab_lbl)

func _add_section_label(text: String, pos: Vector2) -> void:
	var lbl := Label.new()
	lbl.position = pos
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	add_child(lbl)
