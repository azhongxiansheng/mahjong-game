class_name PlayerActionPanel extends Control

const TABLE_ACTION_BUTTON := preload(
	"res://ui/four_player_table/table_action_button.gd")

# 麻将王 — 玩家输入面板（plan: 战斗节点真实可玩 / Step 4）。
#
# 4 人桌底部的玩家命令栏。状态机（与 BC 决策顺序对齐 — 先切牌再问立直）：
#   IDLE                   非玩家回合（AI 出牌中），所有按钮 disabled
#   WAITING_DISCARD        玩家 14 张摸完，点手牌切 / 可选自摸 / 暗杠加杠
#   WAITING_RIICHI_CONFIRM 玩家刚切完牌，BC 算出可立直，问"立直/不立直"
#   WAITING_CLAIM          别家切牌，玩家可荣和/吃/碰/明杠/见逃
#
# TableDecisionAdapter 订阅 player_action_chosen，转成 PlayerDecisionPort 响应。

signal player_action_chosen(choice: Dictionary)
# choice schema:
#   {"action": "discard", "tile_instance_id": int}        — 切牌（entity identity）
#   {"action": "tsumo"}                                   — 自摸宣告
#   {"action": "riichi_yes"}                              — 立直确认（BC 调 declare_riichi）
#   {"action": "riichi_no"}                               — 立直跳过
#   {"action": "ron", "discarder_seat": int}              — 荣和宣告
#   {"action": "pon", "discarder_seat": int}              — 碰
#   {"action": "minkan", "discarder_seat": int}           — 明杠
#   {"action": "chi", "discarder_seat": int}              — 吃（仅下家）
#   {"action": "skip"}                                    — 见逃响应窗口
#   {"action": "claim_tile_pick", "tile_instance_id": int} — 吃/碰实体选择

enum State { IDLE, WAITING_DISCARD, WAITING_RIICHI_CONFIRM, WAITING_CLAIM, WAITING_KYUUSYU }

var _state: State = State.IDLE
var _claim_discarder_seat: int = -1

var _bg: ColorRect = null  # 仅在有按钮 visible 时才显示，避免遮挡桌面
var _ritual_band: Panel = null
var _label_status: Label = null
# 文本以 "…" 结尾时奏动画(. / .. / ...)循环让玩家感知 AI 在思考。
# Tween 在 enter_idle 设新文本时启停。
var _dots_tween: Tween = null
var _dots_base_text: String = ""
var _btn_riichi: Button = null     # WAITING_RIICHI_CONFIRM 用 — "立直"
var _btn_tsumo: Button = null      # WAITING_DISCARD 用 — "自摸"
var _btn_ron: Button = null        # WAITING_CLAIM 用 — "和"
var _btn_chi: Button = null        # WAITING_CLAIM 用 — "吃"（仅下家）
var _btn_pon: Button = null        # WAITING_CLAIM 用 — "碰"
var _btn_minkan: Button = null     # WAITING_CLAIM 用 — "杠"
var _btn_skip: Button = null       # WAITING_CLAIM/WAITING_RIICHI_CONFIRM 用 — "跳过"
var _btn_kyuusyu: Button = null    # WAITING_KYUUSYU 用 — "九种九牌"(途中流局)
var _btn_ankan: Button = null      # WAITING_DISCARD 用 — "暗杠"
var _btn_added_kan: Button = null  # WAITING_DISCARD 用 — "加杠"
var _btn_consumable: Button = null # WAITING_DISCARD 用 — "道具"（主动消耗品）

# 合法动作仪式带：仅显示当前可点按钮，HBox 居中。
# PlayableTable 定位在手牌正上方。
const PANEL_W: float = 720.0
const PANEL_H: float = 78.0
const BTN_W: float = 108.0
const BTN_H: float = 52.0

var _btn_bar: HBoxContainer = null

