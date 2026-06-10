extends GutTest

# 玩家自杠（暗杠/加杠）流程回归测试。
#
# 修复的 bug 群（2026-06-10）：
#   P0: _get_discard_decision 暗杠/加杠后 return null 被 _step_discard_async
#       当"本局结束"（_settled=true）— 玩家一开杠整局直接终止。
#   P1: _step_draw_async 末尾 _try_ai_self_kan 对玩家 seat 0 也生效，
#       HeuristicAi"能杠就杠"替玩家自动开杠。
#   P1: _should_accept_tsumo（自摸窗口）显示暗杠/加杠按钮但 while 循环
#       不处理这两个 action — 死按钮。
#   P1: 玩家吃/碰后喰い替え限制无 enforcement（只有 AI 路径规避）。
#
# 用真实 PlayerActionPanel（入树跑 _ready 建按钮）+ 裸 SeatPanel
# （set_hand_clickable 对未建 row 是 null 安全的）。

var _bc: PlayableBattleController
var _panel: PlayerActionPanel
var _sp: SeatPanel

# 4×W1 可暗杠 + 10 张孤张杂牌（岭上摸任何牌都不可能胡 → 流程必回切牌等待）
const HAND_WITH_QUAD: Array = [
	TileId.W1, TileId.W1, TileId.W1, TileId.W1,
	TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
	TileId.HAKU, TileId.HATSU, TileId.CHUN,
	TileId.T1, TileId.T9, TileId.S1,
]

func before_each() -> void:
	_bc = PlayableBattleController.new(42, 0, false)
	_bc.set_ai_think_delay(0.0)
	_panel = PlayerActionPanel.new()
	add_child_autofree(_panel)
	_sp = SeatPanel.new()
	autofree(_sp)
	_bc.bind_ui(_panel, _sp, get_tree())

func _set_hand(seat: Seat, ids: Array) -> void:
	seat.hand._tiles.clear()
	for id in ids:
		seat.hand.add(Tile.new(id))

# ---- P0：暗杠后本局不应结束 ----

func test_player_ankan_in_discard_window_does_not_end_hand() -> void:
	var seat: Seat = _bc.state.seats[0]
	_set_hand(seat, HAND_WITH_QUAD)
	_bc.state.current_seat = 0
	_bc.state.phase = BattlePhase.Kind.DISCARD
	var done := {}
	var runner := func():
		await _bc._step_discard_async()
		done["finished"] = true
	runner.call()
	# 控制器此时 await player_action_chosen；点"暗杠"
	_panel.player_action_chosen.emit({"action": "ankan"})
	await wait_physics_frames(2)
	assert_eq(seat.melds.size(), 1, "暗杠 meld 应成立")
	assert_eq(seat.melds[0].kind, Meld.Kind.ANKAN)
	assert_false(_bc._settled, "暗杠后本局不应结束（修复前 P0：直接 settle）")
	assert_false(done.has("finished"), "_step_discard_async 应继续等玩家切牌")
	# 杠后已摸岭上（10 杂张 + 1 岭上 = 11 张），切一张完成本步
	var tid: int = int(seat.hand.to_id_array()[0])
	_panel.player_action_chosen.emit({"action": "discard", "tile_id": tid})
	await wait_physics_frames(2)
	assert_true(done.has("finished"), "切牌后 _step_discard_async 应完成")
	assert_false(_bc._settled, "正常切牌收尾，本局继续")
	assert_eq(_bc.state.discards_per_seat[0].size(), 1, "弃牌入河")

# ---- P1：自摸窗口暗杠按钮曾被静默忽略 ----

func test_tsumo_window_ankan_applies_and_continues() -> void:
	var seat: Seat = _bc.state.seats[0]
	_set_hand(seat, HAND_WITH_QUAD)
	_bc.state.current_seat = 0
	var result := {}
	var co := func():
		result["accept"] = await _bc._should_accept_tsumo(0, Tile.new(TileId.W1), {})
	co.call()
	_panel.player_action_chosen.emit({"action": "ankan"})
	await wait_physics_frames(2)
	assert_eq(seat.melds.size(), 1, "自摸窗口点暗杠应成立（修复前被静默忽略）")
	assert_false(result.has("accept"), "杠后窗口继续等玩家选择")
	var tid: int = int(seat.hand.to_id_array()[0])
	_panel.player_action_chosen.emit({"action": "discard", "tile_id": tid})
	await wait_physics_frames(2)
	assert_true(result.has("accept"), "选切牌后窗口应返回")
	assert_false(bool(result["accept"]), "杠 + 切牌路径拒绝原 tsumo")
	assert_false(_bc._settled, "本局继续")
	assert_eq(_bc._pending_discard_tile_id, tid, "切牌选择缓存给 _get_discard_decision")

