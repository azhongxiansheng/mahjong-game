class_name PlayableTable extends Control

# 麻将王 — 战斗节点真实可玩 顶层容器。
#
# 组合 FourPlayerTable + PlayerActionPanel + PlayableBattleController，
# 跑一局完整东风局玩家可玩对战。
#
# 1280×800：上方 720 给 four_player_table（含旋转的 4 个 SeatPanel），
# 下方 80 给 player_action_panel。

const FOUR_PLAYER_TABLE := preload("res://ui/four_player_table/four_player_table.tscn")
const PLAYER_ACTION_PANEL := preload("res://ui/four_player_table/player_action_panel.tscn")

const TABLE_HEIGHT: float = 720.0
const ACTION_PANEL_HEIGHT: float = 80.0

var _table: FourPlayerTable = null
var _action_panel: PlayerActionPanel = null
var _bc: PlayableBattleController = null

var _seat_panel_player: SeatPanel = null

func _ready() -> void:
	custom_minimum_size = Vector2(DT.VIEW_W, TABLE_HEIGHT + ACTION_PANEL_HEIGHT)
	_build_layout()
	# 成就解锁 → toast 弹"🏆 成就解锁:xxx"。autoload 可能晚 ready,defer connect。
	var sm = get_node_or_null("/root/StatsManager")
	if sm and sm.has_signal("achievement_unlocked") \
			and not sm.achievement_unlocked.is_connected(_on_achievement_unlocked):
		sm.achievement_unlocked.connect(_on_achievement_unlocked)


# StatsManager 发解锁信号 → 用 toast 标显示。延 700ms 让 SFX/粒子先播。
func _on_achievement_unlocked(_id: String, meta: Dictionary) -> void:
	var nm: String = String(meta.get("name", ""))
	if nm == "":
		return
	var captured := nm
	get_tree().create_timer(0.7).timeout.connect(func():
		_show_toast_text("🏆 成就解锁:%s" % captured))

func _build_layout() -> void:
	# Bg 覆盖整个 viewport,让桌底 ActionPanel 区跟桌面同色,避免桌外背景跳变。
	var bg := ColorRect.new()
	bg.size = Vector2(DT.VIEW_W, TABLE_HEIGHT + ACTION_PANEL_HEIGHT)
	bg.color = DT.BG_BASE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_table = FOUR_PLAYER_TABLE.instantiate()
	_table.position = Vector2(0, 0)
	add_child(_table)

	_action_panel = PLAYER_ACTION_PANEL.instantiate()
	# ActionPanel 在桌底 y=TABLE_HEIGHT 起 80 px（独立区域不跟玩家手牌 y=640-700 重叠）
	_action_panel.position = Vector2((_table.TABLE_WIDTH - PlayerActionPanel.PANEL_W) / 2.0, TABLE_HEIGHT)
	add_child(_action_panel)

func play_hand_async(bc: PlayableBattleController) -> Dictionary:
	_bc = bc
	if _table.seat_panels.size() >= 1:
		_seat_panel_player = _table.seat_panels[0]
		if not _seat_panel_player.player_card_clicked.is_connected(_on_player_tile_clicked):
			_seat_panel_player.player_card_clicked.connect(_on_player_tile_clicked)
	_bc.bind_ui(_action_panel, _seat_panel_player, get_tree())
	_table.bind_battle_state(bc.state, 0, 4)
	_action_panel.enter_idle("准备开局…")
	_attach_event_polling()
	# 注册到 DebugOverlay (F3 调试面板) — 让运行时可观测 BC state。
	var dbg = get_node_or_null("/root/DebugOverlay")
	if dbg:
		dbg.register_battle_controller(bc)
	# Pro 日志:开局 + 收局摘要进 Log,可在 DebugOverlay 看
	var log_node = get_node_or_null("/root/Log")
	if log_node and bc.state:
		log_node.info("battle", "hand begin hand=%d dealer=%d wind=%d" % [
			int(bc.state.hand_number), int(bc.state.dealer_seat),
			int(bc.state.round_wind)])
	# 开局 splash:"东 1 局 · AI 2 是庄家" 大字 1.3s。fade-in/out 让玩家
	# 明确感知"新一局开始 + 谁是庄"。
	await _show_hand_start_splash(bc.state)
	var result: Dictionary = await bc.run_to_end_async()
	if dbg:
		dbg.unregister_battle_controller(bc)
	if log_node:
		log_node.info("battle", "hand end last_event=%s" % str(result.get("last_event", "")))
	_action_panel.enter_idle("本局结束")
	_table.bind_battle_state(bc.state, 0, 4)
	# 记终身统计 + 检测成就解锁(发 achievement_unlocked signal,toast 在 _on_achievement_unlocked)
	_record_hand_stats(bc)
	# 胡牌或流局后弹结算 overlay：玩家点继续才推进下一局
	await _show_hand_result_overlay(result)
	return result


