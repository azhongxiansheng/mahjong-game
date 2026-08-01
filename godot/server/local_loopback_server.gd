class_name LocalLoopbackServer
extends RefCounted

# E2-02 / #232：本地 loopback 权威桩。
# 包裹 BattleController 唯一 apply_action(Action, ActionSource) 入口。
# 对外核心 API：new(config, dealer_seat)、start、submit_action、publish_snapshot、
# events_since、event_journal、current_server_seq。
# 不保留 PASS 特判 / NYI / 旧构造 / 旧裸 Dictionary 路径。

const MAX_AI_STEPS := 2000
const ERROR_NOT_STARTED := "NOT_STARTED"
const ERROR_UNAUTHORIZED := "UNAUTHORIZED"
const ERROR_COMMAND_ID_CONFLICT := "COMMAND_ID_CONFLICT"
const ERROR_EVENT_PUBLISH_FAILED := "EVENT_PUBLISH_FAILED"
## E5-04：可回放权威时钟基线（ms）；grace_deadline_at 不得依赖墙钟。
const REWARD_CLOCK_BASE_MS := 1_700_000_000_000

var _config: GameSessionConfig = null
var _dealer_seat: int = 0
## 自建 BC 强拥有；Practice 注入 BC 仅 WeakRef（不环引用 PBC）。
var _bc_owned: BattleController = null
var _bc_injected: WeakRef = null
var _bc: BattleController:
	get:
		if _bc_injected != null:
			var r = _bc_injected.get_ref()
			return r as BattleController
		return _bc_owned
	set(value):
		_bc_owned = value
		_bc_injected = null
var _room_id: String = ""
var _server_seq: int:
	get:
		return _publisher.server_seq
	set(value):
		_publisher.server_seq = value
var _started: bool = false
# restore 失败后不可再证明权威状态；实例永久 fail-closed，只能丢弃重建。
var _rollback_failed: bool = false
# ARCH-02 #392：server_seq / 四席 journal 所有权委托 AuthorityEventPublisher；
# 本类经属性透传保持全部既有读写点与测试内省面不变。
var _publisher := AuthorityEventPublisher.new()
var _journals: Array:
	get:
		return _publisher.journals
	set(value):
		_publisher.journals = value
# ARCH-02 #392：命令指纹/幂等缓存委托 AuthorityCommandProcessor。
var _commands := AuthorityCommandProcessor.new()
# 只读内省兼容面（characterization 测试经 get("_command_cache") 看 size/键集）；
# 一切写路径必须走 _commands。
var _command_cache: Dictionary:
	get:
		return _commands.entries()
# seat → participant wire ("HUMAN"/"AI")
var _participants: Array = []
# 本局起始分：仅 start 成功后冻结；失败 start 不得污染（空 = 未冻结）
var _hand_start_scores: Array = []
# #375：本局起始本场 / 立直棒（与起始分同生命周期冻结）
var _hand_start_honba: int = 0
var _hand_start_riichi_sticks: int = 0
# #375：本局结算提交幂等 tracker
var _settlement_tracker: Dictionary = HandSettlement.empty_tracker()
# E2-04：构造期模式模块包（STANDARD 四零 / TRASH_TALK 最小对象）
var mode_modules: ModeModuleBundle = null
# #241：快照 module provider 注册表（STANDARD 仅 core_table；TRASH_TALK + reward_window）
# ARCH-02 #392：snapshot registry / 按席 SNAP 组装委托 AuthoritySnapshotService；
# 属性透传保持公开内省面（snapshot_registry）不变。
var _snapshots := AuthoritySnapshotService.new()
var snapshot_registry: SnapshotModuleRegistry:
	get:
		return _snapshots.registry
	set(value):
		_snapshots.registry = value
# #241：HUMAN 席临时 AI 接管（不改 participants 配置）
var _ai_control_seats: Dictionary = {}  # seat(int) -> bool
# 测试：下一次 publish_snapshot 强制失败（不改业务路径）
var _fail_next_snapshot: bool = false
# 测试：下一次 ACTION_APPLIED/SNAP 发布强制失败（AI step / submit 共用 emit）
var _fail_next_action_publish: bool = false
## #376 R4 测试：仅 start_next_hand 内首个 publish_snapshot 失败（不消耗通用 fail_next）
var _fail_next_hand_start_snapshot: bool = false
var fail_next_hand_start_snapshot_hit_count: int = 0
## #376 R4 测试：MATCH_SETTLED 已发布后强制失败（验证外层 rollback 清 MATCH flag）
var _fail_after_match_settled_for_test: bool = false
var fail_after_match_settled_hit_count: int = 0
## #376 R5 测试：下一次 match_authority payload 强制空（禁 fallback）
var _fail_match_authority_payload: bool = false
var fail_match_authority_payload_hit_count: int = 0
# #241：本局 HAND_SETTLED 是否已发布（幂等，禁止重复 seq/journal；多局不得靠全局 journal 粗查）
var _hand_settled_emitted: bool = false
## #256：整场 MATCH_SETTLED 是否已权威发布（O(1) 完成态；不经 event_journal 克隆）
var _match_settled_emitted: bool = false
## 测试/诊断：event_journal 被调用次数（每次会 _clone_events 全量复制）
var event_journal_call_count: int = 0
## #379：BC.events 已投影到 journal 的下标（O(新增) 游标；禁止 action 热路径 event_journal）
var _skill_bc_proj_upto: int = 0
## E5-04：权威奖励时钟（仅 advance_reward_time 单调推进；禁止墙钟/伪造跳跃）
var _reward_authority_now_ms: int = REWARD_CLOCK_BASE_MS
## 整场是否结束：仅显式注入；默认 null=未知→流局按 match 继续(FULL_GRANT)
## #376：生产路径优先 match_end_after_hand；本字段仅保留测试/遗留 seam。
var _reward_match_ended = null
## CLOSING 后是否曾见过开放 CLAIM/ROB 窗（用于区分「尚未开 CLAIM」与「CLAIM 已终态」）
var _reward_claim_seen_open: bool = false
## 流局/终场 scoring close 因 grace 延迟：须先 SETTLED 再 HAND_SETTLED
var _reward_hand_settled_deferred: bool = false
## #253：权威内部 apply 中，禁止 PBC 再路由回 Loopback
var _internal_apply: bool = false
## #376：Callable(settlement: Dictionary) -> bool；生产由 HeadlessRoomSession 绑定。
## 判断本局 HAND_SETTLED 后是否终场（连庄/半庄规则），不得依赖 set_reward_match_ended。
var match_end_after_hand: Callable = Callable()
## #376：Callable(settlement: Dictionary) -> Dictionary
## 返回 {finished:bool, bc:BattleController|null}；未终场时提供下一局 BC。
var on_hand_settled_committed: Callable = Callable()
## #376：match owner（HeadlessRoomSession）— capture/restore 与 snapshot 投影。
var match_owner: Object = null
## #376：Action/Reward 事务级冻结（含 match + BC 所有权），供完整回滚。
var _tx_match_freeze: Dictionary = {}
var _tx_bc_strong: BattleController = null
var _tx_bc_owned: BattleController = null
var _tx_bc_injected: WeakRef = null
## #376 P1-2：mutation 前 ARS；失败后禁止现拍
var _tx_bc_ars: AuthorityReplaySnapshot = null
var _tx_ai_control: Dictionary = {}
var _tx_hand_start_scores: Array = []
var _tx_hand_start_honba: int = 0
var _tx_hand_start_riichi: int = 0
var _tx_reward_match_ended = null
var _tx_server_seq: int = -1
var _tx_journals: Array = []
var _tx_settlement_tracker: Dictionary = {}
var _tx_hand_settled_emitted: bool = false
var _tx_match_settled_emitted: bool = false
var _tx_rw_state: Dictionary = {}
var _tx_rw_clock: int = -1
var _tx_claim_seen: bool = false
var _tx_hand_deferred: bool = false
## #379：事务冻结时的技能投影游标
var _tx_skill_bc_proj_upto: int = 0
## 嵌套/重复 begin 防护
var _tx_active: bool = false


func is_processing_internal() -> bool:
	return _internal_apply


func _apply_on_bc(action: Action, source: StringName) -> ActionResolution:
	if _bc == null:
		return null
	_internal_apply = true
	var res: ActionResolution = _bc.apply_action(action, source)
	_internal_apply = false
	return res


## inject_bc / inject_modules：练习场与 PBC 共享同一 BC+模块（#253 生产入口）。
func _init(
	config: GameSessionConfig = null,
	dealer_seat: int = 0,
	inject_bc: BattleController = null,
	inject_modules: ModeModuleBundle = null
) -> void:
	_config = config
	_dealer_seat = dealer_seat
	_server_seq = 0
	_started = false
	_rollback_failed = false
	_journals = [[], [], [], []]
	_commands.clear()
	_hand_start_scores = []
	_hand_start_honba = 0
	_hand_start_riichi_sticks = 0
	_settlement_tracker = HandSettlement.empty_tracker()
	_participants = [&"HUMAN", &"AI", &"AI", &"AI"]
	mode_modules = null
	snapshot_registry = SnapshotModuleRegistry.make_standard()
	_ai_control_seats = {}
	_fail_next_snapshot = false
	_fail_next_action_publish = false
	_fail_next_hand_start_snapshot = false
	fail_next_hand_start_snapshot_hit_count = 0
	_fail_after_match_settled_for_test = false
	fail_after_match_settled_hit_count = 0
	_fail_match_authority_payload = false
	fail_match_authority_payload_hit_count = 0
	_hand_settled_emitted = false
	_match_settled_emitted = false
	event_journal_call_count = 0
	_skill_bc_proj_upto = 0
	_reward_authority_now_ms = REWARD_CLOCK_BASE_MS
	_reward_match_ended = null
	_reward_claim_seen_open = false
	_reward_hand_settled_deferred = false
	if config != null:
		_room_id = config.session_id
		var parts: Array = config.participants
		if parts.size() == 4:
			_participants = parts.duplicate()
		if inject_modules != null:
			mode_modules = inject_modules
		else:
			mode_modules = ModeModuleBundle.from_config(config)
		# #252：仅 TRASH_TALK 注册 reward_window；STANDARD 严格仅 core_table
		if mode_modules != null and mode_modules.is_trash_talk():
			snapshot_registry = SnapshotModuleRegistry.make_trash_talk()
			# #253：实例 ID 公开 match 命名空间 = session_id（可回放、跨房间唯一）
			if mode_modules.item_inventory != null:
				mode_modules.item_inventory.set_match_namespace(str(config.session_id))
		if inject_bc != null:
			_bc_owned = null
			_bc_injected = weakref(inject_bc)
		else:
			_bc_injected = null
			_bc_owned = BattleController.new(config.seed, dealer_seat, false, TileId.E, 0)
		if _bc != null:
			_bc.bind_mode_modules(mode_modules)
	else:
		_room_id = ""
		_bc_owned = null
		_bc_injected = null


func start() -> bool:
	if _rollback_failed:
		return false
	if _started:
		return false
	if _bc == null or _bc.state == null:
		return false
	# 任何 mutation 前捕获 ARS 并冻结服务端副作用字段
	var snap: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(_bc)
	if snap == null:
		return false
	var auth_h: String = snap.sha256()
	if auth_h.is_empty() or auth_h.length() != 64 or not snap.can_restore():
		return false
	# 无副作用时点：mutation 前读取本局起始分/本场/立直棒候选；仅 start 成功后提交
	var start_scores_candidate: Array = _capture_scores_array()
	if start_scores_candidate.size() != 4:
		return false
	var start_honba_candidate: int = int(_bc.state.honba)
	var start_riichi_candidate: int = int(_bc.state.riichi_sticks)
	var frozen_seq: int = _server_seq
	var frozen_journals: Array = []
	for s in range(4):
		frozen_journals.append(_clone_events(_journals[s] as Array))
	var frozen_cache: Dictionary = _commands.capture()
	var frozen_started: bool = _started
	var frozen_hand_start: Array = _hand_start_scores.duplicate()
	var frozen_hand_start_honba: int = _hand_start_honba
	var frozen_hand_start_riichi_sticks: int = _hand_start_riichi_sticks
	# #253 Round 8：prepare 与后续 mutation 同一事务；含 inv/slot/registry index
	var frozen_rw: Dictionary = _reward_capture_state()
	var frozen_rw_clock: int = _reward_authority_now_ms
	var frozen_claim_seen: bool = _reward_claim_seen_open
	var frozen_hand_deferred: bool = _reward_hand_settled_deferred
	var frozen_hand_settled: bool = _hand_settled_emitted
	var frozen_settlement_tracker: Dictionary = _settlement_tracker.duplicate(true)

	# #253：跨局库存实例 → 新 BC.registry 重绑（relic held / delayed armed）
	if mode_modules != null and mode_modules.is_trash_talk() and _item_module() != null:
		var prep: Dictionary = ItemAuthority.prepare_new_hand(
			_bc, _item_module(), _ability_slots()
		)
		if not bool(prep.get("ok", false)):
			# prepare 内部已回滚自身 mutation；再冻结合约保证与调用前一致
			_reward_restore_state(frozen_rw)
			return false
	# 跨局：共享 RewardWindow 与新 BC.hand_seq 不一致时 hard_reset，由 _maybe_open 重开
	var rw_boot: RewardWindowModule = _reward_module()
	if rw_boot != null and _bc != null and _bc.state != null:
		if int(rw_boot.hand_seq) != int(_bc.state.hand_seq) \
				or rw_boot.phase == RewardWindowModule.PHASE_OPEN \
				or rw_boot.phase == RewardWindowModule.PHASE_CLOSING:
			rw_boot.hard_reset()
	# DRAW → 摸牌；ROOM_SNAPSHOT(IDLE) → OPENED → ROOM_SNAPSHOT(OPEN) → TURN_PROMPT
	# 开窗后补发新鲜 SNAP，供 prompt/重连持有 OPEN 投影（非仅 IDLE）
	_ensure_drawn()
	# #253+#379：start 首摸可触发跨局 armed delayed；finalize 批内 SKILL 先于 ITEM_* 并配 SNAP
	if not _finalize_item_triggers():
		return _fail_start_rollback(
			snap, frozen_seq, frozen_journals, frozen_cache, frozen_rw,
			frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
			frozen_hand_settled, frozen_started, frozen_hand_start, frozen_hand_start_honba, frozen_hand_start_riichi_sticks, frozen_settlement_tracker,
			0
		)
	if not publish_snapshot():
		return _fail_start_rollback(
			snap, frozen_seq, frozen_journals, frozen_cache, frozen_rw,
			frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
			frozen_hand_settled, frozen_started, frozen_hand_start, frozen_hand_start_honba, frozen_hand_start_riichi_sticks, frozen_settlement_tracker
		)
	# E5-04 / #252：权威开局快照后、首条 TURN_PROMPT 前开窗
	if not _maybe_open_reward_window():
		return _fail_start_rollback(
			snap, frozen_seq, frozen_journals, frozen_cache, frozen_rw,
			frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
			frozen_hand_settled, frozen_started, frozen_hand_start, frozen_hand_start_honba, frozen_hand_start_riichi_sticks, frozen_settlement_tracker
		)
	# 开窗后 OPEN 投影 SNAP（seq 连续；失败全回滚）
	if _reward_module() != null:
		if not publish_snapshot():
			return _fail_start_rollback(
				snap, frozen_seq, frozen_journals, frozen_cache, frozen_rw,
				frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
				frozen_hand_settled, frozen_started, frozen_hand_start, frozen_hand_start_honba, frozen_hand_start_riichi_sticks, frozen_settlement_tracker
			)
	# AI 庄：先推进到真人决策入口再发 TURN/CLAIM prompt（否则 AI TURN 会令 start 失败）
	if not _auto_advance_ai():
		return _fail_start_rollback(
			snap, frozen_seq, frozen_journals, frozen_cache, frozen_rw,
			frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
			frozen_hand_settled, frozen_started, frozen_hand_start, frozen_hand_start_honba, frozen_hand_start_riichi_sticks, frozen_settlement_tracker
		)
	# #379：AI 链技能在 settlement 前投影
	if not _publish_pending_skill_triggered_from_bc():
		return _fail_start_rollback(
			snap, frozen_seq, frozen_journals, frozen_cache, frozen_rw,
			frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
			frozen_hand_settled, frozen_started, frozen_hand_start, frozen_hand_start_honba, frozen_hand_start_riichi_sticks, frozen_settlement_tracker
		)
	if bool(_bc.get("_settled")):
		# #375：AI 庄 start 内终局（如合法 TSUMO）须同事务发布 HAND_SETTLED。
		# 顺序：先冻结起分供 HandSettlement → 清空本局 tracker/emitted → emit；
		# 成功后不得再清空已提交 tracker（commit 写入的 canonical 必须保留）。
		_hand_start_scores = start_scores_candidate
		_hand_start_honba = start_honba_candidate
		_hand_start_riichi_sticks = start_riichi_candidate
		_settlement_tracker = HandSettlement.empty_tracker()
		_hand_settled_emitted = false
		if not _emit_settled_if_needed():
			return _fail_start_rollback(
				snap, frozen_seq, frozen_journals, frozen_cache, frozen_rw,
				frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
				frozen_hand_settled, frozen_started, frozen_hand_start,
				frozen_hand_start_honba, frozen_hand_start_riichi_sticks,
				frozen_settlement_tracker
			)
		# deferred（TRASH_TALK CLOSING）仍算 start 成功；已发布则 tracker/emitted 已提交
		_started = true
		return true
	if not _emit_private_prompt():
		return _fail_start_rollback(
			snap, frozen_seq, frozen_journals, frozen_cache, frozen_rw,
			frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
			frozen_hand_settled, frozen_started, frozen_hand_start, frozen_hand_start_honba, frozen_hand_start_riichi_sticks, frozen_settlement_tracker
		)
	_hand_start_scores = start_scores_candidate
	_hand_start_honba = start_honba_candidate
	_hand_start_riichi_sticks = start_riichi_candidate
	_settlement_tracker = HandSettlement.empty_tracker()
	_hand_settled_emitted = false
	_started = true
	return true


