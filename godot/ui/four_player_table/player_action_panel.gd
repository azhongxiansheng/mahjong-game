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

enum State { IDLE, WAITING_DISCARD, WAITING_RIICHI_CONFIRM, WAITING_CLAIM }

var _state: State = State.IDLE
var _claim_discarder_seat: int = -1

var _label_status: Label = null
var _btn_riichi: Button = null     # WAITING_RIICHI_CONFIRM 用 — "立直"
var _btn_tsumo: Button = null      # WAITING_DISCARD 用 — "自摸"
var _btn_ron: Button = null        # WAITING_CLAIM 用 — "荣和"
var _btn_chi: Button = null        # WAITING_CLAIM 用 — "吃"（仅下家）
var _btn_pon: Button = null        # WAITING_CLAIM 用 — "碰"
var _btn_minkan: Button = null     # WAITING_CLAIM 用 — "杠"
var _btn_skip: Button = null       # WAITING_CLAIM/WAITING_RIICHI_CONFIRM 用 — "跳过"

const PANEL_W: float = 480.0  # 容纳 7 个按钮（立直/自摸/荣/吃/碰/杠/跳过）
const PANEL_H: float = 110.0

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	_build_ui()
	_apply_state(State.IDLE)

func _build_ui() -> void:
	# 雀魂式：右下角悬浮 280×110 紧凑面板（不再底部全宽长条）
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.10, 0.85)
	bg.size = Vector2(PANEL_W, PANEL_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_label_status = Label.new()
	_label_status.position = Vector2(12, 8)
	_label_status.size = Vector2(PANEL_W - 24, 24)
	_label_status.add_theme_font_size_override("font_size", 14)
	_label_status.add_theme_color_override("font_color", Color(0.95, 0.95, 0.85))
	_label_status.text = "等待 AI..."
	add_child(_label_status)

	# 7 个按钮一排：立直 / 自摸 / 荣和 / 吃 / 碰 / 杠 / 跳过
	_btn_riichi = _make_btn("立直", 12, 36)
	_btn_tsumo = _make_btn("自摸", 12 + 66, 36)
	_btn_ron = _make_btn("荣和", 12 + 132, 36)
	_btn_chi = _make_btn("吃", 12 + 198, 36)
	_btn_pon = _make_btn("碰", 12 + 264, 36)
	_btn_minkan = _make_btn("杠", 12 + 330, 36)
	_btn_skip = _make_btn("跳过", 12 + 396, 36)

	_btn_riichi.pressed.connect(_on_btn_riichi)
	_btn_tsumo.pressed.connect(_on_btn_tsumo)
	_btn_ron.pressed.connect(_on_btn_ron)
	_btn_chi.pressed.connect(_on_btn_chi)
	_btn_pon.pressed.connect(_on_btn_pon)
	_btn_minkan.pressed.connect(_on_btn_minkan)
	_btn_skip.pressed.connect(_on_btn_skip)

func _make_btn(text: String, x: float, y: float = 20.0) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.position = Vector2(x, y)
	btn.size = Vector2(60, 60)
	btn.add_theme_font_size_override("font_size", 16)
	btn.disabled = true
	btn.visible = false  # 雀魂式：只在触发时才显示
	add_child(btn)
	return btn

# 显示一个按钮（同时 enable）；其它代码用 enable_btn 替代 .disabled = false。
func _show_btn(btn: Button) -> void:
	btn.disabled = false
	btn.visible = true

func _hide_btn(btn: Button) -> void:
	btn.disabled = true
	btn.visible = false

# ---- 公开 API（PlayableTable / PlayableBattleController 调） ----

# 进入"等玩家切牌"状态。can_tsumo 由 BC 的 _check_tsumo 算。
# 立直在切完牌之后再问（与 BC 决策顺序对齐），所以这里不显示立直按钮。
func enter_waiting_discard(can_tsumo: bool) -> void:
	_state = State.WAITING_DISCARD
	_label_status.text = "轮到你出牌（点手牌切）"
	_hide_btn(_btn_riichi)
	if can_tsumo:
		_show_btn(_btn_tsumo)
	else:
		_hide_btn(_btn_tsumo)
	_hide_btn(_btn_ron)
	_hide_btn(_btn_chi)
	_hide_btn(_btn_pon)
	_hide_btn(_btn_minkan)
	_hide_btn(_btn_skip)

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
	_hide_btn(_btn_riichi)
	_hide_btn(_btn_tsumo)
	if can_ron:
		_show_btn(_btn_ron)
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
	_show_btn(_btn_skip)

func enter_idle(status_text: String = "等待 AI...") -> void:
	_state = State.IDLE
	_label_status.text = status_text
	_hide_btn(_btn_riichi)
	_hide_btn(_btn_tsumo)
	_hide_btn(_btn_ron)
	_hide_btn(_btn_chi)
	_hide_btn(_btn_pon)
	_hide_btn(_btn_minkan)
	_hide_btn(_btn_skip)

func _apply_state(s: State) -> void:
	match s:
		State.IDLE: enter_idle()
		_: pass  # 其它状态由专门 enter_* 入口

# ---- 玩家点击 hand 时由 PlayableTable 转发进来 ----
func on_hand_tile_clicked(tile_id: int) -> void:
	if _state == State.WAITING_DISCARD:
		player_action_chosen.emit({"action": "discard", "tile_id": tile_id})

# ---- 按钮回调 ----

func _on_btn_riichi() -> void:
	if _state == State.WAITING_RIICHI_CONFIRM:
		player_action_chosen.emit({"action": "riichi_yes"})

func _on_btn_tsumo() -> void:
	if _state == State.WAITING_DISCARD:
		player_action_chosen.emit({"action": "tsumo"})

func _on_btn_ron() -> void:
	if _state == State.WAITING_CLAIM:
		player_action_chosen.emit({"action": "ron", "discarder_seat": _claim_discarder_seat})

func _on_btn_chi() -> void:
	if _state == State.WAITING_CLAIM:
		player_action_chosen.emit({"action": "chi", "discarder_seat": _claim_discarder_seat})

func _on_btn_pon() -> void:
	if _state == State.WAITING_CLAIM:
		player_action_chosen.emit({"action": "pon", "discarder_seat": _claim_discarder_seat})

func _on_btn_minkan() -> void:
	if _state == State.WAITING_CLAIM:
		player_action_chosen.emit({"action": "minkan", "discarder_seat": _claim_discarder_seat})

func _on_btn_skip() -> void:
	if _state == State.WAITING_RIICHI_CONFIRM:
		player_action_chosen.emit({"action": "riichi_no"})
	elif _state == State.WAITING_CLAIM:
		player_action_chosen.emit({"action": "skip"})
