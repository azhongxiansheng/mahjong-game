extends GutTest
# E2-02 Red：A) loopback→NBC 逐步投影；B) ARS 链 id 探测。禁网络 e2e。
# source-string gate 为过渡（Green 后应删）；行为/反射才是长期契约。

const SP := "res://server/local_loopback_server.gd"
const NP := "res://battle/networked_battle_controller.gd"
const BP := "res://battle/battle_controller.gd"
const IAUTH := "res://battle/i_authoritative_battle_controller.gd"
const AP := "res://battle/authority_replay_snapshot.gd"
const SID := "m12-loopback-e2e"
const CHARS := [&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"]
const PARTS := [&"HUMAN", &"AI", &"AI", &"AI"]
const SNAP := ["snapshot_server_seq", "next_server_seq", "seat_view", "modules"]
const CORE := [
	"recipient_seat", "hand_seq", "dealer_seat", "current_seat", "phase",
	"round_wind", "hand_number", "honba", "riichi_sticks", "live_wall_count",
	"dora_indicators", "viewer_next_draw", "seats",
]

func _exact(d: Dictionary, keys: Array) -> bool:
	if d.keys().size() != keys.size():
		return false
	for k in keys:
		if not d.has(k):
			return false
	return true

func _cmd(n: int) -> String:
	return "550e8400-e29b-41d4-a716-%012d" % n

func _read(p: String) -> String:
	if not ResourceLoader.exists(p):
		return ""
	var f := FileAccess.open(p, FileAccess.READ)
	return f.get_as_text() if f else ""

## 精确子串计数（非 contains），用于 source gate 拒重复声明。
func _count_src(src: String, needle: String) -> int:
	var n := 0
	var i := 0
	while true:
		var p: int = src.find(needle, i)
		if p < 0:
			break
		n += 1
		i = p + needle.length()
	return n

func _cfg() -> GameSessionConfig:
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_STANDARD, PARTS, CHARS, 42, SID, "rv-e2-02")

## 原始返回 exact：任一项非法 → return []，避免后续 .kind 运行时崩溃。
func _exact_ne(raw: Variant, tag: String) -> Array:
	assert_eq(typeof(raw), TYPE_ARRAY, "%s 须 TYPE_ARRAY" % tag)
	if typeof(raw) != TYPE_ARRAY:
		return []
	var a: Array = raw
	var n: int = a.size()
	var valid := true
	for i in range(n):
		if not (a[i] is NetworkedEvent):
			assert_true(false, "%s[%d] NE" % [tag, i])
			valid = false
		elif a[i] is CommandResult:
			assert_true(false, "%s[%d] 禁 CR" % [tag, i])
			valid = false
	assert_eq(a.size(), n)
	if not valid:
		return []
	return a

func _gate(path: String, need: Array, ban: Array, tag: String) -> GDScript:
	assert_true(ResourceLoader.exists(path), "INT_RED: 缺 %s" % tag)
	if not ResourceLoader.exists(path):
		return null
	var src := _read(path)
	for s in need:
		if not src.contains(s):
			assert_true(false, "INT_RED: %s 缺 %s" % [tag, s])
			return null
	for s in ban:
		if src.contains(s):
			assert_true(false, "INT_RED: %s 旧残留 %s" % [tag, s])
			return null
	var scr: GDScript = load(path) as GDScript
	if scr == null or not scr.can_instantiate():
		assert_true(false, "INT_RED: %s load 失败" % tag)
		return null
	return scr

func _server_script() -> GDScript:
	# 过渡 source gate：Green 后应删，不得替代后续行为断言。
	return _gate(SP, ["GameSessionConfig", "func start", "func current_server_seq",
		"func event_journal", "func submit_action", "func events_since"],
		["func run_to_end", "func get_all_events", "func current_seq",
		"kind_not_yet_implemented", "use_heuristic_ai", "seed_value"], "Server")

func _nbc_script() -> GDScript:
	assert_true(ResourceLoader.exists(NP), "INT_RED: 缺 NBC")
	if not ResourceLoader.exists(NP):
		return null
	var f := FileAccess.open(NP, FileAccess.READ)
	var first := f.get_line().strip_edges() if f else ""
	if first != "class_name NetworkedBattleController extends IBattleController":
		assert_true(false, "INT_RED: NBC 须 extends IBattleController")
		return null
	return _gate(NP, ["func ingest_networked_event", "func get_public_view",
		"func get_core_table_view", "func get_event_journal", "func current_seq"],
		["func apply_action", "func run_to_end", "func set_replay_decisions",
		"func extract_player_actions"], "NBC")