## #376：同一房间 identity 下开启下一局。
## 保留 journal / server_seq / mode_modules / AI 接管位；替换 BC 并发布新局 SNAP/prompt。
## 要求：上一局 HAND_SETTLED 已发布且整场未 MATCH_SETTLED。
func start_next_hand(new_bc: BattleController) -> bool:
	if _rollback_failed:
		return false
	if not _started or _match_settled_emitted:
		return false
	if not _hand_settled_emitted:
		return false
	if new_bc == null or new_bc.state == null:
		return false
	# 保留跨局状态
	var frozen_seq: int = _server_seq
	var frozen_journals: Array = []
	for s in range(4):
		frozen_journals.append(_clone_events(_journals[s] as Array))
	var frozen_cache: Dictionary = _commands.capture()
	var frozen_ai: Dictionary = _ai_control_seats.duplicate(true)
	var frozen_rw: Dictionary = _reward_capture_state()
	var frozen_rw_clock: int = _reward_authority_now_ms
	# #379：跨局失败必须恢复旧局投影游标（换 BC 前冻结）
	var frozen_skill_proj: int = _skill_bc_proj_upto
	var prev_bc: BattleController = _bc
	var prev_owned: BattleController = _bc_owned
	var prev_injected: WeakRef = _bc_injected

	# 换 BC（强拥有新局；不触碰 journal）
	_bc_injected = null
	_bc_owned = new_bc
	_dealer_seat = int(new_bc.state.dealer_seat)
	if mode_modules != null:
		new_bc.bind_mode_modules(mode_modules)
	# 恢复 AI 接管标志到新 BC 路径（set_seat_ai_control 只写字典）
	_ai_control_seats = frozen_ai.duplicate(true)
	for seat_k in _ai_control_seats.keys():
		set_seat_ai_control(int(seat_k), bool(_ai_control_seats[seat_k]))

	_hand_settled_emitted = false
	_settlement_tracker = HandSettlement.empty_tracker()
	_hand_start_scores = []
	_hand_start_honba = 0
	_hand_start_riichi_sticks = 0
	_reward_claim_seen_open = false
	_reward_hand_settled_deferred = false
	_reward_match_ended = null
	# #379：新 BC.events 从 0 起投影
	_skill_bc_proj_upto = 0
	# 新局命令指纹与上一局隔离（hand_seq 已变；缓存仍清以免 stale）
	_commands.clear()

	var snap: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(_bc)
	if snap == null or not snap.can_restore():
		_restore_bc_after_next_hand_fail(prev_owned, prev_injected, prev_bc)
		_server_seq = frozen_seq
		_journals = frozen_journals
		_commands.restore(frozen_cache)
		_ai_control_seats = frozen_ai
		_hand_settled_emitted = true
		_skill_bc_proj_upto = frozen_skill_proj
		_reward_restore_state(frozen_rw)
		_reward_authority_now_ms = frozen_rw_clock
		return false

	var start_scores_candidate: Array = _capture_scores_array()
	if start_scores_candidate.size() != 4:
		_restore_bc_after_next_hand_fail(prev_owned, prev_injected, prev_bc)
		_server_seq = frozen_seq
		_journals = frozen_journals
		_commands.restore(frozen_cache)
		_ai_control_seats = frozen_ai
		_hand_settled_emitted = true
		_skill_bc_proj_upto = frozen_skill_proj
		_reward_restore_state(frozen_rw)
		_reward_authority_now_ms = frozen_rw_clock
		return false
	var start_honba_candidate: int = int(_bc.state.honba)
	var start_riichi_candidate: int = int(_bc.state.riichi_sticks)

	if mode_modules != null and mode_modules.is_trash_talk() and _item_module() != null:
		var prep: Dictionary = ItemAuthority.prepare_new_hand(
			_bc, _item_module(), _ability_slots()
		)
		if not bool(prep.get("ok", false)):
			_restore_bc_after_next_hand_fail(prev_owned, prev_injected, prev_bc)
			_server_seq = frozen_seq
			_journals = frozen_journals
			_commands.restore(frozen_cache)
			_ai_control_seats = frozen_ai
			_hand_settled_emitted = true
			_skill_bc_proj_upto = frozen_skill_proj
			_reward_restore_state(frozen_rw)
			_reward_authority_now_ms = frozen_rw_clock
			return false
	var rw_boot: RewardWindowModule = _reward_module()
	if rw_boot != null and _bc != null and _bc.state != null:
		if int(rw_boot.hand_seq) != int(_bc.state.hand_seq) \
				or rw_boot.phase == RewardWindowModule.PHASE_OPEN \
				or rw_boot.phase == RewardWindowModule.PHASE_CLOSING:
			rw_boot.hard_reset()

	_ensure_drawn()
	# #379：跨局首摸技能与 ITEM finalize 同批（SKILL 先于 APPLIED/CONSUMED）
	if not _finalize_item_triggers():
		return _fail_next_hand_rollback(
			snap, frozen_seq, frozen_journals, frozen_cache, frozen_ai,
			frozen_rw, frozen_rw_clock, prev_owned, prev_injected, frozen_skill_proj
		)
	# #376 R4 测试 seam：仅本处命中，证明失败边界在 start_next_hand 首 SNAP
	if _fail_next_hand_start_snapshot:
		_fail_next_hand_start_snapshot = false
		fail_next_hand_start_snapshot_hit_count += 1
		return _fail_next_hand_rollback(
			snap, frozen_seq, frozen_journals, frozen_cache, frozen_ai,
			frozen_rw, frozen_rw_clock, prev_owned, prev_injected, frozen_skill_proj
		)
	if not publish_snapshot():
		return _fail_next_hand_rollback(
			snap, frozen_seq, frozen_journals, frozen_cache, frozen_ai,
			frozen_rw, frozen_rw_clock, prev_owned, prev_injected, frozen_skill_proj
		)
	if not _maybe_open_reward_window():
		return _fail_next_hand_rollback(
			snap, frozen_seq, frozen_journals, frozen_cache, frozen_ai,
			frozen_rw, frozen_rw_clock, prev_owned, prev_injected, frozen_skill_proj
		)
	if _reward_module() != null:
		if not publish_snapshot():
			return _fail_next_hand_rollback(
				snap, frozen_seq, frozen_journals, frozen_cache, frozen_ai,
				frozen_rw, frozen_rw_clock, prev_owned, prev_injected, frozen_skill_proj
			)
	if not _auto_advance_ai():
		return _fail_next_hand_rollback(
			snap, frozen_seq, frozen_journals, frozen_cache, frozen_ai,
			frozen_rw, frozen_rw_clock, prev_owned, prev_injected, frozen_skill_proj
		)
	# AI 链可能再产生技能；settlement 前再冲一次
	if not _publish_pending_skill_triggered_from_bc():
		return _fail_next_hand_rollback(
			snap, frozen_seq, frozen_journals, frozen_cache, frozen_ai,
			frozen_rw, frozen_rw_clock, prev_owned, prev_injected, frozen_skill_proj
		)
	if bool(_bc.get("_settled")):
		_hand_start_scores = start_scores_candidate
		_hand_start_honba = start_honba_candidate
		_hand_start_riichi_sticks = start_riichi_candidate
		_settlement_tracker = HandSettlement.empty_tracker()
		_hand_settled_emitted = false
		if not _emit_settled_if_needed():
			return _fail_next_hand_rollback(
				snap, frozen_seq, frozen_journals, frozen_cache, frozen_ai,
				frozen_rw, frozen_rw_clock, prev_owned, prev_injected, frozen_skill_proj
			)
		return true
	if not _emit_private_prompt():
		return _fail_next_hand_rollback(
			snap, frozen_seq, frozen_journals, frozen_cache, frozen_ai,
			frozen_rw, frozen_rw_clock, prev_owned, prev_injected, frozen_skill_proj
		)
	_hand_start_scores = start_scores_candidate
	_hand_start_honba = start_honba_candidate
	_hand_start_riichi_sticks = start_riichi_candidate
	_settlement_tracker = HandSettlement.empty_tracker()
	_hand_settled_emitted = false
	return true


func _restore_bc_after_next_hand_fail(
	prev_owned: BattleController,
	prev_injected: WeakRef,
	_prev_bc: BattleController
) -> void:
	_bc_owned = prev_owned
	_bc_injected = prev_injected


func _fail_next_hand_rollback(
	snap: AuthorityReplaySnapshot,
	frozen_seq: int,
	frozen_journals: Array,
	frozen_cache: Dictionary,
	frozen_ai: Dictionary,
	frozen_rw: Dictionary,
	frozen_rw_clock: int,
	prev_owned: BattleController,
	prev_injected: WeakRef,
	frozen_skill_proj: int = 0
) -> bool:
	# 尽量 ARS 回滚新 BC 副作用后换回旧 BC；journal/seq/cursor 必须回到调用前
	if snap != null and _bc != null:
		snap.restore_into(_bc)
	_restore_bc_after_next_hand_fail(prev_owned, prev_injected, null)
	_server_seq = frozen_seq
	_journals = []
	for s in range(4):
		if s < frozen_journals.size():
			_journals.append(frozen_journals[s])
		else:
			_journals.append([])
	_commands.restore(frozen_cache)
	_ai_control_seats = frozen_ai
	_hand_settled_emitted = true
	_settlement_tracker = HandSettlement.empty_tracker()
	_skill_bc_proj_upto = maxi(frozen_skill_proj, 0)
	if _bc != null:
		_skill_bc_proj_upto = mini(_skill_bc_proj_upto, _bc.events.size())
	_reward_restore_state(frozen_rw)
	_reward_authority_now_ms = frozen_rw_clock
	_reward_claim_seen_open = false
	_reward_hand_settled_deferred = false
	return false

## start 任一后续步骤失败：ARS + 服务端字段 + inv/slot/registry index 精确回调用前。
## #379：frozen_skill_proj 默认 0（start 入口 cursor）；须显式传入避免 cursor 悬空。
func _fail_start_rollback(
	snap: AuthorityReplaySnapshot,
	frozen_seq: int,
	frozen_journals: Array,
	frozen_cache: Dictionary,
	frozen_rw: Dictionary,
	frozen_rw_clock: int,
	frozen_claim_seen: bool,
	frozen_hand_deferred: bool,
	frozen_hand_settled: bool,
	frozen_started: bool,
	frozen_hand_start: Array,
	frozen_hand_start_honba: int = 0,
	frozen_hand_start_riichi_sticks: int = 0,
	frozen_settlement_tracker: Dictionary = {},
	frozen_skill_proj: int = 0
) -> bool:
	if _rollback_transaction(
		snap, frozen_seq, frozen_journals, frozen_cache,
		frozen_rw, frozen_rw_clock, frozen_claim_seen,
		frozen_hand_deferred, frozen_hand_settled,
		frozen_settlement_tracker, frozen_skill_proj
	):
		_started = frozen_started
		# #375：三项起分冻结须同事务恢复（scores + honba + riichi_sticks）
		_hand_start_scores = frozen_hand_start
		_hand_start_honba = frozen_hand_start_honba
		_hand_start_riichi_sticks = frozen_hand_start_riichi_sticks
	return false


func fail_next_snapshot_for_test() -> void:
	_fail_next_snapshot = true


func fail_next_action_publish_for_test() -> void:
	_fail_next_action_publish = true


## #376 R4：仅跨局 start_next_hand 首 SNAP 失败注入（生产不可达）。
func fail_next_hand_start_snapshot_for_test() -> void:
	_fail_next_hand_start_snapshot = true
	fail_next_hand_start_snapshot_hit_count = 0


## #376 R4：MATCH 已发布后强制本事务失败（生产不可达）。
func fail_after_match_settled_for_test() -> void:
	_fail_after_match_settled_for_test = true
	fail_after_match_settled_hit_count = 0


func publish_snapshot() -> bool:
	if _rollback_failed:
		return false
	if _bc == null or _bc.state == null:
		return false
	if _fail_next_snapshot:
		_fail_next_snapshot = false
		return false
	# 候选 seq：构造/校验全部成功前不得 _alloc_seq / 写 journal
	var candidate: int = _server_seq + 1
	var prepared: Array = []
	for seat in range(4):
		var payload: Dictionary = _build_room_snapshot_payload(seat, candidate)
		if payload.is_empty():
			return false
		var vh: String = ProtocolViewCodec.compute_view_hash(payload)
		if vh.is_empty() or vh.length() != 64:
			return false
		var ne: NetworkedEvent = NetworkedEvent.make(
			"ROOM_SNAPSHOT", candidate, _room_id, payload, vh
		)
		if ne == null:
			return false
		var cloned: NetworkedEvent = NetworkedEvent.from_dict(ne.to_dict())
		if cloned == null:
			return false
		prepared.append(cloned)
	# 四席全部成功后单线程提交
	_server_seq = candidate
	for seat2 in range(4):
		(_journals[seat2] as Array).append(prepared[seat2])
	return true


func current_server_seq() -> int:
	return _server_seq


## E4-02（#244）：合法 PTT_END 权威序号 — 与牌局业务事件同一单调 _server_seq。
## 不写入 NetworkedEvent journal（语音控制帧走独立 WebSocket）；不创建第二套序号。
## 仅 TRASH_TALK；失败不推进序号。
func allocate_ptt_end_server_seq(seat: int, utterance_id: String) -> Dictionary:
	if _rollback_failed:
		return {"ok": false, "code": "COMMAND_REJECTED", "message": "rollback failed"}
	if mode_modules == null or not mode_modules.is_trash_talk():
		return {"ok": false, "code": "UNAUTHORIZED", "message": "voice only TRASH_TALK"}
	if seat < 0 or seat > 3:
		return {"ok": false, "code": "UNAUTHORIZED", "message": "invalid seat"}
	if utterance_id.is_empty():
		return {"ok": false, "code": "COMMAND_REJECTED", "message": "empty utterance"}
	var seq: int = _alloc_seq()
	return {
		"ok": true,
		"code": "",
		"message": "",
		"server_seq": seq,
		"room_id": _room_id,
		"seat": seat,
		"utterance_id": utterance_id,
	}


func event_journal(recipient_seat: int) -> Array:
	if recipient_seat < 0 or recipient_seat > 3:
		return []
	event_journal_call_count += 1
	return _clone_events(_journals[recipient_seat] as Array)


## #256：整场是否已权威 MATCH_SETTLED（O(1)，不克隆 journal）。
func has_match_settled() -> bool:
	return _match_settled_emitted


func events_since(recipient_seat: int, after_server_seq: int) -> Array:
	if recipient_seat < 0 or recipient_seat > 3:
		return []
	var out: Array = []
	for ne in _journals[recipient_seat] as Array:
		if ne is NetworkedEvent and int((ne as NetworkedEvent).server_seq) > after_server_seq:
			var cloned: NetworkedEvent = NetworkedEvent.from_dict(
				(ne as NetworkedEvent).to_dict()
			)
			if cloned != null:
				out.append(cloned)
	return out


## E2-04 真实生产事件发布边界。
## STANDARD 拒绝欢乐 kind 且 server_seq/journal 零变化；
## TRASH_TALK 仅在 NetworkedEvent schema 合法时写入四席 journal。
## 对外要求已 start；开局路径用 `_publish_business_event_core`（快照后、标记 started 前）。
func try_publish_business_event(kind: String, payload: Dictionary) -> bool:
	if _rollback_failed:
		return false
	if not _started:
		return false
	return _publish_business_event_core(kind, payload)


## 内部发布：不检查 _started（供 start 事务内 OPEN 等）。
## view_hash 对齐该席最后已提交 ROOM_SNAPSHOT（与 TURN_PROMPT 同语义），
## 使不改 core 的业务事件走 NBC same-hash 提交；模块投影由后续 SNAP 覆盖。
## 改 core/库存的领域批请用 _publish_domain_events_with_matching_snapshot。
func _publish_business_event_core(kind: String, payload: Dictionary) -> bool:
	if _rollback_failed:
		return false
	if kind.is_empty():
		return false
	if mode_modules != null and not mode_modules.accepts_event_kind(kind):
		return false
	# 候选 seq：校验全部成功前不得推进 _server_seq / 写 journal
	var candidate: int = _server_seq + 1
	var pl: Dictionary = payload.duplicate(true) if typeof(payload) == TYPE_DICTIONARY else {}
	var prepared: Array = []
	for seat in range(4):
		var vh: String = _last_committed_snapshot_view_hash(seat)
		if vh.is_empty() or vh.length() != 64:
			# 尚无 SNAP（极早路径）：回退 payload hash
			vh = ProtocolViewCodec.compute_view_hash(pl)
		if vh.is_empty() or vh.length() != 64:
			return false
		var ne: NetworkedEvent = NetworkedEvent.make(kind, candidate, _room_id, pl, vh)
		if ne == null:
			return false
		var cloned: NetworkedEvent = NetworkedEvent.from_dict(ne.to_dict())
		if cloned == null:
			return false
		prepared.append(cloned)
	_server_seq = candidate
	for seat2 in range(4):
		(_journals[seat2] as Array).append(prepared[seat2])
	return true


## bound_session_id：Worker 已验签 JOIN 后绑定的客户端 session_id。
## 公共房不得用等于 room_id 的 GameSessionConfig.session_id 冒充；空串时练习/直连退回 config。
func submit_action(action: Action, bound_session_id: String = "") -> CommandResult:
	if action == null:
		return _reject_result("", "INVALID_ACTION")
	if _rollback_failed:
		return _reject_result(action.command_id, ERROR_EVENT_PUBLISH_FAILED)
	# 公网/真人提交：source 固定 HUMAN；bound_session_id 进入上游安全指纹。
	return _process_action_core(
		action, true, ActionSource.HUMAN, bound_session_id
	)


## #253：练习 PBC AI / REPLAY 内部路径；须传入原始 source；公网不得调用伪造 HUMAN。
func process_internal_action(
	action: Action, source: StringName = ActionSource.AI
) -> ActionResolution:
	if action == null:
		return ActionResolution.rejected(ActionResolution.INVALID_ACTION)
	if not ActionSource.is_valid(source):
		return ActionResolution.rejected(ActionResolution.INVALID_ACTION)
	# 内部路径不得伪装 HUMAN（真人必须 submit_action）
	if source == ActionSource.HUMAN:
		return ActionResolution.rejected(ActionResolution.INVALID_ACTION)
	if _rollback_failed or not _started or _bc == null:
		return ActionResolution.rejected(ActionResolution.INVALID_ACTION)
	var cr: CommandResult = _process_action_core(action, false, source, "")
	if cr == null:
		return ActionResolution.rejected(ActionResolution.INVALID_ACTION)
	if cr.status == "ACCEPTED":
		return ActionResolution.success([])
	var code := StringName(cr.error_code)
	var mapped: ActionResolution = ActionResolution.rejected(code)
	if mapped == null:
		return ActionResolution.rejected(ActionResolution.RULE_REJECTED)
	return mapped


