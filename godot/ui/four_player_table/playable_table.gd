class_name PlayableTable extends Control

# 麻将王 — 战斗节点真实可玩 顶层容器。
#
# 组合 FourPlayerTable + PlayerActionPanel + PlayableBattleController，
# 跑一局完整东风局玩家可玩对战。
#
# 生产默认复用 FourPlayerTable 2D 完整路径；3D 仅保留为实验模式。

const FOUR_PLAYER_TABLE := preload("res://ui/four_player_table/four_player_table.tscn")
const PLAYER_ACTION_PANEL := preload("res://ui/four_player_table/player_action_panel.tscn")
const TABLE_ACTION_BUTTON_STYLE := preload(
	"res://ui/four_player_table/table_action_button.gd")
const ItemInventoryDrawerScr := preload(
	"res://ui/four_player_table/item_inventory_drawer.gd")
const FirstUseNotices := preload("res://platform/platform_first_use_notices.gd")
const CharacterPresentationCatalogScript := preload(
	"res://presentation/characters/character_presentation_catalog.gd")
const CharacterPresentationRouterScript := preload(
	"res://presentation/characters/character_presentation_router.gd")
const CharacterStatusBadgeScript := preload(
	"res://ui/four_player_table/character_status_badge.gd")

# 高冲击 MomentBand：固定在牌河与操作带之间，1.3s 后卸载。
const MOMENT_BAND_Y: float = 94.0
const MOMENT_BAND_H: float = 32.0
const MOMENT_BAND_ENTER_TIME: float = 0.34
const MOMENT_BAND_EXIT_DELAY: float = 0.98
const MOMENT_BAND_EXIT_TIME: float = 0.32
const MOMENT_BAND_X: float = 550.0
const MOMENT_BAND_W: float = 500.0
const MOMENT_BAND_TRAVEL: float = MOMENT_BAND_W * 1.1
const MOMENT_VARIANTS: Dictionary = {
	"海底捞月": &"haitei",
	"河底捞鱼": &"houtei",
	"岭上开花": &"rinshan",
	"抢杠": &"chankan",
}

# _table 保留类型宽松，让显式实验开关仍可切到 MahjongTable3D。
var _table = null
var _action_panel: PlayerActionPanel = null
var _bc: PlayableBattleController = null
var _decision_adapter: TableDecisionAdapter = null

var _seat_panel_player = null  # SeatPanel 或 MahjongTable3D
# 真 3D 桌（透视 mesh + 2D HUD）仅供显式实验；生产默认走 2D。
var _use_3d: bool = false

# E4-01（#243）：仅 TRASH_TALK 绑定 voice_port → PTT / 采集 / 分座播放。
# E4-03（#245）：挂接 WhisperModelManager 按需 ensure；失败不阻断牌局。
# E7-03（#257）：右下角内联麦克风用途说明 + 模型状态/进度（无弹窗）。
var _voice_port: VoicePortModule = null
var _whisper_model_manager: WhisperModelManager = null
var _ptt_button: Button = null
var _ptt_status: Label = null
var _mic_permission_label: Label = null
var _model_status_label: Label = null
var _model_received_bytes: int = 0
var _model_total_bytes: int = 0
var _ptt_ui_state: StringName = &"idle"
var _voice_capture: VoiceCapturePipeline = null
var _voice_playback: VoicePlaybackRouter = null
var _character_presentation_router = CharacterPresentationRouterScript.new(
	CharacterPresentationCatalogScript.active_profiles())
var _character_status_badge: Control = null

func _ready() -> void:
	# 操作条位于 1600×900 舞台内，是 overlay，不额外增加 72px 高度。
	custom_minimum_size = Vector2(DT.VIEW_W, TableLayout.VIEW_H)
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

# P0：平面桌（关闭 3D 倾桌）。整桌可点、布局可预测。

var _vp_table: SubViewport = null  # 保留字段兼容旧引用；P0 不建倾桌

func _build_layout() -> void:
	custom_minimum_size = Vector2(TableLayout.VIEW_W, TableLayout.VIEW_H)
	var bg := ColorRect.new()
	bg.size = Vector2(TableLayout.VIEW_W, TableLayout.VIEW_H)
	bg.color = DT.BG_BASE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	if _use_3d:
		_table = MahjongTable3D.new()
		_table.position = Vector2(0, 0)
		add_child(_table)
		_seat_panel_player = _table
	else:
		_table = FOUR_PLAYER_TABLE.instantiate()
		_build_flat_table()

	_action_panel = PLAYER_ACTION_PANEL.instantiate()
	_action_panel.position = TableLayout.ACTION_BAR_RECT.position
	_action_panel.size = TableLayout.ACTION_BAR_RECT.size
	add_child(_action_panel)

	_build_top_bar()
	_character_status_badge = CharacterStatusBadgeScript.new()
	add_child(_character_status_badge)

	_dora_widget = DoraWidget.new()
	_dora_widget.position = Vector2(180, 100)
	add_child(_dora_widget)
	_dora_widget.update_state([], 0)
	# 操作条在牌桌、3D 视口（实验模式）及 HUD 之上。
	move_child(_action_panel, get_child_count() - 1)


# 顶栏：stage-header 透明容器 + logo + HUD + loadout + 规则/设置。
func _build_top_bar() -> void:
	var bar := Panel.new()
	bar.name = "TopBar"
	bar.position = Vector2.ZERO
	bar.size = Vector2(TableLayout.TABLE_W, TableLayout.TOP_BAR_H)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color.TRANSPARENT
	bar.add_theme_stylebox_override("panel", bsb)
	add_child(bar)

	var logo := Label.new()
	logo.text = "麻 将 王"
	logo.position = Vector2(18, 6)
	logo.size = Vector2(180, 40)
	logo.add_theme_font_size_override("font_size", 28)
	logo.add_theme_color_override("font_color", DT.TEXT_TITLE)
	logo.add_theme_constant_override("shadow_offset_x", 2)
	logo.add_theme_constant_override("shadow_offset_y", 2)
	logo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)

	var rules_btn := DT.make_button("规则", DT.BtnRole.SECONDARY, Vector2(88, 34))
	rules_btn.name = "RulesButton"
	TABLE_ACTION_BUTTON_STYLE.apply_table_utility_style(rules_btn)
	rules_btn.position = Vector2(TableLayout.TABLE_W - 196, 7)
	rules_btn.pressed.connect(_open_help_overlay)
	add_child(rules_btn)
	var settings_btn := DT.make_button("设置", DT.BtnRole.SECONDARY, Vector2(88, 34))
	settings_btn.name = "SettingsButton"
	TABLE_ACTION_BUTTON_STYLE.apply_table_utility_style(settings_btn)
	settings_btn.position = Vector2(TableLayout.TABLE_W - 100, 7)
	settings_btn.pressed.connect(_open_settings_overlay.bind(settings_btn))
	add_child(settings_btn)


func _open_help_overlay() -> void:
	if get_tree().root.get_node_or_null("_help_overlay_root") != null:
		return
	var overlay := HelpOverlay.new()
	overlay.name = "_help_overlay_root"
	get_tree().root.add_child(overlay)


# 平面满桌：FourPlayerTable 直接挂树，seat0 手牌可点，无 SubViewport/倾桌。
func _build_flat_table() -> void:
	_table.position = Vector2.ZERO
	_table.scale = Vector2.ONE
	add_child(_table)

var _pending_discard_fly: Dictionary = {}  # {from: Vector2, tile_id: int, is_red: bool}


func play_hand_async(bc: PlayableBattleController) -> Dictionary:
	_bc = bc
	_sync_character_status()
	if _use_3d:
		_seat_panel_player = _table
	elif _table.seat_panels.size() >= 1:
		_seat_panel_player = _table.seat_panels[0]
	if _seat_panel_player != null:
		if _seat_panel_player.has_signal("player_card_clicked") \
				and not _seat_panel_player.player_card_clicked.is_connected(_on_player_tile_clicked):
			_seat_panel_player.player_card_clicked.connect(_on_player_tile_clicked)
		if _seat_panel_player.has_signal("hand_tile_hover") \
				and not _seat_panel_player.hand_tile_hover.is_connected(_on_hand_tile_hover):
			_seat_panel_player.hand_tile_hover.connect(_on_hand_tile_hover)
	_decision_adapter = TableDecisionAdapter.new(_action_panel, _seat_panel_player)
	_bc.bind_decision_port(_decision_adapter, get_tree())
	# E4-01：从真实 mode_modules.voice_port 绑定（STANDARD 为 null → 零语音节点）
	bind_voice_from_battle(bc)
	# E5-06：TRASH_TALK 奖励 HUD/抽屉只读接线（不改权威）
	_bind_reward_feedback_from_battle(bc)
	_bind_state_for_deal(bc.state, 0, 4)
	_decision_adapter.present(&"idle", {"text": "准备开局…"})
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
	# T5:发牌演出 — 52 张牌背从桌心轮发飞向四家;期间真手牌隐藏。
	# SettingsManager.skip_deal_animation 可关。
	if not DealAnimation.should_skip(get_tree()):
		_set_hand_rows_visible(false)
		await DealAnimation.play_async(self)
		_set_hand_rows_visible(true)
	var result: Dictionary = await bc.run_to_end_async()
	if dbg:
		dbg.unregister_battle_controller(bc)
	if log_node:
		log_node.info("battle", "hand end last_event=%s" % str(result.get("last_event", "")))
	_decision_adapter.present(&"idle", {"text": "本局结束"})
	_table.bind_battle_state(bc.state, 0, 4)
	_sync_dora_widget(bc.state)
	# 记终身统计 + 检测成就解锁(发 achievement_unlocked signal,toast 在 _on_achievement_unlocked)
	_record_hand_stats(bc)
	# 胡牌或流局后弹结算 overlay：玩家点继续才推进下一局
	await _show_hand_result_overlay(result)
	return result


func bind_character_ids(character_ids: Array) -> void:
	_character_presentation_router.bind_characters(character_ids, _reward_local_seat)
	_sync_viewer_reveal_label()
	_sync_character_status()


## 只读：CharacterPresentationRouter 已绑定的权威四席角色（测试/诊断；不改生产逻辑）。
func presentation_character_ids() -> Array:
	if _character_presentation_router == null:
		return []
	if _character_presentation_router.has_method("bound_character_ids"):
		return _character_presentation_router.bound_character_ids()
	return []


func _sync_viewer_reveal_label() -> void:
	if _table != null and _table.has_method("set_viewer_reveal_label"):
		_table.set_viewer_reveal_label(
			_character_presentation_router.reveal_label_for_local_character(
				_reward_local_seat))
	if _table != null and _table.has_method("set_next_draw_reveal_label"):
		_table.set_next_draw_reveal_label(
			_character_presentation_router.next_draw_label_for_local_character(
				_reward_local_seat))
	if _table != null and _table.has_method("set_seat_draw_forecast_label"):
		_table.set_seat_draw_forecast_label(
			_character_presentation_router.seat_draw_forecast_label_for_local_character(
				_reward_local_seat))


func on_match_scores_updated(scores: Array) -> void:
	_play_character_voice_requests(
		_character_presentation_router.voice_requests_for_scores(scores))


func on_match_finished(summary: Dictionary) -> void:
	var final_scores: Array = summary.get("final_scores", [])
	_play_character_voice_requests(
		_character_presentation_router.voice_requests_for_match_result(final_scores))


# 同一张 PlayableTable 会连续跑多局；必须在新状态 bind 前清上局胜者翻牌，
# 否则 SeatPanel 会继续按旧 revealed hand 重建，发牌采集拿不到 4×13 槽。
func _bind_state_for_deal(state: BattleState, hand_index: int,
		hands_per_round: int) -> void:
	if _table == null:
		return
	if _table is FourPlayerTable:
		for panel in _table.seat_panels:
			if panel != null:
				panel.clear_hand_reveal()
	_table.bind_battle_state(state, hand_index, hands_per_round)
	_sync_dora_widget(state)


func _sync_dora_widget(state: BattleState) -> void:
	if _dora_widget == null or state == null:
		return
	var indicator_ids: Array = []
	if state.dora_indicators != null:
		for tile in state.dora_indicators.visible_tiles():
			if tile != null:
				indicator_ids.append(tile.id)
	_dora_widget.update_state(indicator_ids, state.honba)


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
	var gate_started_usec := Time.get_ticks_usec()
	var last_event: String = String(result.get("last_event", ""))
	var win_event: BattleEvent = null
	for i in range(_bc.events.size() - 1, -1, -1):
		var ev: BattleEvent = _bc.events[i]
		if ev.type == &"WIN_DECLARED":
			win_event = ev
			break
	# drawInfo 必须在上层推进到下一 BattleState 之前冻结；modal 延迟挂载后只读快照。
	var draw_snapshots: Array = []
	if win_event == null and last_event == "EXHAUSTIVE_DRAW":
		draw_snapshots = _build_exhaustive_draw_snapshots()
	# 胡牌先翻手牌。演出分级不能混用其他规则的番数量纲，本仓只有日麻
	# han / yakuman_multiplier，量纲不等价；确认宣告由事件轮询单独播放，
	# 这里不得自行猜分级并追加白闪、方块粒子或整桌震动。
	if win_event != null:
		_reveal_winner_hand(win_event)
	var gate_seconds := _result_modal_gate_seconds(win_event != null, last_event)
	if gate_seconds > 0.0:
		var gate_finished := await _await_result_modal_gate(
			gate_seconds, gate_started_usec)
		if not gate_finished:
			return
	if win_event != null:
		_unmount_win_announces_before_result()
	var shell := _create_result_modal_shell()
	var overlay := shell["overlay"] as Control
	var backdrop := shell["backdrop"] as ColorRect
	var panel := shell["panel"] as Panel
	_animate_reference_result_modal(backdrop, panel)

	# tier 大字：役満 / 倍満 / 跳満 / 満貫 / N 飜 N 符
	var tier := Label.new()
	tier.name = "ResultTitle"
	tier.position = Vector2(36, 24)
	tier.size = Vector2(548, 38)
	tier.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tier.add_theme_font_size_override("font_size", 26)
	tier.add_theme_color_override("font_color", Color("d9b65b"))
	tier.add_theme_constant_override("shadow_offset_x", 2)
	tier.add_theme_constant_override("shadow_offset_y", 2)
	tier.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	panel.add_child(tier)

	# 副标题：谁 · 自摸/荣和
	var subtitle := Label.new()
	subtitle.name = "ResultSubtitle"
	subtitle.position = Vector2(36, 64)
	subtitle.size = Vector2(548, 24)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color("f4ead2d9"))
	panel.add_child(subtitle)

	if win_event != null:
		var winner_seat: int = win_event.actor_seat
		var winner_name: String = "你" if winner_seat == 0 else "AI %d" % winner_seat
		var announce_kind := _confirmed_win_announce_kind(win_event.extra)
		var win_kind: String = {
			&"tsumo": "自摸",
			&"chankan": "抢杠",
			&"ron": "荣和",
		}[announce_kind]
		var fu: int = int(win_event.extra.get("fu", 0))
		var han: int = int(win_event.extra.get("han", 0))
		var yakuman_mul: int = int(win_event.extra.get("yakuman_multiplier", 0))
		tier.text = "%s　和牌" % winner_name
		subtitle.text = "%s · %s" % [win_kind,
			_score_tier_label(han, fu, yakuman_mul)]
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
		subtitle.text = "查听"
	elif last_event == "ABORTIVE_DRAW":
		# 5 种途中流局(日麻 §3.2):九種九牌 / 四风连打 / 四家立直 / 四杠散了 / 三家和了
		tier.text = "中途流局"
		tier.add_theme_color_override("font_color", Color(0.85, 0.62, 0.85))
		subtitle.text = _abortive_reason_label(_find_last_event_extra("ABORTIVE_DRAW"))
	else:
		tier.text = "本局结束"
		subtitle.text = ""

	# Step 1：番种结算。使用单列役；滚分不得在本步骤提前启动。
	_result_anim_tweens.clear()
	var yaku_list: Control = null
	var bonus_list: Control = null
	var total_bar: Control = null
	if win_event != null:
		var result_yaku: Array = win_event.extra.get("yaku_names", [])
		yaku_list = _build_yaku_rows(panel, result_yaku)
		var bonus_rows := _result_bonus_rows(win_event.extra, result_yaku)
		var shown_yaku_count := result_yaku.size()
		if not bonus_rows.is_empty():
			var bonus_delay := (shown_yaku_count + 1) * RESULT_PHASE_INTERVAL
			bonus_list = _build_result_bonus_rows(panel, bonus_rows, bonus_delay)
		if not result_yaku.is_empty():
			var total_delay := _result_total_reveal_delay(
				shown_yaku_count, not bonus_rows.is_empty())
			total_bar = _build_result_total_bar(panel,
				int(win_event.extra.get("han", 0)),
				int(win_event.extra.get("winner_total", 0)), total_delay)

	var hand_strip: Control = null
	if win_event != null and win_event.tile_anchor != null and win_event.tile_anchor.tile != null:
		var is_tsumo := bool(win_event.extra.get("is_tsumo", false))
		hand_strip = _render_winning_hand_strip(panel, win_event.actor_seat,
			win_event.tile_anchor.tile.id, is_tsumo, 96)
	var draw_list: Control = null
	if last_event == "EXHAUSTIVE_DRAW" and not draw_snapshots.is_empty():
		draw_list = _build_draw_result_list(panel, draw_snapshots)

	# 胡牌的 Step 2 不预建；流し满贯属于单页非 win 结果，直接展示真实支付。
	var detail := Label.new()
	detail.name = "ResultDetail"
	detail.position = Vector2(36, 155)
	detail.size = Vector2(548, 285)
	detail.add_theme_font_size_override("font_size", 16)
	detail.add_theme_color_override("font_color", Color("f4ead2"))
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var pending_payments: Array[int] = [0, 0, 0, 0]
	var pending_final_scores: Array[int] = [0, 0, 0, 0]
	var pending_dealer := 0
	var has_nagashi_payment := false
	if win_event != null:
		var winner_total: int = int(win_event.extra.get("winner_total", 0))
		var payout: Dictionary = win_event.extra.get("payout", {})
		for seat in payout.keys():
			var seat_id := int(seat)
			if seat_id >= 0 and seat_id < 4:
				pending_payments[seat_id] -= int(payout[seat])
		var winner_id := int(win_event.actor_seat)
		if winner_id >= 0 and winner_id < 4:
			pending_payments[winner_id] += winner_total
		if _bc != null and _bc.state != null:
			pending_dealer = int(_bc.state.dealer_seat)
			for seat_id in range(4):
				pending_final_scores[seat_id] = int(_bc.state.scores[seat_id]) \
					+ pending_payments[seat_id]
	elif last_event == "NAGASHI_MANGAN" and _bc != null \
			and _bc.state != null:
		var payment_extra: Dictionary = _find_last_event_extra("NAGASHI_MANGAN")
		var nm_winner := int(payment_extra.get("winner_seat", -1))
		pending_dealer = int(_bc.state.dealer_seat)
		var nagashi_payment: Dictionary = NagashiMangan.payout(
			nm_winner, pending_dealer)
		for seat_id in range(4):
			pending_payments[seat_id] = int(nagashi_payment.get(seat_id, 0))
			pending_final_scores[seat_id] = int(_bc.state.scores[seat_id]) \
				+ pending_payments[seat_id]
		has_nagashi_payment = true
	elif last_event == "ABORTIVE_DRAW":
		detail.name = "AbortiveDrawNote"
		detail.position = Vector2(36, 108)
		detail.size = Vector2(548, 80)
		detail.text = "本局不查听、不结算；报听棒结转下一局。"
	else:
		detail.text = "无人胡牌（流局）"
	detail.visible = win_event == null and not is_instance_valid(draw_list) \
		and last_event != "NAGASHI_MANGAN"
	panel.add_child(detail)
	if has_nagashi_payment:
		_build_score_delta_list(panel, pending_final_scores,
			pending_payments, pending_dealer)

	var step_hint := Label.new()
	step_hint.position = Vector2(36, 458)
	step_hint.size = Vector2(548, 20)
	step_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	step_hint.text = "1 / 2 · 番种结算" if win_event != null else ""
	step_hint.add_theme_font_size_override("font_size", 11)
	step_hint.add_theme_color_override("font_color", Color("d9b65b8c"))
	panel.add_child(step_hint)

	var btn := Button.new()
	btn.name = "ResultContinueButton"
	btn.text = "继续 →" if win_event != null else "确定"
	btn.position = Vector2(230, 490)
	btn.custom_minimum_size = Vector2(160, 44)
	btn.focus_mode = Control.FOCUS_ALL
	DT.apply_button_role(btn, DT.BtnRole.PRIMARY)
	var step_state := {"value": 1 if win_event != null else 2}
	btn.pressed.connect(func():
		if int(step_state["value"]) == 1:
			_skip_result_animations()
			step_state["value"] = 2
			if is_instance_valid(yaku_list):
				yaku_list.visible = false
			if is_instance_valid(bonus_list):
				bonus_list.visible = false
			if is_instance_valid(total_bar):
				total_bar.visible = false
			if is_instance_valid(hand_strip):
				hand_strip.visible = false
			tier.text = "分数变动"
			detail.visible = false
			step_hint.text = "2 / 2 · 分数变动"
			btn.text = "确定"
			_build_score_delta_list(panel, pending_final_scores,
				pending_payments, pending_dealer)
			return
		_skip_result_animations()
		overlay.queue_free())
	panel.add_child(btn)
	btn.grab_focus()

	# modal backdrop 不负责关闭；只允许显式按钮推进两步状态机。
	while is_instance_valid(overlay):
		await get_tree().process_frame