# ---- P1：HeuristicAi 不再替玩家自动开杠 ----

func test_ai_does_not_auto_kan_player_seat_when_ui_bound() -> void:
	var bc2 := PlayableBattleController.new(7, 0, true)  # HeuristicAi 能杠就杠
	bc2.bind_ui(_panel, _sp, get_tree())
	var seat: Seat = bc2.state.seats[0]
	_set_hand(seat, HAND_WITH_QUAD)
	bc2.state.current_seat = 0
	bc2._try_ai_self_kan()
	assert_eq(seat.melds.size(), 0, "UI 绑定时玩家 seat 不被 AI 自动开杠")

func test_ai_self_kan_still_works_for_ai_seats() -> void:
	var bc2 := PlayableBattleController.new(7, 0, true)
	bc2.bind_ui(_panel, _sp, get_tree())
	var seat1: Seat = bc2.state.seats[1]
	_set_hand(seat1, HAND_WITH_QUAD)
	bc2.state.current_seat = 1
	bc2._try_ai_self_kan()
	assert_eq(seat1.melds.size(), 1, "AI seat 照常自动杠")
	assert_eq(seat1.melds[0].kind, Meld.Kind.ANKAN)

func test_ai_auto_kan_preserved_without_ui_binding() -> void:
	# 纯 AI 仿真（BattleNodeRunner / GUT e2e）不 bind UI → 父类行为保留
	var bc3 := PlayableBattleController.new(7, 0, true)
	var seat: Seat = bc3.state.seats[0]
	_set_hand(seat, HAND_WITH_QUAD)
	bc3.state.current_seat = 0
	bc3._try_ai_self_kan()
	assert_eq(seat.melds.size(), 1, "无 UI 时保留 AI 自动杠（仿真路径）")

# ---- 立直中保守禁暗杠/加杠 ----

func test_player_ankan_candidates_blocked_during_riichi() -> void:
	var seat: Seat = _bc.state.seats[0]
	_set_hand(seat, HAND_WITH_QUAD)
	assert_false(_bc._player_ankan_candidates(seat).is_empty(), "非立直可暗杠")
	seat.riichi.declare(0, false)
	assert_true(_bc._player_ankan_candidates(seat).is_empty(),
		"立直中保守禁暗杠（v1 不做不变听判定，与 AI decide_self_kan 一致）")

func test_player_added_kan_blocked_during_riichi() -> void:
	var seat: Seat = _bc.state.seats[0]
	seat.riichi.declare(0, false)
	assert_eq(_bc._player_added_kan_tile_id(seat), -1, "立直锁手牌，恒不可加杠")

# ---- 吃搭子交互选择（多组合时点手牌选；修复前永远取第一组） ----

# 玩家手 W1 W2 W4 W5，上家弃 W3 → 三组候选 [W1,W2]/[W2,W4]/[W4,W5]
const HAND_CHI_MULTI: Array = [
	TileId.W1, TileId.W2, TileId.W4, TileId.W5,
	TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
	TileId.HAKU, TileId.HATSU, TileId.CHUN, TileId.T1, TileId.S1,
]

func _setup_chi_claim(hand_ids: Array) -> Tile:
	var seat: Seat = _bc.state.seats[0]
	_set_hand(seat, hand_ids)
	var discarded := Tile.new(TileId.W3)
	# apply_chi 从 discards_per_seat[current_seat] pop 被鸣牌 → 模拟上家(3)刚弃
	_bc.state.current_seat = 3
	_bc.state.discards_per_seat[3].append(discarded)
	return discarded

func test_chi_multi_option_player_picks_companion() -> void:
	var discarded := _setup_chi_claim(HAND_CHI_MULTI)
	var done := {}
	var runner := func():
		await _bc._try_player_claim_async(discarded, 3)
		done["finished"] = true
	runner.call()
	_panel.player_action_chosen.emit({"action": "chi"})
	await wait_physics_frames(1)
	assert_false(done.has("finished"), "多组候选应进入搭子选择,不直接成立")
	# 点 W5 → 唯一含 W5 的组合 [W4,W5]
	_panel.player_action_chosen.emit({"action": "claim_tile_pick", "tile_id": TileId.W5})
	await wait_physics_frames(1)
	assert_true(done.has("finished"))
	var seat: Seat = _bc.state.seats[0]
	assert_eq(seat.melds.size(), 1, "吃成立")
	assert_eq(seat.melds[0].kind, Meld.Kind.CHI)
	var meld_ids: Array = []
	for t in seat.melds[0].tiles:
		meld_ids.append(int(t.id))
	meld_ids.sort()
	assert_eq(meld_ids, [TileId.W3, TileId.W4, TileId.W5], "选定 [W4,W5] 组合而非第一组")
	assert_false(_bc.state.kuikae_restricted[0].is_empty(), "喰い替え限制已设置")