func _process_action_core(
	action: Action,
	require_human: bool,
	source: StringName,
	bound_session_id: String = ""
) -> CommandResult:
	if action == null:
		return _reject_result("", "INVALID_ACTION")
	if not ActionSource.is_valid(source):
		return _reject_result(action.command_id, "INVALID_ACTION")

	# 业务指纹：仅 Action v1 exact-schema + 可规范化 payload 后形成；失败 → 不缓存
	var fp: String = _business_fingerprint(action, bound_session_id)
	if fp.is_empty():
		return _reject_result(action.command_id, "INVALID_ACTION")

	var cmd: String = action.command_id
	var cached: Dictionary = _commands.lookup(cmd, fp)
	if str(cached.get("status", "")) == AuthorityCommandProcessor.STATUS_HIT:
		return _clone_cr(cached.get("result") as CommandResult)
	if str(cached.get("status", "")) == AuthorityCommandProcessor.STATUS_CONFLICT:
		# 异指纹：不覆盖 cache、不分配 seq、不改 journal/BC
		return _reject_result(cmd, ERROR_COMMAND_ID_CONFLICT)

	# 指纹形成后：未开局/越权/错房/模式拒绝等首次结果均缓存
	if not _started:
		var cr_ns := _reject_result(cmd, ERROR_NOT_STARTED)
		_cache_command(cmd, fp, cr_ns)
		return _clone_cr(cr_ns)
	if require_human and not _is_human(int(action.seat)):
		var cr_un := _reject_result(cmd, ERROR_UNAUTHORIZED)
		_cache_command(cmd, fp, cr_un)
		return _clone_cr(cr_un)

	# 房间校验
	if action.room_id != _room_id:
		var cr_room := _reject_result(cmd, "WRONG_ROOM")
		_cache_command(cmd, fp, cr_room)
		return _clone_cr(cr_room)

	if _bc == null or _bc.state == null:
		var cr_st := _reject_result(cmd, "INVALID_ACTION")
		_cache_command(cmd, fp, cr_st)
		return _clone_cr(cr_st)

	# E2-04：STANDARD 模式门控拒绝欢乐命令（MODE_FORBIDDEN，与 E5 NOT_ENABLED 可区分）
	if mode_modules != null and not mode_modules.accepts_command_kind(action.kind):
		var cr_mode := _reject_result(cmd, "MODE_FORBIDDEN")
		_cache_command(cmd, fp, cr_mode)
		return _clone_cr(cr_mode)

	# apply 前捕获 ARS + RewardWindow/库存；capture/hash 失败 → 非缓存 EVENT_PUBLISH_FAILED
	var snap: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(_bc)
	if snap == null:
		return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)
	var auth_h: String = snap.sha256()
	if auth_h.is_empty() or auth_h.length() != 64 or not snap.can_restore():
		return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)
	# #376：整事务冻结 match + BC 所有权（跨局失败可精确回滚）
	if not begin_match_transaction_freeze():
		return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)
	var frozen_seq: int = _server_seq
	var frozen_journals: Array = []
	for s in range(4):
		frozen_journals.append(_clone_events(_journals[s] as Array))
	var frozen_cache: Dictionary = _commands.capture()
	var frozen_rw: Dictionary = _reward_capture_state()
	var frozen_rw_clock: int = _reward_authority_now_ms
	var frozen_claim_seen: bool = _reward_claim_seen_open
	var frozen_hand_deferred: bool = _reward_hand_settled_deferred
	var frozen_hand_settled: bool = _hand_settled_emitted
	var frozen_settlement_tracker: Dictionary = _settlement_tracker.duplicate(true)
	var frozen_skill_proj: int = _skill_bc_proj_upto

	# #253：ITEM_USE 仅命令——不发 ACTION_APPLIED / 无 ITEM_USE 回声
	if action.kind == "ITEM_USE":
		return _submit_item_use(
			action, cmd, fp, snap, frozen_seq, frozen_journals, frozen_cache,
			frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
			frozen_hand_settled,
			frozen_settlement_tracker
		)

	# 捕获弃牌源（DISCARD/RIICHI）
	var discard_source := "HAND"
	var discarded_tile: Tile = null
	if action.kind == "DISCARD" or action.kind == "RIICHI":
		var iid: int = int(action.payload.get("tile_instance_id", -1))
		var seat_obj: Seat = _bc.state.seats[action.seat] as Seat
		if seat_obj != null:
			discarded_tile = seat_obj.hand.find_by_instance_id(iid)
			if discarded_tile != null \
					and int(seat_obj.last_drawn_instance_id) == iid:
				discard_source = "DRAWN"

	var res: ActionResolution = _apply_on_bc(action, source)
	if res == null or not res.accepted:
		var code := "INVALID_ACTION"
		if res != null:
			code = str(res.error_code)
		var cr_rej := _reject_result(cmd, code)
		# 非法动作不分配 server_seq，仍缓存幂等；#376 P1-3：必须释放 freeze
		_cache_command(cmd, fp, cr_rej)
		clear_match_transaction_freeze()
		return _clone_cr(cr_rej)

	# 接受：RW 预消费 → ACTION_APPLIED+ROOM_SNAPSHOT（含动作后投影）→ 待发 CLOSING
	# 失败则 restore BC 与服务端副作用（含 RW/#241 flags）
	var aa_seq: int = _emit_action_applied_then_snapshot(
		action, discarded_tile, discard_source
	)
	if aa_seq < 1:
		_rollback_transaction(
			snap, frozen_seq, frozen_journals, frozen_cache,
			frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
			frozen_hand_settled,
			frozen_settlement_tracker, frozen_skill_proj
		)
		return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)

	# HUMAN apply 起至 AI 链 / 最终 prompt|settlement 为同一事务
	if not _auto_advance_ai():
		_rollback_transaction(
			snap, frozen_seq, frozen_journals, frozen_cache,
			frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
			frozen_hand_settled,
			frozen_settlement_tracker, frozen_skill_proj
		)
		return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)

	# #379：Action/AI 技能必须在 barrier OPEN/ARM 与 HAND/ITEM 之前投影，
	# 否则 _item_after_opened 推进游标会吞掉 pending。
	if not _publish_pending_skill_triggered_from_bc():
		_rollback_transaction(
			snap, frozen_seq, frozen_journals, frozen_cache,
			frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
			frozen_hand_settled,
			frozen_settlement_tracker, frozen_skill_proj
		)
		return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)

	# 和牌/流局优先：BC 已 settled 时必须先 HAND 结果路径（RON/TSUMO → cancel），
	# 禁止先 _reward_try_release_barrier 误 FULL_GRANT（出口优先级 CANCELLED > DISPLAY > FULL）。
	if bool(_bc.get("_settled")):
		if not _emit_settled_if_needed():
			_rollback_transaction(
				snap, frozen_seq, frozen_journals, frozen_cache,
				frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
				frozen_hand_settled,
				frozen_settlement_tracker, frozen_skill_proj
			)
			return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)
	else:
		# 未终局：评分屏障（满 24 CLAIM 全过等）
		if not _reward_try_release_barrier():
			_rollback_transaction(
				snap, frozen_seq, frozen_journals, frozen_cache,
				frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
				frozen_hand_settled,
				frozen_settlement_tracker, frozen_skill_proj
			)
			return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)
		# 屏障释放后可能已 settle 窗口并 OPEN 下一窗；再处理摸打
		if bool(_bc.get("_settled")):
			if not _publish_pending_skill_triggered_from_bc():
				_rollback_transaction(
					snap, frozen_seq, frozen_journals, frozen_cache,
					frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
					frozen_hand_settled,
					frozen_settlement_tracker, frozen_skill_proj
				)
				return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)
			if not _emit_settled_if_needed():
				_rollback_transaction(
					snap, frozen_seq, frozen_journals, frozen_cache,
					frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
					frozen_hand_settled,
					frozen_settlement_tracker, frozen_skill_proj
				)
				return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)
		else:
			var human_draw_path := false
			if int(_bc.state.phase) == BattlePhase.Kind.DRAW:
				var cur_seat: int = int(_bc.state.current_seat)
				if _is_human(cur_seat) and _reward_allows_normal_progress():
					human_draw_path = true
					_ensure_drawn()
			# 摸打/AI 后续技能再冲一次
			if not _publish_pending_skill_triggered_from_bc():
				_rollback_transaction(
					snap, frozen_seq, frozen_journals, frozen_cache,
					frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
					frozen_hand_settled,
					frozen_settlement_tracker, frozen_skill_proj
				)
				return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)
			if bool(_bc.get("_settled")):
				if not _emit_settled_if_needed():
					_rollback_transaction(
						snap, frozen_seq, frozen_journals, frozen_cache,
						frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
						frozen_hand_settled,
						frozen_settlement_tracker, frozen_skill_proj
					)
					return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)
			else:
				if human_draw_path:
					if not publish_snapshot():
						_rollback_transaction(
							snap, frozen_seq, frozen_journals, frozen_cache,
							frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
							frozen_hand_settled,
							frozen_settlement_tracker, frozen_skill_proj
						)
						return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)
				# CLAIM 在 CLOSING 屏障期间仍须对真人可见；普通 TURN 受屏障阻止
				if not _emit_prompt_respecting_reward_barrier():
					_rollback_transaction(
						snap, frozen_seq, frozen_journals, frozen_cache,
						frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
						frozen_hand_settled,
						frozen_settlement_tracker, frozen_skill_proj
					)
					return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)

	# #253：领域事件后结算延迟消耗品触发（内部先冲技能）
	if not _finalize_item_triggers():
		_rollback_transaction(
			snap, frozen_seq, frozen_journals, frozen_cache,
			frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
			frozen_hand_settled,
			frozen_settlement_tracker, frozen_skill_proj
		)
		return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)

	var cr_ok := CommandResult.from_dict({
		"protocol_version": ProtocolConstants.PROTOCOL_VERSION,
		"command_id": cmd,
		"status": "ACCEPTED",
		"server_seq": _server_seq,
		"error_code": "",
	})
	_cache_command(cmd, fp, cr_ok)
	clear_match_transaction_freeze()
	return _clone_cr(cr_ok)


# ---- 内部 ----

## 只有权威 controller 完整恢复成功后，才回退服务端 seq/journal/cache/RewardWindow。
## mutation 前已用 can_restore 预检；若运行时仍失败则关闭提交入口，避免继续分叉。
## #241+#252：冻结覆盖 hand_settled_emitted / 奖励时钟 / claim_seen / deferred。
func _rollback_transaction(
	snap: AuthorityReplaySnapshot,
	frozen_seq: int,
	frozen_journals: Array,
	frozen_cache: Dictionary,
	frozen_rw: Dictionary = {},
	frozen_rw_clock: int = -1,
	frozen_claim_seen: bool = false,
	frozen_hand_deferred: Variant = null,
	frozen_hand_settled: Variant = null,
	frozen_settlement_tracker: Variant = null,
	frozen_skill_proj: Variant = null
) -> bool:
	# #376：先恢复 BC 所有权与 match owner，再 ARS 写入正确的旧 BC
	if not _restore_match_and_bc_ownership():
		_rollback_failed = true
		_started = false
		return false
	if snap == null or _bc == null or not snap.restore_into(_bc):
		_rollback_failed = true
		_started = false
		return false
	_server_seq = frozen_seq
	_journals = frozen_journals
	_commands.restore(frozen_cache)
	var restored_inv_reg := false
	if not frozen_rw.is_empty():
		if not _reward_restore_state(frozen_rw):
			_rollback_failed = true
			_started = false
			return false
		restored_inv_reg = frozen_rw.has("_inv_reg")
	# #253：有同进程 skill 冻结时已精确恢复；否则 ARS 后按 registry 重绑
	var inv_rb: ItemInventoryModule = _item_module()
	if inv_rb != null and _bc != null and not restored_inv_reg:
		inv_rb.rebind_registered_from_registry(_bc.registry)
	if frozen_rw_clock >= 0:
		_reward_authority_now_ms = frozen_rw_clock
	_reward_claim_seen_open = frozen_claim_seen
	if typeof(frozen_hand_deferred) == TYPE_BOOL:
		_reward_hand_settled_deferred = bool(frozen_hand_deferred)
	elif _tx_active:
		_reward_hand_settled_deferred = _tx_hand_deferred
	if typeof(frozen_hand_settled) == TYPE_BOOL:
		_hand_settled_emitted = bool(frozen_hand_settled)
	elif _tx_active:
		_hand_settled_emitted = _tx_hand_settled_emitted
	# #376 R4：外层 rollback 必须恢复 MATCH flag（与 local 路径一致）
	if _tx_active:
		_match_settled_emitted = _tx_match_settled_emitted
		_reward_claim_seen_open = _tx_claim_seen
		_reward_match_ended = _tx_reward_match_ended
	# #375：settlement tracker 与 ARS 同事务恢复，避免 commit 后回滚跳过重提
	if typeof(frozen_settlement_tracker) == TYPE_DICTIONARY:
		_settlement_tracker = (frozen_settlement_tracker as Dictionary).duplicate(true)
	# #379：投影游标与 ARS/journal 同事务回滚
	if typeof(frozen_skill_proj) == TYPE_INT:
		_skill_bc_proj_upto = maxi(int(frozen_skill_proj), 0)
	elif _tx_active:
		_skill_bc_proj_upto = maxi(_tx_skill_bc_proj_upto, 0)
	if _bc != null:
		_skill_bc_proj_upto = mini(_skill_bc_proj_upto, _bc.events.size())
	clear_match_transaction_freeze()
	return true

## 业务指纹（ADR 全文唯一）：session_id + room_id + seat + hand_seq + decision_id
## + kind + 规范化 payload 摘要（payload_sha256）。client_seq 不参与。
## bound_session_id：JOIN 绑定的客户端 session；空串时退回 config.session_id（练习/直连）。
## 公共 Worker 路径必须传入已验签 session，不得依赖 room_id 冒充。
func _business_fingerprint(action: Action, bound_session_id: String = "") -> String:
	# ARCH-02 #392：指纹算法事实源迁至 AuthorityCommandProcessor；此处仅补会话兜底。
	var fallback: String = str(_config.session_id) if _config != null else ""
	return AuthorityCommandProcessor.business_fingerprint(action, fallback, bound_session_id)


func _cache_command(cmd: String, fingerprint: String, cr: CommandResult) -> void:
	_commands.store(cmd, fingerprint, cr)


## #242：确定性核心事件摘要（固定 recipient seat；排除 view_hash 与 Reward/Item/Ability）。
## 材料：每项仅 server_seq + kind + payload；数组 canonical JSON → SHA-256。
const CORE_EVENT_DIGEST_KINDS := [
	"ROOM_SNAPSHOT", "TURN_PROMPT", "CLAIM_WINDOW",
	"ACTION_APPLIED", "HAND_SETTLED", "MATCH_SETTLED",
]


func core_event_digest(recipient_seat: int = 0) -> String:
	if recipient_seat < 0 or recipient_seat > 3:
		return ""
	var items: Array = []
	var journal: Array = event_journal(recipient_seat)
	for item in journal:
		if not (item is NetworkedEvent):
			continue
		var ne: NetworkedEvent = item as NetworkedEvent
		if not CORE_EVENT_DIGEST_KINDS.has(ne.kind):
			continue
		items.append({
			"server_seq": int(ne.server_seq),
			"kind": str(ne.kind),
			"payload": ne.payload.duplicate(true) if typeof(ne.payload) == TYPE_DICTIONARY else {},
		})
	var digest: String = ProtocolViewCodec.compute_view_hash(items)
	if digest.is_empty() or digest.length() != 64:
		return ""
	return digest


## #242：指纹可形成后的会话层拒绝缓存入口（越权/过期连接等由 RoomSession 调用）。
## 无法形成指纹时原样拒绝且不写 cache。
func reject_action_cached(
	action: Action,
	bound_session_id: String,
	code: String
) -> CommandResult:
	if action == null:
		return _reject_result("", code if not code.is_empty() else "INVALID_ACTION")
	var fp: String = _business_fingerprint(action, bound_session_id)
	if fp.is_empty():
		return _reject_result(action.command_id, code if not code.is_empty() else "INVALID_ACTION")
	var cmd: String = action.command_id
	var cached: Dictionary = _commands.lookup(cmd, fp)
	if str(cached.get("status", "")) == AuthorityCommandProcessor.STATUS_HIT:
		return _clone_cr(cached.get("result") as CommandResult)
	if str(cached.get("status", "")) == AuthorityCommandProcessor.STATUS_CONFLICT:
		return _reject_result(cmd, ERROR_COMMAND_ID_CONFLICT)
	var err: String = code if not code.is_empty() else "INVALID_ACTION"
	var cr := _reject_result(cmd, err)
	_cache_command(cmd, fp, cr)
	return _clone_cr(cr)


## 若合法 DRAW：走 IAuth typed server-draw progression（唯一 _step_draw）。
## true = 正常摸牌或荒牌 settle 等领域推进成功；false = 未推进。
func _ensure_drawn() -> bool:
	if _bc == null:
		return false
	return _bc.progress_server_draw()


func _alloc_seq() -> int:
	_server_seq += 1
	return _server_seq


func _append_event(seat: int, ne: NetworkedEvent) -> void:
	var cloned: NetworkedEvent = NetworkedEvent.from_dict(ne.to_dict())
	if cloned != null:
		(_journals[seat] as Array).append(cloned)


func _clone_events(src: Array) -> Array:
	return AuthorityEventPublisher.clone_events(src)


func _clone_cr(cr: CommandResult) -> CommandResult:
	if cr == null:
		return null
	return CommandResult.from_dict(cr.to_dict())


func _reject_result(cmd: String, code: String) -> CommandResult:
	var use_cmd: String = cmd
	if use_cmd.is_empty() or not ProtocolUuid.is_canonical_v4(use_cmd):
		use_cmd = "550e8400-e29b-41d4-a716-000000000099"
	var err: String = code if not code.is_empty() else "INVALID_ACTION"
	return CommandResult.from_dict({
		"protocol_version": ProtocolConstants.PROTOCOL_VERSION,
		"command_id": use_cmd,
		"status": "REJECTED",
		"server_seq": _server_seq,
		"error_code": err,
	})


func _build_room_snapshot_payload(seat: int, seq: int) -> Dictionary:
	# #241：经 registry 组合 modules；组合器不改写模块业务 payload
	# #252/#253：TRASH_TALK 传入 RewardWindow + ItemInventory（按席裁剪）
	# ARCH-02 #392：ctx 组装留在 façade；组合/校验委托 AuthoritySnapshotService。
	if snapshot_registry == null or _bc == null:
		return {}
	var ctx: Dictionary = {"state": _bc.state}
	# #374：权威 roster 进入独立 matching_meta 模块（不改 core_table）。
	if _config != null:
		var chars_ctx: Array = []
		for c in _config.character_ids:
			chars_ctx.append(String(c))
		var parts_ctx: Array = []
		for p in _participants:
			parts_ctx.append(String(p))
		ctx["character_ids"] = chars_ctx
		ctx["participants"] = parts_ctx
		ctx["config"] = _config
	# #376 R5：Headless（match_owner）必须有合法 match_authority；失败整 SNAP 失败。
	# Practice/无 owner：optional fallback（BC 派生）。
	ctx["match_authority"] = _match_authority_payload()
	ctx["has_match_owner"] = match_owner != null
	var rw: RewardWindowModule = _reward_module()
	if rw != null:
		ctx["reward_window"] = rw
	var inv: ItemInventoryModule = _item_module()
	if inv != null:
		ctx["item_inventory"] = inv
	return _snapshots.build_room_snapshot_payload(ctx, seat, seq)


## #376 R5 测试：下一帧 match_authority 强制失败（生产不可达）。
func fail_match_authority_payload_for_test() -> void:
	_fail_match_authority_payload = true
	fail_match_authority_payload_hit_count = 0