# ---- T4 结算编排(spec 2026-06-11 G4) ----

# 正在播放的结算动画 [{tween, finish: Callable}];点击跳过时统一收尾。
var _result_anim_tweens: Array = []
const RESULT_MODAL_SIZE := Vector2(620, 560)
const RESULT_MODAL_PADDING := Vector4(36, 28, 36, 24)
const RESULT_BACKDROP_COLOR := Color("00000055")
const RESULT_PHASE_INTERVAL := 0.7
const RESULT_YAKU_LIGHT_DURATION := 0.26
const RESULT_YAKU_HEAVY_DURATION := 0.28
const RESULT_TOTAL_WAIT := 1.0
const RESULT_TOTAL_DURATION := 0.42
const RESULT_HEAVY_HAN := 8
const RESULT_SCORE_ROLL_DURATION := 1.5
const RESULT_WIN_MODAL_GATE := 3.0
const RESULT_DRAW_MODAL_GATE := 0.5
const RESULT_TILE_SM_SIZE := Vector2(30, 40)
const RESULT_WIN_TILE_SM_SIZE := Vector2(34, 45)
static var _result_felt_shader: Shader = null


# ended win 固定 3000ms，其余普通/途中流局固定 500ms。
static func _result_modal_gate_seconds(has_win: bool, _last_event: String) -> float:
	if has_win:
		return RESULT_WIN_MODAL_GATE
	return RESULT_DRAW_MODAL_GATE


# 用 PlayableTable 子 Timer，而非 SceneTreeTimer；父节点退出树时 Timer 一并退出，
# 不会在旧牌桌外继续回调并挂载孤儿 modal。started_usec 保证门控从函数入口计时。
func _await_result_modal_gate(seconds: float, started_usec: int) -> bool:
	if not is_inside_tree():
		return false
	var elapsed := float(Time.get_ticks_usec() - started_usec) / 1000000.0
	var remaining := maxf(seconds - elapsed, 0.0)
	if remaining <= 0.0:
		return is_inside_tree()
	var timer := Timer.new()
	timer.name = "ResultModalGate"
	timer.one_shot = true
	add_child(timer)
	var gate_state := {"cancelled": false}
	var cancel_gate := func() -> void:
		gate_state["cancelled"] = true
		if is_instance_valid(timer):
			timer.stop()
			timer.timeout.emit()
	tree_exiting.connect(cancel_gate, CONNECT_ONE_SHOT)
	timer.start(remaining)
	await timer.timeout
	if tree_exiting.is_connected(cancel_gate):
		tree_exiting.disconnect(cancel_gate)
	if not bool(gate_state["cancelled"]) and is_instance_valid(timer):
		timer.queue_free()
	return not bool(gate_state["cancelled"]) and is_inside_tree()


# result modal 状态挂载前卸载 win-announce。事件 polling 可能比
# gate 晚一帧创建节点，因此这里按结构状态卸载，避免两个同为 3s 的组件重叠一帧。
func _unmount_win_announces_before_result() -> void:
	for child in get_children():
		if child is CallAnnounce \
				and bool(child.get_meta("is_win_announce", false)):
			remove_child(child)
			child.queue_free()


# vP(drawInfo) 的本仓等价输入：真实 WaitCalculator + noten payout，冻结手牌与
# 副露对象，并在这里按庄家起顺时针排好，后续 modal 不再读取活 BattleState。
func _build_exhaustive_draw_snapshots() -> Array:
	if _bc == null or _bc.state == null or _bc.state.seats.size() < 4:
		return []
	var tenpai_array: Array = []
	for seat_id in range(4):
		var seat: Seat = _bc.state.seats[seat_id]
		tenpai_array.append(WaitCalculator.is_tenpai(seat.hand, seat.melds.all()))
	var payments := ExhaustiveDraw.noten_payout(tenpai_array)
	var snapshots: Array = []
	var dealer := int(_bc.state.dealer_seat)
	for offset in range(4):
		var seat_id := (dealer + offset) % 4
		var seat: Seat = _bc.state.seats[seat_id]
		var hand_snapshot: Array[Tile] = []
		for tile in seat.hand.tiles():
			hand_snapshot.append(_clone_result_tile(tile))
		hand_snapshot.sort_custom(func(a: Tile, b: Tile) -> bool:
			if a.id == b.id:
				return int(a.is_red_dora) < int(b.is_red_dora)
			return a.id < b.id)
		var meld_snapshots: Array[Meld] = []
		for meld in seat.melds.all():
			meld_snapshots.append(_clone_result_meld(meld))
		snapshots.append({
			"seat": seat_id,
			"tenpai": bool(tenpai_array[seat_id]),
			"winKind": "",
			"payment": int(payments.get(seat_id, 0)),
			"hand": hand_snapshot,
			"melds": meld_snapshots,
		})
	return snapshots


static func _clone_result_tile(tile: Tile) -> Tile:
	if tile == null:
		return null
	return Tile.new(tile.id, tile.is_red_dora, tile.owner_seat, tile.instance_id)


static func _clone_result_meld(meld: Meld) -> Meld:
	if meld == null:
		return null
	if not Meld.is_valid_meld_id(meld.meld_id):
		return null

	# 克隆全部 tiles 并保留 identity。
	var cloned_tiles: Array[Tile] = []
	for original in meld.tiles:
		cloned_tiles.append(_clone_result_tile(original))

	# ANKAN：闭式副露，from/called 必须哨兵，called 实体必须空。
	if meld.kind == Meld.Kind.ANKAN:
		if meld.from_seat != Meld.NO_SOURCE_SEAT:
			return null
		if meld.called_tile_instance_id != Tile.INVALID_INSTANCE_ID:
			return null
		if meld.called_tile != null:
			return null
		return Meld.new(Meld.Kind.ANKAN, cloned_tiles, Meld.NO_SOURCE_SEAT,
			meld.meld_id, null)

	# CHI/PON/MINKAN/ADDED_KAN 均为开放副露。
	if meld.kind != Meld.Kind.CHI and meld.kind != Meld.Kind.PON \
			and meld.kind != Meld.Kind.MINKAN and meld.kind != Meld.Kind.ADDED_KAN:
		return null
	if meld.from_seat < 0 or meld.from_seat > 3:
		return null
	if not Tile.is_valid_instance_id(meld.called_tile_instance_id):
		return null
	var called_in_src := false
	for original in meld.tiles:
		if original != null and original.instance_id == meld.called_tile_instance_id:
			called_in_src = true
			break
	if not called_in_src:
		return null

	# ADDED_KAN：先 base PON + meld_id/called，再 promote 写 added identity。
	# 缺 added / 缺 called / added==called / promote 失败 → fail-closed null。
	if meld.kind == Meld.Kind.ADDED_KAN:
		if not Tile.is_valid_instance_id(meld.added_tile_instance_id):
			return null
		if meld.added_tile_instance_id == meld.called_tile_instance_id:
			return null
		var base_tiles: Array[Tile] = []
		var added_copy: Tile = null
		var called_base: Tile = null
		for t in cloned_tiles:
			if t.instance_id == meld.added_tile_instance_id:
				added_copy = t
			else:
				base_tiles.append(t)
				if t.instance_id == meld.called_tile_instance_id:
					called_base = t
		if added_copy == null or called_base == null:
			return null
		var clone_pon := Meld.new(Meld.Kind.PON, base_tiles, meld.from_seat,
			meld.meld_id, called_base)
		if not clone_pon.promote_to_added_kan(added_copy):
			return null
		return clone_pon

	# 其它开放副露：called 必须指向 cloned_tiles 内对象。
	var called_tile: Tile = null
	for t in cloned_tiles:
		if t.instance_id == meld.called_tile_instance_id:
			called_tile = t
			break
	if called_tile == null:
		return null
	return Meld.new(meld.kind, cloned_tiles, meld.from_seat, meld.meld_id, called_tile)


# 公开 `.modal__draw-list` / vP() 的 2D 等价结构：真实暗手后复用
# Fl(flat:true) 渲染快照中的副露。
func _build_draw_result_list(panel: Control, snapshots: Array) -> VBoxContainer:
	var list := VBoxContainer.new()
	list.name = "DrawResultList"
	list.position = Vector2(36, 100)
	list.size = Vector2(548, 350)
	list.add_theme_constant_override("separation", 10)
	panel.add_child(list)
	for snapshot in snapshots:
		var seat_id := int(snapshot.get("seat", -1))
		var tenpai := bool(snapshot.get("tenpai", false))
		var win_kind := String(snapshot.get("winKind", ""))
		var highlighted := tenpai or win_kind != ""
		var payment := int(snapshot.get("payment", 0))
		var row := Panel.new()
		row.name = "DrawSeat%d" % seat_id
		row.custom_minimum_size = Vector2(548, 80)
		row.set_meta("seat_id", seat_id)
		row.set_meta("tenpai", tenpai)
		row.set_meta("winKind", win_kind)
		row.set_meta("payment", payment)
		row.set_meta("meld_count", (snapshot.get("melds", []) as Array).size())
		var row_style := StyleBoxFlat.new()
		row_style.bg_color = Color("d9b65b1f") if highlighted else Color("0000002e")
		row_style.set_corner_radius_all(6)
		if highlighted:
			row_style.border_color = Color("d9b65b40")
			row_style.set_border_width_all(1)
		row.add_theme_stylebox_override("panel", row_style)
		list.add_child(row)

		var seat_name := Label.new()
		seat_name.name = "SeatName"
		seat_name.position = Vector2(10, 5)
		seat_name.size = Vector2(96, 22)
		seat_name.text = "你" if seat_id == 0 else "AI %d" % seat_id
		seat_name.add_theme_font_size_override("font_size", 13)
		seat_name.add_theme_color_override("font_color", Color("f4ead2"))
		row.add_child(seat_name)

		var tag := Label.new()
		tag.name = "Tag"
		tag.position = Vector2(106, 5)
		tag.size = Vector2(58, 22)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.text = "自摸" if win_kind == "tsumo" else \
			"荣和" if win_kind == "ron" else "听" if tenpai else "不听"
		tag.add_theme_font_size_override("font_size", 12)
		var tag_style := StyleBoxFlat.new()
		if win_kind != "":
			tag.add_theme_color_override("font_color", Color("e5c66b"))
			tag_style.bg_color = Color("d4b05c2e")
			tag_style.border_color = Color("d4b05c66")
		elif tenpai:
			tag.add_theme_color_override("font_color", Color("6bc06b"))
			tag_style.bg_color = Color("6bc06b2e")
			tag_style.border_color = Color("6bc06b66")
		else:
			tag.add_theme_color_override("font_color", Color("d97a7a"))
			tag_style.bg_color = Color("d97a7a24")
			tag_style.border_color = Color("d97a7a52")
		tag_style.set_border_width_all(1)
		tag_style.set_corner_radius_all(999)
		tag_style.content_margin_left = 8
		tag_style.content_margin_right = 8
		tag_style.content_margin_top = 1
		tag_style.content_margin_bottom = 1
		tag.add_theme_stylebox_override("normal", tag_style)
		row.add_child(tag)

		var payment_label := Label.new()
		payment_label.name = "Payment"
		payment_label.position = Vector2(430, 3)
		payment_label.size = Vector2(108, 24)
		payment_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		payment_label.text = "+%d" % payment if payment > 0 else str(payment)
		payment_label.add_theme_font_size_override("font_size", 16)
		payment_label.add_theme_color_override("font_color",
			Color("6bc06b") if payment > 0 else
			Color("d97a7a") if payment < 0 else Color("f4ead2"))
		row.add_child(payment_label)

		# `.modal__draw-tiles`: flex-wrap + align-end + 6px gap。
		var tiles := HFlowContainer.new()
		tiles.name = "Tiles"
		tiles.position = Vector2(10, 30)
		tiles.size = Vector2(528, 40)
		tiles.add_theme_constant_override("h_separation", 6)
		tiles.add_theme_constant_override("v_separation", 6)
		tiles.set_meta("reference_align", "flex-end")
		row.add_child(tiles)
		var hand_index := 0
		for tile in snapshot.get("hand", []):
			if tile is Tile:
				var hand_tile := _make_result_tile(
					tile.id, false, tile.is_red_dora, RESULT_TILE_SM_SIZE)
				hand_tile.name = "HandTile%d" % hand_index
				hand_tile.set_meta("result_role", "hand")
				hand_tile.size_flags_vertical = Control.SIZE_SHRINK_END
				tiles.add_child(hand_tile)
				hand_index += 1
		var melds: Array = snapshot.get("melds", [])
		if not melds.is_empty():
			var flat_melds := _build_flat_result_melds(
				melds, RESULT_TILE_SM_SIZE, "FlatMelds")
			flat_melds.size_flags_vertical = Control.SIZE_SHRINK_END
			tiles.add_child(flat_melds)
	return list