func _bc_script() -> GDScript:
	# public facade 唯一在 IAUTH；BP 只覆写 _impl_*，禁重复 public。
	assert_true(ResourceLoader.exists(IAUTH), "INT_RED: 缺 IAUTH")
	assert_true(ResourceLoader.exists(BP), "INT_RED: 缺 BP")
	if not ResourceLoader.exists(IAUTH) or not ResourceLoader.exists(BP):
		return null
	var ia := _read(IAUTH)
	var bp := _read(BP)
	if ia.is_empty() or bp.is_empty():
		assert_true(false, "INT_RED: IAUTH/BP 不可读")
		return null
	# IAUTH：且只验证四条 public facade，各恰好 1 次
	var iauth_public := [
		"func apply_action(",
		"func action_journal(",
		"func load_replay_journal(",
		"func progress_server_draw(",
	]
	for decl in iauth_public:
		var c: int = _count_src(ia, decl)
		assert_eq(c, 1, "INT_RED: IAUTH 须恰好 1× %s（实际 %d）" % [decl, c])
		if c != 1:
			return null
	# BP：对应 _impl_* 各恰好 1；显式拒绝重复 public facade
	var bp_pairs := [
		["func _impl_apply_action(", "func apply_action("],
		["func _impl_action_journal(", "func action_journal("],
		["func _impl_load_replay_journal(", "func load_replay_journal("],
		["func _impl_progress_server_draw(", "func progress_server_draw("],
	]
	for pair in bp_pairs:
		var impl_c: int = _count_src(bp, pair[0])
		var pub_c: int = _count_src(bp, pair[1])
		assert_eq(impl_c, 1, "INT_RED: BP 须恰好 1× %s（实际 %d）" % [pair[0], impl_c])
		assert_eq(pub_c, 0, "INT_RED: BP 禁重复 public %s（实际 %d）" % [pair[1], pub_c])
		if impl_c != 1 or pub_c != 0:
			return null
	# 两侧继续拒绝旧 API（func 声明，非宽松关键词）
	var old_api := [
		"func extract_player_actions",
		"func set_replay_decisions",
		"func set_replay_actions",
	]
	for old in old_api:
		var ia_old: int = _count_src(ia, old)
		var bp_old: int = _count_src(bp, old)
		assert_eq(ia_old, 0, "INT_RED: IAUTH 旧残留 %s" % old)
		assert_eq(bp_old, 0, "INT_RED: BP 旧残留 %s" % old)
		if ia_old != 0 or bp_old != 0:
			return null
	if not (bp.contains("ActionResolution") or bp.contains("action_resolution")):
		assert_true(false, "INT_RED: apply_action 须 ActionResolution")
		return null
	if not bp.contains("IAuthoritative") and not bp.contains("i_authoritative"):
		assert_true(false, "INT_RED: BC 应挂 i_authoritative")
		return null
	var scr: GDScript = load(BP) as GDScript
	if scr == null or not scr.can_instantiate():
		assert_true(false, "INT_RED: BP load 失败")
		return null
	return scr

func _ars_script() -> GDScript:
	assert_true(ResourceLoader.exists(AP), "INT_RED: 缺 ARS")
	if not ResourceLoader.exists(AP):
		return null
	var scr: GDScript = load(AP) as GDScript
	if scr == null:
		assert_true(false, "INT_RED: ARS load 失败")
		return null
	return scr

func _meta(prompt: NetworkedEvent) -> Dictionary:
	if prompt == null or prompt.kind != "TURN_PROMPT":
		return {}
	var p: Dictionary = prompt.payload
	for o in p.get("allowed_actions", []):
		if typeof(o) != TYPE_DICTIONARY or str(o.get("kind", "")) != "DISCARD":
			continue
		var opts: Array = o.get("payload_options", [])
		if opts.is_empty():
			continue
		return {"seat": int(p["seat"]), "hand_seq": int(p["hand_seq"]),
			"decision_id": str(p["decision_id"]),
			"tile_instance_id": int(opts[0]["tile_instance_id"])}
	return {}

