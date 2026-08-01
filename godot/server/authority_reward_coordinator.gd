class_name AuthorityRewardCoordinator extends RefCounted

# ARCH-02 #392（spec 2026-07-29 §5.3）：权威奖励协调组件（第四片）。
# 唯一职责：奖励窗运行时标量状态的所有权（权威时钟、CLAIM 可见性、
# 延迟 HAND_SETTLED、终场三态）+ 只读屏障判定 + 跨局/硬重置。
#
# 明确不承担（仍属 façade）：
# - 事件发布与 journal 追加（需 _room_id / _journals / publish 链）
# - 道具触发编排（_item_after_opened / _after_settled / _after_cancelled）
# - advance_reward_time 的整事务边界（freeze/rollback 跨多组件）
# - mode_modules 所有权：它由 practice_session_launcher / headless_room_session
#   外部写入，且同时承载 item_inventory 与 viewer 模块，归属 façade；
#   本组件一律以 RewardWindowModule 入参形式接收，不持有 bundle。

# #247/#252：权威时钟基准（非墙钟；调用方不得自行推进）。
const CLOCK_BASE_MS := 1_700_000_000_000

var now_ms: int = CLOCK_BASE_MS
var claim_seen_open: bool = false
var hand_settled_deferred: bool = false
## 终场三态：null = 未判定（走规则推导）；true/false = seam 显式指定。
## 禁止标注为 bool —— null 态承载「未判定」语义（LLS 2456 seam 路径）。
var match_ended = null


## 权威时钟单调性校验：非 int 或回退一律拒绝。
static func is_int_ms(v: Variant) -> bool:
	return typeof(v) == TYPE_INT


func is_closing(rw: RewardWindowModule) -> bool:
	return rw != null and rw.phase == RewardWindowModule.PHASE_CLOSING


## 是否允许下一普通摸牌/出牌/TURN_PROMPT（fail-closed）。
## 未 settle 的 CLOSING 不得越过——即使 barrier 已 released 但 try_settle 失败。
func allows_normal_progress(rw: RewardWindowModule) -> bool:
	if rw == null:
		return true
	return rw.phase != RewardWindowModule.PHASE_CLOSING


## CLOSING 期间见过开放的 CLAIM/ROB 窗则记账（claim terminal 判定前置）。
func note_claim_visibility(rw: RewardWindowModule, claim_open: bool) -> void:
	if is_closing(rw) and claim_open:
		claim_seen_open = true


func public_has_aa_seq(rw: RewardWindowModule, aa_seq: int) -> bool:
	if rw == null:
		return false
	for ev in rw.get("_public_events") as Array:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = ev
		if str(d.get("kind", "")) == "ACTION_APPLIED" \
				and int(d.get("server_seq", -1)) == aa_seq:
			return true
	return false


func hard_reset(rw: RewardWindowModule) -> void:
	if rw != null:
		rw.hard_reset()
	now_ms = CLOCK_BASE_MS
	claim_seen_open = false
	hand_settled_deferred = false


## 跨局 start：清 CLAIM/延迟/终场标记，保留权威时钟（时钟跨局单调）。
func reset_for_new_hand() -> void:
	claim_seen_open = false
	hand_settled_deferred = false
	match_ended = null


## 终场已显式判定则返回该值；未判定（null）返回 false 由调用方走规则推导。
func match_ended_is_true() -> bool:
	if typeof(match_ended) == TYPE_BOOL:
		return bool(match_ended)
	return false


func match_ended_decided() -> bool:
	return typeof(match_ended) == TYPE_BOOL