# 公开 Fl(flat:true)：flat 会把 effective owner/claimant 固定为 0，因此直接
# 复用 MeldLayout.compute(meld, 0) 的 nV 翻译；meld 间 6px、牌间 1px。
func _build_flat_result_melds(melds: Array, tile_size: Vector2,
		node_name: String = "FlatMelds") -> HBoxContainer:
	var root := HBoxContainer.new()
	root.name = node_name
	root.add_theme_constant_override("separation", 6)
	root.size_flags_vertical = Control.SIZE_SHRINK_END
	for meld_index in range(melds.size()):
		var meld := melds[meld_index] as Meld
		if meld == null:
			continue
		var group := HBoxContainer.new()
		group.name = "FlatMeld%d" % meld_index
		group.add_theme_constant_override("separation", 1)
		group.size_flags_vertical = Control.SIZE_SHRINK_END
		group.set_meta("meld_kind", meld.kind)
		root.add_child(group)
		var slots := MeldLayout.compute(meld, 0)
		var stack_anchor: Control = null
		for slot_index in range(slots.size()):
			var slot := slots[slot_index] as Dictionary
			var slot_node := _make_flat_result_meld_slot(
				slot, tile_size, slot_index)
			if bool(slot.get("stacked_above", false)) and stack_anchor != null:
				slot_node.position = Vector2(0, -slot_node.size.y - 1)
				stack_anchor.name = "MeldStack"
				stack_anchor.set_meta("stacked_count", 2)
				stack_anchor.add_child(slot_node)
				continue
			group.add_child(slot_node)
			if bool(slot.get("rotated", false)):
				stack_anchor = slot_node
	return root


func _make_flat_result_meld_slot(slot: Dictionary, tile_size: Vector2,
		slot_index: int) -> Control:
	var horizontal := bool(slot.get("rotated", false))
	var face_down := bool(slot.get("face_down", false))
	var visual_size := Vector2(tile_size.y, tile_size.x) if horizontal else tile_size
	var host := Control.new()
	host.name = "FlatMeldTile%d" % slot_index
	host.custom_minimum_size = visual_size
	host.size = visual_size
	host.size_flags_vertical = Control.SIZE_SHRINK_END
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.set_meta("flat_meld_tile", true)
	host.set_meta("tile_id", int(slot.get("tile_id", -1)))
	host.set_meta("horizontal", horizontal)
	host.set_meta("face_down", face_down)
	host.set_meta("stacked_above", bool(slot.get("stacked_above", false)))
	host.set_meta("visual_size", visual_size)
	if face_down:
		var back := _make_result_tile_back(tile_size)
		back.name = "Back"
		host.add_child(back)
		return host
	var face := _make_result_tile(int(slot.get("tile_id", -1)), false,
		bool(slot.get("is_red_dora", false)), tile_size)
	face.name = "Face"
	if horizontal:
		face.pivot_offset = tile_size / 2.0
		face.rotation_degrees = -90
		var half_delta := (tile_size.y - tile_size.x) / 2.0
		face.position = Vector2(half_delta, -half_delta)
	host.add_child(face)
	return host


func _make_result_tile_back(tile_size: Vector2) -> Panel:
	var back := Panel.new()
	back.custom_minimum_size = tile_size
	back.size = tile_size
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("2c5e3f")
	style.border_color = Color("0c231699")
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	back.add_theme_stylebox_override("panel", style)
	return back


# 结算 backdrop / modal 的 Godot 壳；内容按两步状态机装入。
func _create_result_modal_shell() -> Dictionary:
	var overlay := Control.new()
	overlay.name = "ResultOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = RESULT_BACKDROP_COLOR
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(backdrop)
	var panel := Panel.new()
	panel.name = "ResultModal"
	panel.position = TableLayout.RESULT_PANEL_RECT.position
	panel.custom_minimum_size = RESULT_MODAL_SIZE
	panel.size = RESULT_MODAL_SIZE
	panel.clip_contents = false
	var style := DT.make_shared_panel_style("Modal")
	style.set_corner_radius_all(12)
	style.content_margin_left = RESULT_MODAL_PADDING.x
	style.content_margin_top = RESULT_MODAL_PADDING.y
	style.content_margin_right = RESULT_MODAL_PADDING.z
	style.content_margin_bottom = RESULT_MODAL_PADDING.w
	style.shadow_color = Color("0000008c")
	style.shadow_size = 60
	style.shadow_offset = Vector2(0, 20)
	panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(panel)
	var felt := ColorRect.new()
	felt.name = "FeltGradient"
	felt.position = Vector2.ONE
	felt.size = RESULT_MODAL_SIZE - Vector2(2, 2)
	felt.color = Color.WHITE
	felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	felt.material = _make_result_felt_material(felt.size)
	panel.add_child(felt)
	return {"overlay": overlay, "backdrop": backdrop, "panel": panel}


static func _make_result_felt_material(rect_size: Vector2) -> ShaderMaterial:
	if _result_felt_shader == null:
		_result_felt_shader = Shader.new()
		_result_felt_shader.code = """
shader_type canvas_item;
uniform vec2 rect_size = vec2(618.0, 558.0);
uniform float radius = 11.0;
uniform vec4 lacquer_top : source_color = vec4(0.071, 0.075, 0.094, 1.0);
uniform vec4 lacquer_bottom : source_color = vec4(0.027, 0.031, 0.039, 1.0);
uniform vec4 inner_line : source_color = vec4(0.008, 0.008, 0.016, 1.0);
void fragment() {
	vec2 p = UV * rect_size;
	vec2 q = abs(p - rect_size * 0.5) - (rect_size * 0.5 - vec2(radius));
	float dist = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	float alpha = 1.0 - smoothstep(-0.7, 0.7, dist);
	float diagonal = clamp(UV.x * 0.22 + UV.y * 0.78, 0.0, 1.0);
	vec3 lacquer = mix(lacquer_top.rgb, lacquer_bottom.rgb, diagonal);
	float edge_distance = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float inner = smoothstep(0.0, 0.008, edge_distance);
	lacquer = mix(inner_line.rgb, lacquer, inner);
	COLOR = vec4(lacquer, alpha);
}
"""
	var shader_material := ShaderMaterial.new()
	shader_material.shader = _result_felt_shader
	shader_material.set_shader_parameter("rect_size", rect_size)
	shader_material.set_shader_parameter("lacquer_top", Color("121318"))
	shader_material.set_shader_parameter("lacquer_bottom", Color("07080a"))
	shader_material.set_shader_parameter("inner_line", Color("020204"))
	return shader_material


func _animate_reference_result_modal(backdrop: ColorRect, panel: Panel) -> void:
	backdrop.modulate.a = 0.0
	var fade := create_tween()
	fade.tween_property(backdrop, "modulate:a", 1.0, 0.2)
	var target_position := panel.position
	var start_position := target_position + Vector2(0, 8)
	panel.pivot_offset = panel.size / 2.0
	panel.position = start_position
	panel.scale = Vector2.ONE * 0.92
	panel.modulate.a = 0.0
	var update := func(progress: float) -> void:
		if not is_instance_valid(panel):
			return
		var eased := _result_pop_ease(progress)
		panel.position = start_position.lerp(target_position, eased)
		panel.scale = Vector2.ONE * lerpf(0.92, 1.0, eased)
		panel.modulate.a = clampf(eased, 0.0, 1.0)
	var pop := create_tween()
	pop.tween_method(update, 0.0, 1.0, 0.25)


# cubic-bezier(.34,1.56,.64,1) 的数值解，保留 overshoot。
static func _result_pop_ease(progress: float) -> float:
	var x := clampf(progress, 0.0, 1.0)
	var t := x
	for _i in range(6):
		var current_x := _result_bezier_coord(t, 0.34, 0.64)
		var slope := _result_bezier_slope(t, 0.34, 0.64)
		if absf(slope) < 0.00001:
			break
		t = clampf(t - (current_x - x) / slope, 0.0, 1.0)
	return _result_bezier_coord(t, 1.56, 1.0)


static func _result_bezier_coord(t: float, p1: float, p2: float) -> float:
	var u := 1.0 - t
	return 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t


static func _result_bezier_slope(t: float, p1: float, p2: float) -> float:
	var u := 1.0 - t
	return 3.0 * u * u * p1 + 6.0 * u * t * (p2 - p1) \
		+ 3.0 * t * t * (1.0 - p2)

# 役种单列逐条入场：首项等待 700ms，后续每项再等
# 700ms；普通役 260ms，8 番起重役 280ms。
func _build_yaku_rows(panel: Control, yaku_names: Array) -> VBoxContainer:
	var grid := VBoxContainer.new()
	grid.name = "YakuList"
	grid.position = Vector2(36, 160)
	grid.size = Vector2(548, 210)
	grid.add_theme_constant_override("separation", 0)
	panel.add_child(grid)
	var shown: Array = yaku_names
	for i in range(shown.size()):
		var item = shown[i]
		if not (item is Dictionary):
			continue
		var nm: String = String(item.get("name", ""))
		var mul: int = int(item.get("yakuman_multiplier", 0))
		var suffix: String = ""
		if mul > 0:
			suffix = "役満 ×%d" % mul if mul > 1 else "役満"
		else:
			suffix = "%d 飜" % int(item.get("han", 0))
		var row := _make_yaku_row_label(nm, suffix)
		var is_heavy := int(item.get("han", 0)) >= RESULT_HEAVY_HAN
		var reveal_duration := RESULT_YAKU_HEAVY_DURATION \
			if is_heavy else RESULT_YAKU_LIGHT_DURATION
		row.set_meta("reference_heavy", is_heavy)
		row.set_meta("reference_reveal_delay_ms",
			int(round((i + 1) * RESULT_PHASE_INTERVAL * 1000.0)))
		row.set_meta("reference_reveal_duration_ms",
			int(round(reveal_duration * 1000.0)))
		if is_heavy:
			var row_labels := row.get_children().filter(
				func(child: Node): return child is Label)
			if row_labels.size() >= 3:
				(row_labels[0] as Label).add_theme_color_override(
					"font_color", Color("d9b65b"))
				(row_labels[0] as Label).add_theme_font_size_override("font_size", 17)
				(row_labels[2] as Label).add_theme_font_size_override("font_size", 18)
		grid.add_child(row)
		# VBox 接管子节点 position；复刻 yakuRevealIn 的 opacity + scale。
		row.modulate = Color(1, 1, 1, 0)
		row.scale = Vector2(0.96, 0.96)
		var tw := create_tween()
		tw.tween_interval((i + 1) * RESULT_PHASE_INTERVAL)
		tw.tween_property(row, "modulate:a", 1.0, reveal_duration) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(row, "scale", Vector2.ONE, reveal_duration) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var captured := row
		var fin := func():
			if is_instance_valid(captured):
				captured.modulate = Color.WHITE
				captured.scale = Vector2.ONE
		_result_anim_tweens.append({"tween": tw, "finish": fin})
	return grid


static func _make_yaku_row_label(nm: String, suffix: String) -> Control:
	var box := HBoxContainer.new()
	box.custom_minimum_size = Vector2(548, 26)
	box.add_theme_constant_override("separation", 8)
	var name_label := Label.new()
	name_label.text = nm
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color("f4ead2"))
	box.add_child(name_label)
	var dots := Label.new()
	dots.text = "· · · · · · · · · · · · · · · · · · · ·"
	dots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dots.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	dots.add_theme_font_size_override("font_size", 16)
	dots.add_theme_color_override("font_color", Color("d9b65b47"))
	box.add_child(dots)
	var fan := Label.new()
	fan.text = suffix
	fan.add_theme_font_size_override("font_size", 16)
	fan.add_theme_color_override("font_color", Color("d9b65b"))
	box.add_child(fan)
	return box


# bonus（庄家/宝牌/报听/自摸）共用一次 phase；这里接收已适配的
# bonus 行，所有行在同一 260ms tween 内同时揭示。
static func _result_bonus_rows(result: Dictionary, yaku_names: Array) -> Array:
	var named_han := 0
	for item in yaku_names:
		if item is Dictionary and int(item.get("yakuman_multiplier", 0)) == 0:
			named_han += int(item.get("han", 0))
	var rows: Array = []
	var dora_count := maxi(int(result.get("dora_count", 0)), 0)
	var ability_extra := maxi(int(result.get("ability_extra_dora_count", 0)), 0)
	var ability_extra_red := clampi(
		int(result.get("ability_extra_red_dora_count", 0)), 0, dora_count)
	var other_dora := dora_count - ability_extra_red
	if other_dora > 0:
		var dora_name := "宝牌"
		if ability_extra > 0:
			dora_name = "宝牌（含能力额外 +%d）" % ability_extra
		rows.append({"name": dora_name, "han": other_dora})
	if ability_extra_red > 0:
		rows.append({
			"name": "赤宝牌（能力额外 +%d）" % ability_extra_red,
			"han": ability_extra_red,
		})
	var other_bonus := maxi(
		int(result.get("han", 0)) - named_han - dora_count, 0)
	var ability_han_count := clampi(
		int(result.get("ability_extra_han_count", 0)), 0, other_bonus)
	var remaining_ability_han := ability_han_count
	var ability_sources: Variant = result.get("ability_extra_han_sources", [])
	if ability_sources is Array:
		for source_value in ability_sources as Array:
			if not (source_value is Dictionary) or remaining_ability_han <= 0:
				continue
			var source := source_value as Dictionary
			var source_han := mini(
				maxi(int(source.get("han", 0)), 0), remaining_ability_han)
			if source_han <= 0:
				continue
			var source_name := String(source.get("ability_name", "")).strip_edges()
			rows.append({
				"name": "能力加番" if source_name.is_empty() \
					else "能力加番（%s）" % source_name,
				"han": source_han,
			})
			remaining_ability_han -= source_han
	if remaining_ability_han > 0:
		rows.append({"name": "能力加番", "han": remaining_ability_han})
	other_bonus -= ability_han_count
	if other_bonus > 0:
		rows.append({"name": "附加番", "han": other_bonus})
	return rows


