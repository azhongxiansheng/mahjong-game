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
var _decision_adapter: TableDecisionAdapter = null

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

# ---- 3D 透视桌面(spec 2026-06-11 追加;对标参考作 .table-plane rotateX(18°)) ----
#
# 管线:桌面内容(FourPlayerTable)渲染进 SubViewport(2D)→ 贴到 World3D 里
# 绕 X 倾斜的面片 → 透视相机渲染 → TextureRect 回贴 2D。
# 关键决策:**只倾斜展示层** — 玩家 SeatPanel(手牌可点)抽出到平面层,
# 按钮/宣告大字本就在平面层 → 被倾斜的部分零交互,无需鼠标反投影。
# 参考作同构(.seat-bottom-fixed 不参与 table-plane 变换)。

# 透视强度 = 倾角 × 相机近距。参考作 perspective:1200px / 内容高 900px
# ≈ 距离 1.33 倍面高;距离太远倾斜在投影里几乎不可见(首版 2.3 只剩 6% 收窄)。
const TILT_DEG: float = 18.0
const CAM_FOV: float = 42.0
# 取景:桌面要溢出画框(参考作 table-plane top:-140 / rails ±130 都在屏外),
# 桌沿在屏内"飘着"会露出黑边。拉近 + 略下移让底边溢出、顶边near顶。
const CAM_POS := Vector3(0.0, 0.065, 1.12)
const TABLE_RES_SCALE: float = 1.5  # SubViewport 超采样,补偿透视缩小后的清晰度

var _vp_table: SubViewport = null

func _build_layout() -> void:
	# Bg 覆盖整个 viewport,让桌底 ActionPanel 区跟桌面同色,避免桌外背景跳变。
	var bg := ColorRect.new()
	bg.size = Vector2(DT.VIEW_W, TABLE_HEIGHT + ACTION_PANEL_HEIGHT)
	bg.color = DT.BG_BASE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_table = FOUR_PLAYER_TABLE.instantiate()
	_build_tilted_table()

	_action_panel = PLAYER_ACTION_PANEL.instantiate()
	# 操作栏浮在手牌正上方(按钮带底,y 578..626,手牌顶 631)— 鸣牌/自摸
	# 窗口是全局等待点,按钮必须出现在玩家视线焦点处(对标参考作 action-bar)。
	# 旧位置在桌外底部黑条,玩家注意不到,以为游戏卡死。
	_action_panel.position = Vector2(
		(_table.TABLE_WIDTH - PlayerActionPanel.PANEL_W) / 2.0, 550)
	add_child(_action_panel)

	# 顶栏(对标参考截图):logo 左 + 规则/设置按钮右
	_build_top_bar()

	# 宝牌指示窗(平面层左上、顶栏之下):已翻 face-up + 未翻牌背槽
	_dora_widget = DoraWidget.new()
	_dora_widget.position = Vector2(16, 54)
	add_child(_dora_widget)
	_dora_widget.update_indicators([])


