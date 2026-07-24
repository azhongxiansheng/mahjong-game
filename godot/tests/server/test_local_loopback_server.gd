extends GutTest
# E2-02 Red：LocalLoopbackServer。源码闸→load。journal/events_since 走 exact NE（禁静默过滤 CR）。

const PATH := "res://server/local_loopback_server.gd"
const SID := "loopback-session-e2-02"
const CLAIM_SID := "loopback-claim-e2-02"
const CHARS := [&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"]
const PARTS := [&"HUMAN", &"AI", &"AI", &"AI"]
const PARTS_ALL_HUMAN := [&"HUMAN", &"HUMAN", &"HUMAN", &"HUMAN"]
const SNAP := ["snapshot_server_seq", "next_server_seq", "seat_view", "modules"]
const MOD := ["module_key", "schema_version", "payload"]
const CORE := [
	"recipient_seat", "hand_seq", "dealer_seat", "current_seat", "phase",
	"round_wind", "hand_number", "honba", "riichi_sticks", "live_wall_count",
	"dora_indicators", "seats",
]
const SEAT := [
	"seat", "seat_wind", "score", "concealed_tiles", "concealed_count",
	"last_drawn_tile_instance_id", "river", "melds",
	"riichi_declared", "riichi_double", "riichi_discard_index",
]
const AA := ["causation_command_id", "hand_seq", "decision_id", "seat", "action_kind", "resolved_payload"]
const REQ := [
	"GameSessionConfig", "func start", "func publish_snapshot", "func current_server_seq",
	"func event_journal", "func submit_action",
]
const BAN := [
	"use_heuristic_ai", "kind_not_yet_implemented", "func run_to_end", "func get_all_events",
	"func current_seq", "extract_player_actions", "set_replay_decisions", "normalized_payload",
	"seed_value", "_init(seed", "snapshot_for_recipient",
]

## 最小失败注入：仅覆盖 _build_room_snapshot_payload。
## fail_seat 返回空 Dictionary；其余座位必须 super（真实 projector/config/BC）。
## 禁止 mock RecipientViewProjector 或核心规则。
class FailingSnapshotServer extends LocalLoopbackServer:
	var fail_seat: int = 2

	func _build_room_snapshot_payload(seat: int, seq: int) -> Dictionary:
		if int(seat) == fail_seat:
			return {}
		return super._build_room_snapshot_payload(seat, seq)


## 最小失败注入：仅覆盖 _build_turn_prompt_payload → 空 Dictionary。
## 不 mock 其它核心（projector / BC / ARS / claim）；call_count 证明命中。
class FailingTurnPromptServer extends LocalLoopbackServer:
	var call_count: int = 0

	func _build_turn_prompt_payload(_ctx: DecisionContext, _seat: int) -> Dictionary:
		call_count += 1
		return {}


## 最小失败注入：仅覆盖 _build_claim_window_payload。
## 计数；第二次返回空 Dictionary；其余 super（真实 discarded/codec/ctx）。
## 用于暴露 CLAIM 多 recipient 先 alloc_seq / 首 target 半 append。
class FailingClaimPromptServer extends LocalLoopbackServer:
	var call_count: int = 0

	func _build_claim_window_payload(ctx: DecisionContext, dw: DecisionWindow) -> Dictionary:
		call_count += 1
		if call_count == 2:
			return {}
		return super._build_claim_window_payload(ctx, dw)


## 最小失败注入：未来生产 seam `_build_recipient_event`。
## enabled=false 时 start 初始 snapshot 不受影响；命中 kind+seat 时 call_count++ 并 return null。
## 当前生产尚无此方法：不能 super（parse 失败）；未命中路径用 NetworkedEvent.make 等价透传。
## Red 以 call_count=0 / 未 REJECTED 暴露缺口；禁止为 Red 改生产。
class FailingAcceptedBatchServer extends LocalLoopbackServer:
	var enabled: bool = false
	var fail_kind: String = ""
	var fail_seat: int = -1
	var call_count: int = 0

	func _build_recipient_event(
		kind: String, recipient_seat: int, seq: int, payload: Dictionary, view_hash: String
	) -> NetworkedEvent:
		if enabled and kind == fail_kind and int(recipient_seat) == fail_seat:
			call_count += 1
			return null
		# 基类尚无 _build_recipient_event 时 super 无法 parse；语义同未来 production seam。
		return NetworkedEvent.make(kind, seq, _room_id, payload, view_hash)


func _exact(d: Dictionary, keys: Array) -> bool:
	if d.keys().size() != keys.size():
		return false
	for k in keys:
		if not d.has(k):
			return false
	return true

func _cmd(n: int) -> String:
	return "550e8400-e29b-41d4-a716-%012d" % n

func _cfg() -> GameSessionConfig:
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_STANDARD, PARTS, CHARS, 42, SID, "rv-e2-02")

## 真实全 HUMAN 配置：PUBLIC_CASUAL + 四席 HUMAN；CHARS/seed42；session=CLAIM_SID。
func _cfg_all_human() -> GameSessionConfig:
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PUBLIC_CASUAL, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_STANDARD, PARTS_ALL_HUMAN, CHARS, 42, CLAIM_SID, "rv-e2-02")

func _src() -> String:
	if not ResourceLoader.exists(PATH):
		return ""
	var f := FileAccess.open(PATH, FileAccess.READ)
	return f.get_as_text() if f else ""

## 原始返回 exact：TYPE_ARRAY + 长度不变 + 每项 NetworkedEvent；任一项非法 → return []。
func _exact_ne(raw: Variant, tag: String) -> Array:
	assert_eq(typeof(raw), TYPE_ARRAY, "%s 须 TYPE_ARRAY" % tag)
	if typeof(raw) != TYPE_ARRAY:
		return []
	var a: Array = raw
	var n: int = a.size()
	var valid := true
	for i in range(n):
		if not (a[i] is NetworkedEvent):
			assert_true(false, "%s[%d] 须 NetworkedEvent" % [tag, i])
			valid = false
		elif a[i] is CommandResult:
			assert_true(false, "%s[%d] 禁 CommandResult" % [tag, i])
			valid = false
	assert_eq(a.size(), n, "%s 长度不得改写" % tag)
	if not valid:
		return []
	return a

func _contract_ok() -> bool:
	assert_true(ResourceLoader.exists(PATH), "SERVER_RED: 缺 LocalLoopbackServer")
	if not ResourceLoader.exists(PATH):
		return false
	var src := _src()
	assert_false(src.is_empty())
	if src.is_empty():
		return false
	for s in REQ:
		if not src.contains(s):
			assert_true(false, "SERVER_RED: 缺 %s" % s)
			return false
	if not (src.contains("events_since") and (src.contains("recipient_seat")
			or src.contains("after_server_seq") or src.contains("events_since(seat"))):
		assert_true(false, "SERVER_RED: events_since 须双参")
		return false
	for s in BAN:
		if src.contains(s):
			assert_true(false, "SERVER_RED: 旧残留 %s" % s)
			return false
	return true

func _load_server() -> GDScript:
	if not _contract_ok():
		return null
	var scr: GDScript = load(PATH) as GDScript
	if scr == null or not scr.can_instantiate():
		assert_true(false, "SERVER_RED: load/实例化失败")
		return null
	return scr

func _new(scr: GDScript) -> Object:
	if scr == null:
		return null
	var s: Object = scr.new(_cfg(), 0)
	assert_not_null(s)
	return s

func _find(a: Array, k: String) -> NetworkedEvent:
	for e in a:
		if e is NetworkedEvent and e.kind == k:
			return e
	return null

func _snap(ne: NetworkedEvent, seat: int, tag: String) -> Dictionary:
	assert_not_null(ne, tag)
	if ne == null:
		return {}
	assert_eq(ne.kind, "ROOM_SNAPSHOT")
	var p: Dictionary = ne.payload
	assert_true(_exact(p, SNAP), "%s exact-4" % tag)
	assert_eq(int(p["snapshot_server_seq"]), ne.server_seq)
	assert_eq(int(p["next_server_seq"]), ne.server_seq + 1)
	assert_eq(int(p["seat_view"]), seat)
	var keys: Array = []
	for m in p["modules"]:
		assert_true(_exact(m, MOD))
		keys.append(str(m["module_key"]))
	var sk := keys.duplicate()
	sk.sort()
	assert_eq(JSON.stringify(keys), JSON.stringify(sk), "%s modules 升序" % tag)
	var seen := {}
	for k in keys:
		assert_false(seen.has(k))
		seen[k] = true
	assert_true(seen.has("core_table"), "%s 须含 core_table" % tag)
	if not seen.has("core_table"):
		return {}
	var idx: int = keys.find("core_table")
	assert_gte(idx, 0)
	if idx < 0 or idx >= (p["modules"] as Array).size():
		return {}
	var entry: Dictionary = (p["modules"] as Array)[idx]
	assert_eq(int(entry["schema_version"]), 1)
	var core: Dictionary = entry["payload"]
	assert_true(_exact(core, CORE), "%s core exact-12" % tag)
	assert_eq(int(core["recipient_seat"]), seat)
	assert_eq((core["seats"] as Array).size(), 4)
	for i in range(4):
		assert_true(_exact((core["seats"] as Array)[i], SEAT), "%s seat exact-11" % tag)
	var vh := ProtocolViewCodec.compute_view_hash(p)
	assert_eq(vh.length(), 64)
	assert_eq(ne.view_hash, vh)
	return p

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

func _act(meta: Dictionary, n: int, room := SID) -> Action:
	return Action.from_dict({
		"protocol_version": 1, "command_id": _cmd(n), "room_id": room,
		"seat": int(meta["seat"]), "hand_seq": int(meta["hand_seq"]),
		"decision_id": str(meta["decision_id"]), "kind": "DISCARD",
		"payload": {"tile_instance_id": int(meta["tile_instance_id"])}, "client_seq": n})

func _prompt(s: Object) -> NetworkedEvent:
	# 取 seat0 journal 中最后一条 TURN_PROMPT / CLAIM_WINDOW（禁用首条历史 prompt）
	var a := _exact_ne(s.call("event_journal", 0), "prompt")
	for i in range(a.size() - 1, -1, -1):
		var e: NetworkedEvent = a[i] as NetworkedEvent
		if e.kind == "TURN_PROMPT" or e.kind == "CLAIM_WINDOW":
			return e
	return null

func _as_cr(raw: Variant, tag: String) -> CommandResult:
	assert_true(raw is CommandResult, "%s 须 CommandResult（先 Variant）" % tag)
	if not (raw is CommandResult):
		return null
	return raw as CommandResult


func test_added_kan_declaration_builds_serializable_candidate_meld_view() -> void:
	var server := LocalLoopbackServer.new(_cfg_all_human(), 0)
	var bc: BattleController = server._bc
	var seat: Seat = bc.state.seats[0]
	var copies: Array = []
	for tile in bc.state.wall._tiles:
		if tile is Tile and tile.id == TileId.W5:
			copies.append(tile)
	assert_eq(copies.size(), 4, "真实牌墙须有四张 W5")
	if copies.size() != 4:
		return
	seat.hand._tiles.clear()
	seat.melds.clear()
	seat.melds.append(Meld.make_pon(
		[copies[0], copies[1], copies[2]], 1, 0, copies[0]))
	assert_true(seat.hand.add(copies[3]))

	var action: Action = Action.kan(0, {
		"kan_kind": "ADDED_KAN",
		"meld_id": 0,
		"added_tile_instance_id": copies[3].instance_id,
	}, CLAIM_SID, _cmd(900), _cmd(901), 0, 1)
	assert_not_null(action)
	var resolved: Dictionary = server._build_resolved_payload(action, null, "HAND")
	assert_eq(str(resolved.get("meld", {}).get("kind", "")), "ADDED_KAN",
		"声明阶段应投影候选 ADDED_KAN，领域 PON 仍不升级")
	assert_eq((seat.melds[0] as Meld).kind, Meld.Kind.PON,
		"构造网络结果不得提前修改领域状态")

	var event: NetworkedEvent = NetworkedEvent.make(
		"ACTION_APPLIED", 1, CLAIM_SID, {
			"causation_command_id": action.command_id,
			"hand_seq": action.hand_seq,
			"decision_id": action.decision_id,
			"seat": action.seat,
			"action_kind": action.kind,
			"resolved_payload": resolved,
		}, "0".repeat(64))
	assert_not_null(event, "ADDED_KAN 声明必须能进入严格 NetworkedEvent")

func test_api_contract_source_gate() -> void:
	# 过渡源码闸；Green 后行为/反射是长期契约。
	if not _contract_ok():
		return
	assert_not_null(_load_server())

func test_construct_no_side_effects() -> void:
	var server := _new(_load_server())
	if server == null:
		return
	assert_eq(int(server.call("current_server_seq")), 0)
	for seat in range(4):
		assert_eq(_exact_ne(server.call("events_since", seat, 0), "c/e%d" % seat).size(), 0)
		assert_eq(_exact_ne(server.call("event_journal", seat), "c/j%d" % seat).size(), 0)

func test_publish_snapshot_four_seats_one_logical_seq() -> void:
	var server := _new(_load_server())
	if server == null:
		return
	assert_eq(int(server.call("current_server_seq")), 0)
	for seat in range(4):
		assert_eq(_exact_ne(server.call("event_journal", seat), "pre%d" % seat).size(), 0)
	var seq0 := int(server.call("current_server_seq"))
	assert_true(server.has_method("publish_snapshot"))
	assert_true(bool(server.call("publish_snapshot")), "publish_snapshot 须 true")
	assert_eq(int(server.call("current_server_seq")), seq0 + 1, "只增 1 逻辑 seq")
	var logical := -1
	for seat in range(4):
		var j := _exact_ne(server.call("event_journal", seat), "pub%d" % seat)
		assert_eq(j.size(), 1)
		if j.size() < 1:
			return
		var p := _snap(j[0], seat, "ps%d" % seat)
		if p.is_empty():
			return
		if logical < 0:
			logical = int(p["snapshot_server_seq"])
		else:
			assert_eq(int(p["snapshot_server_seq"]), logical)
		assert_eq(j[0].server_seq, logical)
	assert_eq(int(server.call("current_server_seq")), logical)

## Red：单席 payload 失败时 publish_snapshot 须原子失败——seq/四席 journal/authority 全零变化。
## 暴露当前先 alloc seq、再逐席 append 的半提交。
func test_publish_snapshot_fail_seat_atomic_zero_mutation() -> void:
	if not _contract_ok():
		return
	var server := FailingSnapshotServer.new(_cfg(), 0)
	assert_not_null(server, "FailingSnapshotServer 须可构造")
	if server == null:
		return
	server.fail_seat = 2
	var bc: Variant = server.get("_bc")
	assert_not_null(bc, "构造后 server._bc 须非 null")
	if bc == null:
		return
	assert_not_null(bc.state, "构造后 BC.state 须非 null")
	if bc.state == null:
		return
	# 构造后冻结：不 start / 不 accepted / 不 settled
	var seq0: int = int(server.call("current_server_seq"))
	var j0: Array = _journal_sizes(server, "fail_seat0")
	var auth0: String = _authority_domain_hash(server, "fail_seat_auth0")
	assert_eq(seq0, 0)
	for n in j0:
		assert_eq(int(n), 0)
	assert_eq(auth0.length(), 64, "构造后 authority sha256 须 64 位")
	# fail_seat=2 → payload 空 Dictionary；须 false，且不得半提交
	assert_false(
		bool(server.call("publish_snapshot")),
		"单席 _build_room_snapshot_payload 失败时 publish_snapshot 须 false")
	assert_eq(int(server.call("current_server_seq")), seq0, "失败：server_seq 零变化（禁先 alloc）")
	assert_eq(
		JSON.stringify(_journal_sizes(server, "fail_seat1")), JSON.stringify(j0),
		"失败：四席 journal 零变化（禁逐席半 append）")
	assert_eq(
		_authority_domain_hash(server, "fail_seat_auth1"), auth0,
		"失败：AuthorityReplaySnapshot 领域/日志/调度态零变化")