func _build_result_bonus_rows(panel: Control, bonus_rows: Array,
		reveal_delay: float) -> VBoxContainer:
	var list := VBoxContainer.new()
	list.name = "BonusRows"
	list.position = Vector2(36, 365)
	list.size = Vector2(548, 60)
	list.add_theme_constant_override("separation", 0)
	panel.add_child(list)
	var rows: Array[Control] = []
	for item in bonus_rows:
		if not (item is Dictionary):
			continue
		var row := _make_yaku_row_label(String(item.get("name", "")),
			"+%d 飜" % int(item.get("han", 0)))
		row.modulate = Color(1, 1, 1, 0)
		row.scale = Vector2(0.96, 0.96)
		row.set_meta("reference_reveal_delay_ms",
			int(round(reveal_delay * 1000.0)))
		row.set_meta("reference_reveal_duration_ms",
			int(round(RESULT_YAKU_LIGHT_DURATION * 1000.0)))
		list.add_child(row)
		rows.append(row)
	if rows.is_empty():
		return list
	var update := func(progress: float) -> void:
		for row in rows:
			if is_instance_valid(row):
				row.modulate.a = clampf(progress, 0.0, 1.0)
				row.scale = Vector2.ONE * lerpf(0.96, 1.0, progress)
	var tw := create_tween()
	tw.tween_interval(reveal_delay)
	tw.tween_method(update, 0.0, 1.0, RESULT_YAKU_LIGHT_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var finish := func() -> void:
		for row in rows:
			if is_instance_valid(row):
				row.modulate = Color.WHITE
				row.scale = Vector2.ONE
	_result_anim_tweens.append({"tween": tw, "finish": finish})
	return list


# pP() 的 phase 计时直译：每个役 700ms，bonus（若有）只占一个 700ms
# phase，随后 total 再额外等待 1000ms。
func _result_total_reveal_delay(yaku_count: int, has_bonus: bool) -> float:
	var phase_count := maxi(yaku_count, 0) + (1 if has_bonus else 0)
	return phase_count * RESULT_PHASE_INTERVAL + RESULT_TOTAL_WAIT


# totalBarReveal：等待 phase 状态机完成后，用 420ms 入场。
func _build_result_total_bar(panel: Control, total_han: int, score: int,
		reveal_delay: float) -> Panel:
	var bar := Panel.new()
	bar.name = "ResultTotalBar"
	bar.position = Vector2(36, 394)
	bar.size = Vector2(548, 62)
	bar.pivot_offset = bar.size / 2.0
	bar.modulate.a = 0.0
	bar.scale = Vector2.ONE * 0.92
	bar.set_meta("reference_reveal_delay_ms",
		int(round(reveal_delay * 1000.0)))
	bar.set_meta("reference_reveal_duration_ms",
		int(round(RESULT_TOTAL_DURATION * 1000.0)))
	var style := StyleBoxFlat.new()
	style.bg_color = Color("d9b65b26")
	style.border_color = Color("d9b65b73")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	bar.add_theme_stylebox_override("panel", style)
	panel.add_child(bar)
	var total_label := Label.new()
	total_label.name = "TotalHan"
	total_label.position = Vector2(22, 10)
	total_label.size = Vector2(245, 42)
	total_label.text = "合计  %d 番" % total_han
	total_label.add_theme_font_size_override("font_size", 20)
	total_label.add_theme_color_override("font_color", Color("f4ead2"))
	bar.add_child(total_label)
	var score_label := Label.new()
	score_label.name = "TotalScore"
	score_label.position = Vector2(281, 10)
	score_label.size = Vector2(245, 42)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.text = "得分  %d" % score
	score_label.add_theme_font_size_override("font_size", 20)
	score_label.add_theme_color_override("font_color", Color("d9b65b"))
	bar.add_child(score_label)
	var update := func(progress: float) -> void:
		if is_instance_valid(bar):
			bar.modulate.a = clampf(progress, 0.0, 1.0)
			bar.scale = Vector2.ONE * lerpf(0.92, 1.0, progress)
	var tw := create_tween()
	tw.tween_interval(reveal_delay)
	tw.tween_method(update, 0.0, 1.0, RESULT_TOTAL_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var finish := func() -> void:
		if is_instance_valid(bar):
			bar.modulate = Color.WHITE
			bar.scale = Vector2.ONE
	_result_anim_tweens.append({"tween": tw, "finish": finish})
	return bar


# gP() 的四家滚分直译：final 为结算后点数，payment 为本局有符号增减，
# before = final - payment；顺序从庄家起，1500ms cubic-out 同步滚动。
func _build_score_delta_list(panel: Control, final_scores: Array,
		payments: Array, dealer_seat: int) -> VBoxContainer:
	var list := VBoxContainer.new()
	list.name = "ScoreDeltaList"
	list.position = Vector2(36, 106)
	list.size = Vector2(548, 260)
	list.add_theme_constant_override("separation", 6)
	list.set_meta("reference_roll_duration_ms",
		int(round(RESULT_SCORE_ROLL_DURATION * 1000.0)))
	panel.add_child(list)
	var row_states: Array = []
	for offset in range(4):
		var seat_id := (dealer_seat + offset) % 4
		var final_score := int(final_scores[seat_id])
		var payment := int(payments[seat_id])
		var before_score := final_score - payment
		var row := HBoxContainer.new()
		row.name = "ScoreDeltaSeat%d" % seat_id
		row.custom_minimum_size = Vector2(548, 48)
		row.set_meta("seat_id", seat_id)
		row.add_theme_constant_override("separation", 10)
		list.add_child(row)
		var seat_label := Label.new()
		seat_label.name = "SeatName"
		seat_label.custom_minimum_size = Vector2(96, 48)
		seat_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		seat_label.text = ("你" if seat_id == 0 else "AI %d" % seat_id) \
			+ ("  庄" if seat_id == dealer_seat else "")
		seat_label.add_theme_font_size_override("font_size", 16)
		seat_label.add_theme_color_override("font_color", Color("f4ead2"))
		row.add_child(seat_label)
		var before_label := Label.new()
		before_label.name = "Before"
		before_label.custom_minimum_size = Vector2(82, 48)
		before_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		before_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		before_label.text = str(before_score)
		before_label.add_theme_color_override("font_color", Color("f4ead299"))
		row.add_child(before_label)
		var arrow := Label.new()
		arrow.text = "→"
		arrow.custom_minimum_size = Vector2(24, 48)
		arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		arrow.add_theme_color_override("font_color", Color("d9b65b8c"))
		row.add_child(arrow)
		var after_label := Label.new()
		after_label.name = "After"
		after_label.custom_minimum_size = Vector2(92, 48)
		after_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		after_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		after_label.text = str(before_score)
		after_label.add_theme_color_override("font_color", Color("f4ead2"))
		row.add_child(after_label)
		var delta_label := Label.new()
		delta_label.name = "Delta"
		delta_label.custom_minimum_size = Vector2(92, 48)
		delta_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		delta_label.text = "0"
		delta_label.add_theme_color_override("font_color",
			Color("d9b65b") if payment > 0 else Color("ed6b6b"))
		row.add_child(delta_label)
		row_states.append({
			"after": after_label,
			"delta": delta_label,
			"before": before_score,
			"payment": payment,
		})
	var update := func(progress: float) -> void:
		for state in row_states:
			var after_label := state["after"] as Label
			var delta_label := state["delta"] as Label
			if not is_instance_valid(after_label) or not is_instance_valid(delta_label):
				continue
			var payment := int(state["payment"])
			var current_payment := int(round(payment * progress))
			after_label.text = str(int(state["before"]) + current_payment)
			delta_label.text = "+%d" % current_payment \
				if current_payment > 0 else str(current_payment)
	var tw := create_tween()
	tw.tween_method(update, 0.0, 1.0, RESULT_SCORE_ROLL_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var finish := func() -> void:
		update.call(1.0)
	_result_anim_tweens.append({"tween": tw, "finish": finish})
	return list

# 跳过结算动画到终态。有动画在播返 true(本次点击被消费),否则 false。
func _skip_result_animations() -> bool:
	var any_running := false
	for entry in _result_anim_tweens:
		var tw: Tween = entry.get("tween")
		if tw != null and tw.is_valid() and tw.is_running():
			any_running = true
			tw.kill()
		var fin: Callable = entry.get("finish")
		if fin != null and fin.is_valid():
			fin.call()
	_result_anim_tweens.clear()
	return any_running

# 在 overlay panel 内画胡牌：暗手升序 + 间隔 + winning tile（金调高亮）+
# Fl(flat:true) 副露；modal__win-hand 内 tile--sm 覆盖为 34×45。
# 自摸:seat.hand 14 张含 winning_tile → pop 到右侧;荣和:seat.hand 13 张,
# winning tile 来自他家,只需 append。
func _render_winning_hand_strip(parent: Control, winner_seat: int,
		winning_tile_id: int, is_tsumo: bool, y_offset: float) -> Control:
	if _bc == null or _bc.state == null:
		return null
	var winner: Seat = _bc.state.seats[winner_seat]
	if winner == null:
		return null
	# 保留 is_red_dora：用 Tile 列表而非 to_id_array
	var concealed: Array = []  # Array[Tile]
	for t in winner.hand.tiles():
		concealed.append(t)
	var win_red: bool = false
	if is_tsumo:
		for i in range(concealed.size() - 1, -1, -1):
			if concealed[i].id == winning_tile_id:
				win_red = concealed[i].is_red_dora
				concealed.remove_at(i)
				break
	else:
		# 荣和：winning tile 不在手牌；若事件 extra 带 red 以后可扩展
		win_red = false
	concealed.sort_custom(func(a, b): return a.id < b.id)
	# modal__win-hand：手牌组与 meld 组 16px；手牌组内部 2px。
	var strip := HBoxContainer.new()
	strip.name = "WinningHand"
	strip.position = Vector2(0, y_offset)
	strip.size = Vector2(620, 56)
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_theme_constant_override("separation", 16)
	parent.add_child(strip)
	var win_tiles := HBoxContainer.new()
	win_tiles.name = "WinningHandTiles"
	win_tiles.add_theme_constant_override("separation", 2)
	win_tiles.size_flags_vertical = Control.SIZE_SHRINK_END
	strip.add_child(win_tiles)
	for t in concealed:
		win_tiles.add_child(_make_overlay_tile(t.id, false, t.is_red_dora))
	# 暗手与 winning tile 之间留 10 px gap
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(10, RESULT_WIN_TILE_SM_SIZE.y)
	win_tiles.add_child(spacer)
	win_tiles.add_child(_make_overlay_tile(winning_tile_id, true, win_red))
	if not winner.melds.is_empty():
		strip.add_child(_build_flat_result_melds(
			winner.melds.all(), RESULT_WIN_TILE_SM_SIZE, "FlatMelds"))
	return strip


# modal__win-hand 单张 34×45；winning=true 给金色描边包装突出。
func _make_overlay_tile(tile_id: int, is_winning: bool, is_red_dora: bool = false) -> Control:
	return _make_result_tile(tile_id, is_winning, is_red_dora,
		RESULT_WIN_TILE_SM_SIZE)


# 通用结果牌节点；draw 传 30×40，modal__win-hand 传 34×45。
func _make_result_tile(tile_id: int, is_winning: bool, is_red_dora: bool,
		tile_size: Vector2) -> Control:
	var key: String = CardTileBack.tile_id_to_atlas_key(tile_id, is_red_dora)
	var tr := TextureRect.new()
	tr.custom_minimum_size = tile_size
	tr.size = tile_size
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
	wrap.custom_minimum_size = tile_size + Vector2(4, 4)
	wrap.size = tile_size + Vector2(4, 4)
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


# 仅在确认后的和牌状态挂载 win-announce；显式字段优先级固定。
static func _confirmed_win_announce_kind(extra: Dictionary) -> StringName:
	if bool(extra.get("is_tsumo", false)):
		return &"tsumo"
	if bool(extra.get("is_chankan", false)):
		return &"chankan"
	return &"ron"

var _last_event_count: int = 0
var _polling_active: bool = false
var _toast_label: Label = null
var _toast_tween: Tween = null
# T2:待标记的和牌张(rebind 后由 polling loop 应用,-1 = 无)
var _pending_win_tile_id: int = -1
var _dora_widget: DoraWidget = null
# 截图与调试可注入玩家角色外观；实验 3D 路径保持 no-op。
func set_player_persona(display_name: String, portrait_path: String) -> void:
	if not _table is FourPlayerTable or _table.seat_panels.is_empty():
		return
	var player := _table.seat_panels[0] as SeatPanel
	if player != null:
		player.set_ai_persona(display_name, "", portrait_path)


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
			var player_discarded := false
			for i in range(_last_event_count, n):
				var ev: BattleEvent = _bc.events[i]
				_handle_event_toast(ev)
				_play_event_sfx(ev)
				_handle_character_voice_event(ev)
				_handle_event_dramatic(ev)
				if ev != null and ev.type == &"TILE_DISCARDED" and int(ev.actor_seat) == 0:
					player_discarded = true
			_last_event_count = n
			_sync_character_status()
			if is_instance_valid(_table) and _bc.state != null:
				_table.bind_battle_state(_bc.state, 0, 4)
				# 玩家切牌后飞入河（rebind 后河末位已落地）。
				if player_discarded and not _pending_discard_fly.is_empty():
					_play_discard_fly_to_river()
				# T2:rebind 重建完手牌行后应用和牌张脉冲标记
				if _pending_win_tile_id >= 0 and _table.seat_panels.size() > 0:
					_table.seat_panels[0].mark_win_tile(_pending_win_tile_id)
					_pending_win_tile_id = -1
				# 宝牌/本场组合条同步（内部按 key 去重，无变化零开销）。
				_sync_dora_widget(_bc.state)
		if n < _last_event_count:
			_last_event_count = 0
		# E5-06：奖励 journal 可在无 BattleEvent 时前进（STT/grace/ITEM_*）
		_sync_reward_feedback_if_advanced()


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


# 事件演出：鸣牌/立直走局部 CallAnnounce；特殊役只在
# WIN_DECLARED 确认后从 yaku_names 挂 MomentBand。候选态不闪屏、不震桌。
func _handle_event_dramatic(ev: BattleEvent) -> void:
	if ev == null:
		return
	match ev.type:
		&"PLAYER_ACTION":
			# 鸣牌宣告演出(T1):吃/碰/杠书法大字从动作座位方向滑入。
			# AI 的 pon/minkan 走 _resolve_claims、玩家的走 PlayableBC,
			# 两边都 emit PLAYER_ACTION,此处统一接。
			var kind := StringName(String(ev.extra.get("kind", "")))
			if kind in [&"chi", &"pon", &"minkan", &"ankan", &"added_kan"]:
				_play_call_announce(kind, int(ev.actor_seat))
		&"RIICHI_DECLARED":
			_play_call_announce(&"riichi", int(ev.actor_seat))
			# AI 立直 → 该 seat 立绘转蓝调"决意"。actor_seat 越界 / seat 0 无立绘
			# 时 set_emote 是 no-op,不会崩。
			_set_seat_emote(int(ev.actor_seat), "riichi")
			_say_for_seat(int(ev.actor_seat), "riichi")
		&"TSUMO_DECLARED", &"RON_DECLARED":
			# 候选自摸/荣和仍可能被技能取消；确认前只保留和牌张提示。
			# T2:玩家自摸时和牌张心跳脉冲。必须在 rebind 之后标
			# (rebind 全量重建手牌行会清掉),挂 pending 由 polling loop 应用。
			if ev.type == &"TSUMO_DECLARED" and int(ev.actor_seat) == 0 \
					and ev.tile_anchor != null and ev.tile_anchor.tile != null:
				_pending_win_tile_id = ev.tile_anchor.tile.id
		&"WIN_DECLARED":
			var winner_seat := int(ev.actor_seat)
			_play_call_announce(
				_confirmed_win_announce_kind(ev.extra), winner_seat)
			_play_confirmed_moment_band(ev.extra.get("yaku_names", []))
			# 只有确认态才切人物与台词；候选态可能被技能取消。
			_set_seat_emote(winner_seat, "winning")
			_say_for_seat(winner_seat, "winning")
			for s in [0, 1, 2, 3]:
				if s != winner_seat:
					_set_seat_emote(s, "upset")
					_say_for_seat(s, "upset")
		&"GAME_BEGIN":
			# 新局开始 → 4 家 emote 重置 normal；清掉上局结算翻牌
			for s in [0, 1, 2, 3]:
				_set_seat_emote(s, "normal")
				if _table != null and s < _table.seat_panels.size() \
						and _table.seat_panels[s] != null:
					_table.seat_panels[s].clear_hand_reveal()


# 结算前把胜者手牌翻成正面（对手从牌背 → face-up 错峰入场）。
func _reveal_winner_hand(win_event: BattleEvent) -> void:
	if win_event == null or _table == null or _bc == null or _bc.state == null:
		return
	var seat_id: int = int(win_event.actor_seat)
	if seat_id < 0 or seat_id >= _table.seat_panels.size():
		return
	if seat_id >= _bc.state.seats.size():
		return
	var seat: Seat = _bc.state.seats[seat_id]
	var sp = _table.seat_panels[seat_id]
	if sp == null or seat == null or seat.hand == null:
		return
	if sp.has_method("reveal_hand_face_up"):
		sp.reveal_hand_face_up(seat.hand, true)


# T5:发牌演出期间隐藏四家真手牌行(演出结束恢复)。
func _set_hand_rows_visible(b: bool) -> void:
	if _table == null:
		return
	for sp in _table.seat_panels:
		if sp and sp.has_method("set_hand_row_visible"):
			sp.set_hand_row_visible(b)


# T1 宣告演出统一入口:大字 + 该座位立绘(有立绘时)。挂 self 让缩放跟桌面一致。
func _play_call_announce(kind: StringName, seat_id: int) -> void:
	var avatar: Texture2D = null
	if _table != null and seat_id >= 0 and seat_id < _table.seat_panels.size():
		var sp = _table.seat_panels[seat_id]
		if sp and sp.has_method("get_portrait_texture"):
			avatar = sp.get_portrait_texture()
	CallAnnounce.play(self, kind, seat_id, avatar)


static func _moment_from_yaku(yaku_names: Array) -> Dictionary:
	for item in yaku_names:
		if not item is Dictionary:
			continue
		var text: String = String(item.get("name", ""))
		if MOMENT_VARIANTS.has(text):
			return {"text": text, "variant": MOMENT_VARIANTS[text]}
	return {}


func _play_confirmed_moment_band(yaku_names: Array) -> void:
	var moment := _moment_from_yaku(yaku_names)
	if moment.is_empty():
		return
	var previous := get_node_or_null("MomentBand")
	if previous != null:
		remove_child(previous)
		previous.queue_free()

	var variant := StringName(moment["variant"])
	var band := Control.new()
	band.name = "MomentBand"
	band.position = Vector2(MOMENT_BAND_X, MOMENT_BAND_Y)
	band.size = Vector2(MOMENT_BAND_W, MOMENT_BAND_H)
	band.clip_contents = true
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.z_index = 200
	band.set_meta("variant", variant)
	add_child(band)

	var stripe := TextureRect.new()
	stripe.name = "Stripe"
	stripe.position = Vector2(-MOMENT_BAND_TRAVEL, 0)
	stripe.size = band.size
	stripe.texture = _moment_band_gradient(variant)
	stripe.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stripe.stretch_mode = TextureRect.STRETCH_SCALE
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(stripe)

	var top_line := ColorRect.new()
	top_line.name = "TopLine"
	top_line.color = Color("ffffff1f")
	top_line.size = Vector2(MOMENT_BAND_W, 1)
	top_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stripe.add_child(top_line)
	var bottom_line := ColorRect.new()
	bottom_line.name = "BottomLine"
	bottom_line.color = Color("0000004d")
	bottom_line.position = Vector2(0, MOMENT_BAND_H - 1)
	bottom_line.size = Vector2(MOMENT_BAND_W, 1)
	bottom_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stripe.add_child(bottom_line)

	var label := Label.new()
	label.name = "Text"
	label.text = String(moment["text"])
	label.size = stripe.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label_settings := LabelSettings.new()
	var system_font := SystemFont.new()
	system_font.font_names = PackedStringArray([
		"PingFang SC", "Microsoft YaHei", "Hiragino Sans GB",
		"Source Han Sans SC", "Noto Sans SC"])
	system_font.font_weight = 900
	label_settings.font = system_font
	label_settings.font_size = 26
	label_settings.font_color = Color("ffd34d")
	label_settings.outline_size = 2
	label_settings.outline_color = Color("6e370080")
	label_settings.shadow_color = Color("00000080")
	label_settings.shadow_size = 4
	label_settings.shadow_offset = Vector2(0, 2)
	label.label_settings = label_settings
	stripe.add_child(label)

	var tween := create_tween()
	tween.tween_property(stripe, "position", Vector2.ZERO,
		MOMENT_BAND_ENTER_TIME).set_custom_interpolator(
		func(progress: float) -> float:
			return CallAnnounce.sample_cubic_bezier(
				progress, 0.2, 0.9, 0.3, 1.0))
	tween.tween_interval(MOMENT_BAND_EXIT_DELAY - MOMENT_BAND_ENTER_TIME)
	tween.tween_property(stripe, "position",
		Vector2(MOMENT_BAND_TRAVEL, 0), MOMENT_BAND_EXIT_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(band.queue_free)


static func _moment_band_gradient(variant: StringName) -> GradientTexture2D:
	var edge := Color("141a16c7")
	var center := Color("141a16e6")
	match variant:
		&"haitei", &"houtei":
			edge = Color("162c3cdb")
			center = Color("143246eb")
		&"rinshan":
			edge = Color("461e12db")
			center = Color("5c2412eb")
		&"chankan":
			edge = Color("4e141edb")
			center = Color("621622eb")
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.16, 0.5, 0.84, 1.0])
	gradient.colors = PackedColorArray([
		Color.TRANSPARENT, edge, center, edge, Color.TRANSPARENT])
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
	gradient.interpolation_color_space = Gradient.GRADIENT_COLOR_SPACE_SRGB
	var texture := GradientTexture2D.new()
	texture.width = int(TableLayout.VIEW_W)
	texture.height = int(MOMENT_BAND_H)
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0, 0.44)
	texture.fill_to = Vector2(1, 0.56)
	texture.gradient = gradient
	return texture


func _set_seat_emote(seat_id: int, emote: String) -> void:
	if _table == null or seat_id < 0 or seat_id >= _table.seat_panels.size():
		return
	var sp = _table.seat_panels[seat_id]
	if sp and sp.has_method("set_emote"):
		sp.set_emote(emote)


func _say_for_seat(seat_id: int, event_kind: String) -> void:
	if _table == null or seat_id < 0 or seat_id >= _table.seat_panels.size():
		return
	var sp = _table.seat_panels[seat_id]
	if sp and sp.has_method("say_for_event"):
		sp.say_for_event(event_kind)


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


func _handle_character_voice_event(ev: BattleEvent) -> void:
	_play_character_voice_requests(
		_character_presentation_router.voice_requests_for_event(ev))


func _sync_character_status() -> void:
	if _character_status_badge == null or not is_instance_valid(_character_status_badge):
		return
	var status: Dictionary = {}
	if _bc != null and _bc.registry != null:
		status = _character_presentation_router.status_for_registry(
			_bc.registry, _reward_local_seat)
	_character_status_badge.call("set_status", status)


func _play_character_voice_requests(requests: Array) -> void:
	if requests.is_empty():
		return
	var am = get_node_or_null("/root/AudioManager")
	if am == null:
		return
	for request_value in requests:
		if not (request_value is Dictionary):
			continue
		var request := request_value as Dictionary
		am.play_character_voice(
			StringName(String(request.get("character_id", ""))),
			StringName(String(request.get("event_kind", ""))),
			int(request.get("priority", 0)))


# 关键事件 → 顶部金色 toast,玩家不用盯 events 也能感知发生了什么。
# 立直/自摸/荣和/流局/海底/河底 出现就闪 1.5 秒。
func _handle_event_toast(ev: BattleEvent) -> void:
	if ev == null:
		return
	var feedback: Dictionary = _character_presentation_router.feedback_for_event(ev)
	if not feedback.is_empty():
		if bool(feedback.get("suppress_toast", false)):
			return
		var feedback_color: Color = feedback.get("color", Color(1, 0.88, 0.32))
		_show_toast_text(
			String(feedback.get("text", "")),
			feedback_color,
			bool(feedback.get("pulse", false)),
			feedback.get("position", Vector2(420, 12)))
		return
	var text: String = _format_toast_text(ev)
	if text == "":
		return
	_show_toast_text(text)


# 任意文本 toast — 共用于 BC 事件 + 成就解锁等。
func _show_toast_text(
	text: String,
	font_color: Color = Color(1, 0.88, 0.32),
	pulse: bool = false,
	position: Vector2 = Vector2(420, 12)
) -> void:
	if text == "":
		return
	if _toast_label == null:
		_toast_label = Label.new()
		_toast_label.size = Vector2(440, 44)
		_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_toast_label.add_theme_font_size_override("font_size", 26)
		_toast_label.add_theme_constant_override("shadow_offset_x", 2)
		_toast_label.add_theme_constant_override("shadow_offset_y", 2)
		_toast_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_toast_label)
	_toast_label.position = position
	_toast_label.add_theme_color_override("font_color", font_color)
	_toast_label.text = text
	_toast_label.visible = true
	# 淡入 0.18s,显示 1.4s,再淡出 0.35s — 比硬切更有质感,新事件压旧时立刻覆盖。
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_label.modulate = Color(1, 1, 1, 0)
	_toast_label.pivot_offset = _toast_label.size * 0.5
	_toast_label.scale = Vector2(0.96, 0.96) if pulse else Vector2.ONE
	_toast_tween = get_tree().create_tween()
	_toast_tween.set_parallel(pulse)
	_toast_tween.tween_property(_toast_label, "modulate:a", 1.0, 0.18)
	if pulse:
		_toast_tween.tween_property(_toast_label, "scale", Vector2.ONE, 0.22)
		_toast_tween.set_parallel(false)
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
		# 立直/自摸/荣和 已由 CallAnnounce 大字演出承担(T1),不再走 toast
		# 双通道,避免同信息两处闪。
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
	_reward_sync_active = false
	_disconnect_public_command_signals()
	_disconnect_public_transcript()
	_public_reward_session = null
	release_voice_runtime()
	var am = get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("stop_character_voice"):
		am.stop_character_voice()