# 顶栏:书法 logo + 右侧「规则/设置」主题按钮。
func _build_top_bar() -> void:
	var logo := Label.new()
	logo.text = "麻 将 王"
	logo.position = Vector2(18, 6)
	logo.size = Vector2(180, 40)
	logo.add_theme_font_size_override("font_size", 30)
	logo.add_theme_color_override("font_color", Color(0.88, 0.74, 0.38))
	logo.add_theme_constant_override("shadow_offset_x", 2)
	logo.add_theme_constant_override("shadow_offset_y", 2)
	logo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	# Run HUD 内联(RunFlow 战斗时隐藏自身 HUD,HP/金币挂这里)
	_run_hud_label = Label.new()
	_run_hud_label.position = Vector2(212, 14)
	_run_hud_label.size = Vector2(360, 28)
	_run_hud_label.add_theme_font_size_override("font_size", 18)
	_run_hud_label.add_theme_color_override("font_color", Color(0.92, 0.90, 0.82))
	_run_hud_label.add_theme_constant_override("shadow_offset_y", 1)
	_run_hud_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_run_hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_run_hud_label.visible = false
	add_child(_run_hud_label)
	# 对局 loadout 芯片条：能力/遗物/道具，挂顶栏中段
	_loadout_strip = BattleLoadoutStrip.new()
	_loadout_strip.position = Vector2(580, 10)
	_loadout_strip.custom_minimum_size = Vector2(280, 36)
	_loadout_strip.size = Vector2(280, 36)
	add_child(_loadout_strip)
	var rules_btn := Button.new()
	rules_btn.text = "📖 规则"
	rules_btn.position = Vector2(FourPlayerTable.TABLE_WIDTH - 196, 10)
	rules_btn.custom_minimum_size = Vector2(88, 36)
	rules_btn.pressed.connect(_open_help_overlay)
	add_child(rules_btn)
	var settings_btn := Button.new()
	settings_btn.text = "⚙ 设置"
	settings_btn.position = Vector2(FourPlayerTable.TABLE_WIDTH - 100, 10)
	settings_btn.custom_minimum_size = Vector2(88, 36)
	settings_btn.pressed.connect(_open_settings_overlay)
	add_child(settings_btn)


func _open_help_overlay() -> void:
	if get_tree().root.get_node_or_null("_help_overlay_root") != null:
		return
	var overlay := HelpOverlay.new()
	overlay.name = "_help_overlay_root"
	get_tree().root.add_child(overlay)


func _build_tilted_table() -> void:
	var tw_f: float = FourPlayerTable.TABLE_WIDTH
	var th_f: float = FourPlayerTable.TABLE_HEIGHT
	# 2D 桌面离屏渲染(超采样)
	_vp_table = SubViewport.new()
	_vp_table.size = Vector2i(int(tw_f * TABLE_RES_SCALE), int(th_f * TABLE_RES_SCALE))
	_vp_table.transparent_bg = true
	_vp_table.disable_3d = true
	_vp_table.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp_table)
	_table.position = Vector2.ZERO
	_table.scale = Vector2.ONE * TABLE_RES_SCALE
	_vp_table.add_child(_table)
	# 玩家 SeatPanel 抽出到平面层:手牌保持原生坐标可点击
	var sp0: SeatPanel = _table.seat_panels[0]
	if sp0:
		sp0.get_parent().remove_child(sp0)
		sp0.scale = Vector2.ONE  # 不吃超采样缩放
		add_child(sp0)
	# 3D 倾斜面片 + 透视相机
	var vp3d := SubViewport.new()
	vp3d.size = Vector2i(int(tw_f), int(th_f))
	vp3d.transparent_bg = true
	vp3d.own_world_3d = true
	vp3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp3d)
	var cam := Camera3D.new()
	cam.fov = CAM_FOV
	cam.position = CAM_POS
	vp3d.add_child(cam)
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(tw_f / th_f, 1.0)
	quad.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _vp_table.get_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	quad.material_override = mat
	quad.rotation_degrees.x = -TILT_DEG  # 顶边向远处倒
	vp3d.add_child(quad)
	# 回贴 2D
	var tr := TextureRect.new()
	tr.name = "TiltedTableView"
	tr.texture = vp3d.get_texture()
	tr.position = Vector2.ZERO
	tr.size = Vector2(tw_f, th_f)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)
	# 平面层的玩家 SeatPanel 必须在贴图之上
	if sp0:
		move_child(sp0, get_child_count() - 1)