func _act(meta: Dictionary, n: int) -> Action:
	return Action.from_dict({
		"protocol_version": 1, "command_id": _cmd(n), "room_id": SID,
		"seat": int(meta["seat"]), "hand_seq": int(meta["hand_seq"]),
		"decision_id": str(meta["decision_id"]), "kind": "DISCARD",
		"payload": {"tile_instance_id": int(meta["tile_instance_id"])}, "client_seq": n})

func _pub_json(nbc: Object) -> String:
	return JSON.stringify(nbc.call("get_public_view"))

func _j_json(nbc: Object, tag: String) -> String:
	var dicts: Array = []
	for e in _exact_ne(nbc.call("get_event_journal"), tag):
		dicts.append(e.to_dict())
	return JSON.stringify(dicts)

func _enter_discard_action(bc: Object) -> Action:
	var state = bc.get("state")
	var engine = bc.get("engine")
	assert_not_null(state)
	assert_not_null(engine)
	if state == null or engine == null:
		return null
	if int(state.phase) == BattlePhase.Kind.DRAW:
		engine.call("draw_for_current")
	assert_eq(int(state.phase), BattlePhase.Kind.DISCARD)
	var seat: int = int(state.current_seat)
	assert_true(bc.has_method("decision_context_for_seat"))
	if not bc.has_method("decision_context_for_seat"):
		return null
	var ctx_raw: Variant = bc.call("decision_context_for_seat", seat)
	assert_true(ctx_raw is DecisionContext)
	if not (ctx_raw is DecisionContext):
		return null
	var ctx: DecisionContext = ctx_raw
	for o in ctx.allowed_actions:
		if typeof(o) != TYPE_DICTIONARY or str(o.get("kind", "")) != "DISCARD":
			continue
		var opts: Array = o.get("payload_options", [])
		if opts.is_empty():
			continue
		return Action.discard(seat, int(opts[0]["tile_instance_id"]),
			SID, _cmd(9), ctx.decision_id, ctx.hand_seq, 9)
	assert_true(false, "须 DecisionWindow 实体 DISCARD")
	return null

