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

# 参考站固定 1600×900 满桌（取消右栏，能力走顶栏 loadout）
const TABLE_WIDTH: float = TableLayout.TABLE_W
const TABLE_HEIGHT: float = TableLayout.TABLE_H
const ABILITY_PANEL_WIDTH: float = 0.0

const SEAT_PANEL_SCENE := preload("res://ui/four_player_table/seat_panel.tscn")
const CENTER_INFO_SCENE := preload("res://ui/four_player_table/center_info_panel.tscn")
const ABILITY_PANEL_SCENE := preload("res://ui/four_player_table/ability_panel.tscn")
const SEAT_CAPTION_OVERLAY_SCR := preload("res://ui/four_player_table/seat_caption_overlay.gd")
const REWARD_FEEDBACK_PROJECTOR_SCR := preload(
	"res://ui/four_player_table/reward_feedback_projector.gd"
)
const REWARD_POOL_HUD_SCR := preload("res://ui/four_player_table/reward_pool_hud.gd")
const ITEM_INVENTORY_DRAWER_SCR := preload(
	"res://ui/four_player_table/item_inventory_drawer.gd"
)
const ABILITY_BADGE_SCR := preload("res://ui/four_player_table/ability_badge.gd")
const TABLE_ICON_RESOLVER := preload("res://ui/four_player_table/table_icon_resolver.gd")

signal inventory_use_requested(item_instance_id: String)

# 4 个 seat_panel 实例（索引 = seat_id）
var seat_panels: Array[SeatPanel] = []
var center_info: CenterInfoPanel = null
var ability_panel: AbilityPanel = null
# 4 个 DiscardRiver（索引 = seat_id），按日麻习惯朝桌中心方向显示弃牌
var discard_rivers: Array = []
# 4 个 MeldArea（索引 = seat_id），每家副露日麻风格视觉化
# spec docs/superpowers/specs/2026-05-08-meld-area-japanese-style-design.md
var meld_areas: Array = []

# E4-04 / #246：字幕覆盖层（自动创建；仅 UI 注入，不接语音/奖励权威）
# E5-06 / #254：奖池 HUD + 库存抽屉 + 投影 store（display-only）
# 路径 preload，避免新增全局 class_name 触发全量门禁。
var caption_overlay: Control = null
var _reward_feedback_projector = null
var reward_pool_hud: Control = null
var item_inventory_drawer: Control = null
var ability_badge: Control = null
var _inventory_btn: Button = null
var _local_seat: int = 0

func _ready() -> void:
	custom_minimum_size = Vector2(TABLE_WIDTH, TABLE_HEIGHT)
	_build_layout()

# ---- public setters ----