## #376 R5：有 match_owner 时只接受 owner 导出（校验后）；无效绝不 fallback BC。
## 无 owner（Practice/遗留）时由 BC 派生单局等价字段。
func _match_authority_payload() -> Dictionary:
	if _fail_match_authority_payload:
		_fail_match_authority_payload = false
		fail_match_authority_payload_hit_count += 1
		return {}
	var checker := MatchAuthoritySnapshotProvider.new()
	if match_owner != null:
		if not match_owner.has_method("export_match_state"):
			return {}
		var exp: Variant = match_owner.call("export_match_state")
		if typeof(exp) != TYPE_DICTIONARY:
			return {}
		var from_owner: Dictionary = MatchAuthoritySnapshotProvider.from_export(exp as Dictionary)
		if from_owner.is_empty() or not checker.can_restore(from_owner, 0):
			return {}
		return from_owner
	# Practice / 无整场驱动：optional BC 派生
	if _bc == null or _bc.state == null:
		return {}
	var st: BattleState = _bc.state
	var scores: Array = []
	for i in range(4):
		if i < st.scores.size():
			scores.append(int(st.scores[i]))
		else:
			scores.append(0)
	var total_h: int = 4
	var hpr: int = 4
	if _config != null and _config.round_kind == GameSessionConfig.ROUND_HANCHAN:
		total_h = 8
	var finished_bc: bool = bool(_match_settled_emitted)
	var hi_bc: int = maxi(0, int(st.hand_number) - 1)
	if finished_bc:
		hi_bc = total_h
	var hs_bc: int = int(st.hand_seq)
	var derived := {
		"hand_index": hi_bc,
		"hand_seq": hs_bc,
		"next_hand_seq": hs_bc + 1,
		"dealer_seat": int(st.dealer_seat),
		"honba": int(st.honba),
		"riichi_sticks": int(st.riichi_sticks),
		"cumulative_scores": scores,
		"round_wind": int(st.round_wind),
		"finished": finished_bc,
		"total_hands": total_h,
		"hands_per_round": hpr,
	}
	if not checker.can_restore(derived, 0):
		return {}
	return derived


## #376：事务边界 — 冻结 match + BC 所有权 + 预 mutation ARS + journal/seq。
## 已有活跃事务：复用外层（返回 true，不覆盖）。
## BC 存在时必须预拍可 restore 的 ARS；否则零 mutation 返回 false。
func begin_match_transaction_freeze() -> bool:
	if _tx_active:
		return true
	var ars: AuthorityReplaySnapshot = null
	if _bc != null:
		ars = AuthorityReplaySnapshot.capture(_bc)
		if ars == null or not ars.can_restore():
			return false
		var ah: String = ars.sha256()
		if ah.is_empty() or ah.length() != 64:
			return false
	_tx_match_freeze = {}
	if match_owner != null and match_owner.has_method("capture_match_authority_state"):
		var cap: Variant = match_owner.call("capture_match_authority_state")
		if typeof(cap) == TYPE_DICTIONARY:
			_tx_match_freeze = (cap as Dictionary).duplicate(true)
	_tx_bc_strong = _bc
	_tx_bc_owned = _bc_owned
	_tx_bc_injected = _bc_injected
	_tx_bc_ars = ars
	_tx_ai_control = _ai_control_seats.duplicate(true)
	_tx_hand_start_scores = _hand_start_scores.duplicate()
	_tx_hand_start_honba = _hand_start_honba
	_tx_hand_start_riichi = _hand_start_riichi_sticks
	_tx_reward_match_ended = _reward_match_ended
	_tx_server_seq = _server_seq
	_tx_journals = []
	for s in range(4):
		_tx_journals.append(_clone_events(_journals[s] as Array))
	_tx_settlement_tracker = _settlement_tracker.duplicate(true)
	_tx_hand_settled_emitted = _hand_settled_emitted
	_tx_match_settled_emitted = _match_settled_emitted
	_tx_rw_state = _reward_capture_state()
	_tx_rw_clock = _reward_authority_now_ms
	_tx_claim_seen = _reward_claim_seen_open
	_tx_hand_deferred = _reward_hand_settled_deferred
	_tx_skill_bc_proj_upto = _skill_bc_proj_upto
	_tx_active = true
	return true


func clear_match_transaction_freeze() -> void:
	_tx_match_freeze = {}
	_tx_bc_strong = null
	_tx_bc_owned = null
	_tx_bc_injected = null
	_tx_bc_ars = null
	_tx_ai_control = {}
	_tx_hand_start_scores = []
	_tx_hand_start_honba = 0
	_tx_hand_start_riichi = 0
	_tx_reward_match_ended = null
	_tx_server_seq = -1
	_tx_journals = []
	_tx_settlement_tracker = {}
	_tx_hand_settled_emitted = false
	_tx_match_settled_emitted = false
	_tx_rw_state = {}
	_tx_rw_clock = -1
	_tx_skill_bc_proj_upto = 0
	_tx_claim_seen = false
	_tx_hand_deferred = false
	_tx_active = false


func has_match_transaction_freeze() -> bool:
	return _tx_active


## #376：在 ARS 回滚后恢复 match owner 与 BC 所有权。
func _restore_match_and_bc_ownership() -> bool:
	if _tx_bc_strong != null:
		_bc_owned = _tx_bc_owned
		_bc_injected = _tx_bc_injected
		# 若 freeze 时是 inject，确保 weak 仍指向 strong
		if _bc_injected == null and _bc_owned == null and _tx_bc_strong != null:
			_bc_owned = _tx_bc_strong
	if not _tx_ai_control.is_empty() or _ai_control_seats.size() > 0:
		_ai_control_seats = _tx_ai_control.duplicate(true)
	_hand_start_scores = _tx_hand_start_scores.duplicate()
	_hand_start_honba = _tx_hand_start_honba
	_hand_start_riichi_sticks = _tx_hand_start_riichi
	_reward_match_ended = _tx_reward_match_ended
	if _tx_match_freeze.is_empty():
		return true
	if match_owner != null and match_owner.has_method("restore_match_authority_state"):
		return bool(match_owner.call("restore_match_authority_state", _tx_match_freeze))
	return true


## #241：临时 AI 接管/归还。仅影响有效控制，不改 participants 配置。
func set_seat_ai_control(seat: int, enabled: bool) -> void:
	if seat < 0 or seat > 3:
		return
	if enabled:
		_ai_control_seats[seat] = true
	else:
		_ai_control_seats.erase(seat)


func is_seat_ai_controlled(seat: int) -> bool:
	return bool(_ai_control_seats.get(seat, false))


## 配置为 HUMAN 且当前未被 AI 接管。
func is_effectively_human(seat: int) -> bool:
	return _is_human(seat)


## #241：重连 resync——发布当前 ROOM_SNAPSHOT；仅当存在有效真人决策窗时再发 prompt。
## 无真人窗时只发快照仍成功（避免 AI 席 TURN 使 _emit_private_prompt 假失败）。
## 需要 prompt 时与快照原子：失败则 ARS/seq/journal 回滚。
func publish_resync_snapshot_and_prompt() -> Dictionary:
	if _rollback_failed or not _started or _bc == null or _bc.state == null:
		return {"ok": false, "advanced": false, "code": ERROR_EVENT_PUBLISH_FAILED}
	var snap: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(_bc)
	if snap == null or not snap.can_restore():
		return {"ok": false, "advanced": false, "code": ERROR_EVENT_PUBLISH_FAILED}
	var auth_h: String = snap.sha256()
	if auth_h.is_empty() or auth_h.length() != 64:
		return {"ok": false, "advanced": false, "code": ERROR_EVENT_PUBLISH_FAILED}
	var frozen_seq: int = _server_seq
	var frozen_journals: Array = []
	for s in range(4):
		frozen_journals.append(_clone_events(_journals[s] as Array))
	var frozen_cache: Dictionary = _commands.capture()
	var frozen_rw: Dictionary = _reward_capture_state()
	var frozen_rw_clock: int = _reward_authority_now_ms
	var frozen_claim_seen: bool = _reward_claim_seen_open
	var frozen_hand_deferred: bool = _reward_hand_settled_deferred
	var frozen_hand_settled: bool = _hand_settled_emitted
	var frozen_settlement_tracker: Dictionary = _settlement_tracker.duplicate(true)
	if bool(_bc.get("_settled")):
		# 重连：始终先发新鲜 ROOM_SNAPSHOT（首条业务事件）
		if not publish_snapshot():
			return {"ok": false, "advanced": false, "code": ERROR_EVENT_PUBLISH_FAILED}
		# 幂等：若本局尚未 HAND_SETTLED 则补发一次；已发则零副作用
		if not _emit_settled_if_needed():
			_rollback_transaction(
				snap, frozen_seq, frozen_journals, frozen_cache,
				frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
				frozen_hand_settled,
			frozen_settlement_tracker
			)
			return {"ok": false, "advanced": false, "code": ERROR_EVENT_PUBLISH_FAILED}
		return {"ok": true, "advanced": true, "code": ""}
	if not publish_snapshot():
		return {"ok": false, "advanced": false, "code": ERROR_EVENT_PUBLISH_FAILED}
	# 打开窗以判定是否需要真人 prompt
	for s2 in range(4):
		_bc.decision_context_for_seat(s2)
	if not _needs_human_private_prompt():
		return {"ok": true, "advanced": true, "code": ""}
	if not _emit_private_prompt():
		_rollback_transaction(
			snap, frozen_seq, frozen_journals, frozen_cache,
			frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
			frozen_hand_settled,
			frozen_settlement_tracker
		)
		return {"ok": false, "advanced": false, "code": ERROR_EVENT_PUBLISH_FAILED}
	return {"ok": true, "advanced": true, "code": ""}


func _needs_human_private_prompt() -> bool:
	if _bc == null or bool(_bc.get("_settled")):
		return false
	var win = _bc.get("_active_window")
	if win == null or not (win is DecisionWindow):
		return false
	var dw: DecisionWindow = win as DecisionWindow
	if dw.kind == DecisionWindow.KIND_TURN:
		return _is_human(int(dw.subject_seat))
	if dw.kind == DecisionWindow.KIND_CLAIM or dw.kind == DecisionWindow.KIND_ROB_KAN:
		for s in dw.seats():
			var si: int = int(s)
			if _is_human(si) and not dw.has_responded(si):
				return true
	return false


## #241：AI 接管单步——至多一个权威 Action（含其 AA+SNAP 原子发布），然后返回。
## 与 submit_action 同级 ARS 事务；失败全量回滚。无动作时不重复发 snapshot/prompt。
## 返回 {ok, advanced, waiting_human, settled, code}。
func step_ai_once() -> Dictionary:
	if _rollback_failed or not _started or _bc == null or _bc.state == null:
		return {
			"ok": false, "advanced": false, "waiting_human": false,
			"settled": false, "code": ERROR_EVENT_PUBLISH_FAILED,
		}
	if bool(_bc.get("_settled")):
		return {
			"ok": true, "advanced": false, "waiting_human": false,
			"settled": true, "code": "",
		}

	var snap: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(_bc)
	if snap == null or not snap.can_restore():
		return {
			"ok": false, "advanced": false, "waiting_human": false,
			"settled": false, "code": ERROR_EVENT_PUBLISH_FAILED,
		}
	var auth_h: String = snap.sha256()
	if auth_h.is_empty() or auth_h.length() != 64:
		return {
			"ok": false, "advanced": false, "waiting_human": false,
			"settled": false, "code": ERROR_EVENT_PUBLISH_FAILED,
		}
	var frozen_seq: int = _server_seq
	var frozen_journals: Array = []
	for s in range(4):
		frozen_journals.append(_clone_events(_journals[s] as Array))
	var frozen_cache: Dictionary = _commands.capture()
	var frozen_rw: Dictionary = _reward_capture_state()
	var frozen_rw_clock: int = _reward_authority_now_ms
	var frozen_claim_seen: bool = _reward_claim_seen_open
	var frozen_hand_deferred: bool = _reward_hand_settled_deferred
	var frozen_hand_settled: bool = _hand_settled_emitted
	var frozen_settlement_tracker: Dictionary = _settlement_tracker.duplicate(true)

	# CLOSING 屏障：先刷新窗；普通 DRAW/TURN 不得越过；CLAIM/ROB 可推进
	for s0 in range(4):
		_bc.decision_context_for_seat(s0)
	_reward_note_claim_visibility()

	# 仅 AI 席 DRAW 可在本步摸牌；真人 DRAW 等待；CLOSING 屏障禁止普通摸牌
	if int(_bc.state.phase) == BattlePhase.Kind.DRAW:
		var cur: int = int(_bc.state.current_seat)
		if _is_human(cur):
			return {
				"ok": true, "advanced": false, "waiting_human": true,
				"settled": false, "code": "",
			}
		if not _reward_allows_normal_progress():
			return {
				"ok": true, "advanced": false, "waiting_human": false,
				"settled": false, "code": "",
			}
		if not _ensure_drawn():
			return {
				"ok": true, "advanced": false, "waiting_human": false,
				"settled": bool(_bc.get("_settled")), "code": "",
			}
		if bool(_bc.get("_settled")):
			if not _emit_settled_if_needed():
				_rollback_transaction(
					snap, frozen_seq, frozen_journals, frozen_cache,
					frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
					frozen_hand_settled,
			frozen_settlement_tracker
				)
				return {
					"ok": false, "advanced": false, "waiting_human": false,
					"settled": false, "code": ERROR_EVENT_PUBLISH_FAILED,
				}
			return {
				"ok": true, "advanced": true, "waiting_human": false,
				"settled": true, "code": "",
			}
		# AI 摸牌后只发 ROOM_SNAPSHOT；TURN_PROMPT 仅真人（_emit_private_prompt 对 AI 席返回 false）
		# 下一 poll 再选 Action。与 _auto_advance_ai 循环语义一致。
		if not publish_snapshot():
			_rollback_transaction(
				snap, frozen_seq, frozen_journals, frozen_cache,
				frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
				frozen_hand_settled,
			frozen_settlement_tracker
			)
			return {
				"ok": false, "advanced": false, "waiting_human": false,
				"settled": false, "code": ERROR_EVENT_PUBLISH_FAILED,
			}
		return {
			"ok": true, "advanced": true, "waiting_human": false,
			"settled": false, "code": "",
		}

	for s in range(4):
		_bc.decision_context_for_seat(s)
	var win = _bc.get("_active_window")
	if win == null or not (win is DecisionWindow):
		if int(_bc.state.phase) == BattlePhase.Kind.SETTLE:
			_bc.set("_settled", true)
			if not _emit_settled_if_needed():
				_rollback_transaction(
					snap, frozen_seq, frozen_journals, frozen_cache,
					frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
					frozen_hand_settled,
			frozen_settlement_tracker
				)
				return {
					"ok": false, "advanced": false, "waiting_human": false,
					"settled": false, "code": ERROR_EVENT_PUBLISH_FAILED,
				}
			return {
				"ok": true, "advanced": true, "waiting_human": false,
				"settled": true, "code": "",
			}
		return {
			"ok": true, "advanced": false, "waiting_human": false,
			"settled": false, "code": "",
		}

	var dw: DecisionWindow = win as DecisionWindow
	if dw.kind == DecisionWindow.KIND_TURN:
		# CLOSING 屏障：禁止普通 TURN 越过
		if not _reward_allows_normal_progress():
			return {
				"ok": true, "advanced": false, "waiting_human": false,
				"settled": false, "code": "",
			}
		var actor: int = int(dw.subject_seat)
		if _is_human(actor):
			return {
				"ok": true, "advanced": false, "waiting_human": true,
				"settled": false, "code": "",
			}
		var act: Action = _build_ai_turn_action(actor)
		if act == null:
			return {
				"ok": true, "advanced": false, "waiting_human": false,
				"settled": false, "code": "",
			}
		var disc_tile: Tile = null
		var dsrc := "HAND"
		if act.kind == "DISCARD" or act.kind == "RIICHI":
			var iid: int = int(act.payload.get("tile_instance_id", -1))
			var so: Seat = _bc.state.seats[actor] as Seat
			if so != null:
				disc_tile = so.hand.find_by_instance_id(iid)
				if disc_tile != null and int(so.last_drawn_instance_id) == iid:
					dsrc = "DRAWN"
		var res: ActionResolution = _apply_on_bc(act, ActionSource.AI)
		if res == null or not res.accepted:
			# 领域拒绝：不推进；回滚任何意外
			_rollback_transaction(
				snap, frozen_seq, frozen_journals, frozen_cache,
				frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
				frozen_hand_settled,
			frozen_settlement_tracker
			)
			return {
				"ok": true, "advanced": false, "waiting_human": false,
				"settled": false, "code": "",
			}
		# 含 RW 预消费：DISCARD 计入 24、SNAP 投影同步
		if _emit_action_applied(act, disc_tile, dsrc) < 1:
			_rollback_transaction(
				snap, frozen_seq, frozen_journals, frozen_cache,
				frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
				frozen_hand_settled,
			frozen_settlement_tracker
			)
			return {
				"ok": false, "advanced": false, "waiting_human": false,
				"settled": false, "code": ERROR_EVENT_PUBLISH_FAILED,
			}
		# 终局 Action：同一 ARS 事务内必须完成 HAND_SETTLED
		if bool(_bc.get("_settled")):
			if not _emit_settled_if_needed():
				_rollback_transaction(
					snap, frozen_seq, frozen_journals, frozen_cache,
					frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
					frozen_hand_settled,
			frozen_settlement_tracker
				)
				return {
					"ok": false, "advanced": false, "waiting_human": false,
					"settled": false, "code": ERROR_EVENT_PUBLISH_FAILED,
				}
		return {
			"ok": true, "advanced": true, "waiting_human": false,
			"settled": bool(_bc.get("_settled")), "code": "",
		}

	if dw.kind == DecisionWindow.KIND_CLAIM or dw.kind == DecisionWindow.KIND_ROB_KAN:
		for s2 in dw.seats():
			var si: int = int(s2)
			if _is_human(si) and not dw.has_responded(si):
				return {
					"ok": true, "advanced": false, "waiting_human": true,
					"settled": false, "code": "",
				}
		for s3 in dw.seats():
			var si3: int = int(s3)
			if dw.has_responded(si3):
				continue
			var pass_act: Action = _build_ai_claim_action(si3)
			if pass_act == null:
				continue
			var r2: ActionResolution = _apply_on_bc(pass_act, ActionSource.AI)
			if r2 == null or not r2.accepted:
				continue
			if _emit_action_applied(pass_act, null, "HAND") < 1:
				_rollback_transaction(
					snap, frozen_seq, frozen_journals, frozen_cache,
					frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
					frozen_hand_settled,
			frozen_settlement_tracker
				)
				return {
					"ok": false, "advanced": false, "waiting_human": false,
					"settled": false, "code": ERROR_EVENT_PUBLISH_FAILED,
				}
			if bool(_bc.get("_settled")):
				if not _emit_settled_if_needed():
					_rollback_transaction(
						snap, frozen_seq, frozen_journals, frozen_cache,
						frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
						frozen_hand_settled,
			frozen_settlement_tracker
					)
					return {
						"ok": false, "advanced": false, "waiting_human": false,
						"settled": false, "code": ERROR_EVENT_PUBLISH_FAILED,
					}
			return {
				"ok": true, "advanced": true, "waiting_human": false,
				"settled": bool(_bc.get("_settled")), "code": "",
			}
		return {
			"ok": true, "advanced": false, "waiting_human": false,
			"settled": false, "code": "",
		}

	return {
		"ok": true, "advanced": false, "waiting_human": false,
		"settled": false, "code": "",
	}


## 权威状态 sha256（测试/失败注入对照）；不可用时空串。
func authority_hash_for_test() -> String:
	if _bc == null:
		return ""
	var snap: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(_bc)
	if snap == null:
		return ""
	return snap.sha256()


func _public_view_hash_for_seq(seat: int, snap_seq: int) -> String:
	var payload: Dictionary = _build_room_snapshot_payload(seat, snap_seq)
	return ProtocolViewCodec.compute_view_hash(payload)