# 调 StatsManager 把本局结果存进去 — 主要根据 events 找 WIN_DECLARED + 玩家
# 视角(seat 0)推断 is_player_winner / loser_was_player。
func _record_hand_stats(bc) -> void:
	var sm = get_node_or_null("/root/StatsManager")
	if sm == null:
		return
	var win_event = null
	for i in range(bc.events.size() - 1, -1, -1):
		var ev = bc.events[i]
		if ev.type == &"WIN_DECLARED":
			win_event = ev
			break
	var is_player_winner: bool = (win_event != null and int(win_event.actor_seat) == 0)
	var loser_was_player: bool = false
	if win_event != null:
		var discarder: int = int(win_event.extra.get("discarder_seat", -1))
		if discarder == 0 and not is_player_winner:
			loser_was_player = true
	sm.record_hand_end(win_event, is_player_winner, loser_was_player)
	# 玩家立直?扫 RIICHI_DECLARED actor==0
	for ev in bc.events:
		if ev.type == &"RIICHI_DECLARED" and int(ev.actor_seat) == 0:
			var is_double: bool = false  # double riichi 标记在 RiichiState,这里近似查 state
			if bc.state != null and bc.state.seats.size() > 0:
				is_double = bc.state.seats[0].riichi.double_riichi
			sm.record_riichi(is_double)
			break

