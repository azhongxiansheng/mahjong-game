class_name FourPlayerTable extends Control

# 麻将王 — 里程碑 3 第 2 步：4 人桌主场景（plan-3 D4）
#
# 职责（v1，第 2 步骨架版）：
#   - 实例化 4 个 SeatPanel + CenterInfoPanel + AbilityPanel
#   - 4 个 SeatPanel 按 seat_id 自动旋转 0/-90/180/+90 度，摆 4 方位
#   - 暴露 setter API 让外部驱动（GameDriver / SmokeScene）注入数据
#
# 不在第 2 步范围：
#   - 真实牌纹理（→ 第 3 步 card_tile_back.gd）
#   - 与 GameDriver 集成（→ 第 4 步 four_player_table_smoke.tscn）
#   - 印章 + tooltip + 透明牌（→ 第 3 步）

# 4 人桌默认尺寸（spec §14 v1 默认）；右侧 200px 给 AbilityPanel
const TABLE_WIDTH: float = 1080.0
const TABLE_HEIGHT: float = 720.0
const ABILITY_PANEL_WIDTH: float = 200.0

const SEAT_PANEL_SCENE := preload("res://ui/four_player_table/seat_panel.tscn")
const CENTER_INFO_SCENE := preload("res://ui/four_player_table/center_info_panel.tscn")
const ABILITY_PANEL_SCENE := preload("res://ui/four_player_table/ability_panel.tscn")

# 4 个 seat_panel 实例（索引 = seat_id）
var seat_panels: Array[SeatPanel] = []
var center_info: CenterInfoPanel = null
var ability_panel: AbilityPanel = null
# 4 个 DiscardRiver（索引 = seat_id），按日麻习惯朝桌中心方向显示弃牌
var discard_rivers: Array = []
# 4 个 MeldArea（索引 = seat_id），每家副露日麻风格视觉化
# spec docs/superpowers/specs/2026-05-08-meld-area-japanese-style-design.md
var meld_areas: Array = []

func _ready() -> void:
	custom_minimum_size = Vector2(TABLE_WIDTH + ABILITY_PANEL_WIDTH, TABLE_HEIGHT)
	_build_layout()

# ---- public setters ----

# 把当前 hand 的 BattleState 喂给 4 个 seat panel + center + discard rivers
func bind_battle_state(state: BattleState, hand_index: int, hands_per_round_arg: int = 4) -> void:
	if center_info:
		center_info.bind_state(state, hand_index, hands_per_round_arg)
	for i in range(seat_panels.size()):
		var sp: SeatPanel = seat_panels[i]
		var seat: Seat = state.seats[i]
		sp.bind_seat(seat)
		sp.set_discards_count(state.discards_per_seat[i].size())
		# 当前回合 seat 高亮:Bg 加金色描边,玩家立刻知道"现在该谁出牌"。
		sp.set_active(i == state.current_seat)
		# 玩家自家(seat 0)post-discard 听牌时显示"听"金徽章。
		# 跑 WaitCalculator 仅 13 张时才算(post-draw 14 张走 _check_tsumo 路径,
		# 不在这里跳)。对家不曝光听牌状态(只在玩家自家显示)。
		if i == 0:
			var is_tenpai := false
			if seat.hand.size() == 13:
				var typed_melds: Array[Meld] = []
				for m in seat.melds:
					typed_melds.append(m)
				is_tenpai = WaitCalculator.is_tenpai(seat.hand, typed_melds)
			sp.set_tenpai(is_tenpai)
		# 一发窗口(刚立直未轮一圈)— 所有 seat 都显(玩家算对家一发风险)。
		sp.set_ippatsu(seat.riichi.declared and seat.riichi.ippatsu_window)
	for i in range(discard_rivers.size()):
		var dr: DiscardRiver = discard_rivers[i]
		# 立直宣告时该 seat 的 riichi.riichi_discard_index 标出"这张牌弹出时
		# 同时声了立直" → DiscardRiver 渲染时把它旋 90° (日麻标志记号)。
		var riichi_idx: int = state.seats[i].riichi.riichi_discard_index
		dr.set_tiles(state.discards_per_seat[i], riichi_idx)
	# spec 2026-05-08：每家副露视觉化（chi/pon/minkan/ankan/added_kan）
	for i in range(meld_areas.size()):
		var ma: MeldArea = meld_areas[i]
		ma.set_melds(state.seats[i].melds, i)

# 整场累计分（来自 GameDriver.cumulative_scores）
func bind_cumulative_scores(scores: Array) -> void:
	for i in range(seat_panels.size()):
		seat_panels[i].set_score(int(scores[i]))