## Red：真实 projector/codec 因可见 dora 非法 owner_seat 失败时，
## _build_room_snapshot_payload 须空 Dictionary（禁 seats/dora fallback）；
## publish_snapshot 须 false 且 seq/四席 journal/authority 零变化。
func test_publish_snapshot_projector_fail_no_fallback_atomic() -> void:
	var server := _new(_load_server())
	if server == null:
		return
	var bc: Variant = server.get("_bc")
	assert_not_null(bc, "server._bc 须非 null")
	if bc == null:
		return
	assert_not_null(bc.state, "BC.state 须非 null")
	if bc.state == null:
		return
	var dora: Variant = bc.state.dora_indicators
	assert_not_null(dora, "dora_indicators 须非 null")
	if dora == null:
		return
	assert_gt(dora.visible.size(), 0, "须有可见 dora 指示牌")
	if dora.visible.is_empty():
		return
	var tile: Tile = dora.visible[0] as Tile
	assert_not_null(tile, "visible dora[0] 须为 Tile")
	if tile == null:
		return
	# 污染 owner_seat → ProtocolViewCodec / RecipientViewProjector 真实 fail
	tile.owner_seat = 99
	assert_eq(tile.owner_seat, 99)
	# 真实 projector 须 fail-closed（null）；禁止 mock
	var proj: Variant = RecipientViewProjector.project_core_table(bc.state, 0)
	assert_true(proj == null, "毒化 visible dora 后 project_core_table 须 null")
	# AuthorityReplaySnapshot 仍可捕获（不经 projector / 禁旧 BattleState.snapshot_*）
	var auth_probe: String = _authority_domain_hash(server, "proj_auth_probe")
	assert_eq(auth_probe.length(), 64, "毒化 dora 后 AuthorityReplaySnapshot 仍须可 capture")
	# 直接调用 _build_room_snapshot_payload：须空 Dictionary，禁止空 seats/dora fallback
	var next_seq: int = int(server.call("current_server_seq")) + 1
	var raw_payload: Variant = server.call("_build_room_snapshot_payload", 0, next_seq)
	assert_eq(typeof(raw_payload), TYPE_DICTIONARY, "_build_room_snapshot_payload 须 Dictionary（非 null）")
	if typeof(raw_payload) != TYPE_DICTIONARY:
		return
	var payload: Dictionary = raw_payload
	# 精确禁 fallback：非空且含 modules/core_table 且 seats=[]/dora=[] 仍失败
	if not payload.is_empty():
		var has_fallback_shape := false
		if payload.has("modules") and typeof(payload["modules"]) == TYPE_ARRAY:
			for m in payload["modules"] as Array:
				if typeof(m) != TYPE_DICTIONARY:
					continue
				if str(m.get("module_key", "")) != "core_table":
					continue
				var core: Variant = m.get("payload", null)
				if typeof(core) != TYPE_DICTIONARY:
					continue
				var cd: Dictionary = core
				if cd.has("seats") and cd.has("dora_indicators") \
						and typeof(cd["seats"]) == TYPE_ARRAY \
						and typeof(cd["dora_indicators"]) == TYPE_ARRAY \
						and (cd["seats"] as Array).is_empty() \
						and (cd["dora_indicators"] as Array).is_empty():
					has_fallback_shape = true
		assert_true(
			false,
			"projector 失败须返回空 Dictionary；禁 fallback keys=%s fallback_shape=%s" % [
				JSON.stringify(payload.keys()), str(has_fallback_shape)])
	assert_true(payload.is_empty(), "projector 失败须返回空 Dictionary")
	# 冻结后 publish_snapshot 须原子失败
	var seq0: int = int(server.call("current_server_seq"))
	var j0: Array = _journal_sizes(server, "proj0")
	var auth0: String = _authority_domain_hash(server, "proj_auth0")
	assert_eq(auth0, auth_probe)
	assert_false(
		bool(server.call("publish_snapshot")),
		"真实 projector 失败时 publish_snapshot 须 false")
	assert_eq(int(server.call("current_server_seq")), seq0, "projector fail：server_seq 零变化")
	assert_eq(
		JSON.stringify(_journal_sizes(server, "proj1")), JSON.stringify(j0),
		"projector fail：四席 journal 零变化")
	assert_eq(
		_authority_domain_hash(server, "proj_auth1"), auth0,
		"projector fail：AuthorityReplaySnapshot 领域/日志/调度态零变化")

func test_start_snapshot_then_private_prompt() -> void:
	var server := _new(_load_server())
	if server == null:
		return
	assert_eq(server.get("_started"), false, "start 前 _started 须 false")
	assert_true(bool(server.call("start")))
	assert_eq(server.get("_started"), true, "成功 start 后 _started 须 true")
	var s0 := _exact_ne(server.call("events_since", 0, 0), "st0")
	assert_gte(s0.size(), 2)
	if s0.size() < 2:
		return
	# 本 fixture：dealer/human seat0 → ROOM_SNAPSHOT seq1 后 TURN_PROMPT seq2（非 CLAIM）
	assert_eq(s0[0].kind, "ROOM_SNAPSHOT")
	assert_eq(s0[0].room_id, SID)
	assert_eq(int(s0[0].server_seq), 1, "seat0 首条须 ROOM_SNAPSHOT seq=1")
	var snap_payload := _snap(s0[0], 0, "h0")
	if snap_payload.is_empty():
		return
	assert_eq(s0[1].kind, "TURN_PROMPT",
		"本 fixture human dealer seat0 须 TURN_PROMPT（非 CLAIM_WINDOW）")
	assert_eq(int(s0[1].server_seq), 2, "seat0 次条须 TURN_PROMPT seq=2")
	assert_eq(s0[1].room_id, SID)
	# prompt 不改变 public projection → view_hash 须严格等于前一个 ROOM_SNAPSHOT.view_hash
	assert_eq(s0[1].view_hash, s0[0].view_hash,
		"TURN_PROMPT.view_hash 须严格等于 ROOM_SNAPSHOT.view_hash（投影未变）")
	var seq: int = s0[0].server_seq
	for seat in range(4):
		var evs := _exact_ne(server.call("events_since", seat, 0), "st%d" % seat)
		var p := _snap(_find(evs, "ROOM_SNAPSHOT"), seat, "s%d" % seat)
		if p.is_empty():
			return
		assert_eq(int(p["snapshot_server_seq"]), seq)
		if seat != 0:
			assert_null(_find(evs, "TURN_PROMPT"))
			assert_null(_find(evs, "CLAIM_WINDOW"))

	# 真实 NBC(SID,0) 消费 seat0 真实 journal 两条：须直接 commit prompt，无 pending
	var nbc := NetworkedBattleController.new(SID, 0)
	assert_not_null(nbc)
	if nbc == null:
		return
	var stream: Array = [s0[0], s0[1]]
	assert_true(bool(nbc.ingest_event_stream(stream)),
		"snapshot+同 hash TURN_PROMPT stream 须 true")
	assert_false(nbc.resync_required(), "prompt 直接 commit 后 resync_required 须 false")
	assert_eq(int(nbc.current_seq()), int(s0[1].server_seq),
		"prompt 直接 commit 后 current_seq 须等于 TURN_PROMPT.server_seq（禁停在 snapshot）")
	var journal: Array = nbc.get_event_journal()
	assert_eq(journal.size(), 2, "journal 须严格两条（snapshot+prompt；禁 prompt 只进 pending）")
	if journal.size() >= 1:
		assert_eq(journal[0].kind, "ROOM_SNAPSHOT")
		assert_eq(int(journal[0].server_seq), int(s0[0].server_seq))
	if journal.size() >= 2:
		assert_eq(journal[1].kind, "TURN_PROMPT")
		assert_eq(int(journal[1].server_seq), int(s0[1].server_seq))
	assert_eq(
		JSON.stringify(nbc.get_public_view()), JSON.stringify(snap_payload),
		"prompt 不改 public view；须仍等于 ROOM_SNAPSHOT.payload")


## Red：start 内 snapshot 失败须原子回滚——draw / 可能窗口 / seq / journal / cache / ARS / _started。
## 复用 FailingSnapshotServer(fail_seat=2)；真实 config/BC/ARS；禁 snapshot_hash/snapshot_dict。
func test_start_snapshot_fail_atomic_rollback() -> void:
	if not _contract_ok():
		return
	var server := FailingSnapshotServer.new(_cfg(), 0)
	assert_not_null(server, "FailingSnapshotServer 须可构造")
	if server == null:
		return
	server.fail_seat = 2
	var bc: Variant = server.get("_bc")
	assert_not_null(bc, "构造后 server._bc 须非 null")
	if bc == null:
		return
	assert_not_null(bc.state, "构造后 BC.state 须非 null")
	if bc.state == null:
		return
	# 调用前冻结：_started / seq / 四席 journal sizes / command_cache.size / ARS sha256
	var started0: bool = bool(server.get("_started"))
	var seq0: int = int(server.call("current_server_seq"))
	var j0: Array = _journal_sizes(server, "start_snap0")
	var cache0: int = _command_cache_size(server)
	var auth0: String = _authority_domain_hash(server, "start_snap_auth0")
	assert_eq(started0, false, "start 前 _started 须 false")
	assert_eq(seq0, 0)
	for n in j0:
		assert_eq(int(n), 0)
	assert_eq(cache0, 0, "start 前 command_cache 须空")
	assert_eq(auth0.length(), 64, "构造后 authority sha256 须 64 位")
	# fail_seat=2 → start 内 publish 失败；须 false 且完整回滚 draw/窗口
	assert_false(
		bool(server.call("start")),
		"start 内 snapshot payload 失败时 start 须 false")
	assert_eq(server.get("_started"), false, "失败：_started 须恢复 false（禁半置 true）")
	assert_eq(int(server.call("current_server_seq")), seq0, "失败：server_seq 零变化")
	assert_eq(
		JSON.stringify(_journal_sizes(server, "start_snap1")), JSON.stringify(j0),
		"失败：四席 journal 零变化")
	assert_eq(
		_command_cache_size(server), cache0,
		"失败：command_cache.size 零变化（只读 size，不篡改）")
	assert_eq(
		_authority_domain_hash(server, "start_snap_auth1"), auth0,
		"失败：ARS sha256 相同 → draw 及可能窗口完整回滚")


## Red：start 内 private prompt 失败须原子回滚——含已成功 publish 的 snapshot journal/seq，
## 以及 draw/active window 的 ARS；真实 config/BC/ARS；禁 mock 其它核心。
func test_start_turn_prompt_fail_atomic_rollback() -> void:
	if not _contract_ok():
		return
	var server := FailingTurnPromptServer.new(_cfg(), 0)
	assert_not_null(server, "FailingTurnPromptServer 须可构造")
	if server == null:
		return
	var bc: Variant = server.get("_bc")
	assert_not_null(bc, "构造后 server._bc 须非 null")
	if bc == null:
		return
	assert_not_null(bc.state, "构造后 BC.state 须非 null")
	if bc.state == null:
		return
	# 调用前冻结
	var started0: bool = bool(server.get("_started"))
	var seq0: int = int(server.call("current_server_seq"))
	var j0: Array = _journal_sizes(server, "start_tp0")
	var cache0: int = _command_cache_size(server)
	var auth0: String = _authority_domain_hash(server, "start_tp_auth0")
	assert_eq(started0, false, "start 前 _started 须 false")
	assert_eq(seq0, 0)
	for n in j0:
		assert_eq(int(n), 0)
	assert_eq(cache0, 0)
	assert_eq(auth0.length(), 64)
	# prompt payload 空 → start 须 false；证明命中 override 且 publish 后状态也回滚
	assert_false(
		bool(server.call("start")),
		"start 内 _build_turn_prompt_payload 失败时 start 须 false")
	assert_gt(server.call_count, 0, "须命中 FailingTurnPromptServer._build_turn_prompt_payload")
	assert_eq(server.get("_started"), false, "失败：_started 须恢复 false")
	assert_eq(int(server.call("current_server_seq")), seq0,
		"失败：server_seq 须回滚（含已成功 publish 的 snapshot seq）")
	assert_eq(
		JSON.stringify(_journal_sizes(server, "start_tp1")), JSON.stringify(j0),
		"失败：四席 journal 须回滚（含已 append 的 ROOM_SNAPSHOT）")
	assert_eq(
		_command_cache_size(server), cache0,
		"失败：command_cache.size 零变化（只读 size）")
	assert_eq(
		_authority_domain_hash(server, "start_tp_auth1"), auth0,
		"失败：ARS sha256 相同 → draw/active window 完整回滚")

func test_submit_accepted_causation_followup() -> void:
	var server := _new(_load_server())
	if server == null:
		return
	assert_true(bool(server.call("start")))
	var before := int(server.call("current_server_seq"))
	var meta := _meta(_prompt(server))
	assert_false(meta.is_empty())
	if meta.is_empty():
		return
	var action := _act(meta, 1)
	var jn := _exact_ne(server.call("event_journal", 0), "aj0").size()
	var cr := _as_cr(server.call("submit_action", action), "acc")
	if cr == null:
		return
	assert_eq(cr.status, "ACCEPTED")
	assert_eq(cr.command_id, action.command_id)
	assert_eq(cr.error_code, "")
	var after := _exact_ne(server.call("events_since", 0, before), "af")
	assert_gte(after.size(), 2)
	if after.size() < 2:
		return
	assert_eq(after[0].kind, "ACTION_APPLIED")
	assert_true(_exact(after[0].payload, AA))
	assert_eq(str(after[0].payload["causation_command_id"]), action.command_id)
	assert_eq(cr.server_seq, int(server.call("current_server_seq")),
		"ACCEPTED.server_seq 须指向本次事务最后业务事件")
	assert_eq(cr.server_seq, after[after.size() - 1].server_seq,
		"events_since 最后一条须与 ACCEPTED.server_seq 对齐")
	assert_eq(after[1].kind, "ROOM_SNAPSHOT")
	_snap(after[1], 0, "post")
	assert_eq(after[0].view_hash, after[1].view_hash)
	var ok := false
	for e in after.slice(2):
		if e.kind in ["TURN_PROMPT", "CLAIM_WINDOW", "HAND_SETTLED", "MATCH_SETTLED"]:
			ok = true
	assert_true(ok, "下一 prompt/settle 在 fresh.slice(2)")
	assert_gt(_exact_ne(server.call("event_journal", 0), "aj1").size(), jn)

func test_reject_wrong_decision_room_zero_events() -> void:
	var server := _new(_load_server())
	if server == null:
		return
	assert_true(bool(server.call("start")))
	var seq0 := int(server.call("current_server_seq"))
	var j0 := _exact_ne(server.call("event_journal", 0), "rj0").size()
	var meta := _meta(_prompt(server))
	if meta.is_empty():
		assert_true(false, "须 DISCARD offer")
		return
	var base := _act(meta, 2)
	var bd := base.to_dict()
	bd["decision_id"] = "550e8400-e29b-41d4-a716-0000000000bb"
	bd["command_id"] = _cmd(3)
	var cr1 := _as_cr(server.call("submit_action", Action.from_dict(bd)), "rd")
	if cr1 == null:
		return
	assert_eq(cr1.status, "REJECTED")
	assert_eq(cr1.server_seq, seq0)
	assert_eq(int(server.call("current_server_seq")), seq0)
	assert_eq(_exact_ne(server.call("event_journal", 0), "rj1").size(), j0)
	var br := base.to_dict()
	br["room_id"] = "other-room"
	br["command_id"] = _cmd(4)
	var cr2 := _as_cr(server.call("submit_action", Action.from_dict(br)), "rr")
	if cr2 == null:
		return
	assert_eq(cr2.status, "REJECTED")
	assert_eq(cr2.server_seq, seq0)
	assert_eq(_exact_ne(server.call("event_journal", 0), "rj2").size(), j0)
	assert_false(bool(server.call("start")))
	assert_eq(int(server.call("current_server_seq")), seq0)

func test_events_since_gap_journal_deepcopy() -> void:
	var server := _new(_load_server())
	if server == null:
		return
	assert_true(bool(server.call("start")))
	var all0 := _exact_ne(server.call("events_since", 0, 0), "g0")
	assert_gt(all0.size(), 0)
	if all0.is_empty():
		return
	var first: int = all0[0].server_seq
	for e in _exact_ne(server.call("events_since", 0, first), "g>"):
		assert_gt(e.server_seq, first)
	assert_eq(_exact_ne(server.call("events_since", 0, 999999), "ge").size(), 0)
	assert_lt(_exact_ne(server.call("events_since", 1, 0), "g1").size(), all0.size())
	var j := _exact_ne(server.call("event_journal", 0), "gj0")
	assert_eq(j.size(), all0.size())
	if j.is_empty():
		return
	var orig: Dictionary = j[0].to_dict()
	j.clear()
	var j2 := _exact_ne(server.call("event_journal", 0), "gj1")
	assert_eq(j2.size(), all0.size())
	if j2.is_empty():
		return
	assert_eq(JSON.stringify(j2[0].to_dict()), JSON.stringify(orig))
	j2[0].set("_payload", {"poison": true})
	var j3 := _exact_ne(server.call("event_journal", 0), "gj2")
	assert_gt(j3.size(), 0)
	if j3.is_empty():
		return
	assert_eq(JSON.stringify(j3[0].to_dict()), JSON.stringify(orig))

func _journal_sizes(s: Object, tag: String) -> Array:
	var sizes: Array = []
	for seat in range(4):
		sizes.append(_exact_ne(s.call("event_journal", seat), "%s/j%d" % [tag, seat]).size())
	return sizes


## 只读 command_cache.size；禁止直接写入/清空/篡改 cache 内容。
func _command_cache_size(s: Object) -> int:
	var cache: Variant = s.get("_command_cache")
	assert_eq(typeof(cache), TYPE_DICTIONARY, "_command_cache 须 Dictionary")
	if typeof(cache) != TYPE_DICTIONARY:
		return -1
	return (cache as Dictionary).size()

func _core_fingerprint(s: Object, seat: int, tag: String) -> String:
	var j := _exact_ne(s.call("event_journal", seat), "%s/fp" % tag)
	var snap := _find(j, "ROOM_SNAPSHOT")
	if snap == null:
		return ""
	var p: Dictionary = snap.payload
	for m in p.get("modules", []):
		if str(m.get("module_key", "")) == "core_table":
			return JSON.stringify(m.get("payload", {}))
	return ""

## 真实权威领域 hash：AuthorityReplaySnapshot.capture(BC) → sha256（64 位）。
## 覆盖 BC 领域/行动日志/调度态；禁止 BattleState.snapshot_hash/snapshot_dict 旧双轨。
func _authority_domain_hash(server: Object, tag: String) -> String:
	var bc: Variant = server.get("_bc")
	assert_not_null(bc, "%s: server._bc 须非 null" % tag)
	if bc == null:
		return ""
	var snap: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(bc)
	assert_not_null(snap, "%s: AuthorityReplaySnapshot.capture 须非 null" % tag)
	if snap == null:
		return ""
	var h: String = snap.sha256()
	assert_eq(h.length(), 64, "%s: sha256 须 64 位 hex" % tag)
	return h