# 本局结束后弹结算 panel：胡牌显示 役/番/符/点数；流局显示听牌情况
# 主题化 + tier 大字（役満/倍満/跳満/満貫/N 飜 N 符）+ 玩家胡 / 失点配色。
func _show_hand_result_overlay(result: Dictionary) -> void:
	var last_event: String = String(result.get("last_event", ""))
	var win_event: BattleEvent = null
	for i in range(_bc.events.size() - 1, -1, -1):
		var ev: BattleEvent = _bc.events[i]
		if ev.type == &"WIN_DECLARED":
			win_event = ev
			break
	# 胡牌 → 先放粒子 + 震动,再弹 overlay。让玩家先体验冲击再看结算细节。
	if win_event != null:
		_play_win_effects(win_event)
		await get_tree().create_timer(0.45).timeout
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(DT.BG_BASE.r, DT.BG_BASE.g, DT.BG_BASE.b, 0.85)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(bg)

	# 主题化 Panel（StyleBox 由 run_theme.tres 提供 — 暗底 + 猩红描边）
	# 加大到 560 高,给胡牌 14 张展示行(_render_winning_hand_strip)留位置。
	var panel := Panel.new()
	panel.position = Vector2(280, 120)
	panel.custom_minimum_size = Vector2(720, 560)
	panel.size = Vector2(720, 560)
	overlay.add_child(panel)

	# tier 大字：役満 / 倍満 / 跳満 / 満貫 / N 飜 N 符
	var tier := Label.new()
	tier.position = Vector2(0, 28)
	tier.size = Vector2(720, 80)
	tier.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tier.add_theme_font_size_override("font_size", 56)
	tier.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	tier.add_theme_constant_override("shadow_offset_x", 2)
	tier.add_theme_constant_override("shadow_offset_y", 2)
	tier.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	panel.add_child(tier)

	# 副标题：谁 · 自摸/荣和
	var subtitle := Label.new()
	subtitle.position = Vector2(0, 118)
	subtitle.size = Vector2(720, 32)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_color", Color(0.93, 0.9, 0.78))
	panel.add_child(subtitle)

	if win_event != null:
		var winner_seat: int = win_event.actor_seat
		var winner_name: String = "你" if winner_seat == 0 else "AI %d" % winner_seat
		var is_tsumo: bool = (last_event == "TSUMO_DECLARED"
			or int(win_event.extra.get("discarder_seat", -1)) < 0)
		var win_kind: String = "自摸" if is_tsumo else "荣和"
		var fu: int = int(win_event.extra.get("fu", 0))
		var han: int = int(win_event.extra.get("han", 0))
		var yakuman_mul: int = int(win_event.extra.get("yakuman_multiplier", 0))
		tier.text = _score_tier_label(han, fu, yakuman_mul)
		# 玩家胡=金；失点=猩红；AI 自摸（非玩家放铳）=暗黄
		if winner_seat == 0:
			tier.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		elif not is_tsumo and int(win_event.extra.get("discarder_seat", -1)) == 0:
			tier.add_theme_color_override("font_color", Color(1, 0.32, 0.32))
		else:
			tier.add_theme_color_override("font_color", Color(0.82, 0.78, 0.55))
		subtitle.text = "%s · %s" % [winner_name, win_kind]
	elif last_event == "NAGASHI_MANGAN":
		# 日麻 §6.5 流し満貫:流局时弃牌全幺九且无被鸣 → 满贯支付
		tier.text = "流し満貫"
		tier.add_theme_color_override("font_color", Color(1, 0.78, 0.4))
		var nm_extra: Dictionary = _find_last_event_extra("NAGASHI_MANGAN")
		var nm_seat: int = int(nm_extra.get("winner_seat", -1))
		var nm_name: String = "你" if nm_seat == 0 else "AI %d" % nm_seat
		subtitle.text = "%s · 全幺九弃 + 无被鸣" % nm_name
	elif last_event == "EXHAUSTIVE_DRAW":
		tier.text = "流局"
		tier.add_theme_color_override("font_color", Color(0.7, 0.78, 0.85))
		subtitle.text = "本局无人胡牌"
	elif last_event == "ABORTIVE_DRAW":
		# 5 种途中流局(日麻 §3.2):九種九牌 / 四风连打 / 四家立直 / 四杠散了 / 三家和了
		tier.text = "途中流局"
		tier.add_theme_color_override("font_color", Color(0.85, 0.62, 0.85))
		subtitle.text = _abortive_reason_label(_find_last_event_extra("ABORTIVE_DRAW"))
	else:
		tier.text = "本局结束"
		subtitle.text = ""

	# 役名列表（命中的役 + 各自飜数,空格分隔）
	var yaku_lbl := Label.new()
	yaku_lbl.position = Vector2(40, 160)
	yaku_lbl.size = Vector2(640, 50)
	yaku_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	yaku_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	yaku_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	yaku_lbl.add_theme_font_size_override("font_size", 18)
	yaku_lbl.add_theme_color_override("font_color", Color(1, 0.92, 0.55))
	if win_event != null:
		yaku_lbl.text = _format_yaku_list(win_event.extra.get("yaku_names", []))
	panel.add_child(yaku_lbl)

	# 胡牌 14 张展示行(winning tile 单独右侧 + 金色调突出)
	if win_event != null and win_event.tile_instance != null and win_event.tile_instance.tile != null:
		var is_tsumo: bool = (last_event == "TSUMO_DECLARED"
			or int(win_event.extra.get("discarder_seat", -1)) < 0)
		_render_winning_hand_strip(panel, win_event.actor_seat,
			win_event.tile_instance.tile.id, is_tsumo, 220)

	# 明细：番·符 + 得失分
	var detail := Label.new()
	detail.position = Vector2(48, 290)
	detail.size = Vector2(624, 160)
	detail.add_theme_font_size_override("font_size", 18)
	detail.add_theme_color_override("font_color", Color(0.95, 0.95, 0.85))
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if win_event != null:
		var fu2: int = int(win_event.extra.get("fu", 0))
		var han2: int = int(win_event.extra.get("han", 0))
		var winner_total: int = int(win_event.extra.get("winner_total", 0))
		var payout: Dictionary = win_event.extra.get("payout", {})
		var lines: Array[String] = []
		if int(win_event.extra.get("yakuman_multiplier", 0)) > 0:
			lines.append("番数：—   符：—")
		else:
			lines.append("番数：%d 飜    符：%d" % [han2, fu2])
		lines.append("胜利者得分：%d 点" % winner_total)
		# 显式列出 dora 指示牌让玩家核对算番:visible + 立直胡时 hidden uradora。
		if _bc != null and _bc.state != null:
			var di = _bc.state.dora_indicators
			var dora_names: Array[String] = []
			for tile in di.visible:
				if tile != null:
					dora_names.append(CardTileBack.tile_short_name(tile.id))
			if not dora_names.is_empty():
				lines.append("Dora 指示: " + ", ".join(dora_names))
			# 立直胡 → 显式裏 dora 指示
			var winner_seat: int = int(win_event.actor_seat)
			if winner_seat >= 0 and _bc.state.seats[winner_seat].riichi.declared:
				var ura_names: Array[String] = []
				for tile in di.hidden_uradora:
					if tile != null:
						ura_names.append(CardTileBack.tile_short_name(tile.id))
				if not ura_names.is_empty():
					lines.append("裏 Dora 指示: " + ", ".join(ura_names))
		lines.append("")
		lines.append("点数转移：")
		for seat in payout.keys():
			var seat_int: int = int(seat)
			var amount: int = int(payout[seat])
			var name: String = "你" if seat_int == 0 else "AI %d" % seat_int
			lines.append("  %s  -%d" % [name, amount])
		detail.text = "\n".join(lines)
	else:
		detail.text = "无人胡牌（流局）"
	panel.add_child(detail)

	# 继续按钮(主题化)
	var btn := Button.new()
	btn.text = "继续 →"
	btn.position = Vector2(280, 490)
	btn.custom_minimum_size = Vector2(160, 44)
	btn.pressed.connect(func(): overlay.queue_free())
	panel.add_child(btn)

	# 点击空白处也能继续(保留旧的快速关闭)
	overlay.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			overlay.queue_free())
	while is_instance_valid(overlay):
		await get_tree().process_frame