# ---- helpers ----

# AI 性格化映射:seat_id → (角色名, 打法风格)。
# seat 1 (下家右)、seat 2 (对家上)、seat 3 (上家左) 各挂一个固定 persona。
# v1 用 CharacterPool 里的 3 个 starter character (赤木/开司/鹫巢) 对应风格,
# 让玩家从首局就熟悉这些 IP 角色,后续 character_picker 也用同样名字。
# v2 可改成"每节点随机选 3 个 AI persona",让每场对局有新意。
static func ai_persona_for_seat(seat_id: int) -> Array:
	match seat_id:
		1: return ["赤木", "激进"]   # 下家:增番打法,会主动鸣牌
		2: return ["开司", "速胡"]   # 对家:逆境立直,听牌+1
		3: return ["鹫巣", "防守"]   # 上家:鬼麻防御,透视手牌
	return []  # seat 0 玩家自家不挂 AI persona


# 静态：seat_id → 桌面坐标（相对 Table 区域）。
# 0=下、1=右、2=上、3=左；中央为 (TABLE_WIDTH/2, TABLE_HEIGHT/2)。
# seat 0 margin 比 AI 大 50px,因为玩家自家手牌(60 高)要画在分数框下方,
# 需要留 60+ 垂直空间;AI 手牌只是色块,小得多。
static func seat_position(seat_id: int) -> Vector2:
	var cx := TABLE_WIDTH / 2.0
	var cy := TABLE_HEIGHT / 2.0
	var margin := 110.0
	match seat_id:
		0:
			return Vector2(cx, TABLE_HEIGHT - margin - 50)
		1:
			return Vector2(TABLE_WIDTH - margin, cy)
		2:
			return Vector2(cx, margin)
		3:
			return Vector2(margin, cy)
	return Vector2(cx, cy)

# 默认风牌：dealer 是 E，按 seat_id 与 dealer 偏移决定。
# 但本面板暂不持 dealer 信息；调用方在 bind_battle_state 时由 Seat.seat_wind 直接喂。

# ---- internal ----

const TABLE_BG_PATH := "res://assets/mahjong_table_bg.png"

func _build_layout() -> void:
	# Bg 纯色块已在 .tscn；有桌布贴图资产时盖一张 TextureRect 上去。
	if ResourceLoader.exists(TABLE_BG_PATH):
		var felt := TextureRect.new()
		felt.name = "TableFelt"
		felt.texture = load(TABLE_BG_PATH)
		felt.position = Vector2(0, 0)
		felt.size = Vector2(TABLE_WIDTH, TABLE_HEIGHT)
		felt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		felt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(felt)

	var table := Node2D.new()
	table.name = "Table"
	table.position = Vector2(0, 0)
	add_child(table)

	# 4 个 SeatPanel — seat 0 玩家自家,seat 1/2/3 三家 AI 性格化。
	# 每家 AI 固定挂一个角色 (赤木下家/开司对家/鹫巢上家),不同打法风格,
	# 显示在 SeatInfo 行替代抽象的 "AI 1/2/3"。
	for i in range(4):
		var sp: SeatPanel = SEAT_PANEL_SCENE.instantiate()
		sp.position = seat_position(i)
		sp.set_seat_id(i)  # 自动旋转
		table.add_child(sp)
		seat_panels.append(sp)
		var persona: Array = ai_persona_for_seat(i)
		if persona.size() == 2:
			sp.set_ai_persona(persona[0], persona[1])

	# 4 个 DiscardRiver — 日麻 4 边布局，按 seat 旋转 0/-90/180/+90 度
	for i in range(4):
		var dr := DiscardRiver.new()
		var p := _discard_river_layout(i)
		dr.position = p.position
		dr.rotation_degrees = p.rotation_degrees
		table.add_child(dr)
		discard_rivers.append(dr)

	# 4 个 MeldArea — 日麻"副露摆在自己面前右侧"风格
	# spec 2026-05-08-meld-area-japanese-style-design.md
	for i in range(4):
		var ma := MeldArea.new()
		var mp := _meld_area_layout(i)
		ma.position = mp.position
		ma.rotation_degrees = mp.rotation_degrees
		table.add_child(ma)
		meld_areas.append(ma)

	# CenterInfoPanel
	center_info = CENTER_INFO_SCENE.instantiate()
	center_info.position = Vector2(TABLE_WIDTH / 2.0, TABLE_HEIGHT / 2.0)
	table.add_child(center_info)

	# AbilityPanel：v1 简化为隐藏（spec §14 角色能力 v1 不可见消化干扰）
	ability_panel = ABILITY_PANEL_SCENE.instantiate()
	ability_panel.position = Vector2(TABLE_WIDTH, 0)
	ability_panel.visible = false
	add_child(ability_panel)