func test_a_loopback_to_nbc_projection_convergence() -> void:
	var sscr := _server_script()
	var nscr := _nbc_script()
	if sscr == null or nscr == null:
		return
	var server: Object = sscr.new(_cfg(), 0)
	assert_not_null(server)
	assert_true(bool(server.call("start")))
	var evs := _exact_ne(server.call("events_since", 0, 0), "A0")
	assert_gte(evs.size(), 2)
	if evs.size() < 2:
		return
	var nbc: Object = nscr.new(SID, 0)
	assert_not_null(nbc)
	assert_true(nbc.has_method("current_seq"), "INT_RED: NBC 缺 current_seq")
	if not nbc.has_method("current_seq"):
		return
	var snap0: NetworkedEvent = evs[0]
	assert_eq(snap0.kind, "ROOM_SNAPSHOT")
	assert_true(bool(nbc.call("ingest_networked_event", snap0)))
	var pub: Dictionary = nbc.call("get_public_view")
	assert_true(_exact(pub, SNAP))
	assert_eq(JSON.stringify(pub), JSON.stringify(snap0.payload))
	var core: Dictionary = nbc.call("get_core_table_view")
	assert_true(_exact(core, CORE))
	var pay := {}
	for m in pub["modules"]:
		if str(m["module_key"]) == "core_table":
			pay = m["payload"]
	assert_eq(JSON.stringify(core), JSON.stringify(pay))
	var prompt: NetworkedEvent = evs[1]
	assert_true(prompt.kind == "TURN_PROMPT" or prompt.kind == "CLAIM_WINDOW")
	assert_true(bool(nbc.call("ingest_networked_event", prompt)))
	var meta := _meta(prompt if prompt.kind == "TURN_PROMPT" else null)
	assert_false(meta.is_empty(), "须 TURN_PROMPT+DISCARD")
	if meta.is_empty():
		return
	var action := _act(meta, 1)
	var pub_b := _pub_json(nbc)
	var j_b := _j_json(nbc, "Aj0")
	var jn0: int = _exact_ne(nbc.call("get_event_journal"), "Aj0n").size()
	var pd_b: Dictionary = nbc.call("get_public_view")
	var snap_seq_b: int = int(pd_b.get("snapshot_server_seq", -1))
	var next_seq_b: int = int(pd_b.get("next_server_seq", -1))
	var nbc_seq_b: int = int(nbc.call("current_seq"))
	var srv_seq_b: int = int(server.call("current_server_seq"))
	var cr_raw: Variant = server.call("submit_action", action)
	assert_true(cr_raw is CommandResult)
	if not (cr_raw is CommandResult):
		return
	var cr: CommandResult = cr_raw
	assert_eq(cr.status, "ACCEPTED")
	# CommandResult 禁 ingest：完整 NBC public/journal/current_seq 零修改
	assert_false(bool(nbc.call("ingest_networked_event", cr)), "CR 禁 ingest")
	assert_eq(_pub_json(nbc), pub_b)
	assert_eq(_j_json(nbc, "Acr"), j_b)
	var pd_cr: Dictionary = nbc.call("get_public_view")
	assert_eq(int(pd_cr.get("snapshot_server_seq", -2)), snap_seq_b)
	assert_eq(int(pd_cr.get("next_server_seq", -2)), next_seq_b)
	assert_eq(int(nbc.call("current_seq")), nbc_seq_b, "CR 后 current_seq 零修改")
	# fresh 仅 submit 后事件
	var fresh := _exact_ne(server.call("events_since", 0, srv_seq_b), "Af")
	assert_gte(fresh.size(), 2)
	if fresh.size() < 2:
		return
	assert_eq(fresh[0].kind, "ACTION_APPLIED")
	assert_eq(str(fresh[0].payload["causation_command_id"]), action.command_id)
	assert_eq(cr.server_seq, int(server.call("current_server_seq")),
		"ACCEPTED.server_seq 须指向本次事务最后业务事件")
	assert_eq(cr.server_seq, fresh[fresh.size() - 1].server_seq,
		"fresh 最后一条须与 ACCEPTED.server_seq 对齐")
	# 冻结：异 hash ACTION_APPLIED 只进 pending，不 commit journal / 不改 public / seq
	assert_true(bool(nbc.call("ingest_networked_event", fresh[0])))
	assert_eq(_j_json(nbc, "Aj1"), j_b, "AA pending 后 journal 完全不变")
	assert_eq(_exact_ne(nbc.call("get_event_journal"), "Aj1n").size(), jn0)
	assert_eq(_pub_json(nbc), pub_b, "AA pending 后 public 完全不变")
	assert_eq(int(nbc.call("current_seq")), nbc_seq_b, "AA pending 后 current_seq 完全不变")
	assert_true(nbc.has_method("resync_required"), "INT_RED: NBC 缺 resync_required")
	if nbc.has_method("resync_required"):
		assert_false(bool(nbc.call("resync_required")), "pending 本身不置 resync")
	assert_true(nbc.has_method("desync_check"), "INT_RED: NBC 缺 desync_check")
	if nbc.has_method("desync_check"):
		# pending hash 不得伪装已提交；committed 仍对齐 ingest 前 public
		assert_false(bool(nbc.call("desync_check", fresh[0].view_hash)),
			"pending view_hash 不得 desync_check 通过")
		var committed_vh: String = ProtocolViewCodec.compute_view_hash(
			nbc.call("get_public_view"))
		assert_true(bool(nbc.call("desync_check", committed_vh)),
			"pending 后 committed desync_check 仍成立")
	assert_eq(fresh[1].kind, "ROOM_SNAPSHOT")
	assert_eq(fresh[1].view_hash, fresh[0].view_hash)
	# 匹配 ROOM_SNAPSHOT → 与 pending 一次原子 commit：journal +2，序 AA→SNAP
	assert_true(bool(nbc.call("ingest_networked_event", fresh[1])))
	var j_commit := _exact_ne(nbc.call("get_event_journal"), "Aj2")
	assert_eq(j_commit.size(), jn0 + 2, "匹配 snap 后 journal 恰 +2")
	assert_eq(j_commit[jn0].kind, "ACTION_APPLIED")
	assert_eq(j_commit[jn0 + 1].kind, "ROOM_SNAPSHOT")
	assert_eq(int(j_commit[jn0].server_seq), int(fresh[0].server_seq))
	assert_eq(int(j_commit[jn0 + 1].server_seq), int(fresh[1].server_seq))
	assert_eq(_pub_json(nbc), JSON.stringify(fresh[1].payload), "public=snapshot payload")
	assert_eq(int(nbc.call("current_seq")), int(fresh[1].server_seq),
		"current_seq 到 snapshot seq")
	if nbc.has_method("resync_required"):
		assert_false(bool(nbc.call("resync_required")), "原子 commit 后 resync=false")
	# 后续 tail 继续逐步 ingest
	for i in range(2, fresh.size()):
		assert_true(bool(nbc.call("ingest_networked_event", fresh[i])))
	var last_snap: NetworkedEvent = null
	for i in range(fresh.size() - 1, -1, -1):
		if fresh[i].kind == "ROOM_SNAPSHOT":
			last_snap = fresh[i]
			break
	assert_not_null(last_snap)
	if last_snap == null:
		return
	assert_eq(_pub_json(nbc), JSON.stringify(last_snap.payload),
		"最终 public=最后一张 ROOM_SNAPSHOT，不可错比第一张")
	var tail := false
	for e in fresh.slice(2):
		if e.kind in ["TURN_PROMPT", "CLAIM_WINDOW", "HAND_SETTLED", "MATCH_SETTLED"]:
			tail = true
	assert_true(tail, "下一窗/结算只看 fresh.slice(2)")
	_exact_ne(server.call("event_journal", 0), "Asj")

