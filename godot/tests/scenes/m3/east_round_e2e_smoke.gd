extends Control

# 麻将王 — 里程碑 3 第 4 步：东风战 e2e F6 烟测
#
# 把 GameDriver + BattleController + FourPlayerTable 串成一整场东风战：
#   按钮 "Run next hand"：driver.start_hand() → bc.run_to_end()
#     → driver.apply_result(events) → 流局走 WaitCalculator 算 tenpai
#     → driver.advance_or_finish(result) → 刷 UI
#   按钮 "Auto run all hands"：循环到 driver.finished
#   按钮 "Reset round"：重新 GameDriver.new(seed+1)
#
# 验收（plan-3 第 4 步）：
#   - sum(cumulative_scores) + riichi_sticks*1000 == 100000（每局后断言）
#   - 至少跑一次包含连庄/流局/胡牌混合的整场
#   - UI 4 家 SeatPanel 旋转 0/-90/180/+90 正确，CenterInfoPanel 显示局/Dora/牌墙

const FOUR_PLAYER_TABLE_SCENE := preload("res://ui/four_player_table/four_player_table.tscn")

var _driver: GameDriver = null
var _table: FourPlayerTable = null
var _status_label: Label = null
var _log_label: RichTextLabel = null
var _seed_offset: int = 42

func _ready() -> void:
	custom_minimum_size = Vector2(1280, 800)

	# 4 人桌
	_table = FOUR_PLAYER_TABLE_SCENE.instantiate()
	_table.position = Vector2(0, 80)
	add_child(_table)

	# 顶部按钮区
	var bar := HBoxContainer.new()
	bar.position = Vector2(10, 4)
	bar.add_theme_constant_override("separation", 12)
	add_child(bar)

	var btn_next := Button.new()
	btn_next.text = "Run next hand"
	btn_next.pressed.connect(_on_run_next_hand)
	bar.add_child(btn_next)

	var btn_auto := Button.new()
	btn_auto.text = "Auto run all hands"
	btn_auto.pressed.connect(_on_run_all_hands)
	bar.add_child(btn_auto)

	var btn_reset := Button.new()
	btn_reset.text = "Reset round (seed +1)"
	btn_reset.pressed.connect(_on_reset)
	bar.add_child(btn_reset)

	# 状态条
	_status_label = Label.new()
	_status_label.position = Vector2(10, 40)
	_status_label.size = Vector2(900, 30)
	add_child(_status_label)

	# 事件 log（右侧，可滚动）
	_log_label = RichTextLabel.new()
	_log_label.position = Vector2(1090, 0)
	_log_label.size = Vector2(190, 800)
	_log_label.bbcode_enabled = true
	_log_label.scroll_active = true
	_log_label.scroll_following = true
	add_child(_log_label)

	_init_driver()

# ---- driver lifecycle ----

func _init_driver() -> void:
	_driver = GameDriver.new(_seed_offset)
	_log_clear()
	_log_line("[color=cyan]新对局 seed=%d[/color]" % _seed_offset)
	_refresh_status()
	_refresh_table_no_battle()

func _on_reset() -> void:
	_seed_offset += 1
	_init_driver()

func _on_run_next_hand() -> void:
	if _driver.finished:
		_log_line("[color=yellow]整场已结束，请 Reset[/color]")
		return
	_run_one_hand()

func _on_run_all_hands() -> void:
	if _driver.finished:
		_log_line("[color=yellow]整场已结束，请 Reset[/color]")
		return
	while not _driver.finished:
		_run_one_hand()

func _run_one_hand() -> void:
	var hand_label: String = "东 %d 局 %d 本场" % [_driver.hand_index + 1, _driver.honba]
	_log_line("[color=cyan]>>> %s 开始[/color]" % hand_label)

	var bc := _driver.start_hand()
	var run_result := bc.run_to_end()

	# 先把当前局结束时的 BattleState 渲染上去（advance_or_finish 后 driver.battle 会清空）
	_table.bind_battle_state(bc.state, _driver.hand_index)

	var apply_res := _driver.apply_result(run_result.events)

	# 流局路径：调 WaitCalculator 给每家算 tenpai
	if apply_res.kind == "exhaustive_draw":
		var tenpai_array: Array = []
		for i in range(4):
			var seat: Seat = bc.state.seats[i]
			var typed_melds: Array[Meld] = []
			for m in seat.melds:
				typed_melds.append(m)
			var waits: Array = WaitCalculator.wait_tiles(seat.hand, typed_melds)
			tenpai_array.append(waits.size() > 0)
		apply_res["tenpai_array"] = tenpai_array

	var adv := _driver.advance_or_finish(apply_res)

	# 后置刷新：cumulative_scores（advance 已经更新）
	_table.bind_cumulative_scores(_driver.cumulative_scores)
	_refresh_status()

	# 详细 log
	var color := "green" if adv.renchan else "white"
	_log_line("[color=%s]<<< %s kind=%s%s[/color]" % [
		color, hand_label, adv.kind, " (连庄)" if adv.renchan else ""
	])
	_log_line("    scores=%s" % str(_driver.cumulative_scores))
	_log_line("    sticks=%d 守恒=%s" % [
		_driver.riichi_sticks, "✓" if _driver.is_score_conserved() else "✗"
	])
	if adv.finished:
		_log_line("[color=yellow]==== 整场结束 ====[/color]")
		_log_line("    最终 scores=%s" % str(_driver.cumulative_scores))

	# 守恒断言：失败则刷红色 log
	if not _driver.is_score_conserved():
		_log_line("[color=red]!! 守恒被破坏 !! sum=%d sticks=%d" % [
			_sum_scores(), _driver.riichi_sticks
		])

# ---- helpers ----

func _refresh_status() -> void:
	var hand_str := "东 %d 局 %d 本场" % [_driver.hand_index + 1, _driver.honba]
	if _driver.finished:
		hand_str = "整场结束"
	_status_label.text = "[%s] dealer=seat %d  scores=%s  sticks=%d  守恒=%s" % [
		hand_str,
		_driver.dealer_seat,
		str(_driver.cumulative_scores),
		_driver.riichi_sticks,
		"✓" if _driver.is_score_conserved() else "✗",
	]

# 当 driver.battle == null 时，把 4 panel 设为初始默认值
func _refresh_table_no_battle() -> void:
	for i in range(4):
		var sp: SeatPanel = _table.seat_panels[i]
		sp.set_seat_wind(_default_seat_wind(i, _driver.dealer_seat))
		sp.set_score(_driver.cumulative_scores[i])
		sp.set_hand_size(13)
		sp.set_meld_count(0)
		sp.set_discards_count(0)
		sp.set_riichi(false)
		sp.set_furiten(false)
	if _table.center_info:
		_table.center_info.set_hand_index(_driver.hand_index)
		_table.center_info.set_honba(_driver.honba)
		_table.center_info.set_dora_indicators([])
		_table.center_info.set_wall_remaining(70)
		_table.center_info.set_riichi_sticks(_driver.riichi_sticks)

# 自风按 dealer 偏移；helper 用 BattleState 的 _SEAT_WINDS 同款规则
static func _default_seat_wind(seat_id: int, dealer_seat: int) -> int:
	var seat_winds := [TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N]
	var relative := (seat_id - dealer_seat + 4) % 4
	return seat_winds[relative]

func _sum_scores() -> int:
	var s := 0
	for v in _driver.cumulative_scores:
		s += int(v)
	return s

# ---- log helpers ----

func _log_clear() -> void:
	if _log_label:
		_log_label.text = ""

func _log_line(s: String) -> void:
	if _log_label:
		_log_label.append_text(s + "\n")