func play_hand_async(bc: PlayableBattleController) -> Dictionary:
	_bc = bc
	if _table.seat_panels.size() >= 1:
		_seat_panel_player = _table.seat_panels[0]
		if not _seat_panel_player.player_card_clicked.is_connected(_on_player_tile_clicked):
			_seat_panel_player.player_card_clicked.connect(_on_player_tile_clicked)
	_decision_adapter = TableDecisionAdapter.new(_action_panel, _seat_panel_player)
	_bc.bind_decision_port(_decision_adapter, get_tree())
	_table.bind_battle_state(bc.state, 0, 4)
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
	DT.popin(panel)

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
		# 分级强调:役満/三倍満 tier 大字 tada;玩家自己胡 heartbeat;
		# 玩家放铳 → 整个 panel shake_x"挨了一拳"。延迟让 popin 先落地。
		if yakuman_mul >= 1 or han >= 11:
			DT.attention(tier, "tada", 0.8, 0.3)
		elif winner_seat == 0:
			DT.attention(tier, "heartbeat", 0.6, 0.3)
		elif not is_tsumo and int(win_event.extra.get("discarder_seat", -1)) == 0:
			DT.attention(panel, "shake_x", 0.5, 0.3)
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

	# 役名列表 — T4(spec AC-G4-a):逐条错峰入场替代整段文本。
	# 双列 Grid 容纳 ≤8 条不与下方胡牌行打架;>8 条尾部聚合。
	_result_anim_tweens.clear()
	if win_event != null:
		_build_yaku_rows(panel, win_event.extra.get("yaku_names", []))

	# 胡牌 14 张展示行(winning tile 单独右侧 + 金色调突出)
	if win_event != null and win_event.tile_instance != null and win_event.tile_instance.tile != null:
		var is_tsumo: bool = (last_event == "TSUMO_DECLARED"
			or int(win_event.extra.get("discarder_seat", -1)) < 0)
		_render_winning_hand_strip(panel, win_event.actor_seat,
			win_event.tile_instance.tile.id, is_tsumo, 220)

	# 明细：番·符 + 得失分(得分大数字由 _build_rolling_score 单独渲染)
	var detail := Label.new()
	detail.position = Vector2(48, 322)
	detail.size = Vector2(624, 128)
	detail.add_theme_font_size_override("font_size", 18)
	detail.add_theme_color_override("font_color", Color(0.95, 0.95, 0.85))
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if win_event != null:
		var fu2: int = int(win_event.extra.get("fu", 0))
		var han2: int = int(win_event.extra.get("han", 0))
		var winner_total: int = int(win_event.extra.get("winner_total", 0))
		var payout: Dictionary = win_event.extra.get("payout", {})
		# T4(spec AC-G4-b):胜者得分独立 Label 数字滚动(0→N,金/红辉光)
		_build_rolling_score(panel, winner_total,
			int(win_event.actor_seat) == 0
			or int(win_event.extra.get("discarder_seat", -1)) != 0)
		var lines: Array[String] = []
		if int(win_event.extra.get("yakuman_multiplier", 0)) > 0:
			lines.append("番数：—   符：—")
		else:
			lines.append("番数：%d 飜    符：%d" % [han2, fu2])
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
	btn.position = Vector2(380, 490)
	btn.custom_minimum_size = Vector2(160, 44)
	btn.pressed.connect(func(): overlay.queue_free())
	panel.add_child(btn)

	# 牌谱按钮:点了弹本局所有 events 的文字列表 panel,玩家可复盘"AI 1 弃 W5、
	# 我立直、AI 2 抢杠..."。基于 _bc.events 即时格式化,无需 events sourcing
	# 重放(那需要 UI apply_event 镜像 BC state mutation,工作量超 1 周)。
	# 是 PVP 战报常见形态,玩家可截图分享。
	var replay_btn := Button.new()
	replay_btn.text = "📜 牌谱"
	replay_btn.position = Vector2(180, 490)
	replay_btn.custom_minimum_size = Vector2(160, 44)
	replay_btn.pressed.connect(func(): _show_replay_log(overlay))
	panel.add_child(replay_btn)

	# 点击空白处:动画未播完 → 先跳到终态(spec AC-G4-c);已完 → 关闭
	overlay.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			if _skip_result_animations():
				return
			overlay.queue_free())
	while is_instance_valid(overlay):
		await get_tree().process_frame