## Red：start 前 public submit 必须拒绝；started / server_seq / journal / BC 领域态零修改。
func test_submit_before_start_rejected_zero_mutation() -> void:
	var server := _new(_load_server())
	if server == null:
		return
	var pristine := _new(_load_server())
	if pristine == null:
		return
	assert_eq(server.get("_started"), false, "构造后 started 须 false")
	var seq0 := int(server.call("current_server_seq"))
	var j0 := _journal_sizes(server, "pre0")
	assert_eq(seq0, 0)
	for n in j0:
		assert_eq(int(n), 0)
	# 真实 Action fixture（无 prompt 时手写合法结构字段；start 前不得被接受）
	var action := Action.from_dict({
		"protocol_version": 1, "command_id": _cmd(10), "room_id": SID,
		"seat": 0, "hand_seq": 0, "decision_id": _cmd(99), "kind": "DISCARD",
		"payload": {"tile_instance_id": 1}, "client_seq": 10})
	assert_not_null(action, "Action.from_dict 须成功")
	if action == null:
		return
	var cr := _as_cr(server.call("submit_action", action), "pre_start")
	if cr == null:
		return
	assert_eq(cr.status, "REJECTED", "start 前 submit 须 REJECTED")
	assert_ne(cr.error_code, "", "start 前 reject 须有 error_code")
	assert_eq(server.get("_started"), false, "submit 后 started 仍 false")
	assert_eq(int(server.call("current_server_seq")), seq0, "server_seq 零修改")
	assert_eq(cr.server_seq, seq0, "CR.server_seq 对齐未推进 seq")
	var j1 := _journal_sizes(server, "pre1")
	assert_eq(JSON.stringify(j1), JSON.stringify(j0), "journal 全席零修改")
	# 与未 submit 的同 seed 实例对比：start 后 core 领域指纹一致 → BC 未被污染
	assert_true(bool(server.call("start")), "拒绝后 start 仍可成功")
	assert_true(bool(pristine.call("start")))
	assert_eq(server.get("_started"), true, "start 后 started 须 true")
	var fp_s := _core_fingerprint(server, 0, "mut")
	var fp_p := _core_fingerprint(pristine, 0, "pri")
	assert_false(fp_s.is_empty(), "start 后须有 core_table")
	assert_eq(fp_s, fp_p, "BC 可观测领域态与未污染实例一致")
	# command cache 零写入：start 后以同 command_id 的合法 HUMAN Action 须 ACCEPTED
	var meta := _meta(_prompt(server))
	assert_false(meta.is_empty(), "start 后须有 DISCARD offer")
	if meta.is_empty():
		return
	var human := _act(meta, 10)
	assert_eq(human.command_id, action.command_id, "command_id 须与 start 前同为 _cmd(10)")
	assert_eq(human.command_id, _cmd(10))
	var seq_after_start := int(server.call("current_server_seq"))
	var j_after_start := _exact_ne(server.call("event_journal", 0), "pre_j_post_start").size()
	var cr2 := _as_cr(server.call("submit_action", human), "post_start_same_cmd")
	if cr2 == null:
		return
	assert_eq(cr2.status, "ACCEPTED", "同 command_id 未被 pre-start reject 污染缓存")
	assert_eq(cr2.error_code, "")
	assert_gt(int(server.call("current_server_seq")), seq_after_start)
	assert_gt(_exact_ne(server.call("event_journal", 0), "pre_j_post").size(), j_after_start)

## Red：start 后 public submit 仅允许 HUMAN seat；AI seat 合法 Action → UNAUTHORIZED 且零副作用。
func test_submit_ai_seat_unauthorized_zero_mutation() -> void:
	var server := _new(_load_server())
	if server == null:
		return
	assert_true(bool(server.call("start")))
	assert_eq(server.get("_started"), true, "start 后 started 须 true")
	# PARTS[0]=HUMAN, PARTS[1..3]=AI；确认 fixture 契约
	assert_eq(PARTS[0], &"HUMAN")
	assert_eq(PARTS[1], &"AI")
	var seq0 := int(server.call("current_server_seq"))
	var j0 := _journal_sizes(server, "ai0")
	var fp0 := _core_fingerprint(server, 0, "ai_fp0")
	assert_false(fp0.is_empty())
	var meta := _meta(_prompt(server))
	assert_false(meta.is_empty(), "须有 DISCARD offer（真实合法 Action 基底）")
	if meta.is_empty():
		return
	# 真实合法 Action：从当前 prompt 构造，仅 seat 改为 AI（ParticipantKind.AI）
	var ai_seat := 1
	assert_eq(PARTS[ai_seat], &"AI")
	var d := _act(meta, 20).to_dict()
	d["seat"] = ai_seat
	d["command_id"] = _cmd(20)
	var ai_action := Action.from_dict(d)
	var cr := _as_cr(server.call("submit_action", ai_action), "ai_unauth")
	if cr == null:
		return
	assert_eq(cr.error_code, "UNAUTHORIZED", "AI seat public submit 须 UNAUTHORIZED")
	assert_eq(cr.status, "REJECTED")
	assert_eq(cr.command_id, ai_action.command_id)
	assert_eq(cr.server_seq, seq0)
	assert_eq(int(server.call("current_server_seq")), seq0, "server_seq 零修改")
	var j1 := _journal_sizes(server, "ai1")
	assert_eq(JSON.stringify(j1), JSON.stringify(j0), "journal 全席零修改")
	var fp1 := _core_fingerprint(server, 0, "ai_fp1")
	assert_eq(fp1, fp0, "BC 可观测领域态零修改")
	# command cache 零写入：随后 HUMAN 用同一 command_id 提交须可 ACCEPTED（若误缓存 UNAUTHORIZED 则失败）
	var human := _act(meta, 20)
	assert_eq(human.command_id, ai_action.command_id)
	assert_eq(int(human.seat), 0)
	assert_eq(PARTS[0], &"HUMAN")
	var cr_h := _as_cr(server.call("submit_action", human), "human_same_cmd")
	if cr_h == null:
		return
	assert_eq(cr_h.status, "ACCEPTED", "同 command_id 未被 UNAUTHORIZED 污染缓存")
	assert_eq(cr_h.error_code, "")
	assert_gt(int(server.call("current_server_seq")), seq0)
	assert_gt(_exact_ne(server.call("event_journal", 0), "ai_j_post").size(), int(j0[0]))

## 同 hand_seq 命名空间内另一合法 tile_instance_id（Action.from_dict 可过；非业务可执行断言）。
func _other_namespace_tile_id(hand_seq: int, current_iid: int) -> int:
	var base: int = hand_seq * 136
	var alt: int = current_iid + 1
	if alt > base + 135:
		alt = current_iid - 1
	assert_ne(alt, current_iid, "须选出不同 tile_instance_id")
	assert_gte(alt, base)
	assert_lte(alt, base + 135)
	return alt

## Red：command fingerprint 幂等——同指纹回放原 CR；异指纹 COMMAND_ID_CONFLICT 且不覆盖 cache；client_seq 不参与。
func test_command_fingerprint_idempotency_and_conflict() -> void:
	var server := _new(_load_server())
	if server == null:
		return
	assert_true(bool(server.call("start")))
	var meta := _meta(_prompt(server))
	assert_false(meta.is_empty(), "须有 DISCARD offer（真实合法 Action 基底）")
	if meta.is_empty():
		return

	# ── 1) 首次合法 HUMAN Action → ACCEPTED；冻结 CR.to_dict / seq / 四席 journal / core / authority ──
	var first := _act(meta, 30)
	assert_not_null(first, "Action.from_dict（经 _act）须非 null")
	if first == null:
		return
	assert_eq(int(first.seat), 0)
	assert_eq(PARTS[0], &"HUMAN")
	var cr1 := _as_cr(server.call("submit_action", first), "fp_first")
	if cr1 == null:
		return
	assert_eq(cr1.status, "ACCEPTED", "首次合法 HUMAN 须 ACCEPTED")
	assert_eq(cr1.command_id, first.command_id)
	assert_eq(cr1.error_code, "")
	var frozen_cr: Dictionary = cr1.to_dict().duplicate(true)
	var frozen_seq: int = int(server.call("current_server_seq"))
	var frozen_js: Array = _journal_sizes(server, "fp0")
	var frozen_core: String = _core_fingerprint(server, 0, "fp_core0")
	assert_false(frozen_core.is_empty(), "接受后须有 core_table 指纹")
	var frozen_auth: String = _authority_domain_hash(server, "fp_auth0")
	assert_eq(frozen_auth.length(), 64, "接受后 authority sha256 须 64 位")
	assert_eq(int(frozen_cr["server_seq"]), cr1.server_seq)
	assert_eq(str(frozen_cr["status"]), "ACCEPTED")

	# ── 2) 同 command_id / room / seat / kind / payload，client_seq 不同 → 原 CR 字节等价；状态零变化 ──
	# client_seq 明确不参与业务指纹。
	var d_same := first.to_dict()
	assert_eq(str(d_same["command_id"]), first.command_id)
	assert_eq(str(d_same["room_id"]), first.room_id)
	assert_eq(int(d_same["seat"]), int(first.seat))
	assert_eq(str(d_same["kind"]), first.kind)
	assert_eq(JSON.stringify(d_same["payload"]), JSON.stringify(first.payload))
	d_same["client_seq"] = int(first.client_seq) + 777
	assert_ne(int(d_same["client_seq"]), int(first.client_seq), "client_seq 必须不同")
	var same_fp := Action.from_dict(d_same)
	assert_not_null(same_fp, "同指纹不同 client_seq 的 Action.from_dict 须非 null")
	if same_fp == null:
		return
	assert_eq(same_fp.command_id, first.command_id)
	assert_ne(same_fp.client_seq, first.client_seq)
	assert_eq(same_fp.room_id, first.room_id)
	assert_eq(int(same_fp.seat), int(first.seat))
	assert_eq(same_fp.kind, first.kind)
	assert_eq(JSON.stringify(same_fp.payload), JSON.stringify(first.payload))
	var cr_same := _as_cr(server.call("submit_action", same_fp), "fp_same")
	if cr_same == null:
		return
	assert_eq(
		JSON.stringify(cr_same.to_dict()), JSON.stringify(frozen_cr),
		"同指纹回放须与首次 CommandResult.to_dict 字节等价")
	assert_eq(int(server.call("current_server_seq")), frozen_seq, "同指纹 replay：server_seq 零变化")
	assert_eq(
		JSON.stringify(_journal_sizes(server, "fp_same_j")), JSON.stringify(frozen_js),
		"同指纹 replay：四席 journal 零变化")
	assert_eq(
		_core_fingerprint(server, 0, "fp_same_core"), frozen_core,
		"同指纹 replay：core 零变化")
	assert_eq(
		_authority_domain_hash(server, "fp_same_auth"), frozen_auth,
		"同指纹 replay：AuthorityReplaySnapshot 领域/日志/调度态零变化")

	# ── 3a) 同 command_id / room / seat / kind，normalized payload 换同 hand_seq 命名空间另一合法 id ──
	var other_iid: int = _other_namespace_tile_id(int(meta["hand_seq"]), int(meta["tile_instance_id"]))
	var d_tile := first.to_dict()
	d_tile["payload"] = {"tile_instance_id": other_iid}
	d_tile["client_seq"] = int(first.client_seq) + 1
	var conflict_tile := Action.from_dict(d_tile)
	assert_not_null(conflict_tile, "异 payload 合法 Action.from_dict 须非 null")
	if conflict_tile == null:
		return
	assert_eq(conflict_tile.command_id, first.command_id)
	assert_eq(conflict_tile.room_id, first.room_id)
	assert_eq(int(conflict_tile.seat), int(first.seat))
	assert_eq(conflict_tile.kind, first.kind)
	assert_ne(int(conflict_tile.payload["tile_instance_id"]), int(first.payload["tile_instance_id"]))
	var seq_before_a: int = int(server.call("current_server_seq"))
	var cr_tile := _as_cr(server.call("submit_action", conflict_tile), "fp_tile")
	if cr_tile == null:
		return
	assert_eq(cr_tile.status, "REJECTED", "异 payload 指纹须 REJECTED（禁错误回放首次 ACCEPTED）")
	assert_eq(cr_tile.error_code, "COMMAND_ID_CONFLICT")
	assert_eq(cr_tile.command_id, first.command_id)
	assert_eq(cr_tile.server_seq, seq_before_a, "冲突 CR.server_seq 等于冲突前当前 seq")
	assert_eq(int(server.call("current_server_seq")), frozen_seq, "3a：server_seq 零变化")
	assert_eq(
		JSON.stringify(_journal_sizes(server, "fp_tile_j")), JSON.stringify(frozen_js),
		"3a：四席 journal 零变化")
	assert_eq(
		_core_fingerprint(server, 0, "fp_tile_core"), frozen_core,
		"3a：core 零变化")
	assert_eq(
		_authority_domain_hash(server, "fp_tile_auth"), frozen_auth,
		"3a：AuthorityReplaySnapshot 领域/日志/调度态零变化")

	# ── 3b) 同 command_id，room_id → other-room（异业务指纹）──
	var d_room := first.to_dict()
	d_room["room_id"] = "other-room"
	d_room["client_seq"] = int(first.client_seq) + 2
	var conflict_room := Action.from_dict(d_room)
	assert_not_null(conflict_room, "异 room 合法 Action.from_dict 须非 null")
	if conflict_room == null:
		return
	assert_eq(conflict_room.command_id, first.command_id)
	assert_eq(conflict_room.room_id, "other-room")
	assert_ne(conflict_room.room_id, first.room_id)
	assert_eq(int(conflict_room.seat), int(first.seat))
	assert_eq(conflict_room.kind, first.kind)
	assert_eq(JSON.stringify(conflict_room.payload), JSON.stringify(first.payload))
	var seq_before_b: int = int(server.call("current_server_seq"))
	var cr_room := _as_cr(server.call("submit_action", conflict_room), "fp_room")
	if cr_room == null:
		return
	assert_eq(cr_room.status, "REJECTED", "异 room 指纹须 REJECTED（禁错误回放首次 ACCEPTED）")
	assert_eq(cr_room.error_code, "COMMAND_ID_CONFLICT")
	assert_eq(cr_room.command_id, first.command_id)
	assert_eq(cr_room.server_seq, seq_before_b, "冲突 CR.server_seq 等于冲突前当前 seq")
	assert_eq(int(server.call("current_server_seq")), frozen_seq, "3b：server_seq 零变化")
	assert_eq(
		JSON.stringify(_journal_sizes(server, "fp_room_j")), JSON.stringify(frozen_js),
		"3b：四席 journal 零变化")
	assert_eq(
		_core_fingerprint(server, 0, "fp_room_core"), frozen_core,
		"3b：core 零变化")
	assert_eq(
		_authority_domain_hash(server, "fp_room_auth"), frozen_auth,
		"3b：AuthorityReplaySnapshot 领域/日志/调度态零变化")

	# ── 4) 冲突后再提交步骤 2 同指纹 replay → 仍为首次原 CR；证明冲突未覆盖 cache ──
	var cr_again := _as_cr(server.call("submit_action", same_fp), "fp_again")
	if cr_again == null:
		return
	assert_eq(
		JSON.stringify(cr_again.to_dict()), JSON.stringify(frozen_cr),
		"冲突后同指纹 replay 仍须首次原 CommandResult（cache 未被覆盖）")
	assert_eq(int(server.call("current_server_seq")), frozen_seq, "4：server_seq 零变化")
	assert_eq(
		JSON.stringify(_journal_sizes(server, "fp_again_j")), JSON.stringify(frozen_js),
		"4：四席 journal 零变化")
	assert_eq(
		_core_fingerprint(server, 0, "fp_again_core"), frozen_core,
		"4：core 零变化")
	assert_eq(
		_authority_domain_hash(server, "fp_again_auth"), frozen_auth,
		"4：AuthorityReplaySnapshot 领域/日志/调度态零变化")


func test_command_fingerprint_binds_hand_and_decision_window() -> void:
	var server := LocalLoopbackServer.new(_cfg(), 0)
	var command_id: String = _cmd(360)
	var decision_a: String = _cmd(361)
	var decision_b: String = _cmd(362)
	var base: Action = Action.make_pass(
		0, SID, command_id, decision_a, 0, 10)
	var transport_retry: Action = Action.make_pass(
		0, SID, command_id, decision_a, 0, 999)
	var other_decision: Action = Action.make_pass(
		0, SID, command_id, decision_b, 0, 10)
	var other_hand: Action = Action.make_pass(
		0, SID, command_id, decision_a, 1, 10)
	assert_not_null(base)
	assert_not_null(transport_retry)
	assert_not_null(other_decision)
	assert_not_null(other_hand)

	var fp_base: String = server._business_fingerprint(base)
	assert_eq(server._business_fingerprint(transport_retry), fp_base,
		"client_seq 仅为传输重试序号，不参与业务幂等指纹")
	assert_ne(server._business_fingerprint(other_decision), fp_base,
		"同 command_id 在不同 decision window 必须冲突，不能回放旧 ACCEPTED")
	assert_ne(server._business_fingerprint(other_hand), fp_base,
		"同 command_id 在不同 hand_seq 必须冲突，不能跨局回放旧 ACCEPTED")


## 四席 journal 完整 to_dict 冻结（非仅 sizes）；供原子失败对比。
func _journal_dicts(s: Object, tag: String) -> Array:
	var out: Array = []
	for seat in range(4):
		var j := _exact_ne(s.call("event_journal", seat), "%s/jd%d" % [tag, seat])
		var dicts: Array = []
		for e in j:
			dicts.append((e as NetworkedEvent).to_dict())
		out.append(dicts)
	return out


## 该席 journal 中最后 committed ROOM_SNAPSHOT.view_hash（不假定末条即 snapshot）。
func _last_committed_snap_vh(s: Object, seat: int, tag: String) -> String:
	var j := _exact_ne(s.call("event_journal", seat), "%s/lvh%d" % [tag, seat])
	for i in range(j.size() - 1, -1, -1):
		var e: NetworkedEvent = j[i] as NetworkedEvent
		if e.kind == "ROOM_SNAPSHOT":
			var vh: String = str(e.view_hash)
			assert_eq(vh.length(), 64, "%s seat%d 最后 ROOM_SNAPSHOT.view_hash 须 64" % [tag, seat])
			return vh
	assert_true(false, "%s seat%d 须有 committed ROOM_SNAPSHOT" % [tag, seat])
	return ""