# 响应倒计时（秒，可测试时改短）
var CLAIM_TIMEOUT_SEC: float = 5.0
var RIICHI_TIMEOUT_SEC: float = 6.0
var KYUUSYU_TIMEOUT_SEC: float = 5.0
var _countdown_bar: ProgressBar = null
var _countdown_tween: Tween = null
var _countdown_active: bool = false
var _countdown_remaining: float = 0.0
var _countdown_total: float = 0.0
var _countdown_kind: StringName = &""  # claim / riichi / kyuusyu

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = Vector2(PANEL_W, PANEL_H)
	_build_ui()
	_sync_timeouts_from_settings()
	var sm = get_node_or_null("/root/SettingsManager")
	if sm and sm.has_signal("settings_changed"):
		if not sm.settings_changed.is_connected(_sync_timeouts_from_settings):
			sm.settings_changed.connect(_sync_timeouts_from_settings)
	_apply_state(State.IDLE)


func _sync_timeouts_from_settings() -> void:
	var sm = get_node_or_null("/root/SettingsManager")
	if sm == null:
		return
	if "claim_timeout_sec" in sm:
		CLAIM_TIMEOUT_SEC = float(sm.claim_timeout_sec)
		KYUUSYU_TIMEOUT_SEC = CLAIM_TIMEOUT_SEC
	if "riichi_timeout_sec" in sm:
		RIICHI_TIMEOUT_SEC = float(sm.riichi_timeout_sec)

func _build_ui() -> void:
	_ritual_band = Panel.new()
	_ritual_band.name = "RitualBand"
	_ritual_band.size = Vector2(PANEL_W, PANEL_H)
	_ritual_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ritual_band.visible = false
	var ritual_style := StyleBoxFlat.new()
	ritual_style.bg_color = Color(0.025, 0.035, 0.05, 0.10)
	ritual_style.border_color = Color.TRANSPARENT
	_ritual_band.add_theme_stylebox_override("panel", ritual_style)
	add_child(_ritual_band)

	# 居中胶囊底：只在有合法按钮时显示
	_bg = ColorRect.new()
	_bg.color = Color(DT.BG_BASE.r, DT.BG_BASE.g, DT.BG_BASE.b, 0.08)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.visible = false
	add_child(_bg)

	_label_status = Label.new()
	_label_status.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_label_status.offset_left = 8
	_label_status.offset_right = -8
	_label_status.offset_top = 2
	_label_status.offset_bottom = 26
	_label_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_status.add_theme_font_size_override("font_size", DT.FONT_BODY)
	_label_status.add_theme_color_override("font_color", DT.TEXT_PRIMARY)
	_label_status.add_theme_constant_override("shadow_offset_x", 1)
	_label_status.add_theme_constant_override("shadow_offset_y", 1)
	_label_status.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_label_status.text = "等待 AI..."
	add_child(_label_status)

	# 合法动作 HBox 居中
	_btn_bar = HBoxContainer.new()
	_btn_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_btn_bar.add_theme_constant_override("separation", 12)
	_btn_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_btn_bar.offset_top = 18
	_btn_bar.offset_bottom = -2
	_btn_bar.offset_left = 8
	_btn_bar.offset_right = -8
	add_child(_btn_bar)

	# 倒计时条（仪式带底部细条）
	_countdown_bar = ProgressBar.new()
	_countdown_bar.min_value = 0.0
	_countdown_bar.max_value = 1.0
	_countdown_bar.value = 1.0
	_countdown_bar.show_percentage = false
	_countdown_bar.custom_minimum_size = Vector2(200, 6)
	_countdown_bar.size = Vector2(200, 6)
	_countdown_bar.visible = false
	_countdown_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.95, 0.75, 0.25, 0.95)
	fill.corner_radius_top_left = 3
	fill.corner_radius_top_right = 3
	fill.corner_radius_bottom_left = 3
	fill.corner_radius_bottom_right = 3
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Color(0.15, 0.14, 0.16, 0.9)
	bg_sb.corner_radius_top_left = 3
	bg_sb.corner_radius_top_right = 3
	bg_sb.corner_radius_bottom_left = 3
	bg_sb.corner_radius_bottom_right = 3
	_countdown_bar.add_theme_stylebox_override("fill", fill)
	_countdown_bar.add_theme_stylebox_override("background", bg_sb)
	add_child(_countdown_bar)

	# 每种真实动作固定一套旗标色；内部 choice 协议保持不变。
	_btn_riichi = _make_btn("立直", &"riichi")
	_btn_tsumo = _make_btn("自摸", &"win")
	_btn_ron = _make_btn("和", &"win")
	_btn_chi = _make_btn("吃", &"chi")
	_btn_pon = _make_btn("碰", &"pon")
	_btn_minkan = _make_btn("杠", &"kan")
	_btn_kyuusyu = _make_btn("九种九牌", &"danger")
	_btn_kyuusyu.custom_minimum_size = Vector2(132, BTN_H)
	_btn_kyuusyu.pivot_offset = Vector2(66, BTN_H / 2.0)
	_btn_ankan = _make_btn("暗杠", &"kan")
	_btn_added_kan = _make_btn("加杠", &"kan")
	_btn_consumable = _make_btn("道具", &"item")
	_btn_skip = _make_btn("跳过", &"skip")

	_btn_riichi.pressed.connect(_on_btn_riichi)
	_btn_tsumo.pressed.connect(_on_btn_tsumo)
	_btn_ron.pressed.connect(_on_btn_ron)
	_btn_chi.pressed.connect(_on_btn_chi)
	_btn_pon.pressed.connect(_on_btn_pon)
	_btn_minkan.pressed.connect(_on_btn_minkan)
	_btn_kyuusyu.pressed.connect(_on_btn_kyuusyu)
	_btn_ankan.pressed.connect(_on_btn_ankan)
	_btn_added_kan.pressed.connect(_on_btn_added_kan)
	_btn_consumable.pressed.connect(_on_btn_consumable)
	_btn_skip.pressed.connect(_on_btn_skip)