# 在 overlay panel 内画胡牌 14 张:13 张暗手升序 + 间隔 + winning tile(金调高亮)。
# 副露不画(简化;副露已经在桌面 MeldArea 上看过)。
# 自摸:seat.hand 14 张含 winning_tile → pop 到右侧;荣和:seat.hand 13 张,
# winning tile 来自他家,只需 append。
func _render_winning_hand_strip(parent: Control, winner_seat: int,
		winning_tile_id: int, is_tsumo: bool, y_offset: float) -> void:
	if _bc == null or _bc.state == null:
		return
	var winner: Seat = _bc.state.seats[winner_seat]
	if winner == null:
		return
	var concealed_ids: Array = winner.hand.to_id_array()
	if is_tsumo:
		var idx: int = concealed_ids.find(winning_tile_id)
		if idx >= 0:
			concealed_ids.remove_at(idx)
	concealed_ids.sort()
	# HBox 居中,1 px 牌间隙
	var strip := HBoxContainer.new()
	strip.position = Vector2(0, y_offset)
	strip.size = Vector2(720, 56)
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	# 1 px 紧贴 — 胡牌 14 张牌展示行传统紧贴,**不要**改用 DT.GAP_TIGHT(8)
	# 否则 14 张牌 + 13 个 8px 间隔总宽超 720 容器宽,溢出。
	strip.add_theme_constant_override("separation", 1)
	parent.add_child(strip)
	for tid in concealed_ids:
		strip.add_child(_make_overlay_tile(int(tid), false))
	# 暗手与 winning tile 之间留 10 px gap
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(10, 56)
	strip.add_child(spacer)
	strip.add_child(_make_overlay_tile(winning_tile_id, true))
	# 副露(吃/碰/杠)展示在最右,每个 meld 内 1 px 间隔、meld 间 8 px gap
	for meld in winner.melds:
		var meld_gap := Control.new()
		meld_gap.custom_minimum_size = Vector2(8, 56)
		strip.add_child(meld_gap)
		for t in meld.tiles:
			if t != null:
				strip.add_child(_make_overlay_tile(t.id, false))