## 从 recipient 席 journal 倒序取最后一条已提交 ROOM_SNAPSHOT 的 view_hash。
## seat 非法 / 未找到 / hash 非法 → 空串。禁止按新 seq 重建 snapshot payload。
func _last_committed_snapshot_view_hash(recipient_seat: int) -> String:
	if recipient_seat < 0 or recipient_seat > 3:
		return ""
	return AuthoritySnapshotService.last_committed_snapshot_view_hash(
		_journals[recipient_seat] as Array)


## 可 override 的逐席事件构建 seam：make → null 即 null；再 from_dict 严格 roundtrip clone。
## recipient 仅供测试/子类逐席失败注入；正常实现不使用。
func _build_recipient_event(
	kind: String, _recipient_seat: int, seq: int, payload: Dictionary, view_hash: String
) -> NetworkedEvent:
	return _publisher.build_recipient_event(kind, seq, _room_id, payload, view_hash)


## ACTION_APPLIED 与紧随的 ROOM_SNAPSHOT 共用 post-apply public view_hash。
## #252 Round 9：先按 candidate aa_seq 预消费 RewardWindow（mutate + 收集待发 effect），
## 再构造含动作后 RW 投影的 AA+SNAP，最后发布 CLOSING 等 effect。
## 逻辑：aa_seq = N，snap_seq = N+1；hash = hash(ROOM_SNAPSHOT payload @ N+1)。
## 任一步失败返回 -1；调用方回滚 BC/RW/seq/journals/flags。不抢占 server_seq 至提交瞬间。
func _emit_action_applied_then_snapshot(
	action: Action, discarded_tile: Tile, discard_source: String
) -> int:
	if _fail_next_action_publish:
		_fail_next_action_publish = false
		return -1
	var aa_seq: int = _server_seq + 1
	var snap_seq: int = aa_seq + 1
	var resolved: Dictionary = _build_resolved_payload(action, discarded_tile, discard_source)
	var aa_payload := {
		"causation_command_id": action.command_id,
		"hand_seq": int(action.hand_seq),
		"decision_id": action.decision_id,
		"seat": int(action.seat),
		"action_kind": action.kind,
		"resolved_payload": resolved,
	}
	# 阶段 0：RW 预消费（不写 journal、不分配 seq）；收集待发业务 effect
	var pending_effects: Array = []
	if not _reward_preconsume_for_action(action, aa_seq, aa_payload, pending_effects):
		return -1
	# 阶段 1：四席逐席构造非空 snapshot / 64 位 hash / AA clone / SNAP clone
	var prepared: Array = []
	for seat in range(4):
		var sp: Dictionary = _build_room_snapshot_payload(seat, snap_seq)
		if sp.is_empty():
			return -1
		var vh: String = ProtocolViewCodec.compute_view_hash(sp)
		if vh.is_empty() or vh.length() != 64:
			return -1
		var aa_ev: NetworkedEvent = _build_recipient_event(
			"ACTION_APPLIED", seat, aa_seq, aa_payload, vh
		)
		if aa_ev == null:
			return -1
		var snap_ev: NetworkedEvent = _build_recipient_event(
			"ROOM_SNAPSHOT", seat, snap_seq, sp, vh
		)
		if snap_ev == null:
			return -1
		prepared.append({"aa": aa_ev, "snap": snap_ev})
	# 阶段 2：提交 journal（唯一抢占 seq 点）
	_server_seq = snap_seq
	for seat2 in range(4):
		var pair: Dictionary = prepared[seat2] as Dictionary
		(_journals[seat2] as Array).append(pair["aa"])
		(_journals[seat2] as Array).append(pair["snap"])
	# 阶段 3：发布预消费收集的 CLOSING 等（在 AA+SNAP 之后；失败由调用方整事务回滚）
	for eff in pending_effects:
		if typeof(eff) != TYPE_DICTIONARY:
			return -1
		var ek: String = str((eff as Dictionary).get("kind", ""))
		var ep: Variant = (eff as Dictionary).get("payload", {})
		if ek.is_empty() or typeof(ep) != TYPE_DICTIONARY:
			return -1
		if not try_publish_business_event(ek, ep as Dictionary):
			return -1
	return aa_seq


func _emit_action_applied(action: Action, discarded_tile: Tile, discard_source: String) -> int:
	# AI / step_ai 路径：与 submit 同原子 RW 预消费 + AA+SNAP + 待发 effect
	return _emit_action_applied_then_snapshot(action, discarded_tile, discard_source)


func _build_resolved_payload(action: Action, discarded_tile: Tile, discard_source: String) -> Dictionary:
	match action.kind:
		"DISCARD", "RIICHI":
			var tile_v: Variant = null
			if discarded_tile != null:
				tile_v = ProtocolViewCodec.tile_view_from_tile(discarded_tile)
			if tile_v == null:
				# 兜底：从河取最后一张
				var river: Array = _bc.state.seats[action.seat].river.tiles()
				if not river.is_empty():
					tile_v = ProtocolViewCodec.tile_view_from_tile(river[river.size() - 1])
			if tile_v == null:
				return {}
			return {
				"tile": (tile_v as Dictionary).duplicate(true),
				"discard_source": discard_source if discard_source in ["DRAWN", "HAND"] else "HAND",
			}
		"PASS":
			return {}
		"TSUMO":
			var seat: Seat = _bc.state.seats[action.seat] as Seat
			var wt: Tile = null
			if seat != null:
				wt = seat.hand.find_by_instance_id(seat.last_drawn_instance_id)
			if wt == null:
				return {}
			var tv: Variant = ProtocolViewCodec.tile_view_from_tile(wt)
			if tv == null:
				return {}
			return {"winning_tile": (tv as Dictionary).duplicate(true)}
		"RON":
			var last: Tile = _bc.get("_last_discarded_tile") as Tile
			var from_s: int = int(_bc.get("_last_discarder_seat"))
			if last == null:
				return {}
			var rtv: Variant = ProtocolViewCodec.tile_view_from_tile(last)
			if rtv == null:
				return {}
			return {
				"winning_tile": (rtv as Dictionary).duplicate(true),
				"from_seat": from_s,
			}
		"CHI", "PON", "KAN":
			var actor_seat: Seat = _bc.state.seats[action.seat] as Seat
			if actor_seat == null:
				return {}
			# ADDED_KAN 的首条 ACTION_APPLIED 是加杠声明；抢杠窗结束前领域仍为 PON。
			# 从权威 PON + 手中第四张构造只读候选 MeldView，不能提前 promote。
			if action.kind == "KAN" \
					and str(action.payload.get("kan_kind", "")) == "ADDED_KAN":
				var meld_id: int = int(action.payload.get("meld_id", -1))
				var added_iid: int = int(action.payload.get("added_tile_instance_id", -1))
				var target: Meld = null
				for existing in actor_seat.melds.all():
					if existing is Meld and int((existing as Meld).meld_id) == meld_id:
						target = existing as Meld
						break
				var added_tile: Tile = actor_seat.hand.find_by_instance_id(added_iid)
				if target == null or target.kind != Meld.Kind.PON or added_tile == null:
					return {}
				var candidate_tiles: Array = []
				for existing_tile in target.tiles:
					var existing_view: Variant = ProtocolViewCodec.tile_view_from_tile(existing_tile)
					if existing_view == null:
						return {}
					candidate_tiles.append(existing_view)
				var added_view: Variant = ProtocolViewCodec.tile_view_from_tile(added_tile)
				if added_view == null:
					return {}
				candidate_tiles.append(added_view)
				var candidate: Variant = ProtocolViewCodec.meld_view_from_dict({
					"meld_id": target.meld_id,
					"kind": "ADDED_KAN",
					"from_seat": target.from_seat,
					"called_tile_instance_id": target.called_tile_instance_id,
					"added_tile_instance_id": added_iid,
					"tiles": candidate_tiles,
				})
				if candidate == null:
					return {}
				return {"meld": (candidate as Dictionary).duplicate(true)}
			# 其它鸣牌已在领域提交，取 actor 最新副露。
			if actor_seat.melds.is_empty():
				return {}
			var meld: Meld = actor_seat.melds.last()
			var mv: Variant = ProtocolViewCodec.meld_view_from_meld(meld)
			if mv == null:
				return {}
			return {"meld": (mv as Dictionary).duplicate(true)}
		"DECLARE_ABORTIVE_DRAW":
			return {"reason": "KYUUSYU_KYUUHAI"}
		_:
			return {}


func _emit_private_prompt() -> bool:
	if _bc == null or _bc.state == null:
		return false
	if bool(_bc.get("_settled")):
		return false
	# 不在此处摸牌：DRAW→摸牌→ROOM_SNAPSHOT 由 start/submit 最终路径负责，
	# 保证 TURN_PROMPT.view_hash 对齐含 last_drawn 的 snapshot。
	# typed API：直接打开决策窗（禁止 has_method 兼容 fallback）
	for s in range(4):
		_bc.decision_context_for_seat(s)

	var win = _bc.get("_active_window")
	if win == null or not (win is DecisionWindow):
		return false
	var dw: DecisionWindow = win as DecisionWindow

	if dw.kind == DecisionWindow.KIND_TURN:
		var seat: int = int(dw.subject_seat)
		if not _is_human(seat):
			return false
		var ctx: DecisionContext = dw.context_for_seat(seat)
		if ctx == null:
			return false
		var payload := _build_turn_prompt_payload(ctx, seat)
		if payload.is_empty():
			return false
		# 复用该席最后 committed ROOM_SNAPSHOT.view_hash；禁止按新 seq 重建
		var vh: String = _last_committed_snapshot_view_hash(seat)
		if vh.is_empty():
			return false
		var candidate: int = _server_seq + 1
		var ne: NetworkedEvent = NetworkedEvent.make(
			"TURN_PROMPT", candidate, _room_id, payload, vh
		)
		if ne == null:
			return false
		var cloned: NetworkedEvent = NetworkedEvent.from_dict(ne.to_dict())
		if cloned == null:
			return false
		# #240：同一 candidate 上非目标席发 ROOM_SNAPSHOT filler，保证每席可见流连续
		var prepared: Array = [{"seat": seat, "clone": cloned}]
		for other in range(4):
			if other == seat:
				continue
			var fill: NetworkedEvent = _prepare_snapshot_filler(other, candidate)
			if fill == null:
				return false
			prepared.append({"seat": other, "clone": fill})
		_server_seq = candidate
		for item in prepared:
			(_journals[int(item["seat"])] as Array).append(item["clone"])
		return true

	if dw.kind == DecisionWindow.KIND_CLAIM or dw.kind == DecisionWindow.KIND_ROB_KAN:
		# 同一逻辑 seq，多 recipient variant（仅 human 未响应席）+ 非目标 filler
		var targets: Array = []
		for s in dw.seats():
			var si: int = int(s)
			if not _is_human(si):
				continue
			if dw.has_responded(si):
				continue
			targets.append(si)
		if targets.is_empty():
			return false
		# 候选 seq：全部 seat 构造/roundtrip 成功前不得推进 _server_seq / 写 journal
		var candidate: int = _server_seq + 1
		var prepared: Array = []
		var covered: Dictionary = {}
		for si2 in targets:
			var seat_i: int = int(si2)
			var ctx2: DecisionContext = dw.context_for_seat(seat_i)
			if ctx2 == null:
				return false
			var pay2 := _build_claim_window_payload(ctx2, dw)
			if pay2.is_empty():
				return false
			# 复用该席最后 committed ROOM_SNAPSHOT.view_hash；禁止按新 seq 重建
			var vh2: String = _last_committed_snapshot_view_hash(seat_i)
			if vh2.is_empty() or vh2.length() != 64:
				return false
			var ne2: NetworkedEvent = NetworkedEvent.make(
				"CLAIM_WINDOW", candidate, _room_id, pay2, vh2
			)
			if ne2 == null:
				return false
			var cloned2: NetworkedEvent = NetworkedEvent.from_dict(ne2.to_dict())
			if cloned2 == null:
				return false
			prepared.append({"seat": seat_i, "clone": cloned2})
			covered[seat_i] = true
		for other2 in range(4):
			if covered.has(other2):
				continue
			var fill2: NetworkedEvent = _prepare_snapshot_filler(other2, candidate)
			if fill2 == null:
				return false
			prepared.append({"seat": other2, "clone": fill2})
		# 全部席成功后单线程提交：共享 candidate，每席恰好一条
		_server_seq = candidate
		for item in prepared:
			var seat_j: int = int(item["seat"])
			(_journals[seat_j] as Array).append(item["clone"])
		return true

	return false


## 私有 prompt 序号上非目标席的 ROOM_SNAPSHOT filler（#240 每席可见流连续）。
## 与 TURN_PROMPT/CLAIM_WINDOW 共享同一 candidate server_seq；失败返回 null。
func _prepare_snapshot_filler(seat: int, candidate_seq: int) -> NetworkedEvent:
	if seat < 0 or seat > 3:
		return null
	var sp: Dictionary = _build_room_snapshot_payload(seat, candidate_seq)
	if sp.is_empty():
		return null
	var vh: String = ProtocolViewCodec.compute_view_hash(sp)
	if vh.is_empty() or vh.length() != 64:
		return null
	var ne: NetworkedEvent = NetworkedEvent.make(
		"ROOM_SNAPSHOT", candidate_seq, _room_id, sp, vh
	)
	if ne == null:
		return null
	return NetworkedEvent.from_dict(ne.to_dict())


func _build_turn_prompt_payload(ctx: DecisionContext, seat: int) -> Dictionary:
	var seat_obj: Seat = _bc.state.seats[seat] as Seat
	if seat_obj == null:
		return {}
	var hand_out: Array = []
	for t in seat_obj.hand.tiles():
		var tv: Variant = ProtocolViewCodec.tile_view_from_tile(t)
		if tv == null:
			return {}
		hand_out.append(tv)
	var last_drawn: int = -1
	if Tile.is_valid_instance_id(seat_obj.last_drawn_instance_id):
		last_drawn = int(seat_obj.last_drawn_instance_id)
	return {
		"hand_seq": int(ctx.hand_seq),
		"decision_id": ctx.decision_id,
		"seat": seat,
		"hand": hand_out,
		"last_drawn_tile_instance_id": last_drawn,
		"allowed_actions": ctx.allowed_actions,
	}


func _build_claim_window_payload(ctx: DecisionContext, dw: DecisionWindow) -> Dictionary:
	var discarded: Tile = _bc.get("_last_discarded_tile") as Tile
	if discarded == null:
		return {}
	var tv: Variant = ProtocolViewCodec.tile_view_from_tile(discarded)
	if tv == null:
		return {}
	return {
		"hand_seq": int(ctx.hand_seq),
		"decision_id": ctx.decision_id,
		"discarded_by_seat": int(dw.discarder_seat),
		"discarded_tile": (tv as Dictionary).duplicate(true),
		"allowed_actions": ctx.allowed_actions,
	}


func _is_human(seat: int) -> bool:
	if seat < 0 or seat > 3:
		return false
	# #241：AI 接管中视为非真人（走 ActionSource.AI 自动推进）
	if bool(_ai_control_seats.get(seat, false)):
		return false
	return str(_participants[seat]) == str(GameSessionConfig.PARTICIPANT_HUMAN)


func _is_configured_human(seat: int) -> bool:
	if seat < 0 or seat > 3:
		return false
	return str(_participants[seat]) == str(GameSessionConfig.PARTICIPANT_HUMAN)


## AI 自动推进。成功/正常停在真人决策入口 → true；任一步 AA/SNAP 发布失败 → false。
## DRAW 且 current 为真人时绝不摸牌，交 submit 最终路径：draw → SNAP → TURN_PROMPT。
## CLOSING 屏障：CLAIM 未终态/宽限未满时禁止摸打/TURN 推进。
func _auto_advance_ai() -> bool:
	if _bc == null or _bc.state == null:
		return true
	var steps := 0
	while steps < MAX_AI_STEPS:
		steps += 1
		if bool(_bc.get("_settled")):
			return true
		# 打开窗（先刷新，供 CLAIM 可见性与屏障判定）
		for s in range(4):
			_bc.decision_context_for_seat(s)
		_reward_note_claim_visibility()

		# CLOSING：优先处理 CLAIM；禁止在屏障前进入普通摸打
		if _reward_is_closing():
			if _claim_or_rob_window_open():
				if not _auto_advance_claim_only():
					return false
				continue
			# 和牌已成立：不得 mark terminal / FULL_GRANT，交 submit 外层 cancel
			if bool(_bc.get("_settled")):
				return true
			# CLAIM 路径已结束且未和：冻结 context 并尝试 settle（不伪造时钟）
			if not _reward_try_release_barrier():
				return false
			if not _reward_allows_normal_progress():
				return true

		# 真人 DRAW：禁止提前摸牌
		if int(_bc.state.phase) == BattlePhase.Kind.DRAW:
			var cur: int = int(_bc.state.current_seat)
			if _is_human(cur):
				return true
			if not _reward_allows_normal_progress():
				return true
			if not _ensure_drawn():
				return true
		if bool(_bc.get("_settled")):
			return true
		for s2 in range(4):
			_bc.decision_context_for_seat(s2)
		var win = _bc.get("_active_window")
		if win == null or not (win is DecisionWindow):
			if int(_bc.state.phase) == BattlePhase.Kind.SETTLE:
				_bc.set("_settled", true)
				return true
			return true

		var dw: DecisionWindow = win as DecisionWindow
		if dw.kind == DecisionWindow.KIND_TURN:
			if not _reward_allows_normal_progress():
				return true
			var actor: int = int(dw.subject_seat)
			if _is_human(actor):
				return true
			var act: Action = _build_ai_turn_action(actor)
			if act == null:
				return true
			var disc_tile: Tile = null
			var dsrc := "HAND"
			if act.kind == "DISCARD" or act.kind == "RIICHI":
				var iid: int = int(act.payload.get("tile_instance_id", -1))
				var so: Seat = _bc.state.seats[actor] as Seat
				if so != null:
					disc_tile = so.hand.find_by_instance_id(iid)
					if disc_tile != null and int(so.last_drawn_instance_id) == iid:
						dsrc = "DRAWN"
			var res: ActionResolution = _apply_on_bc(act, ActionSource.AI)
			if res == null or not res.accepted:
				return true
			# AA+SNAP 内已 RW 预消费；禁止再 _reward_on_action_applied（防双计数/双 append）
			var ai_seq: int = _emit_action_applied(act, disc_tile, dsrc)
			if ai_seq < 1:
				return false
			continue

		if dw.kind == DecisionWindow.KIND_CLAIM or dw.kind == DecisionWindow.KIND_ROB_KAN:
			if not _auto_advance_claim_only():
				return false
			continue

		return true
	return true