func _make_btn(text: String, action_kind: StringName) -> Button:
	var btn: Button = TABLE_ACTION_BUTTON.new() as Button
	btn.custom_minimum_size = Vector2(BTN_W, BTN_H)
	btn.size = Vector2(BTN_W, BTN_H)
	btn.configure(text, action_kind)
	btn.disabled = true
	btn.visible = false
	btn.pivot_offset = Vector2(BTN_W / 2.0, BTN_H / 2.0)
	_btn_bar.add_child(btn)
	return btn

# 显示一个按钮（同时 enable）；其它代码用 enable_btn 替代 .disabled = false。
func _show_btn(btn: Button) -> void:
	btn.disabled = false
	btn.visible = true
	_refresh_bg()

func _hide_btn(btn: Button) -> void:
	btn.disabled = true
	btn.visible = false
	_refresh_bg()

# 任意按钮 visible 时显示居中胶囊底；按可见按钮数量收缩宽度。
func _refresh_bg() -> void:
	if _bg == null:
		return
	var n_vis := 0
	for btn in [_btn_riichi, _btn_tsumo, _btn_ron, _btn_chi, _btn_pon, _btn_minkan, _btn_kyuusyu, _btn_ankan, _btn_added_kan, _btn_consumable, _btn_skip]:
		if btn != null and btn.visible:
			n_vis += 1
	_bg.visible = n_vis > 0
	if _ritual_band != null:
		_ritual_band.visible = n_vis > 0
	if n_vis <= 0:
		return
	# 胶囊包住按钮区：status 行 + 按钮行
	var bar_w: float = n_vis * BTN_W + maxi(n_vis - 1, 0) * 12.0 + 32.0
	bar_w = clampf(bar_w, 160.0, PANEL_W)
	_bg.size = Vector2(bar_w, PANEL_H - 4)
	_bg.position = Vector2((PANEL_W - bar_w) / 2.0, 2)
	if _countdown_bar and _countdown_bar.visible:
		_countdown_bar.size = Vector2(maxf(bar_w - 24.0, 80.0), 6)
		_countdown_bar.position = Vector2((PANEL_W - _countdown_bar.size.x) / 2.0, PANEL_H - 10)