# 单张小牌(28×40),winning=true 给金色描边 Panel 包装突出。
func _make_overlay_tile(tile_id: int, is_winning: bool) -> Control:
	const TW := 28
	const TH := 40
	var key: String = CardTileBack.tile_id_to_atlas_key(tile_id)
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(TW, TH)
	tr.size = Vector2(TW, TH)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if key != "":
		var extractor: Node = get_tree().root.get_node_or_null("TextureExtractor")
		if extractor and extractor.has_method("get_tile_texture"):
			tr.texture = extractor.get_tile_texture(key)
	if not is_winning:
		return tr
	# winning tile:套一层 Panel 加金边突出
	var wrap := Panel.new()
	wrap.custom_minimum_size = Vector2(TW + 4, TH + 4)
	wrap.size = Vector2(TW + 4, TH + 4)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(1, 0.85, 0.28)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	wrap.add_theme_stylebox_override("panel", sb)
	tr.position = Vector2(2, 2)
	wrap.add_child(tr)
	return wrap


# 途中流局原因 → 中文展示名
static func _abortive_reason_label(extra: Dictionary) -> String:
	var reason: String = String(extra.get("reason", ""))
	match reason:
		"kyuusyu_kyuuhai": return "九種九牌"
		"suufon_renda": return "四风连打"
		"suucha_riichi": return "四家立直"
		"suukantsu_sanra": return "四杠散了"
		"sancha_houra": return "三家和了"
		_: return "途中流局"


# 在 _bc.events 倒序找最末某类型事件的 extra,不存在返 {}
func _find_last_event_extra(type_name: String) -> Dictionary:
	if _bc == null or _bc.events == null:
		return {}
	for i in range(_bc.events.size() - 1, -1, -1):
		var ev = _bc.events[i]
		if ev != null and String(ev.type) == type_name:
			return ev.extra
	return {}


# Yaku 名 + han 列表 → "立直 1飜 · 自摸 1飜 · 平和 1飜" 风格中点分隔串。
# 役満条目省略 han(为 0),代之以 "(N 倍)"。
static func _format_yaku_list(yaku_names: Array) -> String:
	if yaku_names.is_empty():
		return "（无役）"
	var parts: Array[String] = []
	for item in yaku_names:
		if not (item is Dictionary):
			continue
		var nm: String = String(item.get("name", ""))
		var mul: int = int(item.get("yakuman_multiplier", 0))
		if mul > 0:
			parts.append("%s (%d 倍)" % [nm, mul] if mul > 1 else nm)
		else:
			parts.append("%s %d飜" % [nm, int(item.get("han", 0))])
	return " · ".join(parts)


# 番/符/役満倍数 → 中文 tier 名。
# 役満倍数 ≥ 1 → "X 倍役満"/"役満";否则按番符算満貫层级近似(忽略具体符算细节)。
static func _score_tier_label(han: int, _fu: int, yakuman_mul: int) -> String:
	if yakuman_mul >= 2:
		return "%d 倍役満" % yakuman_mul
	if yakuman_mul == 1:
		return "役満"
	if han >= 13: return "数え役満"
	if han >= 11: return "三倍満"
	if han >= 8:  return "倍満"
	if han >= 6:  return "跳満"
	if han >= 5:  return "満貫"
	# 4 飜 40 符以上 / 3 飜 70 符以上 也是満貫,简化忽略
	return "%d 飜 胡牌" % han

var _last_event_count: int = 0
var _polling_active: bool = false
var _toast_label: Label = null
var _toast_tween: Tween = null