## E4-01：生产绑定入口。STANDARD 的 voice_port=null → 不创建按钮/采集/播放。
# E5-06 rework-3：奖励 journal 运行时同步（room/epoch + seq）；公共会话生命周期绑定。
var _reward_journal_cursor: int = 0
var _public_reward_session: PublicCasualNetworkSession = null
var _reward_source_epoch: String = ""
var _reward_local_seat: int = 0
var _reward_sync_active: bool = false
var _reward_bootstrapped: bool = false
var _last_reward_head_seq: int = -1
var _last_reward_view_sig: String = ""
var _reward_source_gen: int = 0
var _reward_apply_count: int = 0  # 可观察：视图 apply 次数（pending 不得空转加）
# #377：公共牌桌只读投影（仅 committed core_table；pending/resync 冻结）
# #378：公共 UI → PublicCasualNetworkSession.submit_action 命令闭环
var _public_table_committed_seq: int = -1
var _public_table_frozen: bool = false
var _public_decision_view: Dictionary = {}
var _public_network_command_attempts: int = 0
## #378：多 option「先选动作，再选 exact 权威候选」
var _public_pick_kind: String = ""
var _public_pick_selected: Array = []
var _public_input_locked: bool = false
const PublicTableAdapter := preload(
	"res://ui/four_player_table/public_table_projection_adapter.gd")


## E5-06：练习 TT 只读奖励绑定。ITEM_USE 走 PBC.submit_item_use → apply_action。
func _bind_reward_feedback_from_battle(bc: PlayableBattleController) -> void:
	if bc == null or _table == null:
		return
	if not (_table is FourPlayerTable):
		return
	_disconnect_public_transcript()
	_public_reward_session = null
	if not _table.has_signal("inventory_use_requested"):
		return
	if not _table.inventory_use_requested.is_connected(_on_inventory_use_requested):
		_table.inventory_use_requested.connect(_on_inventory_use_requested)
	_reward_local_seat = 0
	if _table.has_method("set_local_seat"):
		_table.set_local_seat(0)
	_sync_viewer_reveal_label()
	var room := "practice"
	if bc.has_meta("local_authority"):
		var auth = bc.get_meta("local_authority")
		if auth != null and auth.get("_room_id") != null:
			room = str(auth.get("_room_id"))
	_begin_reward_source("practice|%s|seat0" % room, 0, true)
	_ensure_reward_sync_loop()


## 公共场 seam：可在 session.start()/nbc 创建之前调用。
## 生命周期内自动跟进 committed journal；pending 不投影。
## #377：同步 core_table 只读投影；不启动 _bc / 本地权威。
## #378：接线 UI Action → session.submit_action；ACCEPTED 等 committed。
func bind_public_casual_session(session: PublicCasualNetworkSession) -> void:
	_disconnect_public_command_signals()
	_disconnect_public_transcript()
	_public_reward_session = session
	_public_table_committed_seq = -1
	_public_table_frozen = false
	_public_decision_view = {}
	_public_network_command_attempts = 0
	_public_pick_kind = ""
	_public_pick_selected.clear()
	_public_input_locked = false
	# 公共路径禁止练习场 _bc
	_bc = null
	if _table != null and _table.has_signal("inventory_use_requested"):
		if not _table.inventory_use_requested.is_connected(_on_inventory_use_requested):
			_table.inventory_use_requested.connect(_on_inventory_use_requested)
	var seat := 0
	var room := "public"
	if session != null:
		seat = int(session.seat) if session.seat >= 0 else 0
		room = str(session.room_id) if not str(session.room_id).is_empty() else "public"
		if not session.transcript_caption.is_connected(_on_public_transcript_caption):
			session.transcript_caption.connect(_on_public_transcript_caption)
		_connect_public_command_signals(session)
	_reward_local_seat = seat
	if _table != null and _table.has_method("set_local_seat"):
		_table.set_local_seat(seat)
	_ensure_public_decision_adapter()
	_wire_public_action_panel_choices()
	_sync_viewer_reveal_label()
	_begin_reward_source("public|%s|seat%d" % [room, seat], seat, true)
	_ensure_reward_sync_loop()
	# 若 nbc 已有 committed，立即投影
	sync_public_table_projection()


func _disconnect_public_transcript() -> void:
	if _public_reward_session == null:
		return
	if _public_reward_session.transcript_caption.is_connected(_on_public_transcript_caption):
		_public_reward_session.transcript_caption.disconnect(_on_public_transcript_caption)


func _on_public_transcript_caption(msg: Dictionary) -> void:
	# 仅展示；不触达 RewardWindow / 库存
	if _table == null or not _table.has_method("inject_caption_display"):
		return
	if msg.is_empty():
		return
	_table.inject_caption_display(msg.duplicate(true))


func _begin_reward_source(epoch: String, seat: int, bootstrap_skip_history: bool) -> void:
	# 每次显式 bind 新 authority/hand 递增 generation，同 room 新 hand seq 重用仍生效
	_reward_source_gen += 1
	_reward_source_epoch = "%s|gen%d" % [String(epoch), _reward_source_gen]
	_reward_local_seat = seat
	_character_presentation_router.set_local_seat(seat)
	_sync_character_status()
	_reward_bootstrapped = false
	_last_reward_head_seq = -1
	_last_reward_view_sig = ""
	_reward_journal_cursor = 0
	_reward_apply_count = 0
	if _table != null and _table.has_method("begin_reward_display_source"):
		_table.begin_reward_display_source(_reward_source_epoch, seat)
	if bootstrap_skip_history:
		# 首帧：视图恢复库存，cursor 推到当前 committed head，不重放历史到账/发动
		_bootstrap_reward_display()


func _bootstrap_reward_display() -> void:
	_apply_reward_views_only()
	var head: int = _peek_reward_journal_head_seq()
	_reward_journal_cursor = maxi(0, head)
	_last_reward_head_seq = head
	if _table != null and _table.has_method("mark_reward_feedback_up_to"):
		_table.mark_reward_feedback_up_to(_reward_source_epoch, head)
	_reward_bootstrapped = true


func _ensure_reward_sync_loop() -> void:
	if _reward_sync_active:
		return
	_reward_sync_active = true
	_reward_sync_loop()


func _reward_sync_loop() -> void:
	while _reward_sync_active:
		var tree := get_tree()
		if tree == null:
			_reward_sync_active = false
			return
		await tree.process_frame
		# #378：实例销毁后不得 resume 报错
		if not is_instance_valid(self) or not _reward_sync_active:
			return
		# 练习场主循环已调 _sync；公共-only 或 bind 早于 start 时由此兜底
		if _public_reward_session != null:
			_sync_reward_feedback_if_advanced()
		elif _bc == null:
			_reward_sync_active = false
			return


func _sync_reward_feedback_if_advanced() -> void:
	if _table == null:
		return
	if not _reward_bootstrapped:
		_bootstrap_reward_display()
		sync_public_table_projection()
		return
	var head: int = _peek_reward_journal_head_seq()
	var sig: String = _reward_view_signature()
	# #377：公共牌桌投影独立于奖励签名，按 committed seq / resync 冻结
	sync_public_table_projection()
	if head <= _reward_journal_cursor and sig == _last_reward_view_sig:
		return
	# 视图有变或 journal 前进：快照恢复 + 仅新 seq 反馈
	_apply_reward_views_only()
	if head > _reward_journal_cursor:
		_consume_reward_journal_events()
	_last_reward_head_seq = head
	_last_reward_view_sig = sig


## #377：仅消费 NBC committed core_table / journal decision；pending 与 resync 冻结画面。
func sync_public_table_projection() -> void:
	if _public_reward_session == null or _public_reward_session.nbc == null:
		return
	if _table == null or not (_table is FourPlayerTable):
		return
	var nbc: NetworkedBattleController = _public_reward_session.nbc
	if nbc.resync_required():
		_public_table_frozen = true
		return
	var core: Dictionary = nbc.get_core_table_view()
	if core.is_empty():
		return
	var committed_seq: int = int(nbc.current_seq())
	# pending 不推进 current_seq（异 hash 队列时 seq 仍停在 last commit）
	if _public_table_frozen and committed_seq <= _public_table_committed_seq:
		return
	if committed_seq == _public_table_committed_seq and not _public_table_frozen:
		_apply_public_decision_from_journal(nbc)
		return
	if committed_seq < _public_table_committed_seq:
		return
	_public_table_frozen = false
	_public_table_committed_seq = committed_seq
	if _table.has_method("bind_core_table_view"):
		_table.bind_core_table_view(core)
	else:
		PublicTableAdapter.apply_core_table(_table as FourPlayerTable, core)
	var meta: Dictionary = nbc.get_matching_meta_view()
	if not meta.is_empty():
		var recip: int = int(core.get("recipient_seat", _reward_local_seat))
		PublicTableAdapter.apply_matching_meta(_table as FourPlayerTable, meta, recip)
		_bind_public_matching_meta_characters()
	_apply_public_decision_from_journal(nbc)
	# 本席手牌点击走 entity id；公共不发网络命令
	_wire_public_bottom_hand_clicks()


func get_public_decision_view() -> Dictionary:
	return _public_decision_view.duplicate(true)


func public_network_command_attempts() -> int:
	return _public_network_command_attempts


## #378：由 UI choice 或测试构建权威 exact Action（不提交）。
func build_public_action_from_choice(choice: Dictionary) -> Action:
	return _build_public_action_from_choice(choice)


func _on_public_player_action_chosen(choice: Dictionary) -> void:
	# #378：公共入口仅以 session 绑定门控；bind_public 时 _bc=null，练习时 session=null
	if _public_reward_session == null:
		return
	if _public_command_ui_busy():
		return
	var action_name := String(choice.get("action", ""))
	# multi-option 实体点选
	if action_name == "claim_tile_pick" or action_name == "discard":
		if not _public_pick_kind.is_empty() and action_name == "claim_tile_pick":
			_on_public_pick_tile(int(choice.get("tile_instance_id", -1)))
			return
		if action_name == "discard":
			# 若处于 RIICHI 选牌，优先 RIICHI option
			if _public_pick_kind == "RIICHI":
				_on_public_pick_tile(int(choice.get("tile_instance_id", -1)))
				return
			var disc_act := _build_public_action_from_choice(choice)
			if disc_act != null:
				_dispatch_public_action(disc_act)
			return
	# 取消多选
	if action_name in ["skip", "pass", "riichi_no", "kyuusyu_no"] and not _public_pick_kind.is_empty():
		if action_name in ["skip", "pass"] and _public_decision_view.get("allowed_actions", []) is Array:
			# CLAIM 的 skip 是 PASS，不是取消选牌
			if _public_has_kind("PASS"):
				_public_pick_kind = ""
				_public_pick_selected.clear()
				var pass_act := _build_public_action_for_kind("PASS", {})
				if pass_act != null:
					_dispatch_public_action(pass_act)
				return
		_cancel_public_pick()
		return
	# 先选动作
	match action_name:
		"chi":
			_begin_or_submit_multi("CHI", 2)
		"pon":
			_begin_or_submit_multi("PON", 2)
		"minkan":
			_begin_or_submit_kan("MINKAN")
		"ankan":
			_begin_or_submit_kan("ANKAN")
		"added_kan":
			_begin_or_submit_kan("ADDED_KAN")
		"riichi", "riichi_yes":
			_begin_or_submit_riichi()
		"tsumo":
			var t := _build_public_action_for_kind("TSUMO", {})
			if t != null:
				_dispatch_public_action(t)
		"ron":
			var r := _build_public_action_for_kind("RON", {})
			if r != null:
				_dispatch_public_action(r)
		"skip", "pass":
			var p := _build_public_action_for_kind("PASS", {})
			if p != null:
				_dispatch_public_action(p)
		"kyuusyu_yes", "kyuusyu":
			var k := _build_public_action_for_kind(
				"DECLARE_ABORTIVE_DRAW", {"reason": "KYUUSYU_KYUUHAI"})
			if k != null:
				_dispatch_public_action(k)
		_:
			pass