## 真实 CLAIM fixture（不 submit_action；不伪造 DecisionWindow/Tile/ActionResolution）。
## start → seat0 真实 TURN_PROMPT DISCARD → bc.apply_action(HUMAN) →
## 断言 CLAIM 窗 → publish_snapshot 四席 post-action snap → 四席 decision_context 打开/确认。
func _arm_claim_after_discard(server: Object, tag: String) -> bool:
	assert_true(bool(server.call("start")), "%s: start 须 true" % tag)
	if not bool(server.get("_started")):
		return false
	var prompt := _prompt(server)
	assert_not_null(prompt, "%s: start 后 seat0 须有 private prompt" % tag)
	if prompt == null:
		return false
	assert_eq(prompt.kind, "TURN_PROMPT", "%s: seat0 须 TURN_PROMPT（非 CLAIM）" % tag)
	var meta := _meta(prompt)
	assert_false(meta.is_empty(), "%s: TURN_PROMPT 须含 DISCARD offer" % tag)
	if meta.is_empty():
		return false
	assert_eq(int(meta["seat"]), 0, "%s: discarder 须 seat0" % tag)
	var action := _act(meta, 200, CLAIM_SID)
	assert_not_null(action, "%s: 真实 DISCARD Action 须可构造" % tag)
	if action == null:
		return false
	var bc: Variant = server.get("_bc")
	assert_not_null(bc, "%s: server._bc 须非 null" % tag)
	if bc == null:
		return false
	# 禁止 submit_action：直接权威入口 apply_action
	var res: ActionResolution = bc.apply_action(action, ActionSource.HUMAN)
	assert_not_null(res, "%s: apply_action 须返 ActionResolution" % tag)
	if res == null:
		return false
	assert_true(res.accepted, "%s: 合法 DISCARD 须 accepted" % tag)
	if not res.accepted:
		return false
	# 打开真实 CLAIM 窗（apply 后 window 已 invalidate；不污染私有字段）
	for s in range(4):
		bc.decision_context_for_seat(s)
	var win = bc.get("_active_window")
	assert_true(win is DecisionWindow, "%s: 须有真实 active DecisionWindow" % tag)
	if not (win is DecisionWindow):
		return false
	assert_eq((win as DecisionWindow).kind, DecisionWindow.KIND_CLAIM,
		"%s: active DecisionWindow.kind 须 CLAIM" % tag)
	if (win as DecisionWindow).kind != DecisionWindow.KIND_CLAIM:
		return false
	# post-action 四席 ROOM_SNAPSHOT（不经 submit 的 AA/AI 路径）
	assert_true(bool(server.call("publish_snapshot")),
		"%s: post-action publish_snapshot 须 true" % tag)
	# 再确认/打开 CLAIM 窗
	for s2 in range(4):
		bc.decision_context_for_seat(s2)
	win = bc.get("_active_window")
	assert_true(win is DecisionWindow, "%s: publish 后仍须有 DecisionWindow" % tag)
	if not (win is DecisionWindow):
		return false
	assert_eq((win as DecisionWindow).kind, DecisionWindow.KIND_CLAIM,
		"%s: publish 后 kind 须仍 CLAIM" % tag)
	return (win as DecisionWindow).kind == DecisionWindow.KIND_CLAIM


## Red：CLAIM 多 recipient 中途 payload 失败须原子零副作用——
## 禁先 alloc seq、禁首 target 半 append；完整 journal JSON + ARS 不变。
func test_claim_window_fail_second_target_atomic_zero_mutation() -> void:
	if not _contract_ok():
		return
	var cfg := _cfg_all_human()
	assert_not_null(cfg, "全 HUMAN GameSessionConfig 须可构造")
	if cfg == null:
		return
	var server := FailingClaimPromptServer.new(cfg, 0)
	assert_not_null(server, "FailingClaimPromptServer 须可构造")
	if server == null:
		return
	if not _arm_claim_after_discard(server, "claim_fail_arm"):
		return
	var bc: Variant = server.get("_bc")
	assert_not_null(bc)
	if bc == null:
		return
	# 冻结：seq + 四席完整 journal to_dict + ARS sha256
	var seq0: int = int(server.call("current_server_seq"))
	var j0: Array = _journal_dicts(server, "claim_fail0")
	var ars0: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(bc)
	assert_not_null(ars0, "冻结前 ARS.capture 须非 null")
	if ars0 == null:
		return
	var auth0: String = ars0.sha256()
	assert_eq(auth0.length(), 64, "冻结前 ARS sha256 须 64")
	# 第二次 _build_claim_window_payload 空 → 须 false 且零半提交
	assert_false(
		bool(server.call("_emit_private_prompt")),
		"CLAIM 中途 payload 失败时 _emit_private_prompt 须 false")
	assert_gte(server.call_count, 2,
		"须至少两次 _build_claim_window_payload（证明第二 target 命中 fail）")
	assert_eq(int(server.call("current_server_seq")), seq0,
		"失败：server_seq 零变化（禁先 _alloc_seq）")
	assert_eq(
		JSON.stringify(_journal_dicts(server, "claim_fail1")), JSON.stringify(j0),
		"失败：四席完整 journal to_dict 零变化（禁首 target 半 append）")
	var ars1: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(bc)
	assert_not_null(ars1)
	if ars1 == null:
		return
	assert_eq(ars1.sha256(), auth0,
		"失败：AuthorityReplaySnapshot.sha256 零变化")


## Red/契约：同 fixture 成功路径——eligible human recipients 同逻辑 seq 各恰 +1 CLAIM_WINDOW；
## view_hash=各席最后 committed ROOM_SNAPSHOT；非 target journal 不变；seq 只 +1。
func test_claim_window_success_multi_recipient_atomic_publish() -> void:
	if not _contract_ok():
		return
	var cfg := _cfg_all_human()
	assert_not_null(cfg, "全 HUMAN GameSessionConfig 须可构造")
	if cfg == null:
		return
	var server: Object = LocalLoopbackServer.new(cfg, 0)
	assert_not_null(server, "LocalLoopbackServer 全 HUMAN 须可构造")
	if server == null:
		return
	if not _arm_claim_after_discard(server, "claim_ok_arm"):
		return
	var bc: Variant = server.get("_bc")
	assert_not_null(bc)
	if bc == null:
		return
	var win = bc.get("_active_window")
	assert_true(win is DecisionWindow)
	if not (win is DecisionWindow):
		return
	var dw: DecisionWindow = win as DecisionWindow
	assert_eq(dw.kind, DecisionWindow.KIND_CLAIM)
	# eligible human recipients：dw.seats 且未 responded（本 fixture 全 HUMAN）
	var eligible: Array = []
	for s in dw.seats():
		var si: int = int(s)
		if dw.has_responded(si):
			continue
		eligible.append(si)
	eligible.sort()
	assert_gt(eligible.size(), 1, "须有多个 CLAIM recipients 才测多席原子")
	if eligible.size() < 2:
		return
	# 冻结各席最后 committed ROOM_SNAPSHOT.view_hash + journal sizes + seq
	var frozen_vh: Dictionary = {}
	var sizes0: Array = []
	for seat in range(4):
		frozen_vh[seat] = _last_committed_snap_vh(server, seat, "claim_ok_vh0")
		sizes0.append(_exact_ne(server.call("event_journal", seat), "claim_ok_sz0/%d" % seat).size())
	var seq0: int = int(server.call("current_server_seq"))
	var j0_non_target: Dictionary = {}
	for seat2 in range(4):
		if eligible.has(seat2):
			continue
		j0_non_target[seat2] = _journal_dicts_one(server, seat2, "claim_ok_nt0")
	# 成功发射
	assert_true(bool(server.call("_emit_private_prompt")),
		"CLAIM 成功路径 _emit_private_prompt 须 true")
	assert_eq(int(server.call("current_server_seq")), seq0 + 1,
		"成功：server_seq 只 +1（同逻辑 seq 多 recipient）")
	var shared_seq: int = -1
	for ti in eligible:
		var seat_i: int = int(ti)
		var j := _exact_ne(server.call("event_journal", seat_i), "claim_ok_j/%d" % seat_i)
		assert_eq(j.size(), int(sizes0[seat_i]) + 1,
			"eligible seat%d 恰 +1 条" % seat_i)
		if j.size() != int(sizes0[seat_i]) + 1:
			return
		var last: NetworkedEvent = j[j.size() - 1] as NetworkedEvent
		assert_eq(last.kind, "CLAIM_WINDOW", "seat%d 新增末条须 CLAIM_WINDOW" % seat_i)
		# 严格 NetworkedEvent.from_dict roundtrip
		var rt: NetworkedEvent = NetworkedEvent.from_dict(last.to_dict())
		assert_not_null(rt, "seat%d CLAIM_WINDOW 须 from_dict roundtrip 成功" % seat_i)
		if rt == null:
			return
		assert_eq(rt.kind, "CLAIM_WINDOW")
		assert_eq(int(rt.server_seq), int(last.server_seq))
		assert_eq(rt.view_hash, last.view_hash)
		assert_eq(JSON.stringify(rt.to_dict()), JSON.stringify(last.to_dict()),
			"seat%d CLAIM_WINDOW roundtrip 字节级一致" % seat_i)
		if shared_seq < 0:
			shared_seq = int(last.server_seq)
		else:
			assert_eq(int(last.server_seq), shared_seq,
				"所有 eligible 共用同一 server_seq")
		assert_eq(last.view_hash, str(frozen_vh[seat_i]),
			"seat%d CLAIM_WINDOW.view_hash 须等于该席冻结 ROOM_SNAPSHOT hash" % seat_i)
	assert_eq(shared_seq, seq0 + 1, "CLAIM_WINDOW.server_seq 须为冻结 seq+1")
	# 非 target journal 完整不变
	for seat3 in range(4):
		if eligible.has(seat3):
			continue
		assert_eq(
			JSON.stringify(_journal_dicts_one(server, seat3, "claim_ok_nt1")),
			JSON.stringify(j0_non_target[seat3]),
			"非 target seat%d journal 完整不变" % seat3)
		assert_eq(
			_exact_ne(server.call("event_journal", seat3), "claim_ok_sz1/%d" % seat3).size(),
			int(sizes0[seat3]),
			"非 target seat%d size 不变" % seat3)


func _journal_dicts_one(s: Object, seat: int, tag: String) -> Array:
	var j := _exact_ne(s.call("event_journal", seat), "%s/one" % tag)
	var dicts: Array = []
	for e in j:
		dicts.append((e as NetworkedEvent).to_dict())
	return dicts


## BC.action_journal 每项 Action.to_dict（禁手改 _action_journal）。
func _bc_action_journal_dicts(bc: Variant, tag: String) -> Array:
	assert_not_null(bc, "%s: bc 须非 null" % tag)
	if bc == null:
		return []
	assert_true(bc.has_method("action_journal"), "%s: bc 须有 action_journal" % tag)
	var out: Array = []
	for item in bc.call("action_journal"):
		assert_true(item is Action, "%s: action_journal 项须 Action" % tag)
		if item is Action:
			out.append((item as Action).to_dict())
	return out


## active DecisionWindow.to_dict；无窗口 → {}。只读 get，禁手改。
func _bc_active_window_dict(bc: Variant) -> Dictionary:
	if bc == null:
		return {}
	var win = bc.get("_active_window")
	if win is DecisionWindow:
		return (win as DecisionWindow).to_dict()
	return {}


## accepted 批处理原子性冻结：seq / 四席 journal to_dict / action_journal /
## active window / ARS.sha256 / command_cache.size。禁旧 BattleState.snapshot_*。
func _freeze_accepted_batch_state(server: Object, tag: String) -> Dictionary:
	var bc: Variant = server.get("_bc")
	assert_not_null(bc, "%s: server._bc 须非 null" % tag)
	var ars: AuthorityReplaySnapshot = null
	if bc != null:
		ars = AuthorityReplaySnapshot.capture(bc)
	assert_not_null(ars, "%s: AuthorityReplaySnapshot.capture 须非 null" % tag)
	var auth: String = ""
	if ars != null:
		auth = ars.sha256()
		assert_eq(auth.length(), 64, "%s: ARS sha256 须 64" % tag)
	return {
		"seq": int(server.call("current_server_seq")),
		"journals": _journal_dicts(server, "%s/j" % tag),
		"action_journal": _bc_action_journal_dicts(bc, "%s/aj" % tag),
		"window": _bc_active_window_dict(bc),
		"auth": auth,
		"cache": _command_cache_size(server),
	}


## 全 HUMAN start → seat0 真实 TURN_PROMPT → 真实 DISCARD（room=CLAIM_SID）。
## 返回 {server, action, meta}；任一步失败 → {}。
func _arm_all_human_discard(server: Object, cmd_n: int, tag: String) -> Dictionary:
	assert_true(bool(server.call("start")), "%s: start 须 true" % tag)
	if not bool(server.get("_started")):
		return {}
	var prompt := _prompt(server)
	assert_not_null(prompt, "%s: start 后 seat0 须有 private prompt" % tag)
	if prompt == null:
		return {}
	assert_eq(prompt.kind, "TURN_PROMPT", "%s: seat0 须 TURN_PROMPT" % tag)
	var meta := _meta(prompt)
	assert_false(meta.is_empty(), "%s: TURN_PROMPT 须含 DISCARD offer" % tag)
	if meta.is_empty():
		return {}
	assert_eq(int(meta["seat"]), 0, "%s: actor 须 seat0" % tag)
	var action := _act(meta, cmd_n, CLAIM_SID)
	assert_not_null(action, "%s: 真实 DISCARD Action 须可构造" % tag)
	if action == null:
		return {}
	assert_eq(action.room_id, CLAIM_SID, "%s: room 须 CLAIM_SID" % tag)
	return {"server": server, "action": action, "meta": meta}


## 失败后与冻结态全零对比（journal/ARS/action_journal/window/cache/seq）。
func _assert_accepted_batch_zero_mutation(server: Object, frozen: Dictionary, tag: String) -> void:
	assert_eq(int(server.call("current_server_seq")), int(frozen["seq"]),
		"%s: server_seq 零变化" % tag)
	assert_eq(
		JSON.stringify(_journal_dicts(server, "%s/j1" % tag)),
		JSON.stringify(frozen["journals"]),
		"%s: 四席完整 journal to_dict 零变化" % tag)
	var bc: Variant = server.get("_bc")
	assert_not_null(bc, "%s: _bc" % tag)
	if bc == null:
		return
	assert_eq(
		JSON.stringify(_bc_action_journal_dicts(bc, "%s/aj1" % tag)),
		JSON.stringify(frozen["action_journal"]),
		"%s: BC action_journal to_dict 零变化" % tag)
	assert_eq(
		JSON.stringify(_bc_active_window_dict(bc)),
		JSON.stringify(frozen["window"]),
		"%s: active DecisionWindow.to_dict 零变化（窗口完整恢复）" % tag)
	var ars: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(bc)
	assert_not_null(ars, "%s: ARS.capture" % tag)
	if ars == null:
		return
	assert_eq(ars.sha256(), str(frozen["auth"]),
		"%s: AuthorityReplaySnapshot.sha256 零变化" % tag)
	assert_eq(_command_cache_size(server), int(frozen["cache"]),
		"%s: command_cache.size 零变化（失败未缓存）" % tag)


## Red：accepted 批 ACTION_APPLIED recipient seat1 构建失败须原子零副作用。
## 失败 seam 命中 → REJECTED；四席 journal/ARS/action_journal/window/cache/seq 全零变化；
## 禁用后同 command_id 重试须 ACCEPTED（证明未缓存且窗口可恢复）。
func test_submit_accepted_action_applied_recipient_fail_atomic_zero_mutation() -> void:
	if not _contract_ok():
		return
	var cfg := _cfg_all_human()
	assert_not_null(cfg)
	if cfg == null:
		return
	var server := FailingAcceptedBatchServer.new(cfg, 0)
	assert_not_null(server, "FailingAcceptedBatchServer 须可构造")
	if server == null:
		return
	assert_eq(server.enabled, false, "start 前 enabled 须 false")
	var armed := _arm_all_human_discard(server, 310, "aa_fail_arm")
	if armed.is_empty():
		return
	var action: Action = armed["action"] as Action
	# 构造后再启用失败，避免影响初始 snapshot/prompt
	server.enabled = true
	server.fail_kind = "ACTION_APPLIED"
	server.fail_seat = 1
	server.call_count = 0
	var frozen: Dictionary = _freeze_accepted_batch_state(server, "aa_fail0")
	var cr := _as_cr(server.call("submit_action", action), "aa_fail_submit")
	if cr == null:
		return
	# Red 闸：seam 未接入时 call_count=0 或仍 ACCEPTED → 断言失败后提前 return，避免噪音
	assert_gt(server.call_count, 0,
		"须命中 FailingAcceptedBatchServer._build_recipient_event(ACTION_APPLIED, seat1)")
	assert_eq(cr.status, "REJECTED",
		"ACTION_APPLIED recipient 失败须 CommandResult REJECTED")
	if server.call_count <= 0 or cr.status != "REJECTED":
		return
	assert_ne(cr.error_code, "", "REJECTED 须非空 error_code")
	assert_eq(cr.command_id, action.command_id)
	assert_eq(cr.server_seq, int(frozen["seq"]), "失败 CR.server_seq 等于冻结 seq")
	_assert_accepted_batch_zero_mutation(server, frozen, "aa_fail")
	# 禁用失败，同 command_id/action 重试 → ACCEPTED（失败未缓存、窗口完整）
	server.enabled = false
	var cr2 := _as_cr(server.call("submit_action", action), "aa_fail_retry")
	if cr2 == null:
		return
	assert_eq(cr2.status, "ACCEPTED",
		"禁用 seam 后同 command_id 重试须 ACCEPTED（失败未写入 command_cache）")
	assert_eq(cr2.error_code, "")
	assert_eq(cr2.command_id, action.command_id)
	assert_gt(int(server.call("current_server_seq")), int(frozen["seq"]),
		"重试成功后 server_seq 须推进")


