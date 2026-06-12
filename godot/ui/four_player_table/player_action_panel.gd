class_name PlayerActionPanel extends Control

# 麻将王 — 玩家输入面板（plan: 战斗节点真实可玩 / Step 4）。
#
# 4 人桌底部的玩家命令栏。状态机（与 BC 决策顺序对齐 — 先切牌再问立直）：
#   IDLE                   非玩家回合（AI 出牌中），所有按钮 disabled
#   WAITING_DISCARD        玩家 14 张摸完，点手牌切 / 可选自摸
#   WAITING_RIICHI_CONFIRM 玩家刚切完牌，BC 算出可立直，问"立直/不立直"
#   WAITING_CLAIM          别家切牌，玩家可荣和/见逃（v1 不支持吃碰杠）
#
# 上层（PlayableTable）订阅 player_action_chosen，await 后拿 dict 决定下一步。

signal player_action_chosen(choice: Dictionary)
# choice schema:
#   {"action": "discard", "tile_id": int}        — 切牌
#   {"action": "tsumo"}                          — 自摸宣告
#   {"action": "riichi_yes"}                     — 立直确认（BC 调 declare_riichi）
#   {"action": "riichi_no"}                      — 立直跳过
#   {"action": "ron", "discarder_seat": int}     — 荣和宣告
#   {"action": "pon", "discarder_seat": int}     — 碰
#   {"action": "minkan", "discarder_seat": int}  — 明杠
#   {"action": "chi", "discarder_seat": int}     — 吃（仅下家）
#   {"action": "skip"}                           — 见逃响应窗口
#   {"action": "claim_tile_pick", "tile_id": int} — 吃搭子选择（WAITING_CLAIM 点手牌）

enum State { IDLE, WAITING_DISCARD, WAITING_RIICHI_CONFIRM, WAITING_CLAIM, WAITING_KYUUSYU }

var _state: State = State.IDLE
var _claim_discarder_seat: int = -1

var _bg: ColorRect = null  # 仅在有按钮 visible 时才显示，避免遮挡桌面
var _label_status: Label = null
# 文本以 "…" 结尾时奏动画(. / .. / ...)循环让玩家感知 AI 在思考。
# Tween 在 enter_idle 设新文本时启停。
var _dots_tween: Tween = null
var _dots_base_text: String = ""
var _btn_riichi: Button = null     # WAITING_RIICHI_CONFIRM 用 — "立直"
var _btn_tsumo: Button = null      # WAITING_DISCARD 用 — "自摸"
var _btn_ron: Button = null        # WAITING_CLAIM 用 — "荣和"
var _btn_chi: Button = null        # WAITING_CLAIM 用 — "吃"（仅下家）
var _btn_pon: Button = null        # WAITING_CLAIM 用 — "碰"
var _btn_minkan: Button = null     # WAITING_CLAIM 用 — "杠"
var _btn_skip: Button = null       # WAITING_CLAIM/WAITING_RIICHI_CONFIRM 用 — "跳过"
var _btn_kyuusyu: Button = null    # WAITING_KYUUSYU 用 — "九種九牌"(途中流局)
var _btn_ankan: Button = null      # WAITING_DISCARD 用 — "暗杠"
var _btn_added_kan: Button = null  # WAITING_DISCARD 用 — "加杠"
var _btn_consumable: Button = null # WAITING_DISCARD 用 — "道具"（主动消耗品）

# 2026-06-13 重做:按钮 60×40→84×48、20 号字,操作栏从桌外底条上移到
# 手牌正上方(PlayableTable 定位)— 鸣牌窗口打开时全局在等玩家,旧版小按钮
# 在视线外,玩家以为卡死(对标参考作 action-bar 浮在手牌上方)。
const PANEL_W: float = 1036.0  # 11 槽 × 92 间距
const PANEL_H: float = 84.0    # status 4-24 + buttons 28-76

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	_build_ui()
	_apply_state(State.IDLE)