func is_countdown_active() -> bool:
	return _countdown_active


func get_countdown_remaining() -> float:
	return _countdown_remaining


func _start_countdown(seconds: float, kind: StringName) -> void:
	_stop_countdown(false)
	if seconds <= 0.0:
		return
	_countdown_kind = kind
	_countdown_total = seconds
	_countdown_remaining = seconds
	_countdown_active = true
	if _countdown_bar:
		_countdown_bar.visible = true
		_countdown_bar.value = 1.0
		_refresh_bg()
	_countdown_tween = create_tween()
	_countdown_tween.tween_method(_on_countdown_tick, seconds, 0.0, seconds)
	_countdown_tween.finished.connect(_on_countdown_finished)


func _on_countdown_tick(remain: float) -> void:
	_countdown_remaining = remain
	if _countdown_bar and _countdown_total > 0.0:
		_countdown_bar.value = remain / _countdown_total
		# 最后 1.5s 变红催促。
		if remain <= 1.5:
			var fill: StyleBoxFlat = _countdown_bar.get_theme_stylebox("fill") as StyleBoxFlat
			if fill:
				var f2 := fill.duplicate() as StyleBoxFlat
				f2.bg_color = Color(0.95, 0.30, 0.25, 0.95)
				_countdown_bar.add_theme_stylebox_override("fill", f2)


func _on_countdown_finished() -> void:
	if not _countdown_active:
		return
	var kind: StringName = _countdown_kind
	_stop_countdown(false)
	_click_sfx()
	match kind:
		&"claim":
			player_action_chosen.emit({"action": "skip"})
		&"riichi":
			player_action_chosen.emit({"action": "riichi_no"})
		&"kyuusyu":
			player_action_chosen.emit({"action": "kyuusyu_no"})
		_:
			player_action_chosen.emit({"action": "skip"})


# stop_emit=false：超时已处理；true：用户操作取消
func _stop_countdown(_user_cancel: bool = true) -> void:
	_countdown_active = false
	_countdown_remaining = 0.0
	_countdown_kind = &""
	if _countdown_tween and _countdown_tween.is_valid():
		_countdown_tween.kill()
	_countdown_tween = null
	if _countdown_bar:
		_countdown_bar.visible = false
		_countdown_bar.value = 1.0


# ---- 公开 API（TableDecisionAdapter 调） ----

# 进入"等玩家切牌"状态。can_tsumo 由 BC 的 _check_tsumo 算。
# 立直在切完牌之后再问（与 BC 决策顺序对齐），所以默认不显示立直按钮。
# #377：公共只读 TURN_PROMPT 可额外展示 RIICHI / KYUUSYU（末尾可选，既有调用兼容）。
func enter_waiting_discard(
	can_tsumo: bool,
	can_ankan: bool = false,
	can_added_kan: bool = false,
	_has_consumable: bool = false,
	can_riichi: bool = false,
	can_kyuusyu: bool = false
) -> void:
	_stop_dots_animation()
	_stop_countdown()
	_state = State.WAITING_DISCARD
	_label_status.text = "轮到你出牌（点手牌切）"
	if can_riichi:
		_show_btn(_btn_riichi)
	else:
		_hide_btn(_btn_riichi)
	if can_tsumo:
		_show_btn(_btn_tsumo)
		# 自摸是最高价值决策,pulse 一次防玩家漏看
		_pulse_attention(_btn_tsumo, 0.45)
	else:
		_hide_btn(_btn_tsumo)
	_hide_btn(_btn_ron)
	_hide_btn(_btn_chi)
	_hide_btn(_btn_pon)
	_hide_btn(_btn_minkan)
	if can_kyuusyu:
		_show_btn(_btn_kyuusyu)
	else:
		_hide_btn(_btn_kyuusyu)
	_hide_btn(_btn_skip)
	if can_ankan:
		_show_btn(_btn_ankan)
	else:
		_hide_btn(_btn_ankan)
	if can_added_kan:
		_show_btn(_btn_added_kan)
	else:
		_hide_btn(_btn_added_kan)
	# E2-02：ITEM_USE 未启用，生产按钮永久隐藏
	_hide_btn(_btn_consumable)