## 仅推进 CLAIM/ROB 窗（可在 CLOSING 屏障期间运行）。
func _auto_advance_claim_only() -> bool:
	for s in range(4):
		_bc.decision_context_for_seat(s)
	var win = _bc.get("_active_window")
	if win == null or not (win is DecisionWindow):
		return true
	var dw: DecisionWindow = win as DecisionWindow
	if dw.kind != DecisionWindow.KIND_CLAIM and dw.kind != DecisionWindow.KIND_ROB_KAN:
		return true
	_reward_claim_seen_open = true
	var need_human := false
	for s2 in dw.seats():
		var si: int = int(s2)
		if _is_human(si) and not dw.has_responded(si):
			need_human = true
			break
	if need_human:
		return true
	for s3 in dw.seats():
		var si3: int = int(s3)
		if dw.has_responded(si3):
			continue
		var pass_act: Action = _build_ai_claim_action(si3)
		if pass_act == null:
			continue
		var r2: ActionResolution = _apply_on_bc(pass_act, ActionSource.AI)
		if r2 == null or not r2.accepted:
			continue
		# AA+SNAP 内已 RW 预消费
		var claim_seq: int = _emit_action_applied(pass_act, null, "HAND")
		if claim_seq < 1:
			return false
		return true
	return true


func _build_ai_turn_action(actor: int) -> Action:
	var ctx: DecisionContext = _bc.decision_context_for_seat(actor)
	if ctx == null:
		return null
	var cmd: String = _next_cmd()
	var did: String = ctx.decision_id
	var hs: int = int(_bc.state.hand_seq)
	if ctx.has_kind("TSUMO"):
		return Action.tsumo(actor, _room_id, cmd, did, hs, _server_seq + 1)
	# 取首个 DISCARD offer
	for offer in ctx.allowed_actions:
		if typeof(offer) != TYPE_DICTIONARY:
			continue
		if str(offer.get("kind", "")) != "DISCARD":
			continue
		var opts: Array = offer.get("payload_options", [])
		if opts.is_empty():
			continue
		var opt: Dictionary = opts[0]
		var iid: int = int(opt.get("tile_instance_id", -1))
		return Action.discard(actor, iid, _room_id, cmd, did, hs, _server_seq + 1)
	return null


func _build_ai_claim_action(seat: int) -> Action:
	var ctx: DecisionContext = _bc.decision_context_for_seat(seat)
	if ctx == null:
		return null
	# AI 有 RON 时仍 PASS（loopback 简化；不 mock 引擎）
	if ctx.has_kind("PASS"):
		return Action.make_pass(
			seat, _room_id, _next_cmd(), ctx.decision_id,
			int(_bc.state.hand_seq), _server_seq + 1
		)
	return null


func _next_cmd() -> String:
	# 与 BC 风格一致的确定性 uuid
	var n: int = _server_seq * 10 + 1 + _commands.size()
	return "550e8400-e29b-41d4-a716-%012d" % (n + 1000)


## 从 BC.state.scores 捕获 4 席整数分；非法 → 空 Array。
func _enforce_settlement_conservation() -> bool:
	# null mode_modules：不静默当 TRASH_TALK；按 STANDARD 严格守恒
	if mode_modules == null:
		return true
	if mode_modules.is_trash_talk():
		return false
	return true


func _capture_scores_array() -> Array:
	if _bc == null or _bc.state == null:
		return []
	var out: Array = []
	for s in _bc.state.scores:
		out.append(int(s))
	if out.size() != 4:
		return []
	return out


## 从真实 BC.events + state.scores + 冻结起始分推导 HAND_SETTLED payload。
## #375：与 GameDriver 共用 HandSettlement（含 noten / 流し满贯 / adjustments）。
## 失败 → {}。
func _build_hand_settled_payload() -> Dictionary:
	if _bc == null or _bc.state == null:
		return {}
	if _hand_start_scores.size() != 4:
		return {}
	var tenpai: Array = HandSettlement.detect_tenpai_array(_bc.state)
	var built: Dictionary = HandSettlement.build(
		_bc.events,
		_hand_start_scores,
		_bc.state,
		tenpai,
		_hand_start_honba,
		_hand_start_riichi_sticks
	)
	if built.is_empty() or not HandSettlement.is_valid_result(built):
		return {}
	return built


## 四席 HAND_SETTLED 原子发布：先全部 make+strict roundtrip，再同一 server_seq 提交。
## 任一 recipient 失败 → false，零 mutation（不增 seq、无半条）。
## 未 settled → true（无需发布）；payload/hash 失败 → false。
## #241：本局幂等——已成功发布后再次调用不得分配 seq / 重复 journal。
## #252：顺序 REWARD_WINDOW_CLOSING → SETTLED|CANCELLED → HAND_SETTLED；
## 延迟宽限未 settle 时不得发 HAND_SETTLED（记 deferred，等 advance_reward_time）。
func _emit_settled_if_needed() -> bool:
	if _bc == null or _bc.state == null:
		return false
	if not bool(_bc.get("_settled")):
		return true
	# 幂等：复用 #241 本局标志；禁止全局 journal 粗查（多局 journal 仍有旧 HAND_SETTLED）
	if _hand_settled_emitted:
		return true
	var payload: Dictionary = _build_hand_settled_payload()
	if payload.is_empty():
		return false
	# E5-04：和牌取消 / 流局 scoring close 必须在 HAND_SETTLED 前完成窗口出口
	if not _reward_on_hand_result(payload):
		return false
	var rw: RewardWindowModule = _reward_module()
	# barrier 未释放：仍 CLOSING → 延后 HAND_SETTLED
	if rw != null and rw.phase == RewardWindowModule.PHASE_CLOSING:
		_reward_hand_settled_deferred = true
		return true
	return _publish_hand_settled_payload(payload)


## 四席同 seq 发布 HAND_SETTLED；本局已发则幂等 true。
## #375：先完整校验 payload，再原子 commit 账本到 BattleState，最后同 seq 发布。
## #376 P1-1：HAND_SETTLED 后先推进 GameDriver，再 MATCH_SETTLED+终态 SNAP
## （终态 match_authority 必须 finished=true / 最终分）。失败精确回滚。
func _publish_hand_settled_payload(payload: Dictionary) -> bool:
	if _hand_settled_emitted:
		_reward_hand_settled_deferred = false
		return true
	if payload.is_empty() or not HandSettlement.is_valid_result(payload):
		return false
	# 延迟 RewardWindow：无外层事务时自建 freeze（含预 mutation ARS）
	var local_freeze := false
	if not _tx_active:
		if not begin_match_transaction_freeze():
			return false
		local_freeze = true
	var candidate: int = _server_seq + 1
	var prepared: Array = []
	for seat in range(4):
		var vh: String = _last_committed_snapshot_view_hash(seat)
		if vh.is_empty() or vh.length() != 64:
			if local_freeze:
				clear_match_transaction_freeze()
			return false
		var ne: NetworkedEvent = _build_recipient_event(
			"HAND_SETTLED", seat, candidate, payload, vh
		)
		if ne == null:
			if local_freeze:
				clear_match_transaction_freeze()
			return false
		prepared.append(ne)
	var ledger: Array = _capture_scores_array()
	if ledger.size() != 4:
		ledger = [0, 0, 0, 0]
		for i in range(4):
			ledger[i] = int(payload["scores"][i])
	if not HandSettlement.commit(
		payload, ledger, _settlement_tracker, _bc.state,
		_hand_start_scores, _enforce_settlement_conservation()
	):
		if local_freeze:
			clear_match_transaction_freeze()
		return false
	_server_seq = candidate
	for seat2 in range(4):
		(_journals[seat2] as Array).append(prepared[seat2])
	_hand_settled_emitted = true
	_reward_hand_settled_deferred = false
	# 天命打破跨局计数：一局权威完成后登记（按 hand_seq 幂等；spec §5.3）
	if mode_modules != null and mode_modules.is_trash_talk() and _item_module() != null:
		ItemAuthority.pity_on_hand_completed(
			_item_module(),
			payload.get("winner_seats", []) as Array,
			int(payload.get("hand_seq", -1))
		)

	# 判定是否终场（推进前）；随后统一先推进 GameDriver
	var expect_match_end: bool = _is_match_ended_for_hand(payload)
	var next_bc: BattleController = null
	if on_hand_settled_committed.is_valid():
		var adv_v: Variant = on_hand_settled_committed.call(payload)
		if typeof(adv_v) != TYPE_DICTIONARY:
			if local_freeze:
				_rollback_hand_transition_local()
			return false
		var adv: Dictionary = adv_v
		# #376 R4：任何非空 error 无条件失败；禁止伪装终场
		if not str(adv.get("error", "")).is_empty():
			if local_freeze:
				_rollback_hand_transition_local()
			return false
		var cb_finished: bool = bool(adv.get("finished", false))
		# expect_match_end 与 callback finished 必须一致
		if cb_finished != expect_match_end:
			if local_freeze:
				_rollback_hand_transition_local()
			return false
		if cb_finished:
			expect_match_end = true
		else:
			next_bc = adv.get("bc", null) as BattleController
			if next_bc == null:
				if local_freeze:
					_rollback_hand_transition_local()
				return false
	elif expect_match_end:
		# 无 match owner 但判定终场：仅 seam 路径（练习/测试 set_reward_match_ended）
		pass

	if expect_match_end:
		_reward_match_ended = true
		# 此时 GameDriver 已为终态；MATCH + SNAP 投影 finished=true / 最终分
		if not _emit_match_settled_and_clear_items():
			if local_freeze:
				_rollback_hand_transition_local()
			return false
		# #376 R4 测试 seam：MATCH 已落盘后失败 → 外层/本地 rollback 须清 MATCH flag
		if _fail_after_match_settled_for_test:
			_fail_after_match_settled_for_test = false
			fail_after_match_settled_hit_count += 1
			if local_freeze:
				_rollback_hand_transition_local()
			return false
		if local_freeze:
			clear_match_transaction_freeze()
		return true

	# 未终场：开下一局
	if next_bc != null:
		if not start_next_hand(next_bc):
			if local_freeze:
				_rollback_hand_transition_local()
			return false
	if local_freeze:
		clear_match_transaction_freeze()
	return true


## #376：无外层 Action 事务时（延迟 HAND_SETTLED）本地完整回滚。
## 必须使用 begin 时预拍的 _tx_bc_ars，禁止失败后再 capture。
func _rollback_hand_transition_local() -> void:
	if not _tx_active:
		return
	if not _restore_match_and_bc_ownership():
		_rollback_failed = true
		clear_match_transaction_freeze()
		return
	if _tx_bc_ars != null and _bc != null:
		if not _tx_bc_ars.restore_into(_bc):
			_rollback_failed = true
			clear_match_transaction_freeze()
			return
	if _tx_server_seq >= 0:
		_server_seq = _tx_server_seq
	if not _tx_journals.is_empty():
		_journals = []
		for s in range(4):
			if s < _tx_journals.size():
				_journals.append(_tx_journals[s])
			else:
				_journals.append([])
	if not _tx_settlement_tracker.is_empty():
		_settlement_tracker = _tx_settlement_tracker.duplicate(true)
	else:
		_settlement_tracker = HandSettlement.empty_tracker()
	_hand_settled_emitted = _tx_hand_settled_emitted
	_match_settled_emitted = _tx_match_settled_emitted
	_reward_match_ended = _tx_reward_match_ended
	_reward_claim_seen_open = _tx_claim_seen
	_reward_hand_settled_deferred = _tx_hand_deferred
	# #379：local hand transition 回滚须恢复技能投影游标
	_skill_bc_proj_upto = maxi(_tx_skill_bc_proj_upto, 0)
	if _bc != null:
		_skill_bc_proj_upto = mini(_skill_bc_proj_upto, _bc.events.size())
	if not _tx_rw_state.is_empty():
		_reward_restore_state(_tx_rw_state)
	if _tx_rw_clock >= 0:
		_reward_authority_now_ms = _tx_rw_clock
	clear_match_transaction_freeze()


## 延迟 HAND_SETTLED：仅在奖励窗已离开 CLOSING 后发布一次。
func _emit_deferred_hand_settled_if_ready() -> bool:
	if not _reward_hand_settled_deferred:
		return true
	if _bc == null or not bool(_bc.get("_settled")):
		return true
	var rw: RewardWindowModule = _reward_module()
	if rw != null and rw.phase == RewardWindowModule.PHASE_CLOSING:
		return true
	var payload: Dictionary = _build_hand_settled_payload()
	if payload.is_empty():
		return false
	return _publish_hand_settled_payload(payload)


# ---- E5-04 RewardWindow 权威消费（练习场 = 未来 Worker 同纯逻辑）----

func _reward_module() -> RewardWindowModule:
	if mode_modules == null or not mode_modules.is_trash_talk():
		return null
	return mode_modules.reward_window


func _reward_hard_reset() -> void:
	var rw: RewardWindowModule = _reward_module()
	if rw != null:
		rw.hard_reset()
	_reward_authority_now_ms = REWARD_CLOCK_BASE_MS
	_reward_claim_seen_open = false
	_reward_hand_settled_deferred = false


func _reward_capture_state() -> Dictionary:
	# #253：同事务冻结 RewardWindow + 库存/武装 + registry skill 索引（回滚原子）。
	var out := {
		"_rw": {},
		"_inv": {},
		"_inv_reg": {},
		"_slots": [],
	}
	var rw: RewardWindowModule = _reward_module()
	if rw != null:
		out["_rw"] = rw.capture_state()
	var inv: ItemInventoryModule = _item_module()
	if inv != null:
		out["_inv"] = inv.capture_state()
		out["_inv_reg"] = inv.duplicate_registered_skills()
	out["_slots"] = _capture_ability_slots_arm()
	return out


func _reward_restore_state(snap: Dictionary) -> bool:
	if snap.is_empty():
		return true
	# 兼容旧纯 RW 快照（无 _rw 包装）
	var rw_snap: Dictionary = {}
	var inv_snap: Dictionary = {}
	var inv_reg: Dictionary = {}
	var slots_snap: Array = []
	var has_inv_reg := false
	if snap.has("_rw") or snap.has("_inv") or snap.has("_slots") or snap.has("_inv_reg"):
		if typeof(snap.get("_rw", null)) == TYPE_DICTIONARY:
			rw_snap = snap["_rw"]
		if typeof(snap.get("_inv", null)) == TYPE_DICTIONARY:
			inv_snap = snap["_inv"]
		if snap.has("_inv_reg") and typeof(snap.get("_inv_reg", null)) == TYPE_DICTIONARY:
			inv_reg = snap["_inv_reg"]
			has_inv_reg = true
		if typeof(snap.get("_slots", null)) == TYPE_ARRAY:
			slots_snap = snap["_slots"]
	else:
		rw_snap = snap
	var rw: RewardWindowModule = _reward_module()
	if rw != null:
		if rw_snap.is_empty():
			return false
		if not rw.restore_state(rw_snap):
			return false
	elif not rw_snap.is_empty():
		return false
	var inv: ItemInventoryModule = _item_module()
	if inv != null:
		if not inv_snap.is_empty() and not inv.restore_state(inv_snap):
			return false
		if has_inv_reg:
			inv.restore_registered_skills(inv_reg)
	if not _restore_ability_slots_arm(slots_snap):
		return false
	return true


## #253：ITEM_USE 专用事务（幂等由 command cache；成功发 CONSUMED/APPLIED + 匹配 ROOM_SNAPSHOT）。
func _submit_item_use(
	action: Action,
	cmd: String,
	fp: String,
	snap: AuthorityReplaySnapshot,
	frozen_seq: int,
	frozen_journals: Array,
	frozen_cache: Dictionary,
	frozen_rw: Dictionary,
	frozen_rw_clock: int,
	frozen_claim_seen: bool,
	frozen_hand_deferred: bool,
	frozen_hand_settled: bool,
	frozen_settlement_tracker: Dictionary = {}
) -> CommandResult:
	# 阶段/decision：须有该席当前 decision 窗且 decision_id 对齐
	if _bc == null or _bc.state == null:
		var cr0 := _reject_result(cmd, "INVALID_ACTION")
		_cache_command(cmd, fp, cr0)
		clear_match_transaction_freeze()
		return _clone_cr(cr0)
	var seat: int = int(action.seat)
	var ctx: DecisionContext = _bc.decision_context_for_seat(seat)
	if ctx == null:
		var cr1 := _reject_result(cmd, "WRONG_DECISION")
		_cache_command(cmd, fp, cr1)
		clear_match_transaction_freeze()
		return _clone_cr(cr1)
	if str(action.decision_id) != str(ctx.decision_id):
		var cr2 := _reject_result(cmd, "WRONG_DECISION")
		_cache_command(cmd, fp, cr2)
		clear_match_transaction_freeze()
		return _clone_cr(cr2)
	if int(action.hand_seq) != int(_bc.state.hand_seq):
		var cr3 := _reject_result(cmd, "WRONG_HAND")
		_cache_command(cmd, fp, cr3)
		clear_match_transaction_freeze()
		return _clone_cr(cr3)
	var item_instance_id := String(action.payload.get("item_instance_id", ""))
	var use_r: Dictionary = ItemAuthority.use_item(
		_bc, _item_module(), seat, item_instance_id, cmd
	)
	if not bool(use_r.get("accepted", false)):
		var code := String(use_r.get("error_code", "INVALID_ACTION"))
		var cr_rej := _reject_result(cmd, code)
		_cache_command(cmd, fp, cr_rej)
		clear_match_transaction_freeze()
		return _clone_cr(cr_rej)
	var domain_events: Array = []
	for ev in use_r.get("events", []):
		if typeof(ev) != TYPE_DICTIONARY:
			_rollback_transaction(
				snap, frozen_seq, frozen_journals, frozen_cache,
				frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
				frozen_hand_settled,
			frozen_settlement_tracker
			)
			return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)
		domain_events.append(ev)
	# 延迟 skill 可能在同事务内已 consumed（罕见）；并入同一批终态 SNAP
	var fin: Dictionary = ItemAuthority.finalize_triggered(_bc, _item_module())
	if not bool(fin.get("ok", false)):
		_rollback_transaction(
			snap, frozen_seq, frozen_journals, frozen_cache,
			frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
			frozen_hand_settled,
			frozen_settlement_tracker
		)
		return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)
	for fev in fin.get("events", []):
		if typeof(fev) == TYPE_DICTIONARY:
			domain_events.append(fev)
	# 即时效果改 core_table；延迟武装改 inventory 投影——均须匹配 ROOM_SNAPSHOT 闭合
	if not _publish_domain_events_with_matching_snapshot(domain_events):
		_rollback_transaction(
			snap, frozen_seq, frozen_journals, frozen_cache,
			frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
			frozen_hand_settled,
			frozen_settlement_tracker
		)
		return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)
	var cr_ok := CommandResult.from_dict({
		"protocol_version": ProtocolConstants.PROTOCOL_VERSION,
		"command_id": cmd,
		"status": "ACCEPTED",
		"server_seq": _server_seq,
		"error_code": "",
	})
	_cache_command(cmd, fp, cr_ok)
	clear_match_transaction_freeze()
	return _clone_cr(cr_ok)