func _attach_event_polling() -> void:
	if _polling_active:
		return
	_polling_active = true
	_polling_loop()

func _polling_loop() -> void:
	while _polling_active and _bc != null:
		await get_tree().process_frame
		if _bc == null:
			return
		var n: int = _bc.events.size()
		if n != _last_event_count:
			# Diff: 新 emit 的事件全过一遍 toast handler;再 rebind 桌面视觉
			for i in range(_last_event_count, n):
				_handle_event_toast(_bc.events[i])
				_play_event_sfx(_bc.events[i])
				_handle_event_dramatic(_bc.events[i])
			_last_event_count = n
			if is_instance_valid(_table) and _bc.state != null:
				_table.bind_battle_state(_bc.state, 0, 4)
		if n < _last_event_count:
			_last_event_count = 0


# BC 事件 → AudioManager SFX 播放;调 AudioManager.sfx_key_for_event 算 key,
# tile_click 路径加少量 pitch_variation 避免连续摸切机械感。
# 一局开始前弹 splash 1.3s,await 完成。让玩家明确感知 "第 N 局 / 庄家"。
func _show_hand_start_splash(state) -> void:
	if state == null:
		return
	var info: Dictionary = HandStartSplash.format_title(
		int(state.hand_number), int(state.round_wind),
		int(state.dealer_seat), int(state.honba))
	var splash := HandStartSplash.make(
		String(info.get("title", "")), String(info.get("subtitle", "")))
	add_child(splash)
	await splash.finished


# 胡牌时 burst 粒子 + 屏幕震动。按 han / yakuman 分级 tier。
# 玩家胡 tier 不变(都好看);AI 胡用 LIGHT 让玩家不觉得过度奖励对手。
# 高光时刻的"重量感"效果 — 立直/Dora 翻牌等不到胡牌的中间事件,加屏震
# + 白闪 + 短 hitstop,让玩家感到"刚才发生了大事"。WIN_DECLARED 的特写
# 走专属的 _play_win_effects (粒子+大屏震)。
#
# 立直: LIGHT 屏震(0.15s 4px) + 白闪 0.2s,让玩家立刻感知到"对手立直了
# 我得防"。即便走 toast 路径,1.5s 文字 + 屏震 双通道更难错过。
# DORA 翻牌: 同立直,提示"新 dora 出现"。
# RINSHAN_DRAW: 短闪,呼应"岭上的紧张感"。
func _handle_event_dramatic(ev: BattleEvent) -> void:
	if ev == null:
		return
	match ev.type:
		&"RIICHI_DECLARED":
			var shake := ScreenShake.for_tier(self, WinBurst.Tier.LIGHT)
			shake.start()
			_flash_screen(0.18, Color(1, 1, 1, 0.35))
			# AI 立直 → 该 seat 立绘转蓝调"决意"。actor_seat 越界 / seat 0 无立绘
			# 时 set_emote 是 no-op,不会崩。
			_set_seat_emote(int(ev.actor_seat), "riichi")
		&"HAITEI", &"HOUTEI":
			# 海底/河底:罕见,玩家可能整个 run 见 1-2 次。补 LIGHT 屏震 +
			# 蓝白闪让它"被注意到"——单纯 toast 容易错过。WIN_DECLARED 紧
			# 跟其后会再播胡牌特效,不冲突。
			var shake2 := ScreenShake.for_tier(self, WinBurst.Tier.LIGHT)
			shake2.start()
			_flash_screen(0.22, Color(0.7, 0.85, 1.0, 0.45))
		&"ABORTIVE_DRAW":
			# 途中流局(四风连打/四家立直/九種九牌/三家和了等):红闪让玩家
			# 注意"这局白打了"。WinBurst 不触发(不是胡牌)。
			_flash_screen(0.3, Color(1.0, 0.7, 0.7, 0.3))
		&"TSUMO_DECLARED", &"RON_DECLARED":
			# 胜者立绘金调,其他 3 家(含玩家)灰调"被胡失落"。RON 时被点炮的家
			# (deal_in_seat)单独更愁,可以加深色;v1 三家都用 upset 已足够。
			_set_seat_emote(int(ev.actor_seat), "winning")
			for s in [0, 1, 2, 3]:
				if s != int(ev.actor_seat):
					_set_seat_emote(s, "upset")
		&"GAME_BEGIN":
			# 新局开始 → 4 家 emote 重置 normal
			for s in [0, 1, 2, 3]:
				_set_seat_emote(s, "normal")