# 任意状态下更新提示文字（如喰い替え拒绝提示），不改按钮可见性。
func set_status_text(text: String) -> void:
	if _label_status:
		_label_status.text = text

# 进入"立直确认"状态：玩家刚切完牌，BC 算出可立直，弹按钮。
func enter_waiting_riichi_confirm() -> void:
	_stop_dots_animation()
	_state = State.WAITING_RIICHI_CONFIRM
	_label_status.text = "可立直 — 选择"
	_show_btn(_btn_riichi)
	_hide_btn(_btn_tsumo)
	_hide_btn(_btn_ron)
	_hide_btn(_btn_chi)
	_hide_btn(_btn_pon)
	_hide_btn(_btn_minkan)
	_hide_btn(_btn_kyuusyu)
	_hide_btn(_btn_ankan)
	_hide_btn(_btn_added_kan)
	_hide_btn(_btn_consumable)
	_show_btn(_btn_skip)  # = "不立直"
	_start_countdown(RIICHI_TIMEOUT_SEC, &"riichi")

# 进入"鸣牌响应"状态：别家切了一张牌，玩家可荣和/吃/碰/杠或见逃。
# 4 个 can_* 标志由战斗层算出，经 TableDecisionAdapter 传入。
func enter_waiting_claim(can_ron: bool, can_chi: bool, can_pon: bool, can_minkan: bool, discarder_seat: int) -> void:
	_stop_dots_animation()
	_state = State.WAITING_CLAIM
	_claim_discarder_seat = discarder_seat
	var hints: Array[String] = []
	if can_ron:
		hints.append("荣和")
	if can_chi:
		hints.append("吃")
	if can_pon:
		hints.append("碰")
	if can_minkan:
		hints.append("杠")
	if hints.size() > 0:
		_label_status.text = "可 %s — 选择" % "/".join(hints)
	else:
		_label_status.text = "等待响应窗口…"
	# 鸣牌窗口 = 全局停下等玩家,整栏脉冲一次确保被看到
	pivot_offset = Vector2(PANEL_W / 2.0, PANEL_H / 2.0)
	_pulse_attention(self, 0.45)
	_hide_btn(_btn_riichi)
	_hide_btn(_btn_tsumo)
	if can_ron:
		_show_btn(_btn_ron)
		# 荣和窗口稍纵即逝,pulse 提示
		_pulse_attention(_btn_ron, 0.45)
	else:
		_hide_btn(_btn_ron)
	if can_chi:
		_show_btn(_btn_chi)
	else:
		_hide_btn(_btn_chi)
	if can_pon:
		_show_btn(_btn_pon)
	else:
		_hide_btn(_btn_pon)
	if can_minkan:
		_show_btn(_btn_minkan)
	else:
		_hide_btn(_btn_minkan)
	_hide_btn(_btn_kyuusyu)
	_hide_btn(_btn_ankan)
	_hide_btn(_btn_added_kan)
	_hide_btn(_btn_consumable)
	_show_btn(_btn_skip)
	_start_countdown(CLAIM_TIMEOUT_SEC, &"claim")