# DiscardRiver 4 边布局（日麻标准）：
# 每家弃牌从自己面前桌心方向展开，旋转 0/-90/180/+90 度让 face 朝桌中心。
# DiscardRiver 内部 local 坐标系：(0,0) 是 left-top 原点，6 张横向 +X，行向 +Y 累积。
# 6×34-2=202 宽，3×50-2=148 高。
# Node2D rotation 把这套坐标转到 4 边方向。
# 中央留 280×280（位置 (500..780, 220..500)）给 CenterInfoPanel + Dora 显示。
const RIVER_W: float = 202.0
const RIVER_H: float = 148.0
static func _discard_river_layout(seat_id: int) -> Dictionary:
	var cx := TABLE_WIDTH / 2.0
	var cy := TABLE_HEIGHT / 2.0
	# inner = 河"内沿"到桌心的距离；让 4 河之间留中央 280×280
	var inner := 140.0
	match seat_id:
		0:
			# 玩家：rotation=0；local (0,0) 在 visual 左上，6 张牌正面朝玩家。
			# 让河顶部贴在 cy + inner（桌心下方一点开始）
			return {"position": Vector2(cx - RIVER_W / 2.0, cy + inner), "rotation_degrees": 0.0}
		1:
			# 右家：rotation=-90（顺时针）。local +X 在 screen 上变 -Y（向上），
			# local +Y 变 +X（向右）。所以 local (0,0) 在 visual 的 (position.x, position.y)，
			# 6 张牌从该点向上排列。让河"内沿"（local Y=0 那条）贴在 cx + inner，
			# 河"开始"贴在 cy + RIVER_W/2（visual 下方）。
			return {"position": Vector2(cx + inner, cy + RIVER_W / 2.0), "rotation_degrees": -90.0}
		2:
			# 对家：rotation=180。local +X 在 screen 上变 -X（向左）；+Y 变 -Y（向上）。
			# local (0,0) 在 visual 右下角；牌从右往左排列（玩家视角是从左到右读）。
			# 让河"内沿"（local Y=0 那条）贴在 cy - inner（桌心上方一点开始），
			# visual 横向 right edge 在 cx + RIVER_W/2。
			return {"position": Vector2(cx + RIVER_W / 2.0, cy - inner), "rotation_degrees": 180.0}
		3:
			# 左家：rotation=+90（逆时针）。local +X 在 screen 上变 +Y（向下），
			# local +Y 变 -X（向左）。让河"内沿" 贴在 cx - inner，
			# 河"开始" 贴在 cy - RIVER_W/2（visual 上方）。
			return {"position": Vector2(cx - inner, cy - RIVER_W / 2.0), "rotation_degrees": 90.0}
	return {"position": Vector2(cx, cy), "rotation_degrees": 0.0}

# MeldArea 4 边布局（日麻"副露摆在自己面前右侧"风格）：
# - MeldArea 内坐标：x=0 是组的最右侧（首组 meld 起点），从右往左累积
# - 4 个角各放 1 个 MeldArea，rotation 让 face 朝桌中心
# - 玩家（seat 0）的 MeldArea 在 桌面 右下角；melds 向左展开
# - 视觉位置略低于 seat_panel 高度，避免与 score / hand 显示重叠
const MELD_MARGIN: float = 30.0  # 距桌边
static func _meld_area_layout(seat_id: int) -> Dictionary:
	match seat_id:
		0:
			# 玩家：rotation=0；x=0 在 visual 桌面右下角；melds 向左 (-X) 展开
			return {"position": Vector2(TABLE_WIDTH - MELD_MARGIN, TABLE_HEIGHT - MELD_MARGIN), "rotation_degrees": 0.0}
		1:
			# 右家：rotation=-90（顺时针）；视觉上 melds 从右上角向下展开
			return {"position": Vector2(TABLE_WIDTH - MELD_MARGIN, MELD_MARGIN), "rotation_degrees": -90.0}
		2:
			# 对家：rotation=180；melds 从左上角向右展开（视觉为对家视角的左下）
			return {"position": Vector2(MELD_MARGIN, MELD_MARGIN), "rotation_degrees": 180.0}
		3:
			# 左家：rotation=+90；melds 从左下角向上展开
			return {"position": Vector2(MELD_MARGIN, TABLE_HEIGHT - MELD_MARGIN), "rotation_degrees": 90.0}
	return {"position": Vector2(0, 0), "rotation_degrees": 0.0}