func _begin_or_submit_multi(kind: String, companion_count: int) -> void:
	var opts := _public_options_of(kind)
	if opts.is_empty():
		return
	if opts.size() == 1:
		var act := _build_public_action_for_kind(kind, opts[0] as Dictionary)
		if act != null:
			_dispatch_public_action(act)
		return
	# 多 option：进入实体选择
	_public_pick_kind = kind
	_public_pick_selected.clear()
	var union_ids: Array = []
	for op in opts:
		if typeof(op) != TYPE_DICTIONARY:
			continue
		for cid in (op as Dictionary).get("companion_tile_instance_ids", []):
			var i := int(cid)
			if not union_ids.has(i):
				union_ids.append(i)
	if _action_panel != null:
		_action_panel.enter_waiting_claim_pick()
		_action_panel.set_status_text("%s — 点选权威候选实体（%d 张）" % [kind, companion_count])
	if _seat_panel_player != null:
		if _seat_panel_player.has_method("set_hand_clickable"):
			_seat_panel_player.set_hand_clickable(true)
		if _seat_panel_player.has_method("dim_hand_except"):
			_seat_panel_player.dim_hand_except(union_ids)


func _begin_or_submit_kan(kan_kind: String) -> void:
	var opts := _public_options_of("KAN")
	var matched: Array = []
	for op in opts:
		if typeof(op) != TYPE_DICTIONARY:
			continue
		if str((op as Dictionary).get("kan_kind", "")) == kan_kind:
			matched.append(op)
	if matched.is_empty():
		return
	if matched.size() == 1:
		var act := _build_public_action_for_kind("KAN", matched[0] as Dictionary)
		if act != null:
			_dispatch_public_action(act)
		return
	# 多 KAN 子型候选：先用第一套可点实体并集（MINKAN companions / ANKAN tiles）
	_public_pick_kind = "KAN:" + kan_kind
	_public_pick_selected.clear()
	var union_ids: Array = []
	for op2 in matched:
		var d: Dictionary = op2 as Dictionary
		var key := "companion_tile_instance_ids"
		if kan_kind == "ANKAN":
			key = "tile_instance_ids"
		elif kan_kind == "ADDED_KAN":
			if d.has("added_tile_instance_id"):
				var aid := int(d["added_tile_instance_id"])
				if not union_ids.has(aid):
					union_ids.append(aid)
			continue
		for cid2 in d.get(key, []):
			var ii := int(cid2)
			if not union_ids.has(ii):
				union_ids.append(ii)
	if _action_panel != null:
		_action_panel.enter_waiting_claim_pick()
		_action_panel.set_status_text("KAN/%s — 点选权威候选" % kan_kind)
	if _seat_panel_player != null:
		if _seat_panel_player.has_method("set_hand_clickable"):
			_seat_panel_player.set_hand_clickable(true)
		if _seat_panel_player.has_method("dim_hand_except") and not union_ids.is_empty():
			_seat_panel_player.dim_hand_except(union_ids)


func _begin_or_submit_riichi() -> void:
	var opts := _public_options_of("RIICHI")
	if opts.is_empty():
		return
	if opts.size() == 1:
		var act := _build_public_action_for_kind("RIICHI", opts[0] as Dictionary)
		if act != null:
			_dispatch_public_action(act)
		return
	_public_pick_kind = "RIICHI"
	_public_pick_selected.clear()
	var ids: Array = []
	for op in opts:
		if typeof(op) == TYPE_DICTIONARY and (op as Dictionary).has("tile_instance_id"):
			ids.append(int((op as Dictionary)["tile_instance_id"]))
	if _action_panel != null:
		_action_panel.set_status_text("立直 — 点选权威切牌实体")
	if _seat_panel_player != null:
		if _seat_panel_player.has_method("set_hand_clickable"):
			_seat_panel_player.set_hand_clickable(true)
		if _seat_panel_player.has_method("dim_hand_except"):
			_seat_panel_player.dim_hand_except(ids)


func _on_public_pick_tile(tile_instance_id: int) -> void:
	if tile_instance_id < 0 or _public_pick_kind.is_empty():
		return
	if _public_pick_kind == "RIICHI":
		var act_r := _build_public_action_for_kind(
			"RIICHI", {"tile_instance_id": tile_instance_id})
		if act_r != null:
			_public_pick_kind = ""
			_public_pick_selected.clear()
			_dispatch_public_action(act_r)
		return
	if _public_pick_kind.begins_with("KAN:"):
		var kk := _public_pick_kind.substr(4)
		if kk == "ADDED_KAN":
			var act_ak := _match_kan_option(kk, {"added_tile_instance_id": tile_instance_id})
			if act_ak != null:
				_public_pick_kind = ""
				_public_pick_selected.clear()
				_dispatch_public_action(act_ak)
			return
		if not _public_pick_selected.has(tile_instance_id):
			_public_pick_selected.append(tile_instance_id)
		var need := 3 if kk == "MINKAN" else 4
		if _public_pick_selected.size() >= need:
			var payload_k := {
				"kan_kind": kk,
			}
			if kk == "MINKAN":
				payload_k["companion_tile_instance_ids"] = _public_pick_selected.duplicate()
			else:
				payload_k["tile_instance_ids"] = _public_pick_selected.duplicate()
			var act_k := _build_public_action_for_kind("KAN", payload_k)
			if act_k != null:
				_public_pick_kind = ""
				_public_pick_selected.clear()
				_dispatch_public_action(act_k)
			else:
				_public_pick_selected.clear()
				if _action_panel != null:
					_action_panel.set_status_text("KAN 候选不匹配，请重选")
		return
	# CHI / PON
	if not _public_pick_selected.has(tile_instance_id):
		_public_pick_selected.append(tile_instance_id)
	if _public_pick_selected.size() >= 2:
		var payload := {"companion_tile_instance_ids": _public_pick_selected.duplicate()}
		var act := _build_public_action_for_kind(_public_pick_kind, payload)
		if act != null:
			_public_pick_kind = ""
			_public_pick_selected.clear()
			_dispatch_public_action(act)
		else:
			_public_pick_selected.clear()
			if _action_panel != null:
				_action_panel.set_status_text("%s 候选不匹配，请重选" % _public_pick_kind)


func _match_kan_option(kan_kind: String, partial: Dictionary) -> Action:
	for op in _public_options_of("KAN"):
		if typeof(op) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = op as Dictionary
		if str(d.get("kan_kind", "")) != kan_kind:
			continue
		if kan_kind == "ADDED_KAN":
			if int(d.get("added_tile_instance_id", -2)) == int(partial.get("added_tile_instance_id", -1)):
				return _build_public_action_for_kind("KAN", d)
	return null


func _cancel_public_pick() -> void:
	_public_pick_kind = ""
	_public_pick_selected.clear()
	if _public_reward_session != null and _public_reward_session.nbc != null:
		_apply_public_decision_from_journal(_public_reward_session.nbc)


func _submit_public_item_use(item_instance_id: String) -> void:
	var decision := _public_current_decision_meta()
	if decision.is_empty():
		return
	var sess := _public_reward_session
	if sess == null or sess.nbc == null:
		return
	# #378 P1：必须精确匹配本席权威库存 instance，不得按 item_id 合并
	if not _public_inventory_has_usable_instance(item_instance_id):
		return
	var cmd := sess.allocate_command_id()
	var cseq := sess.allocate_client_seq()
	if cseq < 0:
		return
	var act := Action.item_use(
		sess.seat, item_instance_id, sess.room_id, cmd,
		str(decision.get("decision_id", "")), int(decision.get("hand_seq", 0)), cseq
	)
	if act != null:
		_dispatch_public_action(act)


func _public_inventory_has_usable_instance(item_instance_id: String) -> bool:
	var iid := String(item_instance_id).strip_edges()
	if iid.is_empty() or _public_reward_session == null or _public_reward_session.nbc == null:
		return false
	var view: Dictionary = _public_reward_session.nbc.get_item_inventory_view()
	var items: Array = view.get("items", []) as Array
	for raw in items:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		if String(row.get("item_instance_id", "")).strip_edges() != iid:
			continue
		# 仅本席可见 held 可 USE 实例；不按 item_id 合并其它 instance
		return bool(ItemInventoryDrawerScr.can_request_use(row))
	return false


func _dispatch_public_action(action: Action) -> void:
	if action == null or _public_reward_session == null:
		return
	if _public_command_ui_busy():
		return
	var err: Error = _public_reward_session.submit_action(action)
	if err != OK:
		return
	_public_network_command_attempts += 1
	_lock_public_inputs("命令已发送，等待权威…")


## #378：session 权威命令状态（pending CR / retry / awaiting committed），不含本地 UI 锁。
## 与 `_public_input_locked` 分离，避免 clear decision 时因本地锁自指永久 busy。
func _public_session_command_busy() -> bool:
	if _public_reward_session == null:
		return false
	if _public_reward_session.is_command_pending():
		return true
	if _public_reward_session.is_awaiting_pending_retry():
		return true
	if _public_reward_session.has_method("is_awaiting_authority_commit") \
			and _public_reward_session.is_awaiting_authority_commit():
		return true
	return false


## #378 R4/R5：本地锁或 session 权威忙则拒绝 UI 提交。
func _public_command_ui_busy() -> bool:
	if _public_input_locked:
		return true
	return _public_session_command_busy()


func _lock_public_inputs(status: String) -> void:
	_public_input_locked = true
	if _action_panel != null:
		_action_panel.enter_idle(status if not status.is_empty() else "命令处理中…")
	if _seat_panel_player != null:
		if _seat_panel_player.has_method("set_hand_clickable"):
			_seat_panel_player.set_hand_clickable(false)
		if _seat_panel_player.has_method("clear_hand_dim"):
			_seat_panel_player.clear_hand_dim()
	if _table != null and _table.has_method("set_inventory_use_locked"):
		_table.set_inventory_use_locked(true)


func _unlock_public_inputs_restore_decision() -> void:
	_public_input_locked = false
	_public_pick_kind = ""
	_public_pick_selected.clear()
	if _table != null and _table.has_method("set_inventory_use_locked"):
		_table.set_inventory_use_locked(false)
	if _public_reward_session != null and _public_reward_session.nbc != null:
		_apply_public_decision_from_journal(_public_reward_session.nbc)


func _on_public_command_accepted(_result: CommandResult) -> void:
	# ACCEPTED 不乐观改牌；保持锁定直至 committed 推进带来新 decision/快照
	_lock_public_inputs("已受理，等待权威事件…")


func _on_public_command_rejected(_code: String, _command_id: String, _message: String) -> void:
	# ERROR 恢复当前权威 decision 与库存可用
	_unlock_public_inputs_restore_decision()


func _on_public_command_pending_dropped(_reason: String) -> void:
	_unlock_public_inputs_restore_decision()


func _public_has_kind(kind: String) -> bool:
	return not _public_options_of(kind).is_empty() or _public_kind_present(kind)