func test_chi_picker_rejects_non_candidate_then_accepts() -> void:
	var discarded := _setup_chi_claim(HAND_CHI_MULTI)
	var done := {}
	var runner := func():
		await _bc._try_player_claim_async(discarded, 3)
		done["finished"] = true
	runner.call()
	_panel.player_action_chosen.emit({"action": "chi"})
	# 点不是候选搭子的 E → 拒绝继续等
	_panel.player_action_chosen.emit({"action": "claim_tile_pick", "tile_id": TileId.E})
	await wait_physics_frames(1)
	assert_false(done.has("finished"), "非候选牌不应选定")
	_panel.player_action_chosen.emit({"action": "claim_tile_pick", "tile_id": TileId.W1})
	await wait_physics_frames(1)
	assert_true(done.has("finished"))
	assert_eq(_bc.state.seats[0].melds.size(), 1, "改点 W1 → [W1,W2] 成立")

func test_chi_picker_skip_cancels_back_to_claim_window() -> void:
	var discarded := _setup_chi_claim(HAND_CHI_MULTI)
	var done := {}
	var runner := func():
		await _bc._try_player_claim_async(discarded, 3)
		done["finished"] = true
	runner.call()
	_panel.player_action_chosen.emit({"action": "chi"})
	_panel.player_action_chosen.emit({"action": "skip"})  # 取消搭子选择 → 回鸣牌窗
	await wait_physics_frames(1)
	assert_false(done.has("finished"), "取消搭子选择应回到鸣牌窗口")
	assert_eq(_bc.state.seats[0].melds.size(), 0)
	_panel.player_action_chosen.emit({"action": "skip"})  # 鸣牌窗口跳过 → 结束
	await wait_physics_frames(1)
	assert_true(done.has("finished"))
	assert_eq(_bc.state.seats[0].melds.size(), 0, "全程未吃")

func test_chi_single_option_applies_directly() -> void:
	# 只有 [W1,W2] 一组 → 不进选择模式直接成立
	var discarded := _setup_chi_claim([
		TileId.W1, TileId.W2,
		TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
		TileId.HAKU, TileId.HATSU, TileId.CHUN,
		TileId.T1, TileId.T9, TileId.S1, TileId.S9,
	])
	var done := {}
	var runner := func():
		await _bc._try_player_claim_async(discarded, 3)
		done["finished"] = true
	runner.call()
	_panel.player_action_chosen.emit({"action": "chi"})
	await wait_physics_frames(1)
	assert_true(done.has("finished"), "单组候选直接成立")
	assert_eq(_bc.state.seats[0].melds.size(), 1)
	assert_eq(_bc.state.seats[0].melds[0].kind, Meld.Kind.CHI)

# ---- P1：喰い替え enforcement ----

func test_player_kuikae_restricted_discard_rejected() -> void:
	var seat: Seat = _bc.state.seats[0]
	# 无四连张的杂牌手（避免暗杠按钮干扰），含 T1
	_set_hand(seat, [
		TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
		TileId.HAKU, TileId.HATSU, TileId.CHUN,
		TileId.T1, TileId.T9, TileId.S1, TileId.S9, TileId.W2, TileId.W5, TileId.W8,
	])
	_bc.state.kuikae_restricted[0] = [TileId.T1]
	_bc.state.current_seat = 0
	_bc.state.phase = BattlePhase.Kind.DISCARD
	var done := {}
	var runner := func():
		await _bc._step_discard_async()
		done["finished"] = true
	runner.call()
	# 点被喰い替え限制的 T1 → 应被拒绝，继续等待
	_panel.player_action_chosen.emit({"action": "discard", "tile_id": TileId.T1})
	await wait_physics_frames(2)
	assert_false(done.has("finished"), "喰い替え受限牌应被拒绝（修复前可非法打出）")
	assert_eq(_bc.state.discards_per_seat[0].size(), 0, "T1 没进弃牌河")
	# 改打不受限的 S9 → 正常完成
	_panel.player_action_chosen.emit({"action": "discard", "tile_id": TileId.S9})
	await wait_physics_frames(2)
	assert_true(done.has("finished"))
	assert_eq(_bc.state.discards_per_seat[0].size(), 1)
	assert_eq(int(_bc.state.discards_per_seat[0][0].id), TileId.S9)