# 把当前 hand 的 BattleState 喂给 4 个 seat panel + center + discard rivers
func bind_battle_state(state: BattleState, hand_index: int, hands_per_round_arg: int = 4) -> void:
	if center_info:
		center_info.bind_state(state, hand_index, hands_per_round_arg)
		# 当前回合家显示名(「你」/AI persona 名)
		if center_info.has_method("set_turn_name"):
			var cur: int = state.current_seat
			var turn_name: String = "你"
			if cur != 0:
				var persona: Array = ai_persona_for_seat(cur)
				turn_name = String(persona[0]) if persona.size() >= 1 else "AI %d" % cur
			center_info.set_turn_name(turn_name)
	# T2(spec 2026-06-11 G2):实宝牌 id 集合(指示牌的下一张),
	# 手牌/河 rebuild 时按它标扫光/金边。
	var dora_ids: Array = []
	if state.dora_indicators:
		for ind in state.dora_indicators.visible:
			if ind != null:
				dora_ids.append(DoraIndicator.dora_from_indicator(ind.id))
	for i in range(seat_panels.size()):
		var sp: SeatPanel = seat_panels[i]
		var seat: Seat = state.seats[i]
		sp.set_dora_ids(dora_ids)
		sp.bind_seat(seat)
		sp.set_discards_count(state.discards_per_seat[i].size())
		# 当前回合 seat 高亮:Bg 加金色描边,玩家立刻知道"现在该谁出牌"。
		sp.set_active(i == state.current_seat)
		# 玩家自家(seat 0)post-discard 听牌时显示"听"金徽章。
		# 跑 WaitCalculator 仅 13 张时才算(post-draw 14 张走 _check_tsumo 路径,
		# 不在这里跳)。对家不曝光听牌状态(只在玩家自家显示)。
		if i == 0:
			var is_tenpai := false
			var waits: Array = []
			if seat.hand.size() == 13:
				var typed_melds: Array[Meld] = []
				for m in seat.melds:
					typed_melds.append(m)
				waits = WaitCalculator.wait_tiles(seat.hand, typed_melds)
				is_tenpai = waits.size() > 0
			sp.set_tenpai(is_tenpai)
			# 雀魂式听牌候补：13 张听牌时在手牌上方画 wait tiles
			if is_tenpai:
				sp.set_wait_tiles(waits)
			else:
				sp.clear_wait_tiles()
		# 一发窗口(刚立直未轮一圈)— 所有 seat 都显(玩家算对家一发风险)。
		sp.set_ippatsu(seat.riichi.declared and seat.riichi.ippatsu_window)
	for i in range(discard_rivers.size()):
		var dr: DiscardRiver = discard_rivers[i]
		# 立直宣告时该 seat 的 riichi.riichi_discard_index 标出"这张牌弹出时
		# 同时声了立直" → DiscardRiver 渲染时把它旋 90° (日麻标志记号)。
		var riichi_idx: int = state.seats[i].riichi.riichi_discard_index
		dr.set_dora_ids(dora_ids)
		dr.set_tiles(state.discards_per_seat[i], riichi_idx)
	# spec 2026-05-08：每家副露视觉化（chi/pon/minkan/ankan/added_kan）
	for i in range(meld_areas.size()):
		var ma: MeldArea = meld_areas[i]
		ma.set_melds(state.seats[i].melds, i)
		var has_meld: bool = not state.seats[i].melds.is_empty()
		var meld_main_extent: float = ma.get_layout_bounds().size.x \
			if has_meld else 0.0
		seat_panels[i].apply_reference_hand_layout(meld_main_extent)
		if has_meld:
			var hand_metrics: Dictionary = seat_panels[i].get_reference_hand_metrics()
			ma.apply_reference_layout(float(hand_metrics["main_extent"]),
				bool(hand_metrics["has_drawn"]))

# 整场累计分（来自 GameDriver.cumulative_scores）
func bind_cumulative_scores(scores: Array) -> void:
	for i in range(seat_panels.size()):
		seat_panels[i].set_score(int(scores[i]))


# 雀魂式全桌同名高亮：河 + 副露 + 自家手牌
func highlight_tile_id(tile_id: int) -> void:
	for dr in discard_rivers:
		if dr is DiscardRiver:
			dr.set_hover_match_id(tile_id)
	for ma in meld_areas:
		if ma is MeldArea:
			ma.set_hover_match_id(tile_id)
	# 自家手牌槽
	if seat_panels.size() > 0 and seat_panels[0]:
		seat_panels[0].highlight_hand_tile_id(tile_id)


func clear_tile_highlight() -> void:
	for dr in discard_rivers:
		if dr is DiscardRiver:
			dr.clear_hover_match()
	for ma in meld_areas:
		if ma is MeldArea:
			ma.clear_hover_match()
	if seat_panels.size() > 0 and seat_panels[0]:
		seat_panels[0].highlight_hand_tile_id(-1)

# ---- helpers ----

# AI 性格化映射:seat_id → (角色名, 打法风格, 立绘路径)。
# seat 1/2/3 各挂固定 persona。立绘资产已就位(round 1 任务 12),情绪由
# SeatPanel.set_emote 通过 modulate 调色表达(RIICHI=蓝、WIN=金、被胡=灰)。
# 牌桌三家 AI 用原创角色(2026-06-12 起):凌夜/阿烈/金老,
# 立绘为 gpt-image-2 原创生成(统一暗绿金调麻将馆光影)。
static func ai_persona_for_seat(seat_id: int) -> Array:
	match seat_id:
		1: return ["凌夜", "激进", "res://assets/roguelike/characters/char_lingye.png"]
		2: return ["阿烈", "速胡", "res://assets/roguelike/characters/char_alie.png"]
		3: return ["金老", "防守", "res://assets/roguelike/characters/char_jinlao.png"]
	return []  # seat 0 玩家自家不挂 AI persona