func _public_kind_present(kind: String) -> bool:
	for a in _public_decision_view.get("allowed_actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("kind", "")) == kind:
			return true
	return false


func _public_options_of(kind: String) -> Array:
	var out: Array = []
	for a in _public_decision_view.get("allowed_actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("kind", "")) != kind:
			continue
		for op in a.get("payload_options", []):
			if typeof(op) == TYPE_DICTIONARY:
				out.append((op as Dictionary).duplicate(true))
	return out


func _public_current_decision_meta() -> Dictionary:
	if _public_decision_view.is_empty():
		return {}
	var decision_id := str(_public_decision_view.get("decision_id", ""))
	if decision_id.is_empty() or not ProtocolUuid.is_canonical_v4(decision_id):
		return {}
	return {
		"decision_id": decision_id,
		"hand_seq": int(_public_decision_view.get("hand_seq", 0)),
	}


func _build_public_action_from_choice(choice: Dictionary) -> Action:
	var action_name := String(choice.get("action", ""))
	match action_name:
		"discard":
			var iid := int(choice.get("tile_instance_id", -1))
			if iid < 0:
				return null
			return _build_public_action_for_kind("DISCARD", {"tile_instance_id": iid})
		"tsumo":
			return _build_public_action_for_kind("TSUMO", {})
		"ron":
			return _build_public_action_for_kind("RON", {})
		"skip", "pass":
			return _build_public_action_for_kind("PASS", {})
		"riichi", "riichi_yes":
			if choice.has("tile_instance_id"):
				return _build_public_action_for_kind(
					"RIICHI", {"tile_instance_id": int(choice["tile_instance_id"])})
			var ropts := _public_options_of("RIICHI")
			if ropts.size() == 1:
				return _build_public_action_for_kind("RIICHI", ropts[0] as Dictionary)
			return null
		"chi":
			var copts := _public_options_of("CHI")
			if copts.size() == 1:
				return _build_public_action_for_kind("CHI", copts[0] as Dictionary)
			return null
		"pon":
			var popts := _public_options_of("PON")
			if popts.size() == 1:
				return _build_public_action_for_kind("PON", popts[0] as Dictionary)
			return null
		"kyuusyu_yes", "kyuusyu":
			return _build_public_action_for_kind(
				"DECLARE_ABORTIVE_DRAW", {"reason": "KYUUSYU_KYUUHAI"})
		_:
			return null


func _build_public_action_for_kind(kind: String, payload: Dictionary) -> Action:
	var sess := _public_reward_session
	if sess == null:
		return null
	var meta := _public_current_decision_meta()
	if meta.is_empty():
		return null
	# 必须命中权威 option 的完整 payload（两侧均 normalize 后 deep equal）
	var normalized: Variant = Action.normalize_payload(kind, payload)
	if normalized == null:
		return null
	var matched := false
	for op in _public_options_of(kind):
		if typeof(op) != TYPE_DICTIONARY:
			continue
		var op_norm: Variant = Action.normalize_payload(kind, op as Dictionary)
		if op_norm == null:
			continue
		if _public_payload_equal(normalized, op_norm):
			matched = true
			# 使用规范化权威 option，避免客户端重算 / 顺序差异
			normalized = (op_norm as Dictionary).duplicate(true)
			break
	if not matched:
		return null
	var cmd := sess.allocate_command_id()
	var cseq := sess.allocate_client_seq()
	if cseq < 0 or not ProtocolUuid.is_canonical_v4(cmd):
		return null
	return Action.from_dict({
		"protocol_version": ProtocolConstants.PROTOCOL_VERSION,
		"command_id": cmd,
		"room_id": sess.room_id,
		"seat": sess.seat,
		"hand_seq": int(meta["hand_seq"]),
		"decision_id": str(meta["decision_id"]),
		"kind": kind,
		"payload": normalized,
		"client_seq": cseq,
	})


func _public_payload_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if typeof(a) == TYPE_DICTIONARY:
		var da: Dictionary = a
		var db: Dictionary = b
		if da.size() != db.size():
			return false
		for k in da.keys():
			if not db.has(k):
				return false
			if not _public_payload_equal(da[k], db[k]):
				return false
		return true
	if typeof(a) == TYPE_ARRAY:
		var aa: Array = a
		var ab: Array = b
		if aa.size() != ab.size():
			return false
		for i in range(aa.size()):
			if not _public_payload_equal(aa[i], ab[i]):
				return false
		return true
	return a == b


func _ensure_public_decision_adapter() -> void:
	if _action_panel == null:
		return
	if _seat_panel_player == null and _table is FourPlayerTable \
			and (_table as FourPlayerTable).seat_panels.size() > 0:
		_seat_panel_player = (_table as FourPlayerTable).seat_panels[0]
	if _decision_adapter == null and _seat_panel_player != null:
		_decision_adapter = TableDecisionAdapter.new(_action_panel, _seat_panel_player)
	_wire_public_action_panel_choices()


func _wire_public_bottom_hand_clicks() -> void:
	if not (_table is FourPlayerTable):
		return
	var bottom = (_table as FourPlayerTable).seat_panels[0] if \
		(_table as FourPlayerTable).seat_panels.size() > 0 else null
	if bottom == null:
		return
	_seat_panel_player = bottom
	if bottom.has_signal("player_card_clicked") \
			and not bottom.player_card_clicked.is_connected(_on_player_tile_clicked):
		bottom.player_card_clicked.connect(_on_player_tile_clicked)


func _wire_public_action_panel_choices() -> void:
	if _action_panel == null:
		return
	if not _action_panel.player_action_chosen.is_connected(_on_public_player_action_chosen):
		_action_panel.player_action_chosen.connect(_on_public_player_action_chosen)


func _connect_public_command_signals(session: PublicCasualNetworkSession) -> void:
	if session == null:
		return
	if session.has_signal("command_accepted") \
			and not session.command_accepted.is_connected(_on_public_command_accepted):
		session.command_accepted.connect(_on_public_command_accepted)
	if session.has_signal("command_rejected") \
			and not session.command_rejected.is_connected(_on_public_command_rejected):
		session.command_rejected.connect(_on_public_command_rejected)
	if session.has_signal("command_pending_dropped") \
			and not session.command_pending_dropped.is_connected(_on_public_command_pending_dropped):
		session.command_pending_dropped.connect(_on_public_command_pending_dropped)
	if session.has_signal("reconnecting") \
			and not session.reconnecting.is_connected(_on_public_session_reconnecting):
		session.reconnecting.connect(_on_public_session_reconnecting)
	if session.has_signal("recovered") \
			and not session.recovered.is_connected(_on_public_session_recovered):
		session.recovered.connect(_on_public_session_recovered)


func _disconnect_public_command_signals() -> void:
	if _public_reward_session == null:
		return
	var session := _public_reward_session
	if session.has_signal("command_accepted") \
			and session.command_accepted.is_connected(_on_public_command_accepted):
		session.command_accepted.disconnect(_on_public_command_accepted)
	if session.has_signal("command_rejected") \
			and session.command_rejected.is_connected(_on_public_command_rejected):
		session.command_rejected.disconnect(_on_public_command_rejected)
	if session.has_signal("command_pending_dropped") \
			and session.command_pending_dropped.is_connected(_on_public_command_pending_dropped):
		session.command_pending_dropped.disconnect(_on_public_command_pending_dropped)
	if session.has_signal("reconnecting") \
			and session.reconnecting.is_connected(_on_public_session_reconnecting):
		session.reconnecting.disconnect(_on_public_session_reconnecting)
	if session.has_signal("recovered") \
			and session.recovered.is_connected(_on_public_session_recovered):
		session.recovered.disconnect(_on_public_session_recovered)
	if _action_panel != null \
			and _action_panel.player_action_chosen.is_connected(_on_public_player_action_chosen):
		_action_panel.player_action_chosen.disconnect(_on_public_player_action_chosen)


func _on_public_session_reconnecting(_code: String, _message: String) -> void:
	# 重连窗口：清除旧 UI decision，禁止新连接提交前的操作
	_public_decision_view = {}
	_public_pick_kind = ""
	_public_pick_selected.clear()
	_lock_public_inputs("重连中…")


func _on_public_session_recovered() -> void:
	# 恢复 snapshot 后若仍有 pending 等待 prompt 匹配，保持锁定
	if _public_reward_session != null and (
		_public_reward_session.is_command_pending() \
		or _public_reward_session.is_awaiting_pending_retry() \
		or (
			_public_reward_session.has_method("is_awaiting_authority_commit")
			and _public_reward_session.is_awaiting_authority_commit()
		)
	):
		_lock_public_inputs("重连恢复中，等待权威决策…")
		return
	_unlock_public_inputs_restore_decision()


func _apply_public_decision_from_journal(nbc: NetworkedBattleController) -> void:
	# 保留 multi-pick：每帧 reward sync 会重入本函数，不得清空同 decision 的选牌。
	var prev_decision_id := str(_public_decision_view.get("decision_id", ""))
	var was_picking := not _public_pick_kind.is_empty()
	_public_decision_view = {}
	if nbc == null:
		_public_pick_kind = ""
		_public_pick_selected.clear()
		return
	var recip: int = int(nbc.recipient_seat)
	# #377 P1-2：从 journal 顺序折叠；较新 ROOM_SNAPSHOT 关闭先前 TURN/CLAIM 窗口
	var last: NetworkedEvent = null
	var core_phase := str(nbc.get_core_table_view().get("phase", ""))
	for item in nbc.get_event_journal():
		if not (item is NetworkedEvent):
			continue
		var ne: NetworkedEvent = item as NetworkedEvent
		if ne.kind == "ROOM_SNAPSHOT":
			last = null
			continue
		if ne.kind == "TURN_PROMPT":
			if int(ne.payload.get("seat", -1)) == recip:
				last = ne
			continue
		if ne.kind == "CLAIM_WINDOW":
			# CLAIM 按 recipient journal 私有下发，无 seat 字段
			last = ne
	if last == null:
		_public_pick_kind = ""
		_public_pick_selected.clear()
		_clear_public_decision_ui(core_phase)
		return
	var new_decision_id := str(last.payload.get("decision_id", ""))
	_public_decision_view = last.payload.duplicate(true)
	# 同 decision 且正在 multi-pick：只刷新权威数据，不打断候选点选
	if was_picking and not prev_decision_id.is_empty() and new_decision_id == prev_decision_id:
		return
	if new_decision_id != prev_decision_id:
		_public_pick_kind = ""
		_public_pick_selected.clear()
	_present_public_allowed_actions(last)


func _clear_public_decision_ui(phase: String = "") -> void:
	_ensure_public_decision_adapter()
	_public_pick_kind = ""
	_public_pick_selected.clear()
	# #378 R5：仅以 session 权威状态判断是否仍忙；本地锁不得参与自指。
	# session 已结束（无 pending/retry/awaiting）时清本地锁与库存 Use，即使无新 prompt。
	# ACCEPTED→committed 窗口内 session 仍 busy，保持锁定不可点。
	if not _public_session_command_busy():
		_public_input_locked = false
		if _table != null and _table.has_method("set_inventory_use_locked"):
			_table.set_inventory_use_locked(false)
	var idle_text := "阶段 %s" % phase if not phase.is_empty() else "等待权威…"
	if _public_input_locked:
		idle_text = "命令处理中…"
	if _decision_adapter != null:
		_decision_adapter.present(&"idle", {"text": idle_text})
	elif _action_panel != null:
		_action_panel.enter_idle(idle_text)
	if _seat_panel_player != null:
		if _seat_panel_player.has_method("set_hand_clickable"):
			_seat_panel_player.set_hand_clickable(false)
		if _seat_panel_player.has_method("clear_hand_dim"):
			_seat_panel_player.clear_hand_dim()


func _present_public_allowed_actions(ne: NetworkedEvent) -> void:
	# #377：按协议 TURN_OFFER_KINDS / CLAIM_OFFER_KINDS 展示；
	# #378：可提交 exact Action。KAN 子型在 payload_options[].kan_kind。
	_ensure_public_decision_adapter()
	if _action_panel == null or ne == null:
		return
	# 命令仍 pending / ACCEPTED 等待 committed 时不重开输入（仅看 session，不含本地锁）
	if _public_session_command_busy():
		_lock_public_inputs("命令处理中…")
		return
	_public_input_locked = false
	if _table != null and _table.has_method("set_inventory_use_locked"):
		_table.set_inventory_use_locked(false)
	# multi-pick 清理由 _apply_public_decision_from_journal（decision 变化时）负责
	var payload: Dictionary = ne.payload
	var allowed: Array = payload.get("allowed_actions", []) as Array
	if ne.kind == "TURN_PROMPT":
		var can_tsumo := false
		var can_ankan := false
		var can_added := false
		var can_riichi := false
		var can_kyuusyu := false
		var discard_iids: Array = []
		for a in allowed:
			if typeof(a) != TYPE_DICTIONARY:
				continue
			var kind := str(a.get("kind", ""))
			var opts: Array = a.get("payload_options", []) as Array
			match kind:
				"TSUMO":
					can_tsumo = true
				"RIICHI":
					can_riichi = true
				"DECLARE_ABORTIVE_DRAW":
					for op_ab in opts:
						if typeof(op_ab) == TYPE_DICTIONARY \
								and str(op_ab.get("reason", "")) == "KYUUSYU_KYUUHAI":
							can_kyuusyu = true
				"DISCARD":
					for op_d in opts:
						if typeof(op_d) != TYPE_DICTIONARY:
							continue
						if op_d.has("tile_instance_id"):
							var diid: int = int(op_d["tile_instance_id"])
							if not discard_iids.has(diid):
								discard_iids.append(diid)
				"KAN":
					for op_k in opts:
						if typeof(op_k) != TYPE_DICTIONARY:
							continue
						var kk := str(op_k.get("kan_kind", ""))
						if kk == "ANKAN":
							can_ankan = true
						elif kk == "ADDED_KAN":
							can_added = true
		_action_panel.enter_waiting_discard(
			can_tsumo, can_ankan, can_added, false, can_riichi, can_kyuusyu)
		if _seat_panel_player != null:
			var clickable := discard_iids.size() > 0 or can_riichi or can_tsumo \
				or can_ankan or can_added or can_kyuusyu
			if _seat_panel_player.has_method("set_hand_clickable"):
				_seat_panel_player.set_hand_clickable(clickable and discard_iids.size() > 0)
			if discard_iids.size() > 0 and _seat_panel_player.has_method("dim_hand_except"):
				_seat_panel_player.dim_hand_except(discard_iids)
			elif _seat_panel_player.has_method("clear_hand_dim"):
				_seat_panel_player.clear_hand_dim()
	elif ne.kind == "CLAIM_WINDOW":
		var can_ron := false
		var can_chi := false
		var can_pon := false
		var can_minkan := false
		# 权威绝对来源席；禁止读 discarder_seat 错字段
		var discarder: int = int(payload.get("discarded_by_seat", -1))
		for a2 in allowed:
			if typeof(a2) != TYPE_DICTIONARY:
				continue
			var kind2 := str(a2.get("kind", ""))
			var opts2: Array = a2.get("payload_options", []) as Array
			match kind2:
				"RON":
					can_ron = true
				"CHI":
					can_chi = true
				"PON":
					can_pon = true
				"PASS":
					pass  # skip 按钮
				"KAN":
					for op_mk in opts2:
						if typeof(op_mk) != TYPE_DICTIONARY:
							continue
						if str(op_mk.get("kan_kind", "")) == "MINKAN":
							can_minkan = true
		_action_panel.enter_waiting_claim(can_ron, can_chi, can_pon, can_minkan, discarder)
		if _seat_panel_player != null:
			if _seat_panel_player.has_method("set_hand_clickable"):
				_seat_panel_player.set_hand_clickable(false)
			if _seat_panel_player.has_method("clear_hand_dim"):
				_seat_panel_player.clear_hand_dim()
	if _public_command_ui_busy():
		_lock_public_inputs("命令处理中…")
	else:
		_action_panel.set_status_text("本席决策 — 选择动作提交权威命令")


func _peek_reward_journal_head_seq() -> int:
	# 仅 committed journal head；不得用 current_seq()（含 pending）以免空转 rebuild
	var head := 0
	if _public_reward_session != null and _public_reward_session.nbc != null:
		for item in _public_reward_session.nbc.get_event_journal():
			if item is NetworkedEvent:
				head = maxi(head, int((item as NetworkedEvent).server_seq))
		return head
	if _bc != null and _bc.has_meta("local_authority"):
		var auth = _bc.get_meta("local_authority")
		if auth != null and auth.has_method("event_journal"):
			for ne in auth.event_journal(0):
				if ne is NetworkedEvent:
					head = maxi(head, int((ne as NetworkedEvent).server_seq))
	return head


func get_reward_apply_count() -> int:
	return _reward_apply_count


func _reward_view_signature() -> String:
	var reward_view: Dictionary = {}
	var inv_view: Dictionary = {}
	_fill_reward_views(reward_view, inv_view)
	# 轻量签名：phase/discard/items 数 + 本席 seat
	var phase := str(reward_view.get("phase", ""))
	var disc := int(reward_view.get("discard_count", -1))
	var items: Array = inv_view.get("items", []) as Array if inv_view.has("items") else []
	var exit_s := str(reward_view.get("window_exit", ""))
	return "%s|%d|%d|%s|%d" % [phase, disc, items.size(), exit_s, _reward_local_seat]


func _fill_reward_views(reward_view: Dictionary, inv_view: Dictionary) -> void:
	reward_view.clear()
	inv_view.clear()
	if _public_reward_session != null and _public_reward_session.nbc != null:
		var nbc: NetworkedBattleController = _public_reward_session.nbc
		reward_view.merge(nbc.get_reward_window_view())
		inv_view.merge(nbc.get_item_inventory_view())
		return
	if _bc != null and _bc.mode_modules != null and _bc.mode_modules.is_trash_talk():
		var rw = _bc.mode_modules.reward_window
		var inv = _bc.mode_modules.item_inventory
		if rw != null and rw.has_method("to_snapshot_dto"):
			var dto: Dictionary = rw.to_snapshot_dto()
			var pay: Variant = dto.get("payload", null)
			if typeof(pay) == TYPE_DICTIONARY:
				reward_view.merge(pay as Dictionary)
		if inv != null and inv.has_method("to_seat_snapshot_dto"):
			var env: Dictionary = inv.to_seat_snapshot_dto(_reward_local_seat)
			if env.has("payload") and typeof(env["payload"]) == TYPE_DICTIONARY:
				inv_view.merge(env["payload"] as Dictionary)
			elif env.has("items"):
				inv_view.merge(env)


func _bind_public_matching_meta_characters() -> void:
	if _public_reward_session == null or _public_reward_session.nbc == null:
		return
	var meta: Dictionary = _public_reward_session.nbc.get_matching_meta_view()
	if meta.is_empty():
		return
	var chars: Variant = meta.get("character_ids", null)
	if typeof(chars) != TYPE_ARRAY or (chars as Array).size() != 4:
		return
	bind_character_ids(chars as Array)


func _apply_reward_views_only() -> void:
	# #374：权威 roster 绑定不依赖库存/奖励子表是否已挂载。
	_bind_public_matching_meta_characters()
	if _table == null or not _table.has_method("apply_reward_views"):
		_last_reward_view_sig = _reward_view_signature()
		return
	var reward_view: Dictionary = {}
	var inv_view: Dictionary = {}
	_fill_reward_views(reward_view, inv_view)
	_table.apply_reward_views(reward_view, inv_view)
	if _table.has_method("apply_viewer_tenpai_waits_view"):
		var tenpai_view: Dictionary = {}
		if _public_reward_session != null and _public_reward_session.nbc != null:
			tenpai_view = _public_reward_session.nbc.get_viewer_tenpai_waits_view()
		_table.apply_viewer_tenpai_waits_view(tenpai_view)
	if _table.has_method("apply_reward_utterances_display") and not reward_view.is_empty():
		_table.apply_reward_utterances_display(reward_view)
	_reward_apply_count += 1
	_last_reward_view_sig = _reward_view_signature()


## 兼容测试/旧调用：完整刷新（含 journal 增量）。
func _refresh_reward_feedback_views() -> void:
	if not _reward_bootstrapped:
		_bootstrap_reward_display()
	_apply_reward_views_only()
	_consume_reward_journal_events()
	_last_reward_head_seq = _peek_reward_journal_head_seq()
	_last_reward_view_sig = _reward_view_signature()


func _consume_reward_journal_events() -> void:
	if _table == null:
		return
	var events: Array = _collect_committed_reward_events()
	for item in events:
		var ne: NetworkedEvent = null
		if item is NetworkedEvent:
			ne = item as NetworkedEvent
		elif typeof(item) == TYPE_DICTIONARY:
			ne = NetworkedEvent.from_dict(item)
		if ne == null:
			continue
		var seq: int = int(ne.server_seq)
		if seq <= _reward_journal_cursor:
			continue
		var kind := String(ne.kind)
		match kind:
			"REWARD_WINDOW_OPENED", "REWARD_WINDOW_CLOSING", \
			"REWARD_WINDOW_SETTLED", "REWARD_WINDOW_CANCELLED", \
			"ITEM_GRANTED", "ITEM_APPLIED", "ITEM_CONSUMED", \
			"MATCH_SETTLED", "ROOM_SNAPSHOT":
				if _table.has_method("inject_reward_journal_event"):
					_table.inject_reward_journal_event(ne, _reward_source_epoch)
				elif _table.has_method("inject_reward_feedback"):
					_table.inject_reward_feedback(ne)
		_reward_journal_cursor = maxi(_reward_journal_cursor, seq)


func _collect_committed_reward_events() -> Array:
	# 公共：仅 NBC committed journal（pending 不在 journal）
	if _public_reward_session != null and _public_reward_session.nbc != null:
		return _public_reward_session.nbc.get_event_journal()
	# 练习：完整 journal，由 cursor 过滤
	if _bc != null and _bc.has_meta("local_authority"):
		var auth = _bc.get_meta("local_authority")
		if auth != null and auth.has_method("event_journal"):
			return auth.event_journal(0)
	return []


func _on_inventory_use_requested(item_instance_id: String) -> void:
	var iid := String(item_instance_id).strip_edges()
	if iid.is_empty():
		return
	# #378：公共场 ITEM_USE 走 session.submit_action（精确 instance；offer 可无 ITEM_USE）
	if _public_reward_session != null and (
		_bc == null or not _bc.has_meta("local_authority")
	):
		if _public_command_ui_busy():
			return
		_submit_public_item_use(iid)
		return
	if _bc == null:
		return
	if not _bc.has_method("submit_item_use"):
		return
	# 经 PBC 既有 command_id 序列与 apply_action → LocalLoopback
	var res: ActionResolution = _bc.submit_item_use(iid, _reward_local_seat)
	if res != null and res.accepted:
		call_deferred("_sync_reward_feedback_if_advanced")


func bind_voice_from_battle(bc: PlayableBattleController) -> void:
	release_voice_runtime()
	if bc == null or bc.mode_modules == null:
		return
	var port: VoicePortModule = bc.mode_modules.voice_port
	if port == null:
		return
	_voice_port = port
	_ensure_ptt_ui()
	_voice_capture = VoiceCapturePipeline.new()
	_voice_capture.name = "VoiceCapturePipeline"
	add_child(_voice_capture)
	_voice_capture.bind_voice_port(_voice_port)
	_voice_playback = VoicePlaybackRouter.new()
	_voice_playback.name = "VoicePlaybackRouter"
	add_child(_voice_playback)
	_voice_playback.bind_voice_port(_voice_port)
	if not _voice_port.ptt_state_changed.is_connected(_on_ptt_state_changed):
		_voice_port.ptt_state_changed.connect(_on_ptt_state_changed)
	if not _voice_port.microphone_unavailable.is_connected(_on_microphone_unavailable):
		_voice_port.microphone_unavailable.connect(_on_microphone_unavailable)
	# E4-03：首次欢乐场绑定按需准备模型；未就绪不阻断 PTT/牌局。
	_bind_whisper_model_manager(port)
	_refresh_voice_inline_status()


func has_voice_runtime() -> bool:
	return _voice_port != null


func release_voice_runtime() -> void:
	_release_whisper_model_manager()
	if _voice_port != null:
		if _voice_port.ptt_state_changed.is_connected(_on_ptt_state_changed):
			_voice_port.ptt_state_changed.disconnect(_on_ptt_state_changed)
		if _voice_port.microphone_unavailable.is_connected(_on_microphone_unavailable):
			_voice_port.microphone_unavailable.disconnect(_on_microphone_unavailable)
		_voice_port.release_all()
	if _voice_capture != null and is_instance_valid(_voice_capture):
		_voice_capture.stop_capture()
		_voice_capture.queue_free()
	_voice_capture = null
	if _voice_playback != null and is_instance_valid(_voice_playback):
		_voice_playback.release_all()
		_voice_playback.queue_free()
	_voice_playback = null
	if _ptt_button != null and is_instance_valid(_ptt_button):
		_ptt_button.queue_free()
	_ptt_button = null
	if _ptt_status != null and is_instance_valid(_ptt_status):
		_ptt_status.queue_free()
	_ptt_status = null
	if _mic_permission_label != null and is_instance_valid(_mic_permission_label):
		_mic_permission_label.queue_free()
	_mic_permission_label = null
	if _model_status_label != null and is_instance_valid(_model_status_label):
		_model_status_label.queue_free()
	_model_status_label = null
	_model_received_bytes = 0
	_model_total_bytes = 0
	_ptt_ui_state = &"idle"
	_voice_port = null


func _bind_whisper_model_manager(port: VoicePortModule) -> void:
	_release_whisper_model_manager()
	if port == null:
		return
	var mgr: WhisperModelManager = port.whisper_model_manager()
	# 生产：首次 bind 创建生产 manager；测试可预注入 fixture manager。
	if mgr == null or not is_instance_valid(mgr):
		mgr = WhisperModelManager.new()
		mgr.name = "WhisperModelManager"
		mgr.apply_production_manifest()
		port.attach_whisper_model_manager(mgr)
	if mgr.get_parent() != null and mgr.get_parent() != self:
		mgr.get_parent().remove_child(mgr)
	if mgr.get_parent() != self:
		mgr.name = "WhisperModelManager"
		add_child(mgr)
	_whisper_model_manager = mgr
	if not mgr.state_changed.is_connected(_on_whisper_state_changed):
		mgr.state_changed.connect(_on_whisper_state_changed)
	if not mgr.progress_changed.is_connected(_on_whisper_progress_changed):
		mgr.progress_changed.connect(_on_whisper_progress_changed)
	if not mgr.error_changed.is_connected(_on_whisper_error_changed):
		mgr.error_changed.connect(_on_whisper_error_changed)
	var m: Dictionary = mgr.get_manifest()
	_model_total_bytes = int(m.get("size_bytes", 0))
	_model_received_bytes = mgr.get_received_bytes()
	_refresh_voice_inline_status()
	mgr.ensure_ready()


func _release_whisper_model_manager() -> void:
	if _whisper_model_manager == null:
		return
	var mgr: WhisperModelManager = _whisper_model_manager
	_whisper_model_manager = null
	if not is_instance_valid(mgr):
		if _voice_port != null:
			_voice_port.attach_whisper_model_manager(null)
		return
	# 先断 UI 信号，避免 release/状态回调再进牌桌
	if mgr.state_changed.is_connected(_on_whisper_state_changed):
		mgr.state_changed.disconnect(_on_whisper_state_changed)
	if mgr.progress_changed.is_connected(_on_whisper_progress_changed):
		mgr.progress_changed.disconnect(_on_whisper_progress_changed)
	if mgr.error_changed.is_connected(_on_whisper_error_changed):
		mgr.error_changed.disconnect(_on_whisper_error_changed)
	# release：取消在途 HTTP/解析 token；保留磁盘合法 partial
	mgr.release()
	if _voice_port != null:
		_voice_port.attach_whisper_model_manager(null)
	# 禁止在信号/回调锁内同步 free()；queue_free 最迟下帧回收。
	# manager 销毁路径只 kill 活跃 resolve 子进程，绝不 wait_to_finish 阻塞主线程。
	mgr.queue_free()


func _ensure_ptt_ui() -> void:
	if _ptt_button != null and is_instance_valid(_ptt_button):
		return
	# 右下角内联说明 + PTT：
	# ┌ 麦克风仅在按住说话时启用 ┐
	# │ 模型：下载中 37% …       │
	# └────── [🎙 按住说话] ─────┘
	# 避开居中行动栏（Y=700,W=720）与 seat0 手牌。
	var panel_w := 240.0
	var panel_x := TableLayout.TABLE_W - panel_w - 16.0

	_mic_permission_label = Label.new()
	_mic_permission_label.name = "MicPermissionLabel"
	_mic_permission_label.text = "麦克风仅在按住说话时启用"
	_mic_permission_label.position = Vector2(panel_x, 764.0)
	_mic_permission_label.size = Vector2(panel_w, 22.0)
	_mic_permission_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mic_permission_label.add_theme_font_size_override("font_size", 13)
	_mic_permission_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_mic_permission_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mic_permission_label)

	_model_status_label = Label.new()
	_model_status_label.name = "ModelStatusLabel"
	_model_status_label.text = "模型：检查中…"
	_model_status_label.position = Vector2(panel_x, 786.0)
	_model_status_label.size = Vector2(panel_w, 22.0)
	_model_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_model_status_label.add_theme_font_size_override("font_size", 13)
	_model_status_label.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0, 0.95))
	# 失败/取消时可点击重试
	_model_status_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_model_status_label.gui_input.connect(_on_model_status_gui_input)
	add_child(_model_status_label)

	_ptt_status = Label.new()
	_ptt_status.name = "PttStatusLabel"
	_ptt_status.text = ""
	_ptt_status.position = Vector2(panel_x, 808.0)
	_ptt_status.size = Vector2(panel_w, 20.0)
	_ptt_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ptt_status.add_theme_font_size_override("font_size", 13)
	_ptt_status.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_ptt_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ptt_status)

	_ptt_button = Button.new()
	_ptt_button.name = "PttButton"
	_ptt_button.text = "🎙 按住说话"
	_ptt_button.position = Vector2(panel_x + (panel_w - 160.0) * 0.5, 832.0)
	_ptt_button.size = Vector2(160.0, 40.0)
	_ptt_button.focus_mode = Control.FOCUS_NONE
	_ptt_button.button_down.connect(_on_ptt_button_down)
	_ptt_button.button_up.connect(_on_ptt_button_up)
	add_child(_ptt_button)