## Red：accepted 批 ROOM_SNAPSHOT recipient seat2 构建失败须原子零副作用。
func test_submit_accepted_room_snapshot_recipient_fail_atomic_zero_mutation() -> void:
	if not _contract_ok():
		return
	var cfg := _cfg_all_human()
	assert_not_null(cfg)
	if cfg == null:
		return
	var server := FailingAcceptedBatchServer.new(cfg, 0)
	assert_not_null(server, "FailingAcceptedBatchServer 须可构造")
	if server == null:
		return
	assert_eq(server.enabled, false, "start 前 enabled 须 false")
	var armed := _arm_all_human_discard(server, 311, "rs_fail_arm")
	if armed.is_empty():
		return
	var action: Action = armed["action"] as Action
	server.enabled = true
	server.fail_kind = "ROOM_SNAPSHOT"
	server.fail_seat = 2
	server.call_count = 0
	var frozen: Dictionary = _freeze_accepted_batch_state(server, "rs_fail0")
	var cr := _as_cr(server.call("submit_action", action), "rs_fail_submit")
	if cr == null:
		return
	assert_gt(server.call_count, 0,
		"须命中 FailingAcceptedBatchServer._build_recipient_event(ROOM_SNAPSHOT, seat2)")
	assert_eq(cr.status, "REJECTED",
		"ROOM_SNAPSHOT recipient 失败须 CommandResult REJECTED")
	if server.call_count <= 0 or cr.status != "REJECTED":
		return
	assert_ne(cr.error_code, "", "REJECTED 须非空 error_code")
	assert_eq(cr.command_id, action.command_id)
	assert_eq(cr.server_seq, int(frozen["seq"]), "失败 CR.server_seq 等于冻结 seq")
	_assert_accepted_batch_zero_mutation(server, frozen, "rs_fail")
	server.enabled = false
	var cr2 := _as_cr(server.call("submit_action", action), "rs_fail_retry")
	if cr2 == null:
		return
	assert_eq(cr2.status, "ACCEPTED",
		"禁用 seam 后同 command_id 重试须 ACCEPTED（失败未写入 command_cache）")
	assert_eq(cr2.error_code, "")
	assert_eq(cr2.command_id, action.command_id)
	assert_gt(int(server.call("current_server_seq")), int(frozen["seq"]),
		"重试成功后 server_seq 须推进")


## 真实 TileSkillFactory 虚拟牌锚点必须能参与 accepted-action 发布失败回滚，并允许同 command 重试。
func test_submit_publish_fail_rolls_back_real_tile_skill_factory_anchor() -> void:
	var cfg := _cfg_all_human()
	var server := FailingAcceptedBatchServer.new(cfg, 0)
	assert_not_null(server)
	if server == null:
		return
	var armed := _arm_all_human_discard(server, 313, "skill_anchor_arm")
	if armed.is_empty():
		return
	var bc: BattleController = server.get("_bc") as BattleController
	assert_not_null(bc)
	if bc == null:
		return
	assert_true(TileSkillFactory.inject_one(bc.registry, &"xray_1w_v1", 0),
		"必须使用真实 TileSkillFactory 虚拟牌锚点")
	var preflight := AuthorityReplaySnapshot.capture(bc)
	assert_not_null(preflight)
	assert_true(preflight != null and preflight.can_restore(),
		"真实技能锚点快照必须可恢复")

	var action: Action = armed["action"] as Action
	server.enabled = true
	server.fail_kind = "ROOM_SNAPSHOT"
	server.fail_seat = 2
	var frozen: Dictionary = _freeze_accepted_batch_state(server, "skill_anchor_frozen")
	var cr := _as_cr(server.call("submit_action", action), "skill_anchor_fail")
	assert_not_null(cr)
	if cr == null:
		return
	assert_eq(cr.status, "REJECTED")
	assert_eq(cr.error_code, "EVENT_PUBLISH_FAILED")
	_assert_accepted_batch_zero_mutation(server, frozen, "skill_anchor_rollback")

	server.enabled = false
	var retry := _as_cr(server.call("submit_action", action), "skill_anchor_retry")
	assert_not_null(retry)
	if retry != null:
		assert_eq(retry.status, "ACCEPTED", "失败解除后同 command_id 必须可重试")


## capture 可 hash 但不可 restore 的领域状态必须在 apply_action 前 fail closed。
## 这里使用真实 registry API 注册不受支持的 anchor，证明不能先 mutation 再赌回滚成功。
func test_submit_unrestorable_snapshot_fails_before_domain_mutation() -> void:
	var cfg := _cfg_all_human()
	var server := FailingAcceptedBatchServer.new(cfg, 0)
	assert_not_null(server)
	if server == null:
		return
	var armed := _arm_all_human_discard(server, 314, "unrestorable_arm")
	if armed.is_empty():
		return
	var bc: BattleController = server.get("_bc") as BattleController
	var bad_skill := SkillResource.new()
	bad_skill.id = &"unsupported_anchor_fixture"
	bc.registry.register(bad_skill, "unsupported-anchor")
	var snap := AuthorityReplaySnapshot.capture(bc)
	assert_not_null(snap)
	assert_eq(snap.sha256().length(), 64, "该缺陷夹具必须可 hash")
	assert_false(snap.can_restore(), "不受支持 anchor 的快照必须不可恢复")

	var frozen: Dictionary = _freeze_accepted_batch_state(server, "unrestorable_frozen")
	var action: Action = armed["action"] as Action
	server.enabled = true
	server.fail_kind = "ACTION_APPLIED"
	server.fail_seat = 1
	var cr := _as_cr(server.call("submit_action", action), "unrestorable_submit")
	assert_not_null(cr)
	if cr == null:
		return
	assert_eq(cr.status, "REJECTED")
	assert_eq(cr.error_code, "EVENT_PUBLISH_FAILED")
	assert_eq(server.call_count, 0,
		"不可恢复快照必须在领域 mutation/事件发布前拒绝")
	_assert_accepted_batch_zero_mutation(server, frozen, "unrestorable_fail_closed")


## 回滚本身失败代表权威状态已不可证明；该实例必须永久关闭所有提交入口。
func test_rollback_failure_permanently_closes_start_publish_and_submit() -> void:
	var started := LocalLoopbackServer.new(_cfg_all_human(), 0)
	assert_not_null(started)
	if started == null:
		return
	var armed := _arm_all_human_discard(started, 315, "rollback_failed_arm")
	if armed.is_empty():
		return
	var bc: BattleController = started.get("_bc") as BattleController
	var snap := AuthorityReplaySnapshot.capture(bc)
	assert_not_null(snap)
	if snap == null:
		return
	var frozen: Dictionary = _freeze_accepted_batch_state(started, "rollback_failed_frozen")
	# 临时断开 target，令真实快照的 restore_into 进入并返回 false；随后恢复引用，
	# 证明失败状态本身（而不是 _bc 为空）永久封闭公开入口。
	started.set("_bc", null)
	assert_false(bool(started.call(
		"_rollback_transaction", snap, int(frozen["seq"]), frozen["journals"], {}
	)), "restore_into 失败必须关闭已启动实例")
	assert_eq(started.get("_rollback_failed"), true,
		"真实 restore 失败必须留下不可逆熔断状态")
	started.set("_bc", bc)
	var cr := _as_cr(started.call("submit_action", armed["action"]), "rollback_failed_submit")
	assert_not_null(cr)
	if cr != null:
		assert_eq(cr.status, "REJECTED")
		assert_eq(cr.error_code, "EVENT_PUBLISH_FAILED",
			"永久关闭后 submit 须报告权威发布失败，不得伪装成普通未启动")
	assert_false(bool(started.call("publish_snapshot")),
		"rollback failure 后 publish_snapshot 必须永久关闭")
	assert_false(bool(started.call("start")),
		"rollback failure 后 start 必须永久关闭")


## 契约：普通 LocalLoopbackServer 全 HUMAN accepted 后四席严格 AA→ROOM_SNAPSHOT 配对。
## 不要求最终 server_seq 恰为 seq+2（后续 CLAIM prompt 可占 seq+3）；
## CR.server_seq 必须指向本次事务最后业务事件。
func test_submit_accepted_action_applied_room_snapshot_paired_four_seats() -> void:
	if not _contract_ok():
		return
	var cfg := _cfg_all_human()
	assert_not_null(cfg)
	if cfg == null:
		return
	var server: Object = LocalLoopbackServer.new(cfg, 0)
	assert_not_null(server, "LocalLoopbackServer 全 HUMAN 须可构造")
	if server == null:
		return
	var armed := _arm_all_human_discard(server, 312, "pair_arm")
	if armed.is_empty():
		return
	var action: Action = armed["action"] as Action
	var before_seq: int = int(server.call("current_server_seq"))
	var sizes0: Array = _journal_sizes(server, "pair0")
	var cr := _as_cr(server.call("submit_action", action), "pair_submit")
	if cr == null:
		return
	assert_eq(cr.status, "ACCEPTED", "全 HUMAN 合法 DISCARD 须 ACCEPTED")
	assert_eq(cr.error_code, "")
	assert_eq(cr.command_id, action.command_id)
	var aa_seq: int = before_seq + 1
	var snap_seq: int = before_seq + 2
	assert_eq(cr.server_seq, int(server.call("current_server_seq")),
		"CR.server_seq 须等于事务结束时的最后业务事件 seq")
	var shared_aa_payload: String = ""
	var shared_aa_seq: int = -1
	for seat in range(4):
		var after := _exact_ne(server.call("events_since", seat, before_seq), "pair/e%d" % seat)
		assert_gte(after.size(), 2, "seat%d events_since 至少 AA+SNAP" % seat)
		if after.size() < 2:
			return
		# 严格前两条：ACTION_APPLIED(seq+1) → ROOM_SNAPSHOT(seq+2)
		assert_eq(after[0].kind, "ACTION_APPLIED",
			"seat%d 首条新增须 ACTION_APPLIED" % seat)
		assert_eq(int(after[0].server_seq), aa_seq,
			"seat%d ACTION_APPLIED.server_seq 须 before+1" % seat)
		assert_true(_exact(after[0].payload, AA), "seat%d AA payload exact-6" % seat)
		assert_eq(str(after[0].payload["causation_command_id"]), action.command_id)
		assert_eq(after[1].kind, "ROOM_SNAPSHOT",
			"seat%d 次条新增须 ROOM_SNAPSHOT" % seat)
		assert_eq(int(after[1].server_seq), snap_seq,
			"seat%d ROOM_SNAPSHOT.server_seq 须 before+2" % seat)
		assert_eq(after[0].view_hash, after[1].view_hash,
			"seat%d AA 与 ROOM_SNAPSHOT view_hash 须相同" % seat)
		var snap_vh := ProtocolViewCodec.compute_view_hash(after[1].payload)
		assert_eq(after[1].view_hash, snap_vh,
			"seat%d ROOM_SNAPSHOT.view_hash 须等于 ProtocolViewCodec.compute_view_hash(payload)" % seat)
		# 四席各恰好新增这两个批次事件后才可有 CLAIM prompt
		var j := _exact_ne(server.call("event_journal", seat), "pair/j%d" % seat)
		assert_gte(j.size(), int(sizes0[seat]) + 2,
			"seat%d journal 至少 +2（AA+SNAP）" % seat)
		if j.size() < int(sizes0[seat]) + 2:
			return
		var idx_aa: int = int(sizes0[seat])
		assert_eq(j[idx_aa].kind, "ACTION_APPLIED")
		assert_eq(int(j[idx_aa].server_seq), aa_seq)
		assert_eq(j[idx_aa + 1].kind, "ROOM_SNAPSHOT")
		assert_eq(int(j[idx_aa + 1].server_seq), snap_seq)
		# 批次之后才可出现 CLAIM_WINDOW（若有）
		for k in range(idx_aa + 2, j.size()):
			if j[k].kind == "CLAIM_WINDOW":
				assert_gt(int(j[k].server_seq), snap_seq,
					"seat%d CLAIM_WINDOW 须在批次 seq 之后" % seat)
		# AA payload/seq 四席一致（view_hash 按席位投影可不同）
		var aa_pl: String = JSON.stringify(after[0].payload)
		if shared_aa_payload.is_empty():
			shared_aa_payload = aa_pl
			shared_aa_seq = int(after[0].server_seq)
		else:
			assert_eq(aa_pl, shared_aa_payload,
				"seat%d ACTION_APPLIED.payload 须与 seat0 一致" % seat)
			assert_eq(int(after[0].server_seq), shared_aa_seq,
				"seat%d ACTION_APPLIED.seq 须与 seat0 一致" % seat)
	# 不要求最终 server_seq 恰为 seq+2（CLAIM 可占 +3）
	assert_gte(int(server.call("current_server_seq")), snap_seq,
		"最终 server_seq 至少到 ROOM_SNAPSHOT seq")
	var max_published_seq := before_seq
	for seat in range(4):
		var final_events := _exact_ne(
			server.call("events_since", seat, before_seq), "pair/final%d" % seat
		)
		for event in final_events:
			max_published_seq = maxi(max_published_seq, int(event.server_seq))
	assert_eq(cr.server_seq, max_published_seq,
		"CR.server_seq 须与本次事务全局最后业务事件对齐")


# ---------------------------------------------------------------------------
# E2-02 协议选项 A：AI 链回到真人 / 事务回滚 / post-DRAW SNAP+PROMPT 原子
# ---------------------------------------------------------------------------

## 探针：super._auto_advance_ai 返回后，若下一决策是真人 TURN，记录是否已提前摸牌。
## 正确：phase=DRAW 且 last_drawn 非法（尚未摸）。错误：已摸（DISCARD + last_drawn 合法）。
class AiReturnDrawProbeServer extends LocalLoopbackServer:
	var auto_returned_for_human_turn: bool = false
	var human_already_drawn_on_auto_return: bool = false
	var human_seat_on_return: int = -1
	var phase_on_return: int = -1

	func reset_draw_probe() -> void:
		auto_returned_for_human_turn = false
		human_already_drawn_on_auto_return = false
		human_seat_on_return = -1
		phase_on_return = -1

	func _auto_advance_ai() -> bool:
		var ok: bool = super._auto_advance_ai()
		if _bc == null or _bc.state == null:
			return ok
		if bool(_bc.get("_settled")):
			return ok
		var st: BattleState = _bc.state
		var cur: int = int(st.current_seat)
		var win = _bc.get("_active_window")
		var human_turn := false
		if win is DecisionWindow:
			var dw: DecisionWindow = win as DecisionWindow
			if dw.kind == DecisionWindow.KIND_TURN and _is_human(int(dw.subject_seat)):
				human_turn = true
				cur = int(dw.subject_seat)
		elif _is_human(cur) and (
				int(st.phase) == BattlePhase.Kind.DRAW
				or int(st.phase) == BattlePhase.Kind.DISCARD):
			# 修复后：DRAW+human 可能尚无窗；仍视为回到真人回合入口
			human_turn = true
		if not human_turn:
			return ok
		auto_returned_for_human_turn = true
		human_seat_on_return = cur
		phase_on_return = int(st.phase)
		var so: Seat = st.seats[cur] as Seat
		if so == null:
			return ok
		var drawn: bool = Tile.is_valid_instance_id(so.last_drawn_instance_id)
		# 提前摸牌：AI 返回时真人已持有 last_drawn（phase 多为 DISCARD）
		if drawn:
			human_already_drawn_on_auto_return = true
		return ok


## 注入：AI 链期间 _build_recipient_event 失败。
## enabled 后累计 call_count；超过 fail_after_calls 且 kind 匹配时 return null。
## 默认 fail_after_calls=8：跳过 human 首批 4×(AA+SNAP)，第 9 次（AI 首条）失败。
class FailingAiAdvancePublishServer extends LocalLoopbackServer:
	var enabled: bool = false
	var fail_after_calls: int = 8
	var fail_kind: String = "ACTION_APPLIED"
	var call_count: int = 0
	var fail_hit: int = 0

	func _build_recipient_event(
		kind: String, recipient_seat: int, seq: int, payload: Dictionary, view_hash: String
	) -> NetworkedEvent:
		if enabled:
			call_count += 1
			if call_count > fail_after_calls:
				if fail_kind.is_empty() or kind == fail_kind:
					fail_hit += 1
					return null
		return super._build_recipient_event(kind, recipient_seat, seq, payload, view_hash)


## 注入：enabled 后 _build_turn_prompt_payload 返回空（start 时 enabled=false 不受影响）。
class FailingTurnPromptEnabledServer extends LocalLoopbackServer:
	var enabled: bool = false
	var call_count: int = 0

	func _build_turn_prompt_payload(ctx: DecisionContext, seat: int) -> Dictionary:
		if enabled:
			call_count += 1
			return {}
		return super._build_turn_prompt_payload(ctx, seat)


## 注入：仅当 seat0 已有合法 last_drawn（post-DRAW 领域态）时，seat0 payload 失败。
## start / human 弃牌后 / AI 链中 seat0 未摸牌 → 不 fail；最终摸牌后 ROOM_SNAPSHOT 才命中。
class FailingPostDrawSnapshotServer extends LocalLoopbackServer:
	var enabled: bool = false
	var call_count: int = 0
	var fail_hit: int = 0

	func _build_room_snapshot_payload(seat: int, seq: int) -> Dictionary:
		if enabled and int(seat) == 0 and _bc != null and _bc.state != null:
			var so: Seat = _bc.state.seats[0] as Seat
			if so != null and Tile.is_valid_instance_id(so.last_drawn_instance_id):
				call_count += 1
				fail_hit += 1
				return {}
		return super._build_room_snapshot_payload(seat, seq)