# ---- T4 结算编排(spec 2026-06-11 G4) ----

# 正在播放的结算动画 [{tween, finish: Callable}];点击跳过时统一收尾。
var _result_anim_tweens: Array = []

# 役种双列逐条入场。每条「役名  N飜」,0.08s/条错峰,从左淡入滑入。
func _build_yaku_rows(panel: Control, yaku_names: Array) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.position = Vector2(80, 148)
	grid.size = Vector2(560, 68)
	grid.add_theme_constant_override("h_separation", 48)
	grid.add_theme_constant_override("v_separation", 2)
	panel.add_child(grid)
	var shown: Array = yaku_names.slice(0, 8)
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
		var row := Label.new()
		row.text = "%s　%s" % [nm, suffix]
		row.custom_minimum_size = Vector2(256, 22)
		row.add_theme_font_size_override("font_size", 18)
		row.add_theme_color_override("font_color", Color(1, 0.92, 0.55))
		grid.add_child(row)
		# 错峰淡入(0.08s/条)。注:Grid 接管子节点 position,只动 modulate。
		row.modulate = Color(1, 1, 1, 0)
		var tw := create_tween()
		tw.tween_interval(0.12 + i * 0.08)
		tw.tween_property(row, "modulate:a", 1.0, 0.22)
		var captured := row
		var fin := func():
			if is_instance_valid(captured):
				captured.modulate = Color.WHITE
		_result_anim_tweens.append({"tween": tw, "finish": fin})
	if yaku_names.size() > 8:
		var more := Label.new()
		more.text = "…等 %d 役" % yaku_names.size()
		more.add_theme_font_size_override("font_size", 16)
		more.add_theme_color_override("font_color", Color(0.8, 0.74, 0.5))
		grid.add_child(more)