# 静态：seat_id → 桌面坐标（相对 Table 区域）。契约见 TableLayout。
static func seat_position(seat_id: int) -> Vector2:
	return TableLayout.seat_anchor(seat_id)

# 默认风牌：dealer 是 E，按 seat_id 与 dealer 偏移决定。
# 但本面板暂不持 dealer 信息；调用方在 bind_battle_state 时由 Seat.seat_wind 直接喂。

# ---- internal ----

func _build_layout() -> void:
	# 整桌舞台（毡 + 木框烘焙图 + 暗角/中心光）
	TableStage.build(self, TABLE_WIDTH, TABLE_HEIGHT)

	var table := Node2D.new()
	table.name = "Table"
	table.position = Vector2(0, 0)
	add_child(table)
	_build_board_frame(table)

	# 4 个 SeatPanel — seat 0 玩家自家,seat 1/2/3 三家 AI 性格化。
	# 每家 AI 固定挂一个角色 (下家/对家/上家),不同打法风格,
	# 显示在 SeatInfo 行替代抽象的 "AI 1/2/3"。
	for i in range(4):
		var sp: SeatPanel = SEAT_PANEL_SCENE.instantiate()
		sp.position = seat_position(i)
		sp.set_seat_id(i)  # 自动旋转
		table.add_child(sp)
		seat_panels.append(sp)
		var persona: Array = ai_persona_for_seat(i)
		if persona.size() >= 2:
			var pp: String = String(persona[2]) if persona.size() >= 3 else ""
			sp.set_ai_persona(persona[0], persona[1], pp)

	# 4 个 DiscardRiver — 日麻 4 边布局，按 seat 旋转 0/-90/180/+90 度
	for i in range(4):
		var dr := DiscardRiver.new()
		dr.set_seat_id(i)
		var p := _discard_river_layout(i)
		dr.position = p.position
		dr.rotation_degrees = p.rotation_degrees
		dr.scale = p.scale
		table.add_child(dr)
		discard_rivers.append(dr)

	# 4 个 MeldArea — 日麻"副露摆在自己面前右侧"风格
	# spec 2026-05-08-meld-area-japanese-style-design.md
	for i in range(4):
		var ma := MeldArea.new()
		ma.set_seat_id(i)
		ma.rotation_degrees = SeatPanel.SEAT_ROTATION_DEGREES[i]
		table.add_child(ma)
		meld_areas.append(ma)

	# CenterInfoPanel
	center_info = CENTER_INFO_SCENE.instantiate()
	var center_layout := TableLayout.center_plate()
	center_info.position = center_layout.position
	center_info.scale = center_layout.scale
	table.add_child(center_info)

	# AbilityPanel：隐藏，能力走顶栏 loadout
	ability_panel = ABILITY_PANEL_SCENE.instantiate()
	ability_panel.visible = false
	ability_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ability_panel)

	# E4-04：字幕覆盖层（鼠标穿透；不随 seat 旋转）
	caption_overlay = SEAT_CAPTION_OVERLAY_SCR.new()
	caption_overlay.name = "SeatCaptionOverlay"
	caption_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption_overlay)
	_reward_feedback_projector = REWARD_FEEDBACK_PROJECTOR_SCR.new()
	_reward_feedback_projector.set_local_seat(_local_seat)

	# E5-06：奖池 HUD（常驻）
	reward_pool_hud = REWARD_POOL_HUD_SCR.new()
	reward_pool_hud.name = "RewardPoolHud"
	add_child(reward_pool_hud)

	# E5-06：库存抽屉（默认关闭）
	item_inventory_drawer = ITEM_INVENTORY_DRAWER_SCR.new()
	item_inventory_drawer.name = "ItemInventoryDrawer"
	item_inventory_drawer.use_item_requested.connect(_on_inventory_use_requested)
	add_child(item_inventory_drawer)

	# #326：真实角色视图驱动的紧凑技能徽章；不接线隐藏 AbilityPanel。
	ability_badge = ABILITY_BADGE_SCR.new()
	ability_badge.name = "AbilityBadge"
	add_child(ability_badge)

	# 顶栏「库存 N」入口（不改牌桌尺寸）
	_inventory_btn = Button.new()
	_inventory_btn.name = "InventoryButton"
	_inventory_btn.text = "库存 0"
	_inventory_btn.focus_mode = Control.FOCUS_NONE
	_inventory_btn.position = Vector2(1040.0, 8.0)
	_inventory_btn.size = Vector2(100.0, 32.0)
	_inventory_btn.icon = TABLE_ICON_RESOLVER.texture(TABLE_ICON_RESOLVER.INVENTORY_ICON)
	_inventory_btn.add_theme_constant_override("icon_max_width", 24)
	_inventory_btn.pressed.connect(_on_inventory_btn_pressed)
	add_child(_inventory_btn)
	_refresh_reward_ui()


