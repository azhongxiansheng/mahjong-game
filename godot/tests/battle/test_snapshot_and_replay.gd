extends GutTest

# E2-02：权威快照 + action_journal + load_replay_journal 契约。
# 仅测公开 API：AuthorityReplaySnapshot / apply_action / action_journal /
# load_replay_journal / replay_status / run_to_end。
# 禁止：snapshot_dict/snapshot_hash、extract_player_actions、set_replay_decisions、
# set 私有字段、has_method fallback、恢复旧 BattleState snapshot。

const ROOM := "local"
const SEED_A := 42
const SEED_B := 43
const CMD_UUID := "550e8400-e29b-41d4-a716-0000000000a1"

# 回放业务等值字段：从 AuthorityReplaySnapshot.to_dict 选取。
# 故意排除 expected_replay / replay_status / replay_idx / ai / action_cmd_seq。
const BUSINESS_KEYS := [
	"hand_seq", "phase", "current_seat", "dealer_seat", "round_wind",
	"hand_number", "honba", "riichi_sticks", "scores", "turn_count",
	"first_round_active", "furiten_flags", "ron_cancelled",
	"haitei_forced_seat", "extra_dora_count", "extra_red_dora_count",
	"revealed", "kuikae", "momentum_total", "momentum_scores",
	"wall", "dora", "ura", "seats", "skills",
	"action_journal", "event_journal", "settled",
	"last_event", "last_discarder", "last_discarded",
	"window", "pending_added_kan", "battle_seed",
]


func _make_bc(p_seed: int, use_heuristic: bool = true) -> BattleController:
	return BattleController.new(p_seed, 0, use_heuristic)


func _clone_journal(src: Array) -> Array:
	var out: Array = []
	for item in src:
		assert_true(item is Action, "journal 元素须为 Action")
		var cloned: Action = Action.from_dict((item as Action).to_dict())
		assert_not_null(cloned, "Action.to_dict/from_dict roundtrip")
		out.append(cloned)
	return out


func _enter_discard(bc: BattleController) -> void:
	assert_not_null(bc.state)
	assert_not_null(bc.engine)
	if bc.state.phase == BattlePhase.Kind.DRAW:
		var drawn: Tile = bc.engine.draw_for_current()
		assert_not_null(drawn, "开局 DRAW 须能摸牌")
	assert_eq(bc.state.phase, BattlePhase.Kind.DISCARD)


func _first_discard_offer_iid(ctx: DecisionContext) -> int:
	assert_not_null(ctx)
	for offer in ctx.allowed_actions:
		if typeof(offer) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = offer
		if str(d.get("kind", "")) != "DISCARD":
			continue
		for opt in d.get("payload_options", []):
			if opt is Dictionary and (opt as Dictionary).has("tile_instance_id"):
				return int((opt as Dictionary)["tile_instance_id"])
	assert_true(false, "DecisionContext 须 offer DISCARD")
	return -1


func _legal_discard_action(bc: BattleController) -> Action:
	_enter_discard(bc)
	var seat: int = bc.state.current_seat
	var ctx: DecisionContext = bc.decision_context_for_seat(seat)
	assert_not_null(ctx, "TURN DecisionContext 必须存在")
	var iid: int = _first_discard_offer_iid(ctx)
	assert_true(Tile.is_instance_id_in_hand_seq(iid, bc.state.hand_seq),
		"tile_instance_id 须属本局 canonical namespace")
	assert_true(ctx.allows("DISCARD", {"tile_instance_id": iid}))
	var act: Action = Action.discard(
		seat, iid, ROOM, CMD_UUID, ctx.decision_id, bc.state.hand_seq, 1
	)
	assert_not_null(act, "合法 DISCARD Action 不得为 null")
	assert_true(ProtocolUuid.is_canonical_v4(act.command_id), "command_id 须 UUID v4")
	return act