func _set_seat_emote(seat_id: int, emote: String) -> void:
	if _table == null or seat_id < 0 or seat_id >= _table.seat_panels.size():
		return
	var sp: SeatPanel = _table.seat_panels[seat_id]
	if sp and sp.has_method("set_emote"):
		sp.set_emote(emote)


# 全屏白闪 — 短瞬覆盖全屏的半透明 ColorRect, tween alpha 1→0。
# 不阻塞其他事件,挂 self 顶层 z_index 让胡牌粒子之类不被遮。
func _flash_screen(duration: float, color: Color) -> void:
	var flash := ColorRect.new()
	flash.color = color
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 1000
	add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.0, duration).set_ease(Tween.EASE_OUT)
	tw.tween_callback(flash.queue_free)


func _play_win_effects(win_event: BattleEvent) -> void:
	var tier := _win_tier(win_event)
	# Hitstop:胡牌前 0.12s 全屏微暗 + 白闪,模拟"瞬间空气凝固"。tier 越高
	# 闪越亮(役満到 0.65 alpha);玩家有"刚才那一下不简单"的体感。
	var flash_alpha: float = 0.35 + 0.10 * tier  # LIGHT=0.35 / YAKUMAN=0.65
	_flash_screen(0.5, Color(1, 1, 1, flash_alpha))
	# 粒子 — 挂 self(PlayableTable),坐标取屏幕中心
	var burst := WinBurst.new()
	burst.position = Vector2(640, 400)
	add_child(burst)
	burst.play(tier)
	# 屏幕震动 — 抖 self.position
	var shake := ScreenShake.for_tier(self, tier)
	shake.start()


# 决定胡牌特效层级:役満 / 倍満+(11飜+) / 跳満+(6飜+) / 普通
func _win_tier(win_event: BattleEvent) -> int:
	if win_event == null:
		return WinBurst.Tier.LIGHT
	var yakuman_mul: int = int(win_event.extra.get("yakuman_multiplier", 0))
	var han: int = int(win_event.extra.get("han", 0))
	# 玩家胡 vs AI 胡:同样 tier(AI 胡也是表演)
	if yakuman_mul >= 1:
		return WinBurst.Tier.YAKUMAN
	if han >= 11:
		return WinBurst.Tier.HEAVY  # 三倍満
	if han >= 6:
		return WinBurst.Tier.MEDIUM  # 跳満/倍満
	return WinBurst.Tier.LIGHT


func _play_event_sfx(ev: BattleEvent) -> void:
	if ev == null:
		return
	var am = get_node_or_null("/root/AudioManager")
	if am == null:
		return
	var key: String = AudioManager.sfx_key_for_event(ev.type, ev.extra)
	if key == "":
		return
	# 切牌/摸牌 30+次/局 → 加 ±6% 音调随机化
	var pitch_var := 0.06 if (key == "tile_click" or key == "tile_draw") else 0.0
	am.play(key, pitch_var)


# 关键事件 → 顶部金色 toast,玩家不用盯 events 也能感知发生了什么。
# 立直/自摸/荣和/流局/海底/河底 出现就闪 1.5 秒。
func _handle_event_toast(ev: BattleEvent) -> void:
	if ev == null:
		return
	var text: String = _format_toast_text(ev)
	if text == "":
		return
	_show_toast_text(text)