# ---- E4-04 字幕 / E5-06 奖励反馈注入（仅 display；零权威副作用）----

## 注入一条字幕 partial/final/AI 文本。成功更新覆盖层显示。
func inject_caption_display(input: Dictionary) -> Dictionary:
	if caption_overlay == null:
		return {"ok": false, "reason": "NO_OVERLAY"}
	return caption_overlay.ingest_caption(input)


## 安全包装真实 AI selector 输出：强制 source=ai_text、kind=final，拒绝伪装麦克风。
## ai_line 来自 TrashTalkAiLineSelector.select_ai_line；extras 可含 now_ms/display_revision。
func inject_ai_caption_display(ai_line: Variant, extras: Dictionary = {}) -> Dictionary:
	if typeof(ai_line) != TYPE_DICTIONARY or (ai_line as Dictionary).is_empty():
		return {"ok": false, "reason": "EMPTY_AI_LINE"}
	var payload: Dictionary = (ai_line as Dictionary).duplicate(true)
	# 强制 AI 语义，不信任输入伪装
	payload["source"] = "ai_text"
	payload["kind"] = "final"
	payload.erase("is_mic")
	# language → lang
	if payload.has("language") and not payload.has("lang"):
		payload["lang"] = payload["language"]
	if extras.has("now_ms"):
		payload["now_ms"] = extras["now_ms"]
	if extras.has("display_revision"):
		payload["display_revision"] = extras["display_revision"]
	return inject_caption_display(payload)


## 注入奖励权威事件的展示投影。仅接受 NetworkedEvent 或 schema-valid 六键 wire。
## 不修改权威 RewardWindow/库存模块。
func inject_reward_feedback(event: Variant) -> Dictionary:
	if _reward_feedback_projector == null:
		_reward_feedback_projector = REWARD_FEEDBACK_PROJECTOR_SCR.new()
		_reward_feedback_projector.set_local_seat(_local_seat)
	var proj: Dictionary = _reward_feedback_projector.project(event)
	if not bool(proj.get("ok", false)):
		return proj
	_refresh_reward_ui()
	return proj


## 从 NBC/练习权威只读视图刷新（不改权威状态）。
func apply_reward_views(reward_view: Dictionary, inventory_view: Dictionary) -> void:
	if _reward_feedback_projector == null:
		_reward_feedback_projector = REWARD_FEEDBACK_PROJECTOR_SCR.new()
		_reward_feedback_projector.set_local_seat(_local_seat)
	if not reward_view.is_empty():
		_reward_feedback_projector.apply_reward_window_view(reward_view)
	if not inventory_view.is_empty():
		_reward_feedback_projector.apply_item_inventory_view(inventory_view)
	_refresh_reward_ui()