## 从 CLAIM_WINDOW 构造 seat0 PASS（1H fixture）。
func _pass_act(prompt: NetworkedEvent, n: int, room := SID, seat: int = 0) -> Action:
	assert_not_null(prompt, "PASS 须有 CLAIM_WINDOW prompt")
	if prompt == null:
		return null
	assert_eq(prompt.kind, "CLAIM_WINDOW", "PASS 基底须 CLAIM_WINDOW")
	var p: Dictionary = prompt.payload
	return Action.from_dict({
		"protocol_version": 1, "command_id": _cmd(n), "room_id": room,
		"seat": seat, "hand_seq": int(p.get("hand_seq", 0)),
		"decision_id": str(p.get("decision_id", "")), "kind": "PASS",
		"payload": {}, "client_seq": n})


## 按当前 private prompt 构造 seat0 合法 Action（TURN→DISCARD / CLAIM→PASS）。
func _human_action_from_prompt(server: Object, n: int, room := SID) -> Action:
	var pr := _prompt(server)
	assert_not_null(pr, "须有 private prompt")
	if pr == null:
		return null
	if pr.kind == "TURN_PROMPT":
		var meta := _meta(pr)
		assert_false(meta.is_empty(), "TURN_PROMPT 须含 DISCARD")
		if meta.is_empty():
			return null
		return _act(meta, n, room)
	if pr.kind == "CLAIM_WINDOW":
		return _pass_act(pr, n, room, 0)
	assert_true(false, "未知 prompt kind=%s" % pr.kind)
	return null


## 推进至 seat3 弃牌后、seat0 尚未 PASS 的 CLAIM_WINDOW。
## 路径：start 后 seat0 DISCARD + 两次 PASS（seat1/seat2 弃牌后）。
## 下一次 human PASS 经 AI 链应进入 seat0 DRAW/TURN。
func _arm_claim_before_seat0_return_turn(server: Object, start_cmd: int, tag: String) -> int:
	assert_true(bool(server.call("start")), "%s: start 须 true" % tag)
	var cmd_n: int = start_cmd
	# 1) seat0 首巡 DISCARD
	var a0 := _human_action_from_prompt(server, cmd_n, SID)
	assert_not_null(a0, "%s: seat0 DISCARD 须可构造" % tag)
	if a0 == null:
		return -1
	var cr0 := _as_cr(server.call("submit_action", a0), "%s/a0" % tag)
	if cr0 == null or cr0.status != "ACCEPTED":
		assert_eq(cr0.status if cr0 else "", "ACCEPTED", "%s: seat0 DISCARD 须 ACCEPTED" % tag)
		return -1
	cmd_n += 1
	# 2-3) seat1、seat2 弃牌后的 CLAIM → PASS
	for step in range(2):
		var pr := _prompt(server)
		assert_not_null(pr, "%s: step%d 须有 prompt" % [tag, step])
		if pr == null:
			return -1
		assert_eq(pr.kind, "CLAIM_WINDOW",
			"%s: step%d 须 CLAIM_WINDOW（AI 弃牌后）" % [tag, step])
		var ap := _pass_act(pr, cmd_n, SID, 0)
		assert_not_null(ap)
		if ap == null:
			return -1
		var crp := _as_cr(server.call("submit_action", ap), "%s/pass%d" % [tag, step])
		if crp == null or crp.status != "ACCEPTED":
			assert_eq(crp.status if crp else "", "ACCEPTED",
				"%s: step%d PASS 须 ACCEPTED" % [tag, step])
			return -1
		cmd_n += 1
	var pr_final := _prompt(server)
	assert_not_null(pr_final, "%s: 最终须有 CLAIM_WINDOW（seat3 弃牌后）" % tag)
	if pr_final == null:
		return -1
	assert_eq(pr_final.kind, "CLAIM_WINDOW",
		"%s: arm 结束后须 CLAIM_WINDOW，下一次 PASS 回到 seat0 TURN" % tag)
	return cmd_n


## seat0 journal 末两条须为 post-DRAW ROOM_SNAPSHOT 紧邻 TURN_PROMPT；
## hash 一致；prompt hand / last_drawn 与 snapshot 私有手牌一致。
func _assert_seat0_post_draw_snap_prompt_adjacent(server: Object, tag: String) -> void:
	var j := _exact_ne(server.call("event_journal", 0), "%s/j0" % tag)
	assert_gte(j.size(), 2, "%s: seat0 journal 至少 2 条" % tag)
	if j.size() < 2:
		return
	var snap_ne: NetworkedEvent = j[j.size() - 2] as NetworkedEvent
	var prompt_ne: NetworkedEvent = j[j.size() - 1] as NetworkedEvent
	assert_eq(snap_ne.kind, "ROOM_SNAPSHOT",
		"%s: 倒数第二条须为 post-DRAW ROOM_SNAPSHOT" % tag)
	assert_eq(prompt_ne.kind, "TURN_PROMPT",
		"%s: 末条须为 TURN_PROMPT" % tag)
	assert_eq(prompt_ne.view_hash, snap_ne.view_hash,
		"%s: TURN_PROMPT.view_hash 须严格等于紧邻 ROOM_SNAPSHOT.view_hash" % tag)
	var snap_payload := _snap(snap_ne, 0, "%s/snap" % tag)
	if snap_payload.is_empty():
		return
	var modules: Array = snap_payload["modules"] as Array
	var core: Dictionary = {}
	for m in modules:
		if str(m.get("module_key", "")) == "core_table":
			core = m["payload"] as Dictionary
			break
	assert_false(core.is_empty(), "%s: snapshot 须含 core_table" % tag)
	if core.is_empty():
		return
	var seats: Array = core["seats"] as Array
	assert_gte(seats.size(), 1)
	var seat0_view: Dictionary = seats[0] as Dictionary
	var concealed: Array = seat0_view.get("concealed_tiles", []) as Array
	var snap_last: int = int(seat0_view.get("last_drawn_tile_instance_id", -1))
	assert_true(Tile.is_valid_instance_id(snap_last),
		"%s: post-DRAW snapshot seat0.last_drawn 须合法 instance_id" % tag)
	assert_gt(concealed.size(), 0, "%s: post-DRAW snapshot 私有手牌非空" % tag)

	var pp: Dictionary = prompt_ne.payload
	assert_eq(int(pp.get("seat", -1)), 0)
	var prompt_hand: Array = pp.get("hand", []) as Array
	var prompt_last: int = int(pp.get("last_drawn_tile_instance_id", -1))
	assert_eq(prompt_last, snap_last,
		"%s: prompt.last_drawn 须等于 snapshot 私有 last_drawn" % tag)
	assert_eq(prompt_hand.size(), concealed.size(),
		"%s: prompt.hand 长度须等于 snapshot concealed_tiles" % tag)
	# instance_id 集合一致（顺序允许排序后比）
	var snap_iids: Array = []
	for tv in concealed:
		if typeof(tv) == TYPE_DICTIONARY:
			snap_iids.append(int(tv.get("instance_id", -1)))
	var prompt_iids: Array = []
	for tv2 in prompt_hand:
		if typeof(tv2) == TYPE_DICTIONARY:
			prompt_iids.append(int(tv2.get("instance_id", -1)))
	snap_iids.sort()
	prompt_iids.sort()
	assert_eq(JSON.stringify(prompt_iids), JSON.stringify(snap_iids),
		"%s: prompt.hand instance_id 集合须等于 snapshot 私有手牌" % tag)
	# hash 自洽
	var recomputed: String = ProtocolViewCodec.compute_view_hash(snap_payload)
	assert_eq(snap_ne.view_hash, recomputed,
		"%s: ROOM_SNAPSHOT.view_hash 须等于 payload 重算" % tag)


## Red：1 HUMAN + 3 AI；真实 human PASS（seat3 弃后）经 AI 链回到 seat0 TURN。
## 1) AI 返回前 seat0 绝不能提前 draw；
## 2) 最终 journal：post-DRAW ROOM_SNAPSHOT 紧邻 TURN_PROMPT，hash/手牌/last_drawn 一致。
func test_human_ai_chain_back_seat0_no_early_draw_snap_prompt() -> void:
	if not _contract_ok():
		return
	var server := AiReturnDrawProbeServer.new(_cfg(), 0)
	assert_not_null(server, "AiReturnDrawProbeServer 须可构造")
	if server == null:
		return
	var cmd_n: int = _arm_claim_before_seat0_return_turn(server, 400, "ai_chain_arm")
	if cmd_n < 0:
		return
	var action := _human_action_from_prompt(server, cmd_n, SID)
	assert_not_null(action, "临界 human PASS 须可构造")
	if action == null:
		return
	assert_eq(action.kind, "PASS", "临界动作须 PASS（经 AI 链回 seat0 DRAW）")
	server.reset_draw_probe()

	var cr := _as_cr(server.call("submit_action", action), "ai_chain_submit")
	if cr == null:
		return
	assert_eq(cr.status, "ACCEPTED", "合法 HUMAN PASS 须 ACCEPTED")
	assert_eq(cr.error_code, "")
	assert_eq(cr.command_id, action.command_id)
	assert_true(server.auto_returned_for_human_turn,
		"AI 链须回到 human TURN（或 DRAW 入口）")
	assert_eq(server.human_seat_on_return, 0, "回到的真人须 seat0")
	assert_false(server.human_already_drawn_on_auto_return,
		"AI 返回前 seat0 绝不能提前 draw")
	_assert_seat0_post_draw_snap_prompt_adjacent(server, "ai_chain")


## Red：AI 自动推进中 ACTION_APPLIED recipient 构建失败 → 整笔 human command 事务回滚；
## seq/journals/ARS/cache 零变化；失败不缓存；同 command_id 可重试。
func test_ai_action_applied_publish_fail_rolls_back_whole_command() -> void:
	if not _contract_ok():
		return
	var server := FailingAiAdvancePublishServer.new(_cfg(), 0)
	assert_not_null(server)
	if server == null:
		return
	assert_eq(server.enabled, false)
	# 首巡 DISCARD 即可触发 AI 链发布（claim PASS AA）；不必回到 seat0 TURN
	assert_true(bool(server.call("start")), "start 须 true")
	var action := _human_action_from_prompt(server, 410, SID)
	assert_not_null(action)
	if action == null:
		return
	# 跳过 human 首批 8 次 _build_recipient_event，第 9 次起 AI ACTION_APPLIED 失败
	server.enabled = true
	server.fail_after_calls = 8
	server.fail_kind = "ACTION_APPLIED"
	server.call_count = 0
	server.fail_hit = 0
	var frozen: Dictionary = _freeze_accepted_batch_state(server, "ai_aa_fail0")
	var cr := _as_cr(server.call("submit_action", action), "ai_aa_fail_submit")
	if cr == null:
		return
	assert_gt(server.fail_hit, 0,
		"须命中 AI 链 _build_recipient_event(ACTION_APPLIED) 失败注入")
	assert_eq(cr.status, "REJECTED",
		"AI ACTION_APPLIED 发布失败须整笔 REJECTED（禁半提交后仍 ACCEPTED）")
	if server.fail_hit <= 0 or cr.status != "REJECTED":
		return
	assert_eq(cr.error_code, "EVENT_PUBLISH_FAILED",
		"失败 error_code 须 EVENT_PUBLISH_FAILED")
	assert_eq(cr.command_id, action.command_id)
	assert_eq(cr.server_seq, int(frozen["seq"]))
	_assert_accepted_batch_zero_mutation(server, frozen, "ai_aa_fail")
	server.enabled = false
	var cr2 := _as_cr(server.call("submit_action", action), "ai_aa_fail_retry")
	if cr2 == null:
		return
	assert_eq(cr2.status, "ACCEPTED",
		"禁用后同 command_id 重试须 ACCEPTED（失败未写入 cache）")
	assert_eq(cr2.error_code, "")
	assert_eq(cr2.command_id, action.command_id)
	assert_gt(int(server.call("current_server_seq")), int(frozen["seq"]))


## Red：AI 自动推进中 ROOM_SNAPSHOT recipient 构建失败 → 同样整笔回滚可重试。
func test_ai_room_snapshot_publish_fail_rolls_back_whole_command() -> void:
	if not _contract_ok():
		return
	var server := FailingAiAdvancePublishServer.new(_cfg(), 0)
	assert_not_null(server)
	if server == null:
		return
	assert_true(bool(server.call("start")), "start 须 true")
	var action := _human_action_from_prompt(server, 411, SID)
	assert_not_null(action)
	if action == null:
		return
	# human 8 次后：第 9=AI AA；第 10=AI SNAP → fail_after_calls=9
	server.enabled = true
	server.fail_after_calls = 9
	server.fail_kind = "ROOM_SNAPSHOT"
	server.call_count = 0
	server.fail_hit = 0
	var frozen: Dictionary = _freeze_accepted_batch_state(server, "ai_rs_fail0")
	var cr := _as_cr(server.call("submit_action", action), "ai_rs_fail_submit")
	if cr == null:
		return
	assert_gt(server.fail_hit, 0,
		"须命中 AI 链 _build_recipient_event(ROOM_SNAPSHOT) 失败注入")
	assert_eq(cr.status, "REJECTED",
		"AI ROOM_SNAPSHOT 发布失败须整笔 REJECTED")
	if server.fail_hit <= 0 or cr.status != "REJECTED":
		return
	assert_eq(cr.error_code, "EVENT_PUBLISH_FAILED")
	assert_eq(cr.command_id, action.command_id)
	assert_eq(cr.server_seq, int(frozen["seq"]))
	_assert_accepted_batch_zero_mutation(server, frozen, "ai_rs_fail")
	server.enabled = false
	var cr2 := _as_cr(server.call("submit_action", action), "ai_rs_fail_retry")
	if cr2 == null:
		return
	assert_eq(cr2.status, "ACCEPTED",
		"禁用后同 command_id 重试须 ACCEPTED")
	assert_eq(cr2.error_code, "")
	assert_gt(int(server.call("current_server_seq")), int(frozen["seq"]))


## Red：最终 TURN_PROMPT 构建失败（AI 链成功回到 seat0 TURN 后）→ 整笔回滚可重试。
func test_final_turn_prompt_fail_rolls_back_whole_command() -> void:
	if not _contract_ok():
		return
	var server := FailingTurnPromptEnabledServer.new(_cfg(), 0)
	assert_not_null(server)
	if server == null:
		return
	assert_eq(server.enabled, false)
	var cmd_n: int = _arm_claim_before_seat0_return_turn(server, 420, "final_tp_arm")
	if cmd_n < 0:
		return
	var action := _human_action_from_prompt(server, cmd_n, SID)
	assert_not_null(action)
	if action == null:
		return
	assert_eq(action.kind, "PASS")
	server.enabled = true
	server.call_count = 0
	var frozen: Dictionary = _freeze_accepted_batch_state(server, "final_tp_fail0")
	var cr := _as_cr(server.call("submit_action", action), "final_tp_fail_submit")
	if cr == null:
		return
	assert_gt(server.call_count, 0,
		"须命中最终路径 _build_turn_prompt_payload 失败注入")
	assert_eq(cr.status, "REJECTED",
		"最终 TURN_PROMPT 失败须整笔 REJECTED（禁 AI 半提交后仍 ACCEPTED）")
	if server.call_count <= 0 or cr.status != "REJECTED":
		return
	assert_eq(cr.error_code, "EVENT_PUBLISH_FAILED")
	assert_eq(cr.command_id, action.command_id)
	assert_eq(cr.server_seq, int(frozen["seq"]))
	_assert_accepted_batch_zero_mutation(server, frozen, "final_tp_fail")
	server.enabled = false
	var cr2 := _as_cr(server.call("submit_action", action), "final_tp_fail_retry")
	if cr2 == null:
		return
	assert_eq(cr2.status, "ACCEPTED",
		"禁用后同 command_id 重试须 ACCEPTED")
	assert_eq(cr2.error_code, "")
	assert_gt(int(server.call("current_server_seq")), int(frozen["seq"]))


## Red：最终 post-DRAW ROOM_SNAPSHOT 构建失败 → 整笔回滚可重试。
## 覆盖「DRAW mutation 后、TURN_PROMPT 前」四席 SNAP 发布失败路径。
func test_final_post_draw_snapshot_fail_rolls_back_whole_command() -> void:
	if not _contract_ok():
		return
	var server := FailingPostDrawSnapshotServer.new(_cfg(), 0)
	assert_not_null(server)
	if server == null:
		return
	assert_eq(server.enabled, false)
	var cmd_n: int = _arm_claim_before_seat0_return_turn(server, 421, "final_snap_arm")
	if cmd_n < 0:
		return
	var action := _human_action_from_prompt(server, cmd_n, SID)
	assert_not_null(action)
	if action == null:
		return
	assert_eq(action.kind, "PASS")
	server.enabled = true
	server.call_count = 0
	server.fail_hit = 0
	var frozen: Dictionary = _freeze_accepted_batch_state(server, "final_snap_fail0")
	var cr := _as_cr(server.call("submit_action", action), "final_snap_fail_submit")
	if cr == null:
		return
	# 当前缺陷：AI 提前 draw 后直接 TURN_PROMPT、无 post-DRAW publish_snapshot → fail_hit=0
	if server.fail_hit <= 0:
		assert_true(false,
			"最终路径须在 seat0 已摸牌后再次 _build_room_snapshot_payload（post-DRAW SNAP）；当前未命中")
		return
	assert_eq(cr.status, "REJECTED",
		"post-DRAW ROOM_SNAPSHOT 失败须整笔 REJECTED")
	if cr.status != "REJECTED":
		return
	assert_eq(cr.error_code, "EVENT_PUBLISH_FAILED")
	assert_eq(cr.command_id, action.command_id)
	assert_eq(cr.server_seq, int(frozen["seq"]))
	_assert_accepted_batch_zero_mutation(server, frozen, "final_snap_fail")
	server.enabled = false
	var cr2 := _as_cr(server.call("submit_action", action), "final_snap_fail_retry")
	if cr2 == null:
		return
	assert_eq(cr2.status, "ACCEPTED",
		"禁用后同 command_id 重试须 ACCEPTED")
	assert_eq(cr2.error_code, "")
	assert_gt(int(server.call("current_server_seq")), int(frozen["seq"]))