## #253：0..N 条业务事件 + 1 条 ROOM_SNAPSHOT 共用 post-state view_hash（对齐 AA+SNAP）。
## 空 events 时仍发 SNAP（延迟武装仅改库存/registry 投影）。
func _publish_domain_events_with_matching_snapshot(events: Array) -> bool:
	if _rollback_failed or _bc == null:
		return false
	var n_ev: int = events.size()
	var first_seq: int = _server_seq + 1
	var snap_seq: int = _server_seq + n_ev + 1
	# 阶段 1：逐席构造终态 SNAP + 共享 vh 的业务事件
	var prepared_by_seat: Array = []  # seat -> {events: Array[NetworkedEvent], snap: NetworkedEvent}
	for seat in range(4):
		var sp: Dictionary = _build_room_snapshot_payload(seat, snap_seq)
		if sp.is_empty():
			return false
		var vh: String = ProtocolViewCodec.compute_view_hash(sp)
		if vh.is_empty() or vh.length() != 64:
			return false
		var seat_evs: Array = []
		for i in range(n_ev):
			var raw = events[i]
			if typeof(raw) != TYPE_DICTIONARY:
				return false
			var kind := String((raw as Dictionary).get("kind", ""))
			var pl: Variant = (raw as Dictionary).get("payload", {})
			if kind.is_empty() or typeof(pl) != TYPE_DICTIONARY:
				return false
			if mode_modules != null and not mode_modules.accepts_event_kind(kind):
				return false
			var ev_seq: int = first_seq + i
			var ne: NetworkedEvent = _build_recipient_event(
				kind, seat, ev_seq, (pl as Dictionary).duplicate(true), vh
			)
			if ne == null:
				return false
			seat_evs.append(ne)
		var snap_ev: NetworkedEvent = _build_recipient_event(
			"ROOM_SNAPSHOT", seat, snap_seq, sp, vh
		)
		if snap_ev == null:
			return false
		prepared_by_seat.append({"events": seat_evs, "snap": snap_ev})
	# 阶段 2：提交 journal
	_server_seq = snap_seq
	for seat2 in range(4):
		var pack: Dictionary = prepared_by_seat[seat2] as Dictionary
		for ne2 in pack["events"]:
			(_journals[seat2] as Array).append(ne2)
			if ne2 is NetworkedEvent and (ne2 as NetworkedEvent).kind == "MATCH_SETTLED":
				_match_settled_emitted = true
		(_journals[seat2] as Array).append(pack["snap"])
	return true


func _item_module() -> ItemInventoryModule:
	if mode_modules == null or not mode_modules.is_trash_talk():
		return null
	return mode_modules.item_inventory


func _ability_slots() -> Array:
	if mode_modules == null or not mode_modules.is_trash_talk():
		return []
	return mode_modules.character_ability_slots


func _capture_ability_slots_arm() -> Array:
	var out: Array = []
	for slot_v in _ability_slots():
		if not (slot_v is CharacterAbilitySlot):
			out.append({})
			continue
		var slot: CharacterAbilitySlot = slot_v as CharacterAbilitySlot
		out.append({
			"armed": slot.armed,
			"active_window_id": slot.active_window_id,
			"registry_registered": slot.registry_registered,
		})
	return out


func _restore_ability_slots_arm(snap: Array) -> bool:
	var slots: Array = _ability_slots()
	if snap.is_empty():
		return true
	if snap.size() != slots.size():
		return false
	var restored_skills: Array = []
	restored_skills.resize(slots.size())
	for i in range(slots.size()):
		if not (slots[i] is CharacterAbilitySlot):
			continue
		if typeof(snap[i]) != TYPE_DICTIONARY:
			return false
		var slot: CharacterAbilitySlot = slots[i] as CharacterAbilitySlot
		var d: Dictionary = snap[i]
		var want_reg: bool = bool(d.get("registry_registered", false))
		if want_reg:
			var restored_skill := _registered_character_skill(slot.seat, slot.ability_id)
			if restored_skill == null:
				return false
			restored_skills[i] = restored_skill
	for i in range(slots.size()):
		if not (slots[i] is CharacterAbilitySlot):
			continue
		var slot: CharacterAbilitySlot = slots[i] as CharacterAbilitySlot
		var d: Dictionary = snap[i]
		var want_reg: bool = bool(d.get("registry_registered", false))
		if want_reg:
			slot.skill = restored_skills[i] as SkillResource
		# want_reg 已由预检确认存在权威 entry；这里只处理快照要求注销的方向。
		if slot.registry_registered and not want_reg and _bc != null and slot.skill != null:
			_bc.registry.unregister(slot.skill, slot.seat)
		slot.armed = bool(d.get("armed", false))
		slot.active_window_id = d.get("active_window_id", null)
		slot.registry_registered = want_reg
	return true


func _registered_character_skill(seat: int, ability_id: StringName) -> SkillResource:
	if _bc == null or _bc.registry == null:
		return null
	for entry_value in _bc.registry.get_all_entries():
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry := entry_value as Dictionary
		var anchor_value: Variant = entry.get("anchor", null)
		if typeof(anchor_value) != TYPE_INT or int(anchor_value) != seat:
			continue
		var skill := entry.get("skill") as SkillResource
		if skill != null and skill.is_ability and skill.id == ability_id:
			return skill
	return null


## #253：SETTLED(FULL_GRANT) → 4×ITEM_GRANTED → 注册 relic；随后 DISARM active。
## 业务事件与终态 ROOM_SNAPSHOT 共用 view_hash，供 NBC 原子提交。
func _item_after_settled(settled_payload: Dictionary, matrix: Array) -> bool:
	var inv: ItemInventoryModule = _item_module()
	if inv == null:
		return true
	var outcome := String(settled_payload.get("outcome", ""))
	var window_id := String(settled_payload.get("window_id", ""))
	var domain: Array = []
	if outcome == "FULL_GRANT":
		var chars: Array = []
		if _config != null:
			for c in _config.character_ids:
				chars.append(String(c))
		var hand_ends := _bc != null and bool(_bc.get("_settled"))
		var match_ns := ""
		if _config != null:
			match_ns = str(_config.session_id)
		var gr: Dictionary = ItemAuthority.grant_full_from_settled(
			inv, settled_payload, matrix, chars, "", hand_ends, match_ns
		)
		if not bool(gr.get("ok", false)):
			return false
		for g in gr.get("grants", []):
			if typeof(g) != TYPE_DICTIONARY:
				return false
			var pl: Dictionary = g.get("payload", {})
			if not ItemAuthority.register_relic_for_grant(_bc, inv, pl):
				return false
			domain.append({"kind": "ITEM_GRANTED", "payload": pl})
	# 任何 SETTLED 出口后 DISARM active（保留 FULL_GRANT 刚写的 pending）
	var dis: Dictionary = ItemAuthority.disarm_all_active(
		_bc, inv, _ability_slots(), window_id
	)
	if not bool(dis.get("ok", false)):
		return false
	for ev in dis.get("events", []):
		if typeof(ev) == TYPE_DICTIONARY:
			domain.append(ev)
	if not _publish_domain_events_with_matching_snapshot(domain):
		return false
	# 终场 DISPLAY_ONLY：不得在此发 MATCH_SETTLED。
	# E5 冻结序为 HAND_SETTLED → MATCH_SETTLED；MATCH 仅由 _publish_hand_settled_payload 触发。
	return true


## #253：CANCELLED → DISARM；pending 必须为空。终场和牌随后 MATCH_SETTLED 清库存。
func _item_after_cancelled(cancelled_payload: Dictionary) -> bool:
	var inv: ItemInventoryModule = _item_module()
	if inv == null:
		return true
	var window_id := String(cancelled_payload.get("window_id", ""))
	var r: Dictionary = ItemAuthority.on_cancel_by_win(
		_bc, inv, _ability_slots(), window_id
	)
	if not bool(r.get("ok", false)):
		return false
	var domain: Array = []
	for ev in r.get("events", []):
		if typeof(ev) == TYPE_DICTIONARY:
			domain.append(ev)
	if not _publish_domain_events_with_matching_snapshot(domain):
		return false
	return true


func _is_match_ended_now() -> bool:
	return _is_match_ended_for_hand({})


## #376：结合 match owner 回调 / 测试 seam / payload.match_ended 判断终场。
func _is_match_ended_for_hand(hand_payload: Dictionary) -> bool:
	if match_end_after_hand.is_valid() and not hand_payload.is_empty():
		return bool(match_end_after_hand.call(hand_payload))
	if typeof(_reward_match_ended) == TYPE_BOOL:
		return bool(_reward_match_ended)
	if hand_payload.has("match_ended") and typeof(hand_payload["match_ended"]) == TYPE_BOOL:
		return bool(hand_payload["match_ended"])
	if match_end_after_hand.is_valid():
		return bool(match_end_after_hand.call(hand_payload))
	return false


## HAND_SETTLED 后：若整场结束则 MATCH_SETTLED + 清库存/武装/registry + 匹配终态 SNAP。
## 先清场再发事件，使 MATCH 与 SNAP 共用清场后 view_hash（NBC 不得 same-hash 半投影）。
func _emit_match_settled_and_clear_items() -> bool:
	if not _is_match_ended_now():
		return true
	# 已发过则幂等清场（O(1) 标志，不克隆 journal）
	if _match_settled_emitted:
		ItemAuthority.clear_match(_bc, _item_module(), _ability_slots())
		return true
	var scores: Array = _capture_scores_array()
	if scores.size() != 4:
		return false
	var order: Array = MatchSettlement.build_seat_order(scores)
	var round_kind := "EAST"
	if _config != null:
		var rk := str(_config.round_kind)
		if rk == str(GameSessionConfig.ROUND_HANCHAN) or rk == "HANCHAN":
			round_kind = "HANCHAN"
		else:
			round_kind = "EAST"
	var payload := {
		"round_kind": round_kind,
		"final_scores": scores,
		"seat_order": order,
	}
	# 先清权威库存/slot/registry，再发 MATCH_SETTLED + 终态 SNAP（同 view_hash）
	ItemAuthority.clear_match(_bc, _item_module(), _ability_slots())
	if not _publish_domain_events_with_matching_snapshot([
		{"kind": "MATCH_SETTLED", "payload": payload},
	]):
		return false
	# 双保险：publish 路径已置位；此处保证语义显式
	_match_settled_emitted = true
	return true


## 延迟消耗品触发后结算公开事件。
## #379：pending SKILL_TRIGGERED 与 ITEM_APPLIED/CONSUMED 同一 domain 批发布，
## 保证相对序 SKILL < APPLIED < CONSUMED 且共享匹配 ROOM_SNAPSHOT（start 路径 NBC 可 ingest）。
func _finalize_item_triggers() -> bool:
	var domain: Array = []
	# 先收集尚未投影的技能归因（不提前推进游标）
	_collect_skill_triggered_domain_from_bc(domain, _skill_bc_proj_upto)
	var inv: ItemInventoryModule = _item_module()
	if inv != null:
		var fin: Dictionary = ItemAuthority.finalize_triggered(_bc, inv)
		if not bool(fin.get("ok", false)):
			return false
		for ev in fin.get("events", []):
			if typeof(ev) != TYPE_DICTIONARY:
				return false
			domain.append(ev)
	if domain.is_empty():
		return true
	if not _publish_domain_events_with_matching_snapshot(domain):
		return false
	# 仅批成功后确认游标（覆盖本批涉及的 BC 技能事件）
	if _bc != null:
		_skill_bc_proj_upto = maxi(_skill_bc_proj_upto, _bc.events.size())
	return true


## #253：OPEN 后、常规事件前 ARM。
## #379：先冲 pending 技能；ARM/GAME_BEGIN 新技能并入 domain，仅批成功后确认游标。
func _item_after_opened(opened_payload: Dictionary) -> bool:
	var inv: ItemInventoryModule = _item_module()
	if inv == null:
		return true
	# barrier 前 Action/AI 技能不得被后续游标推进吞掉
	if not _publish_pending_skill_triggered_from_bc():
		return false
	var window_id := String(opened_payload.get("window_id", ""))
	var bc_mark: int = 0
	if _bc != null:
		bc_mark = _bc.events.size()
	var r: Dictionary = ItemAuthority.arm_seats_on_open(
		_bc, inv, _ability_slots(), window_id
	)
	if not bool(r.get("ok", false)):
		return false
	var domain: Array = []
	for ev in r.get("events", []):
		if typeof(ev) == TYPE_DICTIONARY:
			domain.append(ev)
	# GAME_BEGIN 等价激活写入 BC.events 的 SKILL_TRIGGERED → 公开 journal
	# 仅收集，不提前推进游标（失败时仍可被外层回滚后从旧游标重投）
	_collect_skill_triggered_domain_from_bc(domain, bc_mark)
	if domain.is_empty():
		if _bc != null:
			_skill_bc_proj_upto = maxi(_skill_bc_proj_upto, _bc.events.size())
		return true
	if not _publish_domain_events_with_matching_snapshot(domain):
		return false
	if _bc != null:
		_skill_bc_proj_upto = maxi(_skill_bc_proj_upto, _bc.events.size())
	return true


## #379：从 BC.events[since_index..] 提取 SKILL_TRIGGERED 并入 domain（不改游标）。
func _collect_skill_triggered_domain_from_bc(domain: Array, since_index: int) -> void:
	if _bc == null or domain == null:
		return
	if mode_modules == null or not mode_modules.is_trash_talk():
		return
	if not mode_modules.accepts_event_kind("SKILL_TRIGGERED"):
		return
	# 与未投影边界安全合并：不得从 since_index 起跳过更早 pending
	var start: int = maxi(mini(since_index, _skill_bc_proj_upto), 0)
	start = maxi(start, _skill_bc_proj_upto)
	for i in range(start, _bc.events.size()):
		var bev: BattleEvent = _bc.events[i] as BattleEvent
		if bev == null or bev.type != &"SKILL_TRIGGERED":
			continue
		var pl: Dictionary = _public_skill_triggered_payload_from_bc(bev)
		if pl.is_empty():
			continue
		domain.append({"kind": "SKILL_TRIGGERED", "payload": pl})


## 兼容旧名：收集后仅在调用方确认成功时再推进游标（见 _item_after_opened）。
func _append_skill_triggered_domain_from_bc(domain: Array, since_index: int) -> void:
	_collect_skill_triggered_domain_from_bc(domain, since_index)

## #379：BattleEvent.SKILL_TRIGGERED.extra → 公开 NetworkedEvent payload。
func _public_skill_triggered_payload_from_bc(bev: BattleEvent) -> Dictionary:
	if bev == null or bev.type != &"SKILL_TRIGGERED":
		return {}
	var ex: Dictionary = bev.extra if typeof(bev.extra) == TYPE_DICTIONARY else {}
	var skill_id := str(ex.get("skill_id", ""))
	if skill_id.is_empty():
		return {}
	var ben := int(ex.get("beneficiary_seat", bev.actor_seat))
	if ben < 0 or ben > 3:
		ben = int(bev.actor_seat)
	var actor := int(ex.get("actor_seat", ben))
	if actor < 0 or actor > 3:
		actor = ben
	var source_kind := str(ex.get("source_kind", ""))
	if source_kind.is_empty():
		if skill_id.begins_with("relic_"):
			source_kind = "relic"
		elif ex.has("item_instance_id") and not str(ex.get("item_instance_id", "")).is_empty():
			source_kind = "item"
		else:
			source_kind = "character"
	var hand_seq: int = int(ex.get("hand_seq", -1))
	if hand_seq < 0 and _bc != null and _bc.state != null:
		hand_seq = int(_bc.state.hand_seq)
	if hand_seq < 0:
		hand_seq = 0
	var pl := {
		"actor_seat": actor,
		"beneficiary_seat": ben,
		"skill_id": skill_id,
		"skill_name": str(ex.get("skill_name", "")),
		"source_event": str(ex.get("source_event", "")),
		"source_kind": source_kind,
		"hand_seq": hand_seq,
	}
	if pl["source_event"].is_empty():
		return {}
	if ex.has("han_delta"):
		pl["han_delta"] = int(ex["han_delta"])
	if ex.has("extra_dora_delta"):
		pl["extra_dora_delta"] = int(ex["extra_dora_delta"])
	if ex.has("extra_red_dora_delta"):
		pl["extra_red_dora_delta"] = int(ex["extra_red_dora_delta"])
	if ex.has("item_instance_id") and not str(ex.get("item_instance_id", "")).is_empty():
		pl["item_instance_id"] = str(ex["item_instance_id"])
	return pl


## #379：将尚未投影的 BC.SKILL_TRIGGERED 发布为公开业务事件。
## 仅扫描 _skill_bc_proj_upto.. 增量，禁止调用 event_journal() 全量克隆。
## 使用 _publish_business_event_core：start/start_next_hand 在 _started=false 时也必须可投。
func _publish_pending_skill_triggered_from_bc() -> bool:
	if _bc == null:
		return true
	if mode_modules == null or not mode_modules.is_trash_talk():
		return true
	if not mode_modules.accepts_event_kind("SKILL_TRIGGERED"):
		return true
	var start: int = maxi(_skill_bc_proj_upto, 0)
	if start > _bc.events.size():
		start = _bc.events.size()
	for i in range(start, _bc.events.size()):
		var bev: BattleEvent = _bc.events[i] as BattleEvent
		if bev == null or bev.type != &"SKILL_TRIGGERED":
			continue
		var pl: Dictionary = _public_skill_triggered_payload_from_bc(bev)
		if pl.is_empty():
			return false
		if not _publish_business_event_core("SKILL_TRIGGERED", pl):
			return false
	_skill_bc_proj_upto = _bc.events.size()
	return true


func _reward_now_ms() -> int:
	return _reward_authority_now_ms


## #247/#252：公开只读 RewardWindow 权威当前时间（与 advance_reward_time 同一时钟域）。
## 非 Worker 墙钟 / lease 单调时钟；调用方不得据此自行推进。
func reward_authority_now_ms() -> int:
	return _reward_authority_now_ms


## 显式权威时钟 tick：原子事务。settle/open/HAND_SETTLED/恢复推进失败则全回滚。
func advance_reward_time(now_ms: int) -> bool:
	if _rollback_failed or not _started:
		return false
	if not _is_int_ms(now_ms):
		return false
	if now_ms < _reward_authority_now_ms:
		return false
	# 无副作用早返回：时钟未变且屏障不需要工作
	if now_ms == _reward_authority_now_ms:
		return true

	# 非 CLOSING 且无延迟 HAND：仅推进权威时钟，无 RW/库存 mutation，无需 ARS 事务。
	# （#253 FULL_GRANT 后 OPEN 的幂等 tick 走此路径；避免 arm/reveal 后 ARS 边界卡住时钟）
	var rw_probe: RewardWindowModule = _reward_module()
	if (rw_probe == null or rw_probe.phase != RewardWindowModule.PHASE_CLOSING) \
			and not _reward_hand_settled_deferred:
		_reward_authority_now_ms = now_ms
		return true

	var snap: AuthorityReplaySnapshot = null
	if _bc != null and _bc.state != null:
		snap = AuthorityReplaySnapshot.capture(_bc)
		if snap == null or not snap.can_restore():
			return false
	# #376：与 Action 同边界 — match + journal + BC 所有权
	if not begin_match_transaction_freeze():
		return false
	var frozen_seq: int = _server_seq
	var frozen_journals: Array = []
	for s in range(4):
		frozen_journals.append(_clone_events(_journals[s] as Array))
	var frozen_cache: Dictionary = _commands.capture()
	var frozen_rw: Dictionary = _reward_capture_state()
	var frozen_clock: int = _reward_authority_now_ms
	var frozen_claim: bool = _reward_claim_seen_open
	var frozen_deferred: bool = _reward_hand_settled_deferred
	var frozen_hand_settled: bool = _hand_settled_emitted
	var frozen_settlement_tracker: Dictionary = _settlement_tracker.duplicate(true)

	# 仅当本 tick 真正完成 CLOSING→终态/OPEN 转换时才恢复普通推进
	var rw0: RewardWindowModule = _reward_module()
	var closing_before: bool = rw0 != null and rw0.phase == RewardWindowModule.PHASE_CLOSING

	_reward_authority_now_ms = now_ms
	var ok := true
	if not _reward_try_release_barrier():
		ok = false
	elif not _emit_deferred_hand_settled_if_ready():
		ok = false
	else:
		var rw1: RewardWindowModule = _reward_module()
		var left_closing: bool = closing_before and rw1 != null \
			and rw1.phase != RewardWindowModule.PHASE_CLOSING
		# 满 24 等：本 tick 完成 barrier/RW 转换且 hand 未 settled → 恢复推进
		if left_closing and _bc != null and not bool(_bc.get("_settled")):
			if not _resume_normal_progress_after_reward_tick():
				ok = false
	if ok:
		clear_match_transaction_freeze()
		return true
	# 全量回滚（含 match owner / BC 所有权）
	if not _rollback_transaction(
		snap, frozen_seq, frozen_journals, frozen_cache,
		frozen_rw, frozen_clock, frozen_claim, frozen_deferred,
		frozen_hand_settled, frozen_settlement_tracker
	):
		return false
	return false