func _business_slice(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in BUSINESS_KEYS:
		assert_true(d.has(k), "AuthorityReplaySnapshot.to_dict 缺业务字段: %s" % k)
		out[k] = d[k]
	return out


func _assert_business_equal(a: Dictionary, b: Dictionary, label: String) -> void:
	var sa: Dictionary = _business_slice(a)
	var sb: Dictionary = _business_slice(b)
	assert_eq(JSON.stringify(sa), JSON.stringify(sb), "业务字段等值: %s" % label)


func _assert_journal_action_dicts_equal(a: Array, b: Array, label: String) -> void:
	assert_eq(a.size(), b.size(), "%s journal size" % label)
	for i in range(a.size()):
		assert_true(a[i] is Action and b[i] is Action, "%s[%d] 须 Action" % [label, i])
		assert_eq(
			(a[i] as Action).to_dict(),
			(b[i] as Action).to_dict(),
			"%s journal[%d] Action dict" % [label, i]
		)


# ---- 1) AuthorityReplaySnapshot 稳定 / 差异 / restore 再 capture ----

func test_authority_snapshot_stable_same_seed():
	var bc1 := _make_bc(SEED_A)
	bc1.run_to_end()
	var s1: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(bc1)
	assert_not_null(s1)
	var h1: String = s1.sha256()
	assert_eq(h1.length(), 64, "sha256 须 64 hex")
	var d1: Dictionary = s1.to_dict()
	# 同实例再 capture 稳定
	var s1b: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(bc1)
	assert_eq(s1b.sha256(), h1)
	assert_eq(JSON.stringify(s1b.to_dict()), JSON.stringify(d1))
	# 同 seed 新 controller 终态权威快照稳定
	var bc2 := _make_bc(SEED_A)
	bc2.run_to_end()
	var s2: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(bc2)
	assert_eq(s2.sha256(), h1, "同 seed 终态 AuthorityReplaySnapshot.sha256 须一致")
	assert_eq(JSON.stringify(s2.to_dict()), JSON.stringify(d1),
		"同 seed 终态 to_dict 须完全一致")


func test_authority_snapshot_sha_differs_with_seed():
	var bc_a := _make_bc(SEED_A)
	bc_a.run_to_end()
	var bc_b := _make_bc(SEED_B)
	bc_b.run_to_end()
	var ha: String = AuthorityReplaySnapshot.capture(bc_a).sha256()
	var hb: String = AuthorityReplaySnapshot.capture(bc_b).sha256()
	assert_ne(ha, hb, "不同 seed SHA 必须不同")


func test_authority_snapshot_restore_into_recapture_identical():
	var src := _make_bc(SEED_A)
	src.run_to_end()
	var snap: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(src)
	assert_not_null(snap)
	var h_src: String = snap.sha256()
	var d_src: Dictionary = snap.to_dict()
	# 不同 seed target；仅公开 restore_into，禁止旧 state snapshot 恢复
	var target := _make_bc(SEED_B)
	assert_true(snap.restore_into(target), "restore_into 须成功")
	var recap: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(target)
	assert_not_null(recap)
	assert_eq(recap.sha256(), h_src, "restore 后再 capture SHA 须与源完全一致")
	assert_eq(JSON.stringify(recap.to_dict()), JSON.stringify(d_src),
		"restore 后再 capture to_dict 须与源完全一致")


# ---- 2) run_to_end → action_journal Action roundtrip ----

func test_action_journal_nonempty_and_action_roundtrip_after_run_to_end():
	var bc := _make_bc(SEED_A)
	bc.run_to_end()
	var journal: Array = bc.action_journal()
	assert_gt(journal.size(), 0, "run_to_end 后 action_journal 须非空")
	for i in range(journal.size()):
		var item = journal[i]
		assert_true(item is Action, "journal[%d] 须为 Action" % i)
		var d: Dictionary = (item as Action).to_dict()
		var back: Action = Action.from_dict(d)
		assert_not_null(back, "journal[%d] to_dict/from_dict 不得 null" % i)
		assert_eq(back.to_dict(), d, "journal[%d] roundtrip dict 等值" % i)
		assert_true(ProtocolUuid.is_canonical_v4(back.command_id),
			"journal[%d].command_id 须 UUID v4" % i)


# ---- 3) load_replay_journal → run_to_end 业务等值 ----

func test_replay_journal_lifecycle_and_business_equivalence():
	var recorder := _make_bc(SEED_A)
	assert_eq(recorder.replay_status(), &"IDLE")
	recorder.run_to_end()
	var recorded: Array = _clone_journal(recorder.action_journal())
	assert_gt(recorded.size(), 0, "录制 journal 须非空")

	var replayer := _make_bc(SEED_A)
	assert_eq(replayer.replay_status(), &"IDLE")
	assert_true(replayer.load_replay_journal(recorded), "load_replay_journal 须成功")
	assert_eq(replayer.replay_status(), &"LOADED")
	assert_eq(replayer.action_journal().size(), 0, "装载后 accepted journal 仍空")
	replayer.run_to_end()
	assert_eq(replayer.replay_status(), &"COMPLETED")

	_assert_journal_action_dicts_equal(
		recorder.action_journal(), replayer.action_journal(), "replay accepted"
	)

	var d_rec: Dictionary = AuthorityReplaySnapshot.capture(recorder).to_dict()
	var d_rep: Dictionary = AuthorityReplaySnapshot.capture(replayer).to_dict()
	_assert_business_equal(d_rec, d_rep, "录制 vs 回放")
	# 显式：不得把 expected_replay / replay 游标 / AI RNG 当业务硬等值
	assert_true(d_rep.has("expected_replay"))
	assert_true(d_rep.has("replay_status"))
	assert_true(d_rep.has("replay_idx"))
	assert_true(d_rep.has("ai"))
	assert_true(d_rep.has("action_cmd_seq"))


# ---- 4) 同 DISCARD × HUMAN / AI / REPLAY 等值 ----

func test_same_discard_human_ai_replay_equivalent():
	# 从真实 DecisionContext offer 构造唯一合法 DISCARD（本局 canonical iid + UUID v4）
	var probe := _make_bc(SEED_A, false)
	var action: Action = _legal_discard_action(probe)
	var action_dict: Dictionary = action.to_dict()
	assert_eq(action.kind, "DISCARD")

	var sources: Array = [ActionSource.HUMAN, ActionSource.AI, ActionSource.REPLAY]
	var captures: Array = []
	for src in sources:
		var bc := _make_bc(SEED_A, false)
		_enter_discard(bc)
		var act: Action = Action.from_dict(action_dict)
		assert_not_null(act)
		if src == ActionSource.REPLAY:
			assert_true(
				bc.load_replay_journal([Action.from_dict(action_dict)]),
				"REPLAY 须先 load 该 Action"
			)
			assert_eq(bc.replay_status(), &"LOADED")
			assert_eq(bc.action_journal().size(), 0)
		var resp: ActionResolution = bc.apply_action(act, src)
		assert_true(resp.accepted, "source=%s 须 accepted" % str(src))
		assert_eq(bc.action_journal().size(), 1)
		assert_eq(
			(bc.action_journal()[0] as Action).to_dict(),
			action_dict,
			"source=%s journal 须同一 Action dict" % str(src)
		)
		if src == ActionSource.REPLAY:
			assert_eq(bc.replay_status(), &"COMPLETED")
		captures.append(AuthorityReplaySnapshot.capture(bc).to_dict())

	assert_eq(captures.size(), 3)
	_assert_business_equal(captures[0], captures[1], "HUMAN vs AI")
	_assert_business_equal(captures[0], captures[2], "HUMAN vs REPLAY")