## 供测试与 UI 复用：把 lifecycle + 字节进度格式化为稳定中文文案。
func format_model_status_text(
	state: StringName, received_bytes: int, total_bytes: int, _error_code: String
) -> String:
	match state:
		&"idle":
			return "模型：待命"
		&"checking":
			return "模型：检查中…"
		&"downloading":
			var pct := _stable_download_percent(received_bytes, total_bytes)
			return "模型：下载中 %d%%" % pct
		&"verifying":
			return "模型：校验中…"
		&"ready":
			return "模型：就绪"
		&"failed":
			return "模型：失败，点此重试"
		&"cancelled":
			return "模型：已取消，点此重试"
		_:
			return "模型：%s" % String(state)


func _stable_download_percent(received_bytes: int, total_bytes: int) -> int:
	if total_bytes <= 0:
		return 0
	if received_bytes <= 0:
		return 0
	if received_bytes >= total_bytes:
		return 100
	# 稳定向下取整，避免 99.9→100 误导
	return int((float(received_bytes) * 100.0) / float(total_bytes))


func _refresh_voice_inline_status() -> void:
	if _model_status_label != null and is_instance_valid(_model_status_label):
		var st: StringName = &"idle"
		var err := ""
		if _whisper_model_manager != null and is_instance_valid(_whisper_model_manager):
			st = _whisper_model_manager.get_lifecycle_state()
			err = _whisper_model_manager.get_error_code()
			_model_received_bytes = _whisper_model_manager.get_received_bytes()
			var m: Dictionary = _whisper_model_manager.get_manifest()
			var total := int(m.get("size_bytes", 0))
			if total > 0:
				_model_total_bytes = total
		_model_status_label.text = format_model_status_text(
			st, _model_received_bytes, _model_total_bytes, err
		)
		_model_status_label.visible = true

	if _ptt_status == null or not is_instance_valid(_ptt_status):
		return
	if _ptt_ui_state == &"speaking":
		_ptt_status.text = "正在说话…"
		_ptt_status.visible = true
	elif _ptt_ui_state == &"unavailable":
		_ptt_status.text = "麦克风不可用"
		_ptt_status.visible = true
	else:
		_ptt_status.text = ""
		_ptt_status.visible = false


func _on_whisper_state_changed(_state: StringName) -> void:
	_refresh_voice_inline_status()


func _on_whisper_progress_changed(received_bytes: int, total_bytes: int) -> void:
	_model_received_bytes = received_bytes
	if total_bytes > 0:
		_model_total_bytes = total_bytes
	_refresh_voice_inline_status()


func _on_whisper_error_changed(_error_code: String) -> void:
	_refresh_voice_inline_status()


func _on_model_status_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_retry_whisper_model_if_needed()


func _retry_whisper_model_if_needed() -> void:
	if _whisper_model_manager == null or not is_instance_valid(_whisper_model_manager):
		return
	var st: StringName = _whisper_model_manager.get_lifecycle_state()
	if st == &"failed" or st == &"cancelled":
		_whisper_model_manager.ensure_ready()


func _on_ptt_button_down() -> void:
	if _voice_port == null:
		return
	# #258：Windows 首次 PTT 应用内说明；确认前不 press_ptt（非 Windows 跳过）
	if FirstUseNotices.needs_ptt_notice():
		_begin_first_ptt_notice()
		return
	# 失败态不阻断 PTT；顺带尝试重新 ensure（可重试语义）
	_retry_whisper_model_if_needed()
	_voice_port.press_ptt()


func _on_ptt_button_up() -> void:
	if _voice_port == null:
		return
	_voice_port.release_ptt()


func _begin_first_ptt_notice() -> void:
	if get_node_or_null("FirstPttNotice") != null:
		return
	var copy: Dictionary = FirstUseNotices.ptt_copy()
	var dlg := ConfirmDialog.show_dialog(
		String(copy.get("title", "")),
		String(copy.get("body", "")),
		String(copy.get("confirm", "我知道了")),
		String(copy.get("cancel", "取消")),
		false,
		300
	)
	dlg.name = "FirstPttNotice"
	dlg.confirmed.connect(_on_first_ptt_notice_confirmed)
	dlg.cancelled.connect(_on_first_ptt_notice_cancelled)
	add_child(dlg)


func _on_first_ptt_notice_confirmed() -> void:
	FirstUseNotices.ack_ptt_notice()
	# 不自动 press_ptt：用户需再次按住说话（避免对话框期间误采集）


func _on_first_ptt_notice_cancelled() -> void:
	# 不 ack：再次按下仍提示
	pass


func _on_ptt_state_changed(state: StringName) -> void:
	_ptt_ui_state = state
	_refresh_voice_inline_status()


func _on_microphone_unavailable() -> void:
	_ptt_ui_state = &"unavailable"
	_refresh_voice_inline_status()
	# 短暂提示后恢复 idle 文案（模型状态行仍保留）
	if get_tree() != null:
		get_tree().create_timer(1.2).timeout.connect(func():
			if _ptt_ui_state == &"unavailable":
				_ptt_ui_state = &"idle"
				_refresh_voice_inline_status()
		)

func _on_player_tile_clicked(tile_instance_id: int) -> void:
	# #378 公共路径：仅 session 绑定即走公共命令；练习绑定 session=null 不进入
	if _public_reward_session != null:
		if _public_command_ui_busy():
			return
		if not _public_pick_kind.is_empty():
			_on_public_pick_tile(tile_instance_id)
			return
		# DISCARD / RIICHI 实体点选 → 走公共 choice 构建
		if _action_panel != null:
			_action_panel.on_hand_tile_clicked(tile_instance_id)
		return
	# 记录起点：按 instance 查 slot；飞牌渲染仍用 slot 上的 tile_id/red
	if _seat_panel_player:
		var from: Vector2 = _seat_panel_player.get_hand_slot_global_center(tile_instance_id)
		var fly_tile_id: int = -1
		var is_red := false
		for s in _seat_panel_player._hand_slots:
			if s != null and is_instance_valid(s) \
					and int(s.get_meta("hand_instance_id", Tile.INVALID_INSTANCE_ID)) \
					== tile_instance_id:
				fly_tile_id = int(s.get_meta("hand_id", -1))
				is_red = bool(s.get_meta("hand_red", false))
				break
		if from != Vector2.ZERO:
			_pending_discard_fly = {
				"from": from, "tile_id": fly_tile_id, "is_red": is_red}
	if _decision_adapter != null:
		_decision_adapter.on_hand_tile_clicked(tile_instance_id)


func _on_hand_tile_hover(tile_id: int, entered: bool) -> void:
	if _table == null:
		return
	if entered:
		_table.highlight_tile_id(tile_id)
	else:
		_table.clear_tile_highlight()


# 切牌飞行：手牌全局坐标 → 河末位（经 SubViewport 缩放映射到平面贴图）。
func _play_discard_fly_to_river() -> void:
	var info: Dictionary = _pending_discard_fly
	_pending_discard_fly = {}
	if info.is_empty() or _table == null:
		return
	var from_g: Vector2 = info.get("from", Vector2.ZERO)
	var tile_id: int = int(info.get("tile_id", -1))
	var is_red: bool = bool(info.get("is_red", false))
	if from_g == Vector2.ZERO or tile_id < 0:
		return
	var to_g: Vector2 = _estimate_river_end_global(0)
	if to_g == Vector2.ZERO:
		return
	var key: String = CardTileBack.tile_id_to_atlas_key(tile_id, is_red)
	var extractor: Node = get_tree().root.get_node_or_null("TextureExtractor")
	var tex: Texture2D = null
	if extractor and key != "":
		tex = extractor.get_tile_texture(key)
	var fly := TextureRect.new()
	fly.texture = tex
	fly.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fly.stretch_mode = TextureRect.STRETCH_SCALE
	fly.size = Vector2(48, 68)
	fly.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fly.z_index = 80
	# 全局 → playable_table 本地
	var from_local: Vector2 = from_g - global_position
	var to_local: Vector2 = to_g - global_position
	fly.position = from_local - fly.size * 0.5
	add_child(fly)
	var mid: Vector2 = (from_local + to_local) * 0.5 + Vector2(0, -48)
	var start_p: Vector2 = from_local - fly.size * 0.5
	var mid_p: Vector2 = mid - fly.size * 0.5
	var end_p: Vector2 = to_local - fly.size * 0.5
	fly.position = start_p
	var tw := create_tween()
	tw.set_parallel(true)
	# 路径：手牌 → 弧顶 → 河末位。
	var path_tw := create_tween()
	path_tw.tween_property(fly, "position", mid_p, 0.11)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	path_tw.tween_property(fly, "position", end_p, 0.13)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(fly, "scale", Vector2(0.72, 0.72), 0.24)
	path_tw.finished.connect(func():
		if is_instance_valid(fly):
			fly.queue_free())


func _estimate_river_end_global(seat_id: int) -> Vector2:
	if _table == null:
		return Vector2.ZERO
	if _use_3d:
		return size * 0.5  # M1：飞牌落点近似桌心
	if seat_id >= _table.discard_rivers.size():
		return Vector2.ZERO
	var dr = _table.discard_rivers[seat_id]
	if dr == null or not dr.has_method("get_last_tile_local_center"):
		return Vector2.ZERO
	var local_c: Vector2 = dr.get_last_tile_local_center()
	return dr.to_global(local_c)

# 键盘 helper：D=切第一张牌；S=跳过；R=立直 yes — 备用调试入口
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not (k.pressed and not k.echo):
		return
	match k.keycode:
		KEY_D:
			if _bc != null and _decision_adapter != null:
				var hand_tiles: Array = _bc.state.seats[0].hand.tiles()
				if hand_tiles.size() > 0:
					_decision_adapter.on_hand_tile_clicked(
						(hand_tiles[0] as Tile).instance_id)
		KEY_S:
			if _decision_adapter != null:
				_decision_adapter.submit_action({"action": "skip"})
		KEY_R:
			if _decision_adapter != null:
				_decision_adapter.submit_action({"action": "riichi_yes"})
		KEY_ESCAPE:
			if get_node_or_null("ResultOverlay") != null:
				get_viewport().set_input_as_handled()
				return
			_open_settings_overlay(find_child("SettingsButton", true, false) as Control)


func _open_settings_overlay(source: Control = null) -> void:
	# 防止 ESC 连按打开多个
	if get_tree().root.get_node_or_null("_settings_overlay_root") != null:
		return
	var overlay := SettingsOverlay.new()
	overlay.name = "_settings_overlay_root"
	overlay.closed.connect(func() -> void:
		if source != null and is_instance_valid(source) \
				and source.focus_mode != Control.FOCUS_NONE:
			source.grab_focus())
	get_tree().root.add_child(overlay)