# 胜者得分大数字滚动(0→total,0.6s quad_out;金=玩家受益/红=玩家放铳)。
func _build_rolling_score(panel: Control, total: int, is_up_for_player: bool) -> void:
	var lbl := Label.new()
	lbl.name = "RollingScore"
	lbl.position = Vector2(48, 284)
	lbl.size = Vector2(624, 34)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 30)
	var color := Color(0.94, 0.84, 0.42) if is_up_for_player else Color(0.93, 0.42, 0.42)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.add_theme_color_override("font_shadow_color",
		Color(color.r, color.g, color.b, 0.35))
	lbl.text = "0 点"
	panel.add_child(lbl)
	var update := func(v: float):
		if is_instance_valid(lbl):
			lbl.text = "%d 点" % int(v)
	var tw := create_tween()
	tw.tween_method(update, 0.0, float(total), 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var fin := func():
		if is_instance_valid(lbl):
			lbl.text = "%d 点" % total
	_result_anim_tweens.append({"tween": tw, "finish": fin})

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
	# 保留 is_red_dora：用 Tile 列表而非 to_id_array
	var concealed: Array = []  # Array[Tile]
	for t in winner.hand._tiles:
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
	# HBox 居中,1 px 牌间隙
	var strip := HBoxContainer.new()
	strip.position = Vector2(0, y_offset)
	strip.size = Vector2(720, 56)
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	# 1 px 紧贴 — 胡牌 14 张牌展示行传统紧贴,**不要**改用 DT.GAP_TIGHT(8)
	# 否则 14 张牌 + 13 个 8px 间隔总宽超 720 容器宽,溢出。
	strip.add_theme_constant_override("separation", 1)
	parent.add_child(strip)
	for t in concealed:
		strip.add_child(_make_overlay_tile(t.id, false, t.is_red_dora))
	# 暗手与 winning tile 之间留 10 px gap
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(10, 56)
	strip.add_child(spacer)
	strip.add_child(_make_overlay_tile(winning_tile_id, true, win_red))
	# 副露(吃/碰/杠)展示在最右,每个 meld 内 1 px 间隔、meld 间 8 px gap
	for meld in winner.melds:
		var meld_gap := Control.new()
		meld_gap.custom_minimum_size = Vector2(8, 56)
		strip.add_child(meld_gap)
		for t in meld.tiles:
			if t != null:
				strip.add_child(_make_overlay_tile(t.id, false, t.is_red_dora))


# 单张小牌(28×40),winning=true 给金色描边 Panel 包装突出。
func _make_overlay_tile(tile_id: int, is_winning: bool, is_red_dora: bool = false) -> Control:
	const TW := 28
	const TH := 40
	var key: String = CardTileBack.tile_id_to_atlas_key(tile_id, is_red_dora)
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
# T2:待标记的和牌张(rebind 后由 polling loop 应用,-1 = 无)
var _pending_win_tile_id: int = -1
var _dora_widget: DoraWidget = null
var _run_hud_label: Label = null
var _loadout_strip: BattleLoadoutStrip = null


# RunFlow 战斗时注入 run 级 HUD(HP/金币/章),内联进顶栏。
func set_run_hud(hp: int, max_hp: int, gold: int, chapter: int) -> void:
	if _run_hud_label == null:
		return
	_run_hud_label.text = "♥ %d/%d    金 %d    第 %d 章" % [hp, max_hp, gold, chapter]
	_run_hud_label.visible = true


# 注入当前 Run 的能力/遗物/消耗品 id，渲染顶栏芯片条。
func set_loadout(ability_ids: Array, relic_ids: Array = [], consumable_ids: Array = []) -> void:
	if _loadout_strip == null:
		return
	_loadout_strip.bind_ids(ability_ids, relic_ids, consumable_ids)

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
				# T2:rebind 重建完手牌行后应用和牌张脉冲标记
				if _pending_win_tile_id >= 0 and _table.seat_panels.size() > 0:
					_table.seat_panels[0].mark_win_tile(_pending_win_tile_id)
					_pending_win_tile_id = -1
				# 宝牌指示窗同步(内部按 key 去重,无变化零开销)
				if _dora_widget and _bc.state.dora_indicators:
					var ind_ids: Array = []
					for ti in _bc.state.dora_indicators.visible:
						if ti != null:
							ind_ids.append(ti.id)
					_dora_widget.update_indicators(ind_ids)
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
		&"PLAYER_ACTION":
			# 鸣牌宣告演出(T1):吃/碰/杠书法大字从动作座位方向滑入。
			# AI 的 pon/minkan 走 _resolve_claims、玩家的走 PlayableBC,
			# 两边都 emit PLAYER_ACTION,此处统一接。
			var kind := StringName(String(ev.extra.get("kind", "")))
			if kind in [&"chi", &"pon", &"minkan", &"ankan", &"added_kan"]:
				_play_call_announce(kind, int(ev.actor_seat))
		&"RIICHI_DECLARED":
			var shake := ScreenShake.for_tier(self, WinBurst.Tier.LIGHT)
			shake.start()
			_flash_screen(0.18, Color(1, 1, 1, 0.35))
			_play_call_announce(&"riichi", int(ev.actor_seat))
			# AI 立直 → 该 seat 立绘转蓝调"决意"。actor_seat 越界 / seat 0 无立绘
			# 时 set_emote 是 no-op,不会崩。
			_set_seat_emote(int(ev.actor_seat), "riichi")
			_say_for_seat(int(ev.actor_seat), "riichi")
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
			# 胡牌宣告大字(T1)。役満升级版在 WIN_DECLARED 分支补刀。
			_play_call_announce(
				&"tsumo" if ev.type == &"TSUMO_DECLARED" else &"ron",
				int(ev.actor_seat))
			# T2:玩家自摸时和牌张心跳脉冲。必须在 rebind 之后标
			# (rebind 全量重建手牌行会清掉),挂 pending 由 polling loop 应用。
			if ev.type == &"TSUMO_DECLARED" and int(ev.actor_seat) == 0 \
					and ev.tile_instance != null and ev.tile_instance.tile != null:
				_pending_win_tile_id = ev.tile_instance.tile.id
			# 胜者立绘金调,其他 3 家(含玩家)灰调"被胡失落"。RON 时被点炮的家
			# (deal_in_seat)单独更愁,可以加深色;v1 三家都用 upset 已足够。
			_set_seat_emote(int(ev.actor_seat), "winning")
			_say_for_seat(int(ev.actor_seat), "winning")
			for s in [0, 1, 2, 3]:
				if s != int(ev.actor_seat):
					_set_seat_emote(s, "upset")
					_say_for_seat(s, "upset")
		&"WIN_DECLARED":
			# 役満:在 tsumo/ron 宣告后 0.5s 追加「役満」更大字号演出
			if int(ev.extra.get("yakuman_multiplier", 0)) >= 1:
				var seat_c := int(ev.actor_seat)
				get_tree().create_timer(0.5).timeout.connect(func():
					if is_inside_tree():
						_play_call_announce(&"yakuman", seat_c))
		&"GAME_BEGIN":
			# 新局开始 → 4 家 emote 重置 normal
			for s in [0, 1, 2, 3]:
				_set_seat_emote(s, "normal")


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
		var sp: SeatPanel = _table.seat_panels[seat_id]
		if sp and sp.has_method("get_portrait_texture"):
			avatar = sp.get_portrait_texture()
	CallAnnounce.play(self, kind, seat_id, avatar)


func _set_seat_emote(seat_id: int, emote: String) -> void:
	if _table == null or seat_id < 0 or seat_id >= _table.seat_panels.size():
		return
	var sp: SeatPanel = _table.seat_panels[seat_id]
	if sp and sp.has_method("set_emote"):
		sp.set_emote(emote)


func _say_for_seat(seat_id: int, event_kind: String) -> void:
	if _table == null or seat_id < 0 or seat_id >= _table.seat_panels.size():
		return
	var sp: SeatPanel = _table.seat_panels[seat_id]
	if sp and sp.has_method("say_for_event"):
		sp.say_for_event(event_kind)


# 全屏白闪 — 短瞬覆盖全屏的半透明 ColorRect, tween alpha 1→0。
# 不阻塞其他事件,挂 self 顶层 z_index 让胡牌粒子之类不被遮。
# 弹本局牌谱回放 panel —— ScrollContainer 内显示所有关键 events 的中文摘要,
# 跟 PVP 战报一样让玩家可复盘 + 截图分享。父 overlay 仍在底,玩家关闭牌谱
# 就回到 hand_result_overlay。
func _show_replay_log(parent_overlay: Control) -> void:
	if _bc == null or _bc.events.is_empty():
		return
	var log_overlay := Control.new()
	log_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	log_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	parent_overlay.add_child(log_overlay)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(DT.BG_BASE.r, DT.BG_BASE.g, DT.BG_BASE.b, 0.92)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_overlay.add_child(bg)
	var panel := Panel.new()
	panel.position = Vector2(160, 60)
	panel.size = Vector2(960, 660)
	log_overlay.add_child(panel)
	DT.popin(panel)
	var title := Label.new()
	title.text = "📜 本局牌谱"
	title.position = Vector2(0, 16)
	title.size = Vector2(960, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", DT.FONT_SUBTITLE)
	title.add_theme_color_override("font_color", DT.TEXT_TITLE)
	panel.add_child(title)
	# Scroll 内放一长 Label。events 数十~百条,纯文本足够。
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(24, 72)
	scroll.size = Vector2(912, 520)
	panel.add_child(scroll)
	var log_label := Label.new()
	log_label.text = _format_event_log()
	log_label.add_theme_font_size_override("font_size", DT.FONT_CAPTION)
	log_label.add_theme_color_override("font_color", DT.TEXT_PRIMARY)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.custom_minimum_size = Vector2(880, 0)
	scroll.add_child(log_label)
	# 关闭按钮
	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.position = Vector2(400, 608)
	close_btn.custom_minimum_size = Vector2(160, 40)
	close_btn.pressed.connect(func(): log_overlay.queue_free())
	panel.add_child(close_btn)


# 把 _bc.events 转中文牌谱字串。每行一条事件,带 seat 名 + 牌名(若有)。
# 过滤噪音事件(PLAYER_ACTION 内部 kind="discard"/"draw" 已被 TILE_DRAWN/
# DISCARDED 表达,不重复显示)。
func _format_event_log() -> String:
	var lines: Array[String] = []
	var hand_no: int = 1
	for ev in _bc.events:
		var line: String = _format_one_event(ev, hand_no)
		if line == "":
			continue
		if ev.type == &"GAME_BEGIN":
			hand_no += 1
		lines.append(line)
	return "\n".join(lines)


func _format_one_event(ev: BattleEvent, _hand_no: int) -> String:
	if ev == null:
		return ""
	var who: String = _seat_short(ev.actor_seat)
	var tile_name: String = ""
	if ev.tile_instance != null:
		tile_name = CardTileBack.tile_short_name(ev.tile_instance.id)
	match ev.type:
		&"GAME_BEGIN":
			return "\n— 局开始 (庄家 %s) —" % who
		&"TILE_DRAWN":
			return ""  # 太密,不显
		&"TILE_DISCARDED":
			return "  %s 弃 %s" % [who, tile_name]
		&"RIICHI_DECLARED":
			return "  ⚡ %s 立直!" % who
		&"TSUMO_DECLARED":
			return "  🎯 %s 自摸 %s!" % [who, tile_name]
		&"RON_DECLARED":
			var ds: int = int(ev.extra.get("discarder_seat", -1))
			return "  🎯 %s 荣胡 %s (点炮: %s)" % [who, tile_name, _seat_short(ds)]
		&"WIN_DECLARED":
			var han: int = int(ev.extra.get("han", 0))
			var fu: int = int(ev.extra.get("fu", 0))
			var ym: int = int(ev.extra.get("yakuman_multiplier", 0))
			if ym > 0:
				return "    ⭐ 役満%s!" % ("" if ym == 1 else " x%d" % ym)
			return "    %d 飜 %d 符" % [han, fu]
		&"EXHAUSTIVE_DRAW":
			return "  — 流局 —"
		&"ABORTIVE_DRAW":
			var reason: String = String(ev.extra.get("reason", ""))
			return "  — 途中流局 (%s) —" % reason
		&"NAGASHI_MANGAN":
			return "  ✨ %s 流し満貫!" % who
		&"HAITEI":
			return "  🌊 海底捞月!"
		&"HOUTEI":
			return "  🌊 河底捞鱼!"
		&"PLAYER_ACTION":
			var kind: String = String(ev.extra.get("kind", ""))
			match kind:
				"chi": return "  %s 吃" % who
				"pon": return "  %s 碰" % who
				"minkan", "ankan", "added_kan": return "  %s 杠" % who
				"riichi": return ""  # RIICHI_DECLARED 已显
			return ""
		&"SKILL_TRIGGERED":
			var skill: String = String(ev.extra.get("skill_name", ""))
			return "    ⚡ 技能 %s (%s)" % [skill, who]
	return ""


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
	if _decision_adapter != null:
		_decision_adapter.on_hand_tile_clicked(tile_id)

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
				var hand_ids: Array = _bc.state.seats[0].hand.to_id_array()
				if hand_ids.size() > 0:
					_decision_adapter.on_hand_tile_clicked(int(hand_ids[0]))
		KEY_S:
			if _decision_adapter != null:
				_decision_adapter.submit_action({"action": "skip"})
		KEY_R:
			if _decision_adapter != null:
				_decision_adapter.submit_action({"action": "riichi_yes"})
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