# 进入"吃/碰实体选择"：手牌可点 claim_tile_pick；仅保留跳过，重启 claim 倒计时。
func enter_waiting_claim_pick() -> void:
	_stop_dots_animation()
	_state = State.WAITING_CLAIM
	_hide_btn(_btn_riichi)
	_hide_btn(_btn_tsumo)
	_hide_btn(_btn_ron)
	_hide_btn(_btn_chi)
	_hide_btn(_btn_pon)
	_hide_btn(_btn_minkan)
	_hide_btn(_btn_kyuusyu)
	_hide_btn(_btn_ankan)
	_hide_btn(_btn_added_kan)
	_hide_btn(_btn_consumable)
	_show_btn(_btn_skip)
	_start_countdown(CLAIM_TIMEOUT_SEC, &"claim")

# 进入"九種九牌"宣告状态:第一巡摸完后 14 张含 ≥ 9 种幺九,玩家可选途中流局。
func enter_waiting_kyuusyu() -> void:
	_stop_dots_animation()
	_state = State.WAITING_KYUUSYU
	_label_status.text = "九種九牌 — 宣告途中流局？"
	_hide_btn(_btn_riichi)
	_hide_btn(_btn_tsumo)
	_hide_btn(_btn_ron)
	_hide_btn(_btn_chi)
	_hide_btn(_btn_pon)
	_hide_btn(_btn_minkan)
	_hide_btn(_btn_ankan)
	_hide_btn(_btn_added_kan)
	_hide_btn(_btn_consumable)
	_show_btn(_btn_kyuusyu)
	_show_btn(_btn_skip)
	# 立直按钮使用本地脉冲，避免和普通鸣牌抢注意力。
	if _btn_kyuusyu:
		_pulse_attention(_btn_kyuusyu, 0.5)
	_start_countdown(KYUUSYU_TIMEOUT_SEC, &"kyuusyu")


func enter_idle(status_text: String = "等待 AI…") -> void:
	_stop_dots_animation()
	_stop_countdown()
	_state = State.IDLE
	_label_status.text = status_text
	_start_dots_animation_if_applicable(status_text)
	_hide_btn(_btn_riichi)
	_hide_btn(_btn_tsumo)
	_hide_btn(_btn_ron)
	_hide_btn(_btn_chi)
	_hide_btn(_btn_pon)
	_hide_btn(_btn_minkan)
	_hide_btn(_btn_kyuusyu)
	_hide_btn(_btn_ankan)
	_hide_btn(_btn_added_kan)
	_hide_btn(_btn_consumable)
	_hide_btn(_btn_skip)


# 若 status 以 "…" 或 "..." 结尾,周期性切换 "X" / "X." / "X.." / "X..." 让
# AI 思考状态有"活的"感觉。文本变化或离开 IDLE 时停。
func _start_dots_animation_if_applicable(text: String) -> void:
	_stop_dots_animation()
	# 检测尾部是否含省略符
	var base: String = text
	if text.ends_with("…"):
		base = text.substr(0, text.length() - 1)
	elif text.ends_with("..."):
		base = text.substr(0, text.length() - 3)
	else:
		return  # 非"思考中"风格文本,不动
	_dots_base_text = base
	# 循环 tween:0.4s 切一次,3 个状态轮换
	_dots_tween = create_tween().set_loops()
	_dots_tween.tween_callback(_set_dots.bind(1)).set_delay(0.0)
	_dots_tween.tween_callback(_set_dots.bind(2)).set_delay(0.4)
	_dots_tween.tween_callback(_set_dots.bind(3)).set_delay(0.4)
	_dots_tween.tween_callback(_set_dots.bind(0)).set_delay(0.4)


func _stop_dots_animation() -> void:
	if _dots_tween and _dots_tween.is_valid():
		_dots_tween.kill()
	_dots_tween = null