# =============================================================================
# #232 HAND_SETTLED A 契约
# =============================================================================

const HAND_SETTLED_KEYS := [
	"hand_seq", "outcome", "winner_seats", "loser_seat", "score_deltas", "scores",
]


## HAND_SETTLED recipient 构建失败注入：命中 kind+seat 时 return null。
class FailingHandSettledServer extends LocalLoopbackServer:
	var enabled: bool = false
	var fail_seat: int = 2
	var call_count: int = 0
	var fail_hit: int = 0

	func _build_recipient_event(
		kind: String, recipient_seat: int, seq: int, payload: Dictionary, view_hash: String
	) -> NetworkedEvent:
		if enabled and kind == "HAND_SETTLED":
			call_count += 1
			if int(recipient_seat) == fail_seat:
				fail_hit += 1
				return null
		return super._build_recipient_event(kind, recipient_seat, seq, payload, view_hash)


## 清空 active 区；返回开局 draw_index 下限后临时回绕到 0，
## 供 fixture 从同一真实 Wall 取 canonical 实体。
## 组牌完成后、打开 DecisionWindow/submit 前必须 _seal_live_wall_draw_index。
func _prep_live(bc: BattleController) -> int:
	var draw_floor: int = int(bc.state.wall._draw_index)
	for s in range(4):
		var seat: Seat = bc.state.seats[s]
		seat.hand = Hand.new()
		seat.melds = []
		seat.last_drawn_instance_id = Tile.INVALID_INSTANCE_ID
		seat.furiten = FuritenState.new()
		bc.state.discards_per_seat[s] = []
	bc.state.wall._draw_index = 0
	return draw_floor


## 组牌后恢复 draw_index ≥ 开局下限，保证 live_wall_count ≤ LIVE_WALL_COUNT_MAX。
## 不放宽协议；实体仍来自真实 Wall（canonical / 唯一 instance_id）。
func _seal_live_wall_draw_index(bc: BattleController, draw_floor: int) -> void:
	var w: Wall = bc.state.wall
	w._draw_index = maxi(int(draw_floor), int(w._draw_index))


func _live_end_wall(w: Wall) -> int:
	return w._tiles.size() - w._dead_wall_size


func _find_live_idx(w: Wall, tid: int, used: Dictionary) -> int:
	var end_i: int = _live_end_wall(w)
	for i in range(w._draw_index, end_i):
		var t: Tile = w._tiles[i]
		if t == null or int(t.id) != int(tid):
			continue
		if used.has(int(t.instance_id)):
			continue
		return i
	return -1


func _draw_live_tid(bc: BattleController, tid: int, used: Dictionary) -> Tile:
	var w: Wall = bc.state.wall
	var live_idx: int = _find_live_idx(w, tid, used)
	assert_true(live_idx >= 0, "live 区无 id=%d" % tid)
	if live_idx < 0:
		return null
	if live_idx != w._draw_index:
		var tmp: Tile = w._tiles[w._draw_index]
		w._tiles[w._draw_index] = w._tiles[live_idx]
		w._tiles[live_idx] = tmp
	var drawn: Tile = w.draw()
	assert_not_null(drawn)
	if drawn != null:
		used[int(drawn.instance_id)] = true
	return drawn


func _hand_live(bc: BattleController, ids: Array, used: Dictionary) -> Hand:
	var h := Hand.new()
	for tid in ids:
		var t: Tile = _draw_live_tid(bc, int(tid), used)
		assert_not_null(t)
		if t != null:
			assert_true(h.add(t))
	return h


func _chiitoi_13() -> Array:
	return [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W9,
	]


func _noise_14_with(tid: int) -> Array:
	return [
		TileId.W2, TileId.W3, TileId.W4, TileId.W6, TileId.W8,
		TileId.T1, TileId.T2, TileId.T3, TileId.T4, TileId.T5,
		TileId.E, TileId.S_WIND, TileId.W_WIND, tid,
	]


## 期望 HAND_SETTLED scores/deltas：state.scores + WIN payout（GameDriver 语义）。
func _expected_final_scores_from_win(
	start_scores: Array, state_scores: Array, win_extra: Dictionary, winner_seat: int
) -> Dictionary:
	var final_scores: Array = []
	for i in range(4):
		final_scores.append(int(state_scores[i]))
	var payout: Dictionary = win_extra.get("payout", {})
	for seat_id in payout:
		final_scores[int(seat_id)] = int(final_scores[int(seat_id)]) - int(payout[seat_id])
	final_scores[winner_seat] = int(final_scores[winner_seat]) + int(win_extra.get("winner_total", 0))
	var deltas: Array = []
	for i2 in range(4):
		deltas.append(int(final_scores[i2]) - int(start_scores[i2]))
	return {"scores": final_scores, "score_deltas": deltas}


func _find_hand_settled(server: Object, seat: int = 0) -> NetworkedEvent:
	var j := _exact_ne(server.call("event_journal", seat), "hs_find")
	for i in range(j.size() - 1, -1, -1):
		var e: NetworkedEvent = j[i] as NetworkedEvent
		if e != null and e.kind == "HAND_SETTLED":
			return e
	return null


func _assert_four_seat_hand_settled_same_seq(server: Object, tag: String) -> NetworkedEvent:
	var ref: NetworkedEvent = null
	var shared_seq: int = -1
	for seat in range(4):
		var seat_hs: NetworkedEvent = _find_hand_settled(server, seat)
		assert_not_null(seat_hs, "%s: seat%d 须有 HAND_SETTLED" % [tag, seat])
		if seat_hs == null:
			return null
		var rt: NetworkedEvent = NetworkedEvent.from_dict(seat_hs.to_dict())
		assert_not_null(rt, "%s: seat%d HAND_SETTLED 须 strict roundtrip" % [tag, seat])
		if rt == null:
			return null
		if shared_seq < 0:
			shared_seq = int(seat_hs.server_seq)
			ref = seat_hs
		else:
			assert_eq(int(seat_hs.server_seq), shared_seq,
				"%s: 四席 HAND_SETTLED 须同一 server_seq" % tag)
		assert_eq(JSON.stringify(seat_hs.payload), JSON.stringify(ref.payload),
			"%s: 四席 HAND_SETTLED payload 须一致" % tag)
	assert_gt(shared_seq, 0, "%s: HAND_SETTLED.server_seq > 0" % tag)
	return ref


## Red：源码不得用 has_method("decision_context_for_seat") 兼容 fallback；typed API 可 start。
func test_private_prompt_uses_typed_decision_context_api() -> void:
	if not _contract_ok():
		return
	var src: String = _src()
	assert_false(src.is_empty(), "须可读 local_loopback_server.gd")
	assert_true(
		src.find('has_method("decision_context_for_seat")') < 0
		and src.find("has_method('decision_context_for_seat')") < 0,
		"_emit_private_prompt 禁止 has_method(decision_context_for_seat) 兼容 fallback")
	var server := _new(_load_server())
	if server == null:
		return
	assert_true(bool(server.call("start")), "typed decision_context_for_seat 须能成功 start")
	assert_not_null(_prompt(server), "start 后 seat0 须有 private prompt")


## Red：本局起始分仅在 start 成功后冻结；失败 start 不得污染。
func test_hand_start_scores_freeze_only_on_successful_start() -> void:
	if not _contract_ok():
		return
	# 失败 start：_hand_start_scores 须保持未冻结
	var fail_srv := FailingSnapshotServer.new(_cfg(), 0)
	assert_not_null(fail_srv)
	if fail_srv == null:
		return
	fail_srv.fail_seat = 2
	var pre_fail = fail_srv.get("_hand_start_scores")
	assert_true(
		pre_fail == null or (typeof(pre_fail) == TYPE_ARRAY and (pre_fail as Array).is_empty()),
		"构造后 _hand_start_scores 须未冻结（null 或空）")
	assert_false(bool(fail_srv.call("start")))
	var post_fail = fail_srv.get("_hand_start_scores")
	assert_true(
		post_fail == null or (typeof(post_fail) == TYPE_ARRAY and (post_fail as Array).is_empty()),
		"失败 start 不得写入/污染 _hand_start_scores")
	# 成功 start：冻结值 = 构造时 BC.state.scores（摸牌不改分）
	var ok_srv := _new(_load_server())
	if ok_srv == null:
		return
	var bc: BattleController = ok_srv.get("_bc") as BattleController
	assert_not_null(bc)
	if bc == null:
		return
	var expected: Array = []
	for s in bc.state.scores:
		expected.append(int(s))
	assert_true(bool(ok_srv.call("start")))
	var frozen = ok_srv.get("_hand_start_scores")
	assert_eq(typeof(frozen), TYPE_ARRAY, "成功 start 须冻结 Array")
	if typeof(frozen) != TYPE_ARRAY:
		return
	assert_eq((frozen as Array).size(), 4)
	assert_eq(JSON.stringify(frozen), JSON.stringify(expected),
		"起始分须等于 start 成功前 BC.state.scores（无副作用时点）")


## Red：真实 BC TSUMO 后 HAND_SETTLED 须 TSUMO + payout 后 scores/deltas + 四席同 seq。
func test_hand_settled_tsumo_real_payout_and_four_seat_seq() -> void:
	if not _contract_ok():
		return
	var cfg := _cfg_all_human()
	assert_not_null(cfg)
	if cfg == null:
		return
	var server := LocalLoopbackServer.new(cfg, 0)
	assert_true(bool(server.call("start")))
	var bc: BattleController = server.get("_bc") as BattleController
	assert_not_null(bc)
	if bc == null:
		return
	var start_raw = server.get("_hand_start_scores")
	assert_eq(typeof(start_raw), TYPE_ARRAY, "须已冻结起始分 Array")
	if typeof(start_raw) != TYPE_ARRAY:
		return
	var start_scores: Array = []
	for s in start_raw as Array:
		start_scores.append(int(s))
	assert_eq(start_scores.size(), 4, "须已冻结起始分")

	# 真实 fixture：seat0 七对听 → 摸 W9 自摸（与 test_battle_e2e 同构）
	var used: Dictionary = {}
	var wall_floor: int = _prep_live(bc)
	bc.state.seats[0].hand = _hand_live(bc, _chiitoi_13(), used)
	bc.state.first_round_active = false
	# 补 14 张：W9 作 last_drawn
	var win_t: Tile = _draw_live_tid(bc, TileId.W9, used)
	assert_not_null(win_t)
	if win_t == null:
		return
	assert_true(bc.state.seats[0].hand.add(win_t))
	bc.state.seats[0].last_drawn_instance_id = win_t.instance_id
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.set("_settled", false)
	bc.set("_active_window", null)
	_seal_live_wall_draw_index(bc, wall_floor)

	var ctx: DecisionContext = bc.decision_context_for_seat(0)
	assert_not_null(ctx, "须有 TURN DecisionContext")
	if ctx == null:
		return
	assert_true(ctx.has_kind("TSUMO"), "fixture 须 offer TSUMO")
	var act: Action = Action.tsumo(
		0, CLAIM_SID, _cmd(500), ctx.decision_id, int(bc.state.hand_seq),
		int(server.call("current_server_seq")) + 1
	)
	var cr := _as_cr(server.call("submit_action", act), "tsumo_settle")
	if cr == null:
		return
	assert_eq(cr.status, "ACCEPTED",
		"真实 TSUMO 须 ACCEPTED status=%s error_code=%s server_seq=%d"
		% [cr.status, cr.error_code, cr.server_seq])
	if cr.status != "ACCEPTED":
		return
	assert_true(bool(bc.get("_settled")), "TSUMO 后 BC 须 settled")

	var settled_ev := _assert_four_seat_hand_settled_same_seq(server, "tsumo")
	assert_not_null(settled_ev)
	if settled_ev == null:
		return
	var p: Dictionary = settled_ev.payload
	assert_true(_exact(p, HAND_SETTLED_KEYS), "HAND_SETTLED exact 6 键")
	assert_eq(str(p["outcome"]), "TSUMO", "不得伪装 EXHAUSTIVE_DRAW")
	assert_eq(p["winner_seats"], [0])
	assert_eq(int(p["loser_seat"]), -1)
	assert_eq(int(p["hand_seq"]), int(bc.state.hand_seq))

	# 从真实 WIN_DECLARED 推导期望 scores/deltas
	var win_ev: BattleEvent = null
	for i in range(bc.events.size() - 1, -1, -1):
		var ev: BattleEvent = bc.events[i]
		if ev.type == &"WIN_DECLARED":
			win_ev = ev
			break
	assert_not_null(win_ev, "须有真实 WIN_DECLARED")
	if win_ev == null:
		return
	var state_scores: Array = []
	for s2 in bc.state.scores:
		state_scores.append(int(s2))
	var expected_scores: Dictionary = _expected_final_scores_from_win(
		start_scores, state_scores, win_ev.extra, int(win_ev.actor_seat)
	)
	assert_eq(JSON.stringify(p["scores"]), JSON.stringify(expected_scores["scores"]),
		"scores 须含 payout 后最终分（非仅 state.scores）")
	assert_eq(JSON.stringify(p["score_deltas"]), JSON.stringify(expected_scores["score_deltas"]),
		"score_deltas 须 = final - start")
	# 无局前棒时本例 sum 可为 0；契约不强制
	assert_gt(int(win_ev.extra.get("winner_total", 0)), 0)
	assert_true(win_ev.extra.has("payout"))


## Red：真实 CLAIM RON 后 HAND_SETTLED 须 RON + loser + payout 分数。
func test_hand_settled_ron_real_payout_and_outcome() -> void:
	if not _contract_ok():
		return
	var cfg := _cfg_all_human()
	assert_not_null(cfg)
	if cfg == null:
		return
	var server := LocalLoopbackServer.new(cfg, 0)
	assert_true(bool(server.call("start")))
	var bc: BattleController = server.get("_bc") as BattleController
	assert_not_null(bc)
	if bc == null:
		return
	var start_raw = server.get("_hand_start_scores")
	assert_eq(typeof(start_raw), TYPE_ARRAY, "须已冻结起始分")
	if typeof(start_raw) != TYPE_ARRAY:
		return
	var start_scores: Array = []
	for s in start_raw as Array:
		start_scores.append(int(s))

	var used: Dictionary = {}
	var wall_floor: int = _prep_live(bc)
	bc.state.seats[0].hand = _hand_live(bc, _chiitoi_13(), used)
	bc.state.seats[0].furiten = FuritenState.new()
	bc.state.first_round_active = false
	# seat1 14 张含 W9，真实 DISCARD → CLAIM RON
	bc.state.seats[1].hand = _hand_live(bc, _noise_14_with(TileId.W9), used)
	var disc: Tile = null
	for t in bc.state.seats[1].hand._tiles:
		if t != null and int(t.id) == TileId.W9:
			disc = t
			break
	assert_not_null(disc)
	if disc == null:
		return
	bc.state.seats[1].last_drawn_instance_id = disc.instance_id
	bc.state.current_seat = 1
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.set("_settled", false)
	bc.set("_active_window", null)
	_seal_live_wall_draw_index(bc, wall_floor)

	var turn_ctx: DecisionContext = bc.decision_context_for_seat(1)
	assert_not_null(turn_ctx)
	if turn_ctx == null:
		return
	var disc_act: Action = Action.discard(
		1, disc.instance_id, CLAIM_SID, _cmd(510), turn_ctx.decision_id,
		int(bc.state.hand_seq), int(server.call("current_server_seq")) + 1
	)
	var cr_d := _as_cr(server.call("submit_action", disc_act), "ron_disc")
	if cr_d == null:
		return
	assert_eq(cr_d.status, "ACCEPTED",
		"seat1 DISCARD 须 ACCEPTED status=%s error_code=%s server_seq=%d cmd=%s phase=%d seat=%d cur=%d did=%s tile=%d"
		% [cr_d.status, cr_d.error_code, cr_d.server_seq, disc_act.command_id,
			int(bc.state.phase), disc_act.seat, int(bc.state.current_seat),
			disc_act.decision_id, disc.instance_id])
	if cr_d.status != "ACCEPTED":
		return
	# 全 HUMAN CLAIM 须全席响应后收窗：seat0 RON + seat2/3 PASS
	var cmd_n: int = 511
	var settled_after_ron := false
	for step in range(3):
		# 找仍有 CLAIM_WINDOW 的席
		var target_seat: int = -1
		var pr: NetworkedEvent = null
		for seat_i in [0, 2, 3]:
			var j := _exact_ne(server.call("event_journal", seat_i), "ron_claim_j%d" % seat_i)
			if j.is_empty():
				continue
			var last: NetworkedEvent = j[j.size() - 1] as NetworkedEvent
			if last != null and last.kind == "CLAIM_WINDOW":
				# 若该席已响应则窗口可能仍是旧 prompt；用 BC 判定
				var win = bc.get("_active_window")
				if win is DecisionWindow and not (win as DecisionWindow).has_responded(seat_i):
					target_seat = seat_i
					pr = last
					break
		assert_true(target_seat >= 0 and pr != null,
			"step%d 须仍有未响应 CLAIM 席 phase=%d settled=%s win=%s"
			% [step, int(bc.state.phase), str(bc.get("_settled")), str(bc.get("_active_window"))])
		if target_seat < 0 or pr == null:
			return
		var pp: Dictionary = pr.payload
		var did: String = str(pp.get("decision_id", ""))
		var claim_hs: int = int(pp.get("hand_seq", 0))
		var act: Action = null
		if target_seat == 0:
			act = Action.ron(
				0, CLAIM_SID, _cmd(cmd_n), did, claim_hs,
				int(server.call("current_server_seq")) + 1
			)
		else:
			act = Action.make_pass(
				target_seat, CLAIM_SID, _cmd(cmd_n), did, claim_hs,
				int(server.call("current_server_seq")) + 1
			)
		cmd_n += 1
		var cr_step := _as_cr(server.call("submit_action", act), "ron_step%d" % step)
		if cr_step == null:
			return
		assert_eq(cr_step.status, "ACCEPTED",
			"CLAIM seat%d 须 ACCEPTED status=%s error_code=%s server_seq=%d did=%s"
			% [target_seat, cr_step.status, cr_step.error_code, cr_step.server_seq, did])
		if cr_step.status != "ACCEPTED":
			return
		if bool(bc.get("_settled")):
			settled_after_ron = true
			break
	assert_true(settled_after_ron or bool(bc.get("_settled")), "RON 收窗后须 settled")
	if not bool(bc.get("_settled")):
		return

	var settled_ev := _assert_four_seat_hand_settled_same_seq(server, "ron")
	assert_not_null(settled_ev)
	if settled_ev == null:
		return
	var p: Dictionary = settled_ev.payload
	assert_eq(str(p["outcome"]), "RON")
	assert_eq(p["winner_seats"], [0])
	assert_eq(int(p["loser_seat"]), 1, "loser 须为放铳 seat1")

	var win_ev: BattleEvent = null
	for i in range(bc.events.size() - 1, -1, -1):
		var ev: BattleEvent = bc.events[i]
		if ev.type == &"WIN_DECLARED":
			win_ev = ev
			break
	assert_not_null(win_ev)
	if win_ev == null:
		return
	var state_scores: Array = []
	for s2 in bc.state.scores:
		state_scores.append(int(s2))
	var expected_scores: Dictionary = _expected_final_scores_from_win(
		start_scores, state_scores, win_ev.extra, 0
	)
	assert_eq(JSON.stringify(p["scores"]), JSON.stringify(expected_scores["scores"]))
	assert_eq(JSON.stringify(p["score_deltas"]), JSON.stringify(expected_scores["score_deltas"]))