## tick 内仅在 RW 实际离开 CLOSING 后调用：AI 链 + 真人 DRAW 收尾 + 提示。
## AI 后若领域 settled → HAND/Reward 顺序；若停在真人 DRAW → ensure_drawn+快照。
func _resume_normal_progress_after_reward_tick() -> bool:
	if _bc == null or _bc.state == null:
		return true
	if not _reward_allows_normal_progress():
		return true
	if not _ensure_human_draw_snapshot_if_needed():
		return false
	if bool(_bc.get("_settled")):
		return _emit_settled_if_needed()
	if not _auto_advance_ai():
		return false
	# AI 链可能终局或把 current 交回真人 DRAW
	if bool(_bc.get("_settled")):
		return _emit_settled_if_needed()
	if not _ensure_human_draw_snapshot_if_needed():
		return false
	if bool(_bc.get("_settled")):
		return _emit_settled_if_needed()
	return _emit_prompt_respecting_reward_barrier()


## 当前为真人 DRAW 且允许普通推进时：摸牌 + 原子 ROOM_SNAPSHOT（失败 false）。
func _ensure_human_draw_snapshot_if_needed() -> bool:
	if _bc == null or _bc.state == null or bool(_bc.get("_settled")):
		return true
	if int(_bc.state.phase) != BattlePhase.Kind.DRAW:
		return true
	var cur: int = int(_bc.state.current_seat)
	if not _is_human(cur):
		return true
	if not _reward_allows_normal_progress():
		return true
	if not _ensure_drawn():
		# 摸牌失败可能已 exhaustive settled
		return true
	if bool(_bc.get("_settled")):
		return true
	return publish_snapshot()


## CLAIM/ROB 在 CLOSING 期间仍须发 CLAIM_WINDOW；普通 TURN 受屏障阻止。
func _emit_prompt_respecting_reward_barrier() -> bool:
	if _bc == null:
		return true
	for s in range(4):
		_bc.decision_context_for_seat(s)
	_reward_note_claim_visibility()
	if _claim_or_rob_window_open():
		return _emit_private_prompt()
	if not _reward_allows_normal_progress():
		return true
	return _emit_private_prompt()


## 整场是否结束的权威注入 seam（LocalLoopback 无完整 match 生命周期时显式设置）。
func set_reward_match_ended(ended: bool) -> void:
	_reward_match_ended = ended


func _is_int_ms(v: Variant) -> bool:
	return typeof(v) == TYPE_INT


func _reward_is_closing() -> bool:
	var rw: RewardWindowModule = _reward_module()
	return rw != null and rw.phase == RewardWindowModule.PHASE_CLOSING


func _claim_or_rob_window_open() -> bool:
	if _bc == null:
		return false
	var win = _bc.get("_active_window")
	if win is DecisionWindow:
		var dw: DecisionWindow = win as DecisionWindow
		return dw.kind == DecisionWindow.KIND_CLAIM \
			or dw.kind == DecisionWindow.KIND_ROB_KAN
	return false


func _reward_note_claim_visibility() -> void:
	if _reward_is_closing() and _claim_or_rob_window_open():
		_reward_claim_seen_open = true


## 是否允许下一普通摸牌/出牌/TURN_PROMPT（屏障 fail-closed）。
## CLOSING 期间一律禁止普通推进；CLAIM 提示走 _emit_prompt_respecting_reward_barrier。
func _reward_allows_normal_progress() -> bool:
	var rw: RewardWindowModule = _reward_module()
	if rw == null:
		return true
	# 未 settle 的 CLOSING 不得越过（即使 barrier 已 released 但 try_settle 失败）
	if rw.phase == RewardWindowModule.PHASE_CLOSING:
		return false
	return true


func _maybe_open_reward_window() -> bool:
	var rw: RewardWindowModule = _reward_module()
	if rw == null:
		return true
	if rw.phase == RewardWindowModule.PHASE_OPEN \
			or rw.phase == RewardWindowModule.PHASE_CLOSING:
		return true
	if _config == null or _bc == null or _bc.state == null:
		return false
	var chars: Array = []
	for c in _config.character_ids:
		chars.append(String(c))
	var parts: Array = []
	for p in _participants:
		parts.append(String(p))
	var pub_ini: Dictionary = TrashTalkPublicContextAdapter.public_snapshot_from_battle_state(
		_bc.state
	)
	# 同 hand 内 FULL_GRANT 后 index+1；hand_seq 变化后首窗归 0
	var window_index: int = 0
	var next_hand: int = int(_bc.state.hand_seq)
	if rw.phase == RewardWindowModule.PHASE_SETTLED:
		if next_hand == int(rw.hand_seq):
			window_index = int(rw.window_index) + 1
		else:
			window_index = 0
	var res: Dictionary = rw.open({
		"seed": int(_config.seed),
		"hand_seq": next_hand,
		"window_index": window_index,
		"rule_version": TrashTalkRuleCatalog.rule_version(),
		"room_id": _room_id,
		"character_ids": chars,
		"language": "zh",
		"participants": parts,
		"public_initial": pub_ini,
	})
	if not bool(res.get("ok", false)):
		return false
	if bool(res.get("idempotent", false)):
		return true
	_reward_claim_seen_open = false
	if not _publish_business_event_core(
		"REWARD_WINDOW_OPENED", res["payload"] as Dictionary
	):
		return false
	# #253：OPEN 后、常规牌局事件前 ARM
	return _item_after_opened(res["payload"] as Dictionary)


## 在 AA+SNAP 提交前按 candidate aa_seq 预消费 RewardWindow。
## - 不写 journal、不递增 _server_seq
## - 将合法公开 ACTION_APPLIED 写入评分上下文；弃牌计数/CLOSING 状态立即生效
## - CLOSING 等业务事件放入 pending_effects，由调用方在 AA+SNAP 之后发布
## - 幂等：同 fingerprint 弃牌不双计数；重复 append 由模块/指纹保护
func _reward_preconsume_for_action(
	action: Action,
	aa_seq: int,
	aa_payload: Dictionary,
	pending_effects: Array
) -> bool:
	var rw: RewardWindowModule = _reward_module()
	if rw == null or action == null:
		return true
	if rw.phase != RewardWindowModule.PHASE_OPEN \
			and rw.phase != RewardWindowModule.PHASE_CLOSING:
		return true
	if aa_seq < 1:
		return false
	# 公开 AA：用 payload 自哈希作 provisional view_hash（格式合法）；journal 最终 AA 用 SNAP hash
	var prov_vh: String = ProtocolViewCodec.compute_view_hash(aa_payload)
	if prov_vh.is_empty() or prov_vh.length() != 64:
		prov_vh = _last_committed_snapshot_view_hash(0)
	if prov_vh.is_empty() or prov_vh.length() != 64:
		return false
	var aa_ne: NetworkedEvent = NetworkedEvent.make(
		"ACTION_APPLIED", aa_seq, _room_id, aa_payload, prov_vh
	)
	if aa_ne == null:
		return false
	var verified: NetworkedEvent = NetworkedEvent.from_dict(aa_ne.to_dict())
	if verified == null:
		return false
	var ap: Dictionary = rw.append_public_event(verified.to_dict())
	if not bool(ap.get("ok", false)):
		if String(ap.get("reason", "")) == "AFTER_CONTEXT_BOUNDARY":
			return true
		return false
	if action.kind == "DISCARD" or action.kind == "RIICHI":
		var is_ai: bool = not _is_human(int(action.seat))
		var res: Dictionary = rw.on_discard_applied({
			"server_seq": aa_seq,
			"seat": int(action.seat),
			"kind": str(action.kind),
			"now_ms": _reward_now_ms(),
			"is_ai": is_ai,
		})
		if not bool(res.get("ok", false)):
			return false
		if String(res.get("kind", "")) == "REWARD_WINDOW_CLOSING" \
				and not bool(res.get("idempotent", false)):
			_reward_claim_seen_open = false
			pending_effects.append({
				"kind": "REWARD_WINDOW_CLOSING",
				"payload": (res["payload"] as Dictionary).duplicate(true),
			})
			# 弃牌后同步刷新 CLAIM 窗（状态在模块上；事件稍后发布）
			if _bc != null:
				for s in range(4):
					_bc.decision_context_for_seat(s)
			if _claim_or_rob_window_open():
				_reward_claim_seen_open = true
			else:
				var bp: int = int(_bc.state.phase) if _bc != null and _bc.state != null else -1
				if bp == BattlePhase.Kind.CLAIM:
					return false
				_reward_claim_seen_open = true
				# context boundary 用 candidate snap_seq 对齐本事务内下一公开序号
				var term0: Dictionary = rw.mark_claim_terminal({
					"context_boundary_server_seq": maxi(aa_seq + 1, 1),
				})
				if not bool(term0.get("ok", false)):
					return false
		elif String(res.get("kind", "")) == "REWARD_WINDOW_CLOSING" \
				and bool(res.get("idempotent", false)):
			# 幂等 CLOSING：不重复发事件，仍刷新 CLAIM 可见性
			if _bc != null:
				for s2 in range(4):
					_bc.decision_context_for_seat(s2)
			if _claim_or_rob_window_open():
				_reward_claim_seen_open = true
	return true


## 兼容：journal 已含 aa_seq 时补消费（仅当预消费路径未用）。优先走 preconsume。
func _reward_on_action_applied(action: Action, aa_seq: int) -> bool:
	var rw: RewardWindowModule = _reward_module()
	if rw == null or action == null:
		return true
	if rw.phase != RewardWindowModule.PHASE_OPEN \
			and rw.phase != RewardWindowModule.PHASE_CLOSING:
		return true
	# 若 public_events 已含该 aa_seq 的 ACTION_APPLIED，则仅处理弃牌幂等（不重复 append）
	if _reward_public_has_aa_seq(aa_seq):
		if action.kind == "DISCARD" or action.kind == "RIICHI":
			var is_ai2: bool = not _is_human(int(action.seat))
			var res2: Dictionary = rw.on_discard_applied({
				"server_seq": aa_seq,
				"seat": int(action.seat),
				"kind": str(action.kind),
				"now_ms": _reward_now_ms(),
				"is_ai": is_ai2,
			})
			if not bool(res2.get("ok", false)):
				return false
			# 预消费路径已处理 CLOSING 发布；此处仅幂等 true
		return true
	# 从 journal 取已提交 AA 再 append（旧路径兜底）
	if not _reward_append_journal_event(aa_seq):
		return false
	if action.kind == "DISCARD" or action.kind == "RIICHI":
		var is_ai: bool = not _is_human(int(action.seat))
		var res: Dictionary = rw.on_discard_applied({
			"server_seq": aa_seq,
			"seat": int(action.seat),
			"kind": str(action.kind),
			"now_ms": _reward_now_ms(),
			"is_ai": is_ai,
		})
		if not bool(res.get("ok", false)):
			return false
		if String(res.get("kind", "")) == "REWARD_WINDOW_CLOSING" \
				and not bool(res.get("idempotent", false)):
			_reward_claim_seen_open = false
			if not try_publish_business_event(
				"REWARD_WINDOW_CLOSING", res["payload"] as Dictionary
			):
				return false
			if _bc != null:
				for s in range(4):
					_bc.decision_context_for_seat(s)
			if _claim_or_rob_window_open():
				_reward_claim_seen_open = true
			else:
				var bp: int = int(_bc.state.phase) if _bc != null and _bc.state != null else -1
				if bp == BattlePhase.Kind.CLAIM:
					return false
				_reward_claim_seen_open = true
				var term0: Dictionary = rw.mark_claim_terminal({
					"context_boundary_server_seq": maxi(_server_seq, 1),
				})
				if not bool(term0.get("ok", false)):
					return false
	return true


func _reward_public_has_aa_seq(aa_seq: int) -> bool:
	var rw: RewardWindowModule = _reward_module()
	if rw == null:
		return false
	for ev in rw.get("_public_events") as Array:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = ev
		if str(d.get("kind", "")) == "ACTION_APPLIED" and int(d.get("server_seq", -1)) == aa_seq:
			return true
	return false


func _reward_append_journal_event(server_seq: int) -> bool:
	var rw: RewardWindowModule = _reward_module()
	if rw == null:
		return true
	if _journals.is_empty():
		return true
	var journal: Array = _journals[0] as Array
	for ne_v in journal:
		if not (ne_v is NetworkedEvent):
			continue
		var ne: NetworkedEvent = ne_v as NetworkedEvent
		if int(ne.server_seq) != server_seq:
			continue
		if ne.kind != "ACTION_APPLIED" and ne.kind != "CLAIM_WINDOW":
			continue
		var raw: Dictionary = ne.to_dict()
		var verified: NetworkedEvent = NetworkedEvent.from_dict(raw)
		if verified == null:
			return false
		var ap: Dictionary = rw.append_public_event(verified.to_dict())
		if not bool(ap.get("ok", false)):
			# AFTER_CONTEXT_BOUNDARY 等非致命边界可忽略后续事件
			if String(ap.get("reason", "")) == "AFTER_CONTEXT_BOUNDARY":
				return true
			return false
		return true
	return true


## 仅在真实 CLAIM 终态（曾见开放窗且现已关闭）或 scoring close 路径冻结 context。
## 禁止把「当前无 DecisionWindow」无条件等同 claim terminal（避免 24 弃后 CLAIM 尚未打开就放行）。
func _reward_try_mark_claim_terminal_if_ready() -> bool:
	var rw: RewardWindowModule = _reward_module()
	if rw == null or rw.phase != RewardWindowModule.PHASE_CLOSING:
		return true
	if rw.claim_is_terminal():
		return true
	# 和牌已成立：不得标 claim terminal（会导向 FULL_GRANT）
	if _bc != null and bool(_bc.get("_settled")):
		return true
	if _claim_or_rob_window_open():
		_reward_claim_seen_open = true
		return true
	# 仅当本窗 CLOSING 后确实开过 CLAIM 且现已关闭，才视为 CLAIM 终态
	if not _reward_claim_seen_open:
		return true
	var term: Dictionary = rw.mark_claim_terminal({
		"context_boundary_server_seq": maxi(_server_seq, 1),
	})
	return bool(term.get("ok", false))


func _reward_try_release_barrier() -> bool:
	var rw: RewardWindowModule = _reward_module()
	if rw == null:
		return true
	if rw.phase != RewardWindowModule.PHASE_CLOSING:
		return true
	if not _reward_try_mark_claim_terminal_if_ready():
		return false
	if not rw.claim_is_terminal():
		return true
	# 禁止伪造 deadline：仅 all-terminal 或真实 now>=deadline
	if not rw.barrier_released(_reward_now_ms()):
		return true
	# 屏障已释放：必须 settle 成功（或幂等）；SCORE/ASSIGN 等失败 fail-closed
	var settled: Dictionary = rw.try_settle({"now_ms": _reward_now_ms()})
	if not bool(settled.get("ok", false)):
		return false
	if bool(settled.get("idempotent", false)):
		return true
	if not try_publish_business_event(
		"REWARD_WINDOW_SETTLED", settled["payload"] as Dictionary
	):
		return false
	# #253：同一事务内 ITEM_GRANTED + DISARM（#252 不发 grant）
	var matrix: Array = settled.get("matrix", [])
	if not _item_after_settled(settled["payload"] as Dictionary, matrix):
		return false
	# 仅同局满 24 FULL_GRANT 开下一窗；hand 已 settled（流局/终场）不得伪造 OPEN
	if String(rw.window_exit) == RewardWindowModule.EXIT_FULL_GRANT \
			and (_bc == null or not bool(_bc.get("_settled"))):
		if not _maybe_open_reward_window():
			return false
	return true


func _reward_on_hand_result(hand_payload: Dictionary) -> bool:
	var rw: RewardWindowModule = _reward_module()
	if rw == null:
		return true
	if rw.phase != RewardWindowModule.PHASE_OPEN \
			and rw.phase != RewardWindowModule.PHASE_CLOSING:
		return true
	var outcome := String(hand_payload.get("outcome", ""))
	if outcome == "RON" or outcome == "TSUMO":
		var can: Dictionary = rw.cancel_by_win({"now_ms": _reward_now_ms()})
		if not bool(can.get("ok", false)):
			return false
		if bool(can.get("idempotent", false)):
			return true
		if not try_publish_business_event(
			"REWARD_WINDOW_CANCELLED", can["payload"] as Dictionary
		):
			return false
		return _item_after_cancelled(can["payload"] as Dictionary)
	# 流局：#376 优先 match owner 回调；否则 seam / payload；默认 match 继续 → FULL_GRANT
	var is_match_end: bool = _is_match_ended_for_hand(hand_payload)
	var result_seq: int = maxi(_server_seq, 1)
	# scoring close：结果判定事务内 claim_is_terminal=true（无 CLAIM 路径）
	_reward_claim_seen_open = true
	var sc: Dictionary = rw.begin_scoring_close({
		"result_server_seq": result_seq,
		"now_ms": _reward_now_ms(),
		"is_match_end": is_match_end,
	})
	if not bool(sc.get("ok", false)):
		return false
	for eff in sc.get("effects", []):
		if typeof(eff) != TYPE_DICTIONARY:
			continue
		var kind := String(eff.get("kind", ""))
		if kind.is_empty():
			continue
		if not try_publish_business_event(kind, eff["payload"] as Dictionary):
			return false
	# 无 utterance 或全终态时可立即 settle；否则等待 advance_reward_time
	if not rw.barrier_released(_reward_now_ms()):
		return true
	var settled2: Dictionary = rw.try_settle({"now_ms": _reward_now_ms()})
	if not bool(settled2.get("ok", false)):
		return false
	if bool(settled2.get("idempotent", false)):
		return true
	if not try_publish_business_event(
		"REWARD_WINDOW_SETTLED", settled2["payload"] as Dictionary
	):
		return false
	var matrix2: Array = settled2.get("matrix", [])
	return _item_after_settled(settled2["payload"] as Dictionary, matrix2)