# 任意文本 toast — 共用于 BC 事件 + 成就解锁等。
func _show_toast_text(text: String) -> void:
	if text == "":
		return
	if _toast_label == null:
		_toast_label = Label.new()
		_toast_label.position = Vector2(420, 12)
		_toast_label.size = Vector2(440, 44)
		_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_toast_label.add_theme_font_size_override("font_size", 26)
		_toast_label.add_theme_color_override("font_color", Color(1, 0.88, 0.32))
		_toast_label.add_theme_constant_override("shadow_offset_x", 2)
		_toast_label.add_theme_constant_override("shadow_offset_y", 2)
		_toast_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_toast_label)
	_toast_label.text = text
	_toast_label.visible = true
	# 淡入 0.18s,显示 1.4s,再淡出 0.35s — 比硬切更有质感,新事件压旧时立刻覆盖。
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_label.modulate = Color(1, 1, 1, 0)
	_toast_tween = get_tree().create_tween()
	_toast_tween.tween_property(_toast_label, "modulate:a", 1.0, 0.18)
	_toast_tween.tween_interval(1.4)
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, 0.35)
	var captured := _toast_tween
	_toast_tween.finished.connect(func():
		if _toast_tween == captured and _toast_label:
			_toast_label.visible = false)


static func _seat_short(actor_seat: int) -> String:
	if actor_seat == 0:
		return "你"
	if actor_seat >= 1 and actor_seat <= 3:
		return "AI %d" % actor_seat
	return "?"


static func _format_toast_text(ev: BattleEvent) -> String:
	match ev.type:
		&"RIICHI_DECLARED":
			return "立直! %s" % _seat_short(ev.actor_seat)
		&"TSUMO_DECLARED":
			return "自摸! %s" % _seat_short(ev.actor_seat)
		&"RON_DECLARED":
			return "荣和! %s" % _seat_short(ev.actor_seat)
		&"EXHAUSTIVE_DRAW":
			return "流局"
		&"NAGASHI_MANGAN":
			return "流し満貫! %s" % _seat_short(ev.actor_seat)
		&"ABORTIVE_DRAW":
			var reason: String = String(ev.extra.get("reason", ""))
			match reason:
				"kyuusyu_kyuuhai": return "途中流局 · 九種九牌"
				"suufon_renda": return "途中流局 · 四风连打"
				"suucha_riichi": return "途中流局 · 四家立直"
				"suukantsu_sanra": return "途中流局 · 四杠散了"
				"sancha_houra": return "途中流局 · 三家和了"
				_: return "途中流局"
		&"HAITEI":
			return "海底捞月!"
		&"HOUTEI":
			return "河底捞鱼!"
		&"GAME_BEGIN":
			return "开局"
		&"SKILL_TRIGGERED":
			var name: String = String(ev.extra.get("skill_name", ""))
			if name == "":
				return ""
			return "⚡ %s — %s" % [name, _seat_short(ev.actor_seat)]
	return ""

func _exit_tree() -> void:
	_polling_active = false

func _on_player_tile_clicked(tile_id: int) -> void:
	if _action_panel != null:
		_action_panel.on_hand_tile_clicked(tile_id)

# 键盘 helper：D=切第一张牌；S=跳过；R=立直 yes — 备用调试入口
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not (k.pressed and not k.echo):
		return
	match k.keycode:
		KEY_D:
			if _bc != null and _action_panel != null:
				var hand_ids: Array = _bc.state.seats[0].hand.to_id_array()
				if hand_ids.size() > 0:
					_action_panel.on_hand_tile_clicked(int(hand_ids[0]))
		KEY_S:
			if _action_panel != null:
				_action_panel.player_action_chosen.emit({"action": "skip"})
		KEY_R:
			if _action_panel != null:
				_action_panel.player_action_chosen.emit({"action": "riichi_yes"})
		KEY_ESCAPE:
			# 唤起设置 overlay(SFX 音量调节);overlay 自己 ESC 关
			_open_settings_overlay()


func _open_settings_overlay() -> void:
	# 防止 ESC 连按打开多个
	if get_tree().root.get_node_or_null("_settings_overlay_root") != null:
		return
	var overlay := SettingsOverlay.new()
	overlay.name = "_settings_overlay_root"
	get_tree().root.add_child(overlay)