# 操作窗口的短促呼吸只使用节点自身 Tween，不依赖全局动画插件；
# Tween 与输入/决策信号并行，绝不成为业务门控。
func _pulse_attention(target: Control, duration: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var base := target.scale
	var tween := target.create_tween()
	tween.tween_property(target, "scale", base * 1.035, duration * 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(target, "scale", base, duration * 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _set_dots(n: int) -> void:
	if _label_status == null:
		return
	var suffix: String = "·".repeat(n) if n > 0 else ""
	_label_status.text = "%s%s" % [_dots_base_text, suffix]

func _apply_state(s: State) -> void:
	match s:
		State.IDLE: enter_idle()
		_: pass  # 其它状态由专门 enter_* 入口

# 内部:点 UI 按钮时奏 button_click SFX(autoload AudioManager 静默回退
# 若资源未生成 — 不影响测试 / 旧场景跑)。
func _click_sfx() -> void:
	var am = get_node_or_null("/root/AudioManager")
	if am != null:
		am.play("button_click", 0.04)


# ---- 玩家点击 hand 时由 PlayableTable 转发进来（参数 = tile_instance_id）----
func on_hand_tile_clicked(tile_instance_id: int) -> void:
	if _state == State.WAITING_DISCARD:
		_click_sfx()
		_emit_choice({"action": "discard", "tile_instance_id": tile_instance_id})
	elif _state == State.WAITING_CLAIM:
		# 吃/碰实体选择模式（多组合时 BC 把手牌设回 clickable 逐张选择）
		_click_sfx()
		_emit_choice({"action": "claim_tile_pick", "tile_instance_id": tile_instance_id})

# ---- 按钮回调 ----

func _emit_choice(choice: Dictionary) -> void:
	_stop_countdown()
	player_action_chosen.emit(choice)


func _on_btn_riichi() -> void:
	if _state == State.WAITING_RIICHI_CONFIRM:
		_click_sfx()
		_emit_choice({"action": "riichi_yes"})

func _on_btn_tsumo() -> void:
	if _state == State.WAITING_DISCARD:
		_click_sfx()
		_emit_choice({"action": "tsumo"})

func _on_btn_ron() -> void:
	if _state == State.WAITING_CLAIM:
		_click_sfx()
		_emit_choice({"action": "ron", "discarder_seat": _claim_discarder_seat})

func _on_btn_chi() -> void:
	if _state == State.WAITING_CLAIM:
		_click_sfx()
		_emit_choice({"action": "chi", "discarder_seat": _claim_discarder_seat})

func _on_btn_pon() -> void:
	if _state == State.WAITING_CLAIM:
		_click_sfx()
		_emit_choice({"action": "pon", "discarder_seat": _claim_discarder_seat})

func _on_btn_minkan() -> void:
	if _state == State.WAITING_CLAIM:
		_click_sfx()
		_emit_choice({"action": "minkan", "discarder_seat": _claim_discarder_seat})

func _on_btn_ankan() -> void:
	if _state == State.WAITING_DISCARD:
		_click_sfx()
		_emit_choice({"action": "ankan"})

func _on_btn_added_kan() -> void:
	if _state == State.WAITING_DISCARD:
		_click_sfx()
		_emit_choice({"action": "added_kan"})

func _on_btn_skip() -> void:
	_click_sfx()
	if _state == State.WAITING_RIICHI_CONFIRM:
		_emit_choice({"action": "riichi_no"})
	elif _state == State.WAITING_CLAIM:
		_emit_choice({"action": "skip"})
	elif _state == State.WAITING_KYUUSYU:
		_emit_choice({"action": "kyuusyu_no"})


func _on_btn_consumable() -> void:
	# E2-02：ITEM_USE NOT_ENABLED — 不产生 choice
	pass

func _on_btn_kyuusyu() -> void:
	if _state == State.WAITING_KYUUSYU:
		_click_sfx()
		_emit_choice({"action": "kyuusyu_yes"})