func _build_ui() -> void:
	# Bg 半透明仅在有按钮时显示，避免空状态遮挡桌面
	_bg = ColorRect.new()
	_bg.color = Color(DT.BG_BASE.r, DT.BG_BASE.g, DT.BG_BASE.b, 0.9)
	_bg.size = Vector2(PANEL_W, PANEL_H)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.visible = false  # IDLE/WAITING_DISCARD 默认隐藏
	add_child(_bg)

	# Status 文字浮在桌面（无 bg），所有状态都可见
	_label_status = Label.new()
	_label_status.position = Vector2(12, 2)
	_label_status.size = Vector2(PANEL_W - 24, 22)
	_label_status.add_theme_font_size_override("font_size", DT.FONT_CAPTION)
	_label_status.add_theme_color_override("font_color", DT.TEXT_PRIMARY)
	# 加文字阴影让浮在桌面上更易读
	_label_status.add_theme_constant_override("shadow_offset_x", 1)
	_label_status.add_theme_constant_override("shadow_offset_y", 1)
	_label_status.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_label_status.text = "等待 AI..."
	add_child(_label_status)

	# 7 个按钮一排：立直 / 自摸 / 荣和 / 吃 / 碰 / 杠 / 跳过（PANEL_H 80 紧凑版）
	# 按动作类型染色,玩家从一组按钮中第一眼分辨"什么动作":
	# 蓝=立直(策略宣告)、金=自摸/荣和(胜利)、红=鸣牌(进攻)、紫=途中流局(规则牌)、灰=跳过(中性)
	_btn_riichi = _make_btn("立直", 12, 28, Color(0.30, 0.55, 0.85))
	_btn_tsumo = _make_btn("自摸", 12 + 92, 28, DT.TEXT_TITLE)
	_btn_ron = _make_btn("荣和", 12 + 184, 28, DT.TEXT_TITLE)
	_btn_chi = _make_btn("吃", 12 + 276, 28, DT.TEXT_DANGER)
	_btn_pon = _make_btn("碰", 12 + 368, 28, DT.TEXT_DANGER)
	_btn_minkan = _make_btn("杠", 12 + 460, 28, DT.TEXT_DANGER)
	_btn_kyuusyu = _make_btn("九種", 12 + 552, 28, Color(0.65, 0.30, 0.85))
	_btn_ankan = _make_btn("暗杠", 12 + 644, 28, Color(0.85, 0.50, 0.15))
	_btn_added_kan = _make_btn("加杠", 12 + 736, 28, Color(0.85, 0.50, 0.15))
	_btn_consumable = _make_btn("道具", 12 + 828, 28, Color(0.95, 0.60, 0.15))
	_btn_skip = _make_btn("跳过", 12 + 920, 28, DT.TEXT_MUTED)

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

func _make_btn(text: String, x: float, y: float = 20.0, accent: Color = Color(0.55, 0.55, 0.55)) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.position = Vector2(x, y)
	btn.size = Vector2(84, 48)  # 大按钮:鸣牌窗口是全局等待点,必须一眼看到
	btn.add_theme_font_size_override("font_size", 20)
	btn.disabled = true
	btn.visible = false  # 雀魂式：只在触发时才显示
	btn.pivot_offset = btn.size / 2.0  # pulse 缩放动效从中心起
	# 用动作色覆盖 4 态 stylebox border,让玩家一眼分辨动作类型。
	for state in ["normal", "hover", "pressed", "focus"]:
		var base: StyleBoxFlat = btn.get_theme_stylebox(state) as StyleBoxFlat
		var sb: StyleBoxFlat = base.duplicate() if base else StyleBoxFlat.new()
		sb.border_color = accent
		sb.border_width_left = 3
		sb.border_width_right = 3
		sb.border_width_top = 3
		sb.border_width_bottom = 3
		btn.add_theme_stylebox_override(state, sb)
	add_child(btn)
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

# 任意按钮 visible 时显示 bg，全 invisible 时隐藏避免遮挡桌面
func _refresh_bg() -> void:
	if _bg == null:
		return
	var any_btn_visible := false
	for btn in [_btn_riichi, _btn_tsumo, _btn_ron, _btn_chi, _btn_pon, _btn_minkan, _btn_kyuusyu, _btn_ankan, _btn_added_kan, _btn_consumable, _btn_skip]:
		if btn != null and btn.visible:
			any_btn_visible = true
			break
	_bg.visible = any_btn_visible

# ---- 公开 API（PlayableTable / PlayableBattleController 调） ----

# 进入"等玩家切牌"状态。can_tsumo 由 BC 的 _check_tsumo 算。
# 立直在切完牌之后再问（与 BC 决策顺序对齐），所以这里不显示立直按钮。
func enter_waiting_discard(can_tsumo: bool, can_ankan: bool = false, can_added_kan: bool = false, has_consumable: bool = false) -> void:
	_state = State.WAITING_DISCARD
	_label_status.text = "轮到你出牌（点手牌切）"
	_hide_btn(_btn_riichi)
	if can_tsumo:
		_show_btn(_btn_tsumo)
		# 自摸是最高价值决策,pulse 一次防玩家漏看
		DT.attention(_btn_tsumo, "pulse", 0.45)
	else:
		_hide_btn(_btn_tsumo)
	_hide_btn(_btn_ron)
	_hide_btn(_btn_chi)
	_hide_btn(_btn_pon)
	_hide_btn(_btn_minkan)
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
	if has_consumable:
		_show_btn(_btn_consumable)
	else:
		_hide_btn(_btn_consumable)