func test_b_authority_replay_snapshot_roundtrip() -> void:
	var ars := _ars_script()
	var bc_scr := _bc_script()
	if ars == null or bc_scr == null:
		return
	var original: Object = bc_scr.new(42, 0, false)
	assert_not_null(original)
	if original == null:
		return
	var action := _enter_discard_action(original)
	assert_not_null(action)
	if action == null:
		return
	var sched: SkillScheduler = original.get("scheduler") as SkillScheduler
	var st: BattleState = original.get("state") as BattleState
	assert_not_null(sched)
	assert_not_null(st)
	var chain0: int = int(sched.get("_next_chain_id"))
	sched.emit_event(BattleEvent.make(&"SNAPSHOT_CHAIN_PROBE", 0, null, {"probe": true}))
	assert_eq(int(st.event_chain_depth), 0)
	assert_eq(int(sched.get("_next_chain_id")), chain0 + 1)
	var snap_a: Variant = ars.call("capture", original)
	assert_not_null(snap_a)
	if snap_a == null:
		return
	assert_true(snap_a.has_method("to_dict") and snap_a.has_method("sha256")
		and snap_a.has_method("restore_into"))
	var d: Dictionary = snap_a.call("to_dict")
	assert_false(d.is_empty())
	assert_false(d.has("modules") or d.has("seat_view") or d.has("snapshot_server_seq"),
		"ARS 非公开 ROOM")
	var ha: String = str(snap_a.call("sha256"))
	assert_eq(ha.length(), 64)
	assert_eq(ha, ha.to_lower())
	assert_true(ha.is_valid_hex_number())
	var restored: Object = bc_scr.new(42, 0, false)
	assert_true(bool(snap_a.call("restore_into", restored)))
	assert_eq(str(ars.call("capture", restored).call("sha256")), ha)
	var ro: Variant = original.call("apply_action", action, ActionSource.HUMAN)
	var rr: Variant = restored.call("apply_action", action, ActionSource.HUMAN)
	assert_true(ro is ActionResolution and rr is ActionResolution)
	if not (ro is ActionResolution and rr is ActionResolution):
		return
	assert_eq(JSON.stringify(ro.to_dict()), JSON.stringify(rr.to_dict()))
	var eo: Array = ro.events
	var er: Array = rr.events
	assert_eq(eo.size(), er.size())
	for i in range(eo.size()):
		var a: Dictionary = eo[i].to_dict()
		var b: Dictionary = er[i].to_dict()
		assert_eq(str(a.get("type", "")), str(b.get("type", "")))
		assert_eq(int(a.get("chain_id", -1)), int(b.get("chain_id", -2)))
		assert_eq(JSON.stringify(a), JSON.stringify(b))
	assert_eq(str(ars.call("capture", original).call("sha256")),
		str(ars.call("capture", restored).call("sha256")))
	assert_true(original.has_method("action_journal") and original.has_method("load_replay_journal"))