## 新房间/本席/authority source：无条件清空去重与上一席库存。
func begin_reward_display_source(epoch: String, seat: int) -> void:
	_local_seat = seat
	if _reward_feedback_projector == null:
		_reward_feedback_projector = REWARD_FEEDBACK_PROJECTOR_SCR.new()
	_reward_feedback_projector.begin_source(epoch, seat, true)
	_refresh_reward_ui()


func mark_reward_feedback_up_to(epoch: String, server_seq: int) -> void:
	if _reward_feedback_projector == null:
		return
	_reward_feedback_projector.mark_feedback_up_to(epoch, server_seq)


## journal 增量（epoch+seq 去重在 projector）。
func inject_reward_journal_event(event: Variant, epoch: String = "") -> Dictionary:
	if _reward_feedback_projector == null:
		_reward_feedback_projector = REWARD_FEEDBACK_PROJECTOR_SCR.new()
		_reward_feedback_projector.set_local_seat(_local_seat)
	var proj: Dictionary = _reward_feedback_projector.ingest_journal_event(event, -1, epoch)
	if not bool(proj.get("ok", false)):
		return proj
	if bool(proj.get("idempotent", false)):
		return proj
	_refresh_reward_ui()
	return proj


## 公开 utterances_by_seat → 字幕 STT 失败 / final / AI（display-only enrichment）。
func apply_reward_utterances_display(reward_view: Dictionary) -> void:
	if _reward_feedback_projector == null:
		_reward_feedback_projector = REWARD_FEEDBACK_PROJECTOR_SCR.new()
	var caps: Array = _reward_feedback_projector.project_utterances_for_display(reward_view)
	for c in caps:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		# enrichment：允许补全 character_id 徽标，不强制新 TTL
		if caption_overlay != null and caption_overlay.has_method("ingest_caption_enrichment"):
			caption_overlay.ingest_caption_enrichment(c as Dictionary)
		else:
			inject_caption_display(c as Dictionary)


func reward_feedback_text() -> String:
	# 契约文案取投影器 last message（不含 HUD 分配摘要后缀）
	if _reward_feedback_projector != null:
		var core: String = String(_reward_feedback_projector.last_feedback_message())
		if not core.is_empty():
			return core
	if caption_overlay == null:
		return ""
	return caption_overlay.reward_feedback_text()


func prize_pool_display() -> Array:
	if _reward_feedback_projector == null:
		return []
	return _reward_feedback_projector.prize_pool()


func pool_title_text() -> String:
	if _reward_feedback_projector == null:
		return ""
	return String(_reward_feedback_projector.pool_title_text())


func inventory_count() -> int:
	if _reward_feedback_projector == null:
		return 0
	return int(_reward_feedback_projector.inventory_count_for_seat(_local_seat))


func inventory_row_ids() -> Array:
	# 真相源为 projector；抽屉仅是视图
	if _reward_feedback_projector == null:
		return []
	var ids: Array = []
	for r in _reward_feedback_projector.local_inventory_instances():
		ids.append(String(r.get("item_instance_id", "")))
	return ids


func open_inventory_drawer() -> void:
	if item_inventory_drawer == null:
		return
	_sync_drawer_rows()
	if item_inventory_drawer.has_method("open_drawer"):
		item_inventory_drawer.open_drawer()
	else:
		item_inventory_drawer.visible = true


func close_inventory_drawer() -> void:
	if item_inventory_drawer == null:
		return
	if item_inventory_drawer.has_method("close_drawer"):
		item_inventory_drawer.close_drawer()
	else:
		item_inventory_drawer.visible = false


func is_inventory_drawer_open() -> bool:
	if item_inventory_drawer == null:
		return false
	if item_inventory_drawer.has_method("is_open"):
		return bool(item_inventory_drawer.is_open())
	return item_inventory_drawer.visible


func has_assignment_display() -> bool:
	if _reward_feedback_projector == null:
		return false
	return bool(_reward_feedback_projector.has_assignment_display())


func set_local_seat(seat: int) -> void:
	_local_seat = seat
	if _reward_feedback_projector != null:
		_reward_feedback_projector.set_local_seat(seat)