# 任意状态下更新提示文字（如喰い替え拒绝提示），不改按钮可见性。
func set_status_text(text: String) -> void:
	if _label_status:
		_label_status.text = text

# 进入"立直确认"状态：玩家刚切完牌，BC 算出可立直，弹按钮。
func enter_waiting_riichi_confirm() -> void:
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

# 进入"鸣牌响应"状态：别家切了一张牌，玩家可荣和/吃/碰/杠或见逃。
# 4 个 can_* 标志由 PlayableBattleController 算出（ClaimValidator）。
func enter_waiting_claim(can_ron: bool, can_chi: bool, can_pon: bool, can_minkan: bool, discarder_seat: int) -> void:
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
	DT.attention(self, "pulse", 0.45)
	_hide_btn(_btn_riichi)
	_hide_btn(_btn_tsumo)
	if can_ron:
		_show_btn(_btn_ron)
		# 荣和窗口稍纵即逝,pulse 提示
		DT.attention(_btn_ron, "pulse", 0.45)
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

# 进入"九種九牌"宣告状态:第一巡摸完后 14 张含 ≥ 9 种幺九,玩家可选途中流局。
func enter_waiting_kyuusyu() -> void:
	_state = State.WAITING_KYUUSYU
	_label_status.text = "可宣告九種九牌(途中流局)— 选择"
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


func enter_idle(status_text: String = "等待 AI…") -> void:
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
	if _dots_tween and _dots_tween.is_valid():
		_dots_tween.kill()
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


# ---- 玩家点击 hand 时由 PlayableTable 转发进来 ----
func on_hand_tile_clicked(tile_id: int) -> void:
	if _state == State.WAITING_DISCARD:
		_click_sfx()
		player_action_chosen.emit({"action": "discard", "tile_id": tile_id})
	elif _state == State.WAITING_CLAIM:
		# 吃搭子选择模式（多组合时 BC 把手牌设回 clickable 等玩家点搭子）
		_click_sfx()
		player_action_chosen.emit({"action": "claim_tile_pick", "tile_id": tile_id})

# ---- 按钮回调 ----

func _on_btn_riichi() -> void:
	if _state == State.WAITING_RIICHI_CONFIRM:
		_click_sfx()
		player_action_chosen.emit({"action": "riichi_yes"})

func _on_btn_tsumo() -> void:
	if _state == State.WAITING_DISCARD:
		_click_sfx()
		player_action_chosen.emit({"action": "tsumo"})

func _on_btn_ron() -> void:
	if _state == State.WAITING_CLAIM:
		_click_sfx()
		player_action_chosen.emit({"action": "ron", "discarder_seat": _claim_discarder_seat})

func _on_btn_chi() -> void:
	if _state == State.WAITING_CLAIM:
		_click_sfx()
		player_action_chosen.emit({"action": "chi", "discarder_seat": _claim_discarder_seat})

func _on_btn_pon() -> void:
	if _state == State.WAITING_CLAIM:
		_click_sfx()
		player_action_chosen.emit({"action": "pon", "discarder_seat": _claim_discarder_seat})

func _on_btn_minkan() -> void:
	if _state == State.WAITING_CLAIM:
		_click_sfx()
		player_action_chosen.emit({"action": "minkan", "discarder_seat": _claim_discarder_seat})

func _on_btn_ankan() -> void:
	if _state == State.WAITING_DISCARD:
		_click_sfx()
		player_action_chosen.emit({"action": "ankan"})

func _on_btn_added_kan() -> void:
	if _state == State.WAITING_DISCARD:
		_click_sfx()
		player_action_chosen.emit({"action": "added_kan"})

func _on_btn_skip() -> void:
	_click_sfx()
	if _state == State.WAITING_RIICHI_CONFIRM:
		player_action_chosen.emit({"action": "riichi_no"})
	elif _state == State.WAITING_CLAIM:
		player_action_chosen.emit({"action": "skip"})
	elif _state == State.WAITING_KYUUSYU:
		player_action_chosen.emit({"action": "kyuusyu_no"})


func _on_btn_consumable() -> void:
	if _state == State.WAITING_DISCARD:
		_click_sfx()
		player_action_chosen.emit({"action": "use_consumable"})

func _on_btn_kyuusyu() -> void:
	if _state == State.WAITING_KYUUSYU:
		_click_sfx()
		player_action_chosen.emit({"action": "kyuusyu_yes"})