## Red：真实 ABORTIVE_DRAW（九种九牌）→ HAND_SETTLED.outcome=ABORTIVE_DRAW。
func test_hand_settled_abortive_draw_real_outcome() -> void:
	if not _contract_ok():
		return
	var cfg := _cfg_all_human()
	assert_not_null(cfg)
	if cfg == null:
		return
	var server := LocalLoopbackServer.new(cfg, 0)
	assert_true(bool(server.call("start")))
	var bc: BattleController = server.get("_bc") as BattleController
	assert_not_null(bc)
	if bc == null:
		return
	var start_raw = server.get("_hand_start_scores")
	assert_eq(typeof(start_raw), TYPE_ARRAY, "须已冻结起始分")
	if typeof(start_raw) != TYPE_ARRAY:
		return
	var start_scores: Array = []
	for s in start_raw as Array:
		start_scores.append(int(s))

	# 九种九牌：14 张含 ≥9 种幺九（手牌 13 + last_drawn）
	var used: Dictionary = {}
	var wall_floor: int = _prep_live(bc)
	var yaochu_ids: Array = [
		TileId.W1, TileId.W9, TileId.T1, TileId.T9, TileId.S1, TileId.S9,
		TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N, TileId.HAKU,
		TileId.HATSU, TileId.CHUN,
	]
	bc.state.seats[0].hand = _hand_live(bc, yaochu_ids, used)
	var drawn: Tile = _draw_live_tid(bc, TileId.W2, used)
	assert_not_null(drawn)
	if drawn == null:
		return
	assert_true(bc.state.seats[0].hand.add(drawn))
	bc.state.seats[0].last_drawn_instance_id = drawn.instance_id
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.state.first_round_active = true
	bc.state.turn_count = 0
	bc.set("_settled", false)
	bc.set("_active_window", null)
	_seal_live_wall_draw_index(bc, wall_floor)

	var ctx: DecisionContext = bc.decision_context_for_seat(0)
	assert_not_null(ctx)
	if ctx == null:
		return
	assert_true(ctx.has_kind("DECLARE_ABORTIVE_DRAW"), "须 offer 九种九牌")
	var act: Action = Action.declare_abortive_draw(
		0, "KYUUSYU_KYUUHAI", CLAIM_SID, _cmd(520), ctx.decision_id,
		int(bc.state.hand_seq), int(server.call("current_server_seq")) + 1
	)
	var cr := _as_cr(server.call("submit_action", act), "abortive")
	if cr == null:
		return
	assert_eq(cr.status, "ACCEPTED",
		"九种九牌须 ACCEPTED status=%s error_code=%s server_seq=%d cmd=%s phase=%d settled=%s did=%s"
		% [cr.status, cr.error_code, cr.server_seq, act.command_id,
			int(bc.state.phase), str(bc.get("_settled")), act.decision_id])
	if cr.status != "ACCEPTED":
		return
	var settled_ev := _assert_four_seat_hand_settled_same_seq(server, "abortive")
	assert_not_null(settled_ev)
	if settled_ev == null:
		return
	var p: Dictionary = settled_ev.payload
	assert_eq(str(p["outcome"]), "ABORTIVE_DRAW")
	assert_eq((p["winner_seats"] as Array).size(), 0)
	assert_eq(int(p["loser_seat"]), -1)
	var state_scores: Array = []
	for s2 in bc.state.scores:
		state_scores.append(int(s2))
	var deltas: Array = []
	for i in range(4):
		deltas.append(int(state_scores[i]) - int(start_scores[i]))
	assert_eq(JSON.stringify(p["scores"]), JSON.stringify(state_scores),
		"流局 scores 须 = state.scores（无 payout）")
	assert_eq(JSON.stringify(p["score_deltas"]), JSON.stringify(deltas))


## Red：真实 EXHAUSTIVE_DRAW（无牌可摸）→ outcome=EXHAUSTIVE_DRAW，非固定伪装。
func test_hand_settled_exhaustive_draw_real_outcome() -> void:
	if not _contract_ok():
		return
	var cfg := _cfg_all_human()
	assert_not_null(cfg)
	if cfg == null:
		return
	var server := LocalLoopbackServer.new(cfg, 0)
	assert_true(bool(server.call("start")))
	var bc: BattleController = server.get("_bc") as BattleController
	assert_not_null(bc)
	if bc == null:
		return
	var start_raw = server.get("_hand_start_scores")
	assert_eq(typeof(start_raw), TYPE_ARRAY, "须已冻结起始分")
	if typeof(start_raw) != TYPE_ARRAY:
		return
	var start_scores: Array = []
	for s in start_raw as Array:
		start_scores.append(int(s))

	# 耗尽 live wall：draw_index 推到 live end，phase=DRAW → 提交 PASS 不可；
	# 直接让 AI/推进路径在 DRAW 无牌时 settle。全 HUMAN：手动把 wall 耗尽后
	# 调引擎路径触发 EXHAUSTIVE，再经 _emit_settled_if_needed 发布。
	var w: Wall = bc.state.wall
	w._draw_index = _live_end_wall(w)
	bc.state.phase = BattlePhase.Kind.DRAW
	bc.state.current_seat = 0
	bc.set("_settled", false)
	bc.set("_active_window", null)
	# 真实 domain：draw_for_current 返 null → EXHAUSTIVE_DRAW
	var drawn: Tile = bc.engine.draw_for_current()
	assert_true(drawn == null, "live 耗尽后 draw 须 null")
	# 与 BC._step_draw 一致：emit + settled
	if not bool(bc.get("_settled")):
		bc._emit(&"EXHAUSTIVE_DRAW", -1, null, {})
		bc.set("_settled", true)
	assert_true(bool(bc.get("_settled")))

	var seq0: int = int(server.call("current_server_seq"))
	var ok: bool = bool(server.call("_emit_settled_if_needed"))
	assert_true(ok, "_emit_settled_if_needed 须 true（bool 返回）")
	assert_eq(int(server.call("current_server_seq")), seq0 + 1,
		"成功发布须仅 +1 逻辑 seq")
	var settled_ev := _assert_four_seat_hand_settled_same_seq(server, "exhaustive")
	assert_not_null(settled_ev)
	if settled_ev == null:
		return
	var p: Dictionary = settled_ev.payload
	assert_eq(str(p["outcome"]), "EXHAUSTIVE_DRAW")
	assert_eq((p["winner_seats"] as Array).size(), 0)
	assert_eq(int(p["loser_seat"]), -1)
	var state_scores: Array = []
	for s2 in bc.state.scores:
		state_scores.append(int(s2))
	var deltas: Array = []
	for i in range(4):
		deltas.append(int(state_scores[i]) - int(start_scores[i]))
	assert_eq(JSON.stringify(p["scores"]), JSON.stringify(state_scores))
	assert_eq(JSON.stringify(p["score_deltas"]), JSON.stringify(deltas))


## 契约：1H+3AI 真实 CLAIM 链至 seat3 弃后、seat0 最后 PASS 前精确耗尽 live wall；
## 合法 seat0 PASS 经真实 submit → ACCEPTED；BC.events 含真实 EXHAUSTIVE_DRAW；
## 四席 HAND_SETTLED 同 seq 且 outcome=EXHAUSTIVE_DRAW。
## 禁手工 emit / set settled / 直接 _emit_settled_if_needed（须走 submit 发布路径）。
func test_arm_pass_empty_live_wall_exhaustive_draw_hand_settled_via_submit() -> void:
	if not _contract_ok():
		return
	var cfg := _cfg()
	assert_not_null(cfg)
	if cfg == null:
		return
	var server := LocalLoopbackServer.new(cfg, 0)
	assert_not_null(server)
	if server == null:
		return
	var cmd_n: int = _arm_claim_before_seat0_return_turn(server, 540, "exh_arm")
	if cmd_n < 0:
		return
	var bc: BattleController = server.get("_bc") as BattleController
	assert_not_null(bc, "须有真实 BC")
	if bc == null:
		return
	var wall: Wall = bc.state.wall
	assert_not_null(wall, "须有真实 Wall")
	if wall == null:
		return
	# 最后 PASS 前：live wall 精确耗尽；下一次 seat0 DRAW 应触发真实 EXHAUSTIVE_DRAW
	wall._draw_index = _live_end_wall(wall)

	var pr := _prompt(server)
	assert_not_null(pr, "PASS 前须有 CLAIM_WINDOW prompt")
	if pr == null:
		return
	assert_eq(pr.kind, "CLAIM_WINDOW", "临界 prompt 须 CLAIM_WINDOW")
	var act := _pass_act(pr, cmd_n, SID, 0)
	assert_not_null(act, "须能从当前 prompt 构造合法 seat0 PASS")
	if act == null:
		return
	assert_eq(act.kind, "PASS")

	var cr := _as_cr(server.call("submit_action", act), "exh_pass")
	if cr == null:
		return
	assert_eq(cr.status, "ACCEPTED",
		"耗尽 live 后合法 seat0 PASS 须 ACCEPTED status=%s error_code=%s server_seq=%d cmd=%s"
		% [cr.status, cr.error_code, cr.server_seq, act.command_id])
	if cr.status != "ACCEPTED":
		return
	assert_eq(cr.error_code, "")
	assert_eq(cr.command_id, act.command_id)

	# BC.events 须含真实 domain EXHAUSTIVE_DRAW（非手工 emit）
	var found_exh := false
	for i in range(bc.events.size() - 1, -1, -1):
		var ev: BattleEvent = bc.events[i]
		if ev != null and ev.type == &"EXHAUSTIVE_DRAW":
			found_exh = true
			break
	assert_true(found_exh, "BC.events 须含真实 EXHAUSTIVE_DRAW")

	var settled_ev := _assert_four_seat_hand_settled_same_seq(server, "exh_submit")
	assert_not_null(settled_ev, "四席须有 HAND_SETTLED")
	if settled_ev == null:
		return
	assert_eq(str(settled_ev.payload.get("outcome", "")), "EXHAUSTIVE_DRAW",
		"HAND_SETTLED.outcome 须 EXHAUSTIVE_DRAW")


## Red：HAND_SETTLED recipient 构建失败 → 零半提交；submit 整笔回滚；同 command_id 可重试。
func test_hand_settled_recipient_fail_zero_commit_and_submit_rollback_retry() -> void:
	if not _contract_ok():
		return
	var cfg := _cfg_all_human()
	assert_not_null(cfg)
	if cfg == null:
		return
	var server := FailingHandSettledServer.new(cfg, 0)
	assert_not_null(server)
	if server == null:
		return
	assert_true(bool(server.call("start")))
	var bc: BattleController = server.get("_bc") as BattleController
	assert_not_null(bc)
	if bc == null:
		return

	var used: Dictionary = {}
	var wall_floor: int = _prep_live(bc)
	bc.state.seats[0].hand = _hand_live(bc, _chiitoi_13(), used)
	bc.state.first_round_active = false
	var win_t: Tile = _draw_live_tid(bc, TileId.W9, used)
	assert_not_null(win_t)
	if win_t == null:
		return
	assert_true(bc.state.seats[0].hand.add(win_t))
	bc.state.seats[0].last_drawn_instance_id = win_t.instance_id
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.set("_settled", false)
	bc.set("_active_window", null)
	_seal_live_wall_draw_index(bc, wall_floor)

	var ctx: DecisionContext = bc.decision_context_for_seat(0)
	assert_not_null(ctx)
	if ctx == null:
		return
	assert_true(ctx.has_kind("TSUMO"))
	var act: Action = Action.tsumo(
		0, CLAIM_SID, _cmd(530), ctx.decision_id, int(bc.state.hand_seq),
		int(server.call("current_server_seq")) + 1
	)
	server.enabled = true
	server.fail_seat = 2
	server.call_count = 0
	server.fail_hit = 0
	var frozen: Dictionary = _freeze_accepted_batch_state(server, "hs_fail0")
	var cr := _as_cr(server.call("submit_action", act), "hs_fail_submit")
	if cr == null:
		return
	assert_gt(server.fail_hit, 0,
		"须命中 HAND_SETTLED recipient 失败注入（seat2） status=%s error_code=%s server_seq=%d fail_hit=%d call_count=%d settled=%s phase=%d"
		% [cr.status, cr.error_code, cr.server_seq, server.fail_hit, server.call_count,
			str(bc.get("_settled")), int(bc.state.phase)])
	assert_eq(cr.status, "REJECTED",
		"HAND_SETTLED 发布失败须整笔 REJECTED status=%s error_code=%s server_seq=%d fail_hit=%d"
		% [cr.status, cr.error_code, cr.server_seq, server.fail_hit])
	if server.fail_hit <= 0 or cr.status != "REJECTED":
		return
	assert_eq(cr.error_code, "EVENT_PUBLISH_FAILED")
	assert_eq(cr.command_id, act.command_id)
	assert_eq(cr.server_seq, int(frozen["seq"]))
	_assert_accepted_batch_zero_mutation(server, frozen, "hs_fail")
	# 任一座 journal 不得出现 HAND_SETTLED 半条
	for seat in range(4):
		assert_null(_find_hand_settled(server, seat),
			"失败后 seat%d 不得有 HAND_SETTLED" % seat)

	server.enabled = false
	var cr2 := _as_cr(server.call("submit_action", act), "hs_fail_retry")
	if cr2 == null:
		return
	assert_eq(cr2.status, "ACCEPTED",
		"禁用后同 command_id 重试须 ACCEPTED status=%s error_code=%s server_seq=%d"
		% [cr2.status, cr2.error_code, cr2.server_seq])
	assert_eq(cr2.error_code, "")
	assert_gt(int(server.call("current_server_seq")), int(frozen["seq"]))
	var settled_ev := _assert_four_seat_hand_settled_same_seq(server, "hs_retry")
	assert_not_null(settled_ev)
	if settled_ev != null:
		assert_eq(str(settled_ev.payload.get("outcome", "")), "TSUMO")


## Red：直接 _emit_settled_if_needed 在 recipient 中途失败时零 mutation（禁 alloc+半 append）。
func test_emit_settled_recipient_mid_fail_zero_seq_and_journal() -> void:
	if not _contract_ok():
		return
	var server := FailingHandSettledServer.new(_cfg_all_human(), 0)
	assert_not_null(server)
	if server == null:
		return
	assert_true(bool(server.call("start")))
	var bc: BattleController = server.get("_bc") as BattleController
	assert_not_null(bc)
	if bc == null:
		return
	# 直接注入 settled + 真实 ABORTIVE 事件（不经 mock 规则，仅标记已结算）
	bc._emit(&"ABORTIVE_DRAW", -1, null, {"reason": "suufon_renda"})
	bc.set("_settled", true)
	server.enabled = true
	server.fail_seat = 1
	server.fail_hit = 0
	var seq0: int = int(server.call("current_server_seq"))
	var j0: Array = _journal_dicts(server, "emit_mid0")
	var ok: bool = bool(server.call("_emit_settled_if_needed"))
	assert_false(ok, "recipient 失败须 return false")
	assert_gt(server.fail_hit, 0, "须命中 fail_seat")
	assert_eq(int(server.call("current_server_seq")), seq0,
		"失败：server_seq 零变化（禁先 alloc）")
	assert_eq(
		JSON.stringify(_journal_dicts(server, "emit_mid1")), JSON.stringify(j0),
		"失败：四席 journal 零变化（禁半 append）")