func _on_inventory_btn_pressed() -> void:
	if is_inventory_drawer_open():
		close_inventory_drawer()
	else:
		open_inventory_drawer()


func _on_inventory_use_requested(item_instance_id: String) -> void:
	var iid := item_instance_id.strip_edges()
	if iid.is_empty():
		return
	if _reward_feedback_projector != null:
		var target: String = String(_reward_feedback_projector.use_target_instance_id(iid))
		if target.is_empty():
			return
		inventory_use_requested.emit(target)
	else:
		inventory_use_requested.emit(iid)


func _sync_drawer_rows() -> void:
	if item_inventory_drawer == null or _reward_feedback_projector == null:
		return
	if item_inventory_drawer.has_method("set_instances"):
		item_inventory_drawer.set_instances(
			_reward_feedback_projector.local_inventory_instances()
		)


func _refresh_reward_ui() -> void:
	if _reward_feedback_projector == null:
		return
	var title: String = String(_reward_feedback_projector.pool_title_text())
	var rows: Array = _reward_feedback_projector.prize_pool_display_rows()
	var msg: String = String(_reward_feedback_projector.last_feedback_message())
	# 出口分配摘要附加到反馈条（CANCELLED 不带）
	if _reward_feedback_projector.has_assignment_display():
		var asg: Dictionary = _reward_feedback_projector.assignment_display()
		var parts: PackedStringArray = PackedStringArray()
		for s in range(4):
			var key := str(s)
			if asg.has(key):
				parts.append("S%d→%s" % [s, String(asg[key])])
			elif asg.has(s):
				parts.append("S%d→%s" % [s, String(asg[s])])
		if parts.size() > 0 and not msg.contains("作废"):
			msg = "%s｜%s" % [msg, " ".join(parts)]
	if reward_pool_hud != null:
		if reward_pool_hud.has_method("set_title"):
			reward_pool_hud.set_title(title)
		if reward_pool_hud.has_method("set_prize_pool_rows"):
			reward_pool_hud.set_prize_pool_rows(rows)
		if reward_pool_hud.has_method("set_feedback"):
			reward_pool_hud.set_feedback(msg)
	# 兼容 #246 banner 路径
	if caption_overlay != null:
		var kind := String(_reward_feedback_projector.last_feedback().get("feedback_kind", ""))
		if kind.begins_with("SETTLED_") or kind == "CANCELLED_BY_WIN" \
				or kind == "ITEM_GRANTED" or kind == "ITEM_APPLIED":
			caption_overlay.set_reward_banner_text(
				String(_reward_feedback_projector.last_feedback_message())
			)
	if _inventory_btn != null:
		_inventory_btn.text = "库存 %d" % inventory_count()
	if ability_badge != null and ability_badge.has_method("set_view"):
		ability_badge.set_view(_reward_feedback_projector.local_ability_view())
	if is_inventory_drawer_open():
		_sync_drawer_rows()


# 直接翻译参考 `.board-frame` SVG：1 条闭合外框 + 4 条斜接线。
# 点位已在 TableLayout 中按 table-plane 逐点投影，线宽保持 CSS 的 2.4px。
static func _build_board_frame(parent: Node2D) -> void:
	var frame := Node2D.new()
	frame.name = "BoardFrame"
	parent.add_child(frame)
	var paths := TableLayout.board_frame_paths()
	frame.add_child(_make_board_frame_line(
		"Outer", paths.outer, Color("00000080"), true))
	var dividers: Array = paths.dividers
	for divider_index in range(dividers.size()):
		frame.add_child(_make_board_frame_line(
			"Divider%d" % divider_index, dividers[divider_index],
			Color("00000047"), false))


static func _make_board_frame_line(node_name: String,
		points: PackedVector2Array, color: Color, closed: bool) -> Line2D:
	var line := Line2D.new()
	line.name = node_name
	line.points = points
	line.default_color = color
	line.width = 2.4
	line.closed = closed
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.antialiased = true
	return line


static func _discard_river_layout(seat_id: int) -> Dictionary:
	return TableLayout.discard_river(seat_id)
