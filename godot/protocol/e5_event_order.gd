extends RefCounted

# E2-02（#232）E5 静态 fixture 偏序校验
#
# 纯函数：仅判断 kind 序列是否属于 ADR 合法路径族，并按 meta 约束
# FULL_GRANT / DISPLAY_ONLY 的 grant 次数与 grant_seats。
# 不是业务状态机；不发射事件、不维护窗口、不写库存 / active / pending。
# 无 class_name，不接入任何生产控制器。
#
# 路径用局部小解析器表达（非枚举少数完整数组）：
# - 满24 claim full-grant 或 cancel
# - 普通 cancel
# - 非终场流局
# - 终场 display
# - OPEN→CANCELLED
#
# kinds 元素与 meta keys 必须 typeof == TYPE_STRING（拒 StringName / 数字；禁止 str 静默转换）。

const _META_KEYS := {
	"settled_outcome": true,
	"grant_seats": true,
}
const _OUTCOMES := {
	"FULL_GRANT": true,
	"DISPLAY_ONLY": true,
}


## kinds: 事件 kind 字符串序列；meta 可选，如 { "settled_outcome": "FULL_GRANT" }
static func is_legal_sequence(kinds: Array, meta: Dictionary = {}) -> bool:
	var seq: Array = []
	for k in kinds:
		# 禁止 StringName / 数字 / 其它类型经 str() 静默进入路径匹配
		if typeof(k) != TYPE_STRING:
			return false
		seq.append(k)

	if not _is_legal_path(seq):
		return false
	return _meta_constraints_ok(seq, meta)


# ---- 路径小解析器 ----

static func _is_legal_path(seq: Array) -> bool:
	return (
		_match_full24_claim(seq)
		or _match_ordinary_cancel(seq)
		or _match_non_terminal_draw(seq)
		or _match_terminal_display(seq)
		or _match_open_cancel(seq)
	)


## 满24：ACTION→CLOSING→CLAIM→ACTION → (SETTLED+4×GRANT+tail | CANCEL+cancel-tail)
static func _match_full24_claim(seq: Array) -> bool:
	var i := 0
	if not _at(seq, i, "ACTION_APPLIED"):
		return false
	i += 1
	if not _at(seq, i, "REWARD_WINDOW_CLOSING"):
		return false
	i += 1
	if not _at(seq, i, "CLAIM_WINDOW"):
		return false
	i += 1
	if not _at(seq, i, "ACTION_APPLIED"):
		return false
	i += 1
	if i >= seq.size():
		return false
	if seq[i] == "REWARD_WINDOW_SETTLED":
		i += 1
		if not _eat_n(seq, i, "ITEM_GRANTED", 4):
			return false
		i += 4
		return _match_full24_post_grant_tail(seq, i)
	if seq[i] == "REWARD_WINDOW_CANCELLED":
		return _match_cancel_tail(seq, i)
	return false


## FULL_GRANT 后：可直接结束，或 0..4 DISARM → OPEN → 0..4 ARM
static func _match_full24_post_grant_tail(seq: Array, i: int) -> bool:
	if i == seq.size():
		return true
	var j: int = _consume_ability_run(seq, i, "CHARACTER_ABILITY_DISARMED", 4)
	if j < 0:
		return false
	if not _at(seq, j, "REWARD_WINDOW_OPENED"):
		return false
	j += 1
	var k: int = _consume_ability_run(seq, j, "CHARACTER_ABILITY_ARMED", 4)
	if k < 0:
		return false
	return k == seq.size()


## 普通 / 第24弃和牌 cancel：CANCELLED → 0..4 DISARM → HAND_SETTLED → 可选 MATCH_SETTLED
static func _match_ordinary_cancel(seq: Array) -> bool:
	return _match_cancel_tail(seq, 0)


static func _match_cancel_tail(seq: Array, i: int) -> bool:
	if not _at(seq, i, "REWARD_WINDOW_CANCELLED"):
		return false
	i += 1
	var j: int = _consume_ability_run(seq, i, "CHARACTER_ABILITY_DISARMED", 4)
	if j < 0:
		return false
	if not _at(seq, j, "HAND_SETTLED"):
		return false
	j += 1
	if j == seq.size():
		return true
	if _at(seq, j, "MATCH_SETTLED") and j + 1 == seq.size():
		return true
	return false


## 非终场流局：CLOSING→SETTLED→4×GRANT→0..4 DISARM→HAND_SETTLED→OPEN→0..4 ARM
static func _match_non_terminal_draw(seq: Array) -> bool:
	var i := 0
	if not _at(seq, i, "REWARD_WINDOW_CLOSING"):
		return false
	i += 1
	if not _at(seq, i, "REWARD_WINDOW_SETTLED"):
		return false
	i += 1
	if not _eat_n(seq, i, "ITEM_GRANTED", 4):
		return false
	i += 4
	var j: int = _consume_ability_run(seq, i, "CHARACTER_ABILITY_DISARMED", 4)
	if j < 0:
		return false
	if not _at(seq, j, "HAND_SETTLED"):
		return false
	j += 1
	if not _at(seq, j, "REWARD_WINDOW_OPENED"):
		return false
	j += 1
	var k: int = _consume_ability_run(seq, j, "CHARACTER_ABILITY_ARMED", 4)
	if k < 0:
		return false
	return k == seq.size()


## 终场 DISPLAY_ONLY：CLOSING→SETTLED→0..4 DISARM→HAND_SETTLED→MATCH_SETTLED（零 grant）
static func _match_terminal_display(seq: Array) -> bool:
	var i := 0
	if not _at(seq, i, "REWARD_WINDOW_CLOSING"):
		return false
	i += 1
	if not _at(seq, i, "REWARD_WINDOW_SETTLED"):
		return false
	i += 1
	# 禁止 grant 插入此路径
	if i < seq.size() and seq[i] == "ITEM_GRANTED":
		return false
	var j: int = _consume_ability_run(seq, i, "CHARACTER_ABILITY_DISARMED", 4)
	if j < 0:
		return false
	if not _at(seq, j, "HAND_SETTLED"):
		return false
	j += 1
	if not _at(seq, j, "MATCH_SETTLED"):
		return false
	j += 1
	return j == seq.size()


static func _match_open_cancel(seq: Array) -> bool:
	return (
		seq.size() == 2
		and seq[0] == "REWARD_WINDOW_OPENED"
		and seq[1] == "REWARD_WINDOW_CANCELLED"
	)


# ---- meta fail-closed ----

static func _meta_constraints_ok(seq: Array, meta: Dictionary) -> bool:
	# keys 必须 TYPE_STRING；仅允许 settled_outcome / grant_seats；未知键拒绝
	for k in meta.keys():
		if typeof(k) != TYPE_STRING:
			return false
		if not _META_KEYS.has(k):
			return false

	var has_outcome := meta.has("settled_outcome")
	var has_seats := meta.has("grant_seats")
	var outcome: String = ""

	if has_outcome:
		if typeof(meta["settled_outcome"]) != TYPE_STRING:
			return false
		outcome = meta["settled_outcome"]
		if not _OUTCOMES.has(outcome):
			return false

	var grant_count := _count_kind(seq, "ITEM_GRANTED")

	if has_seats:
		# grant_seats 存在 ⇒ 必须 outcome=FULL_GRANT
		if outcome != "FULL_GRANT":
			return false
		var seats: Variant = meta["grant_seats"]
		if typeof(seats) != TYPE_ARRAY:
			return false
		var arr: Array = seats as Array
		if arr.size() != 4:
			return false
		var expected := [0, 1, 2, 3]
		for i in range(4):
			# 不得 str/int/float 静默强转
			if typeof(arr[i]) != TYPE_INT:
				return false
			if arr[i] != expected[i]:
				return false

	if has_outcome:
		# settled_outcome 语义绑定 SETTLED：序列必须恰含一次 REWARD_WINDOW_SETTLED
		# （cancel / open-cancel 无 SETTLED，不得挂 FULL_GRANT / DISPLAY_ONLY）
		if _count_kind(seq, "REWARD_WINDOW_SETTLED") != 1:
			return false
		if outcome == "FULL_GRANT":
			if grant_count != 4:
				return false
		elif outcome == "DISPLAY_ONLY":
			if grant_count != 0:
				return false

	# 空 meta：仅路径层约束
	return true


# ---- 解析 helpers ----

static func _at(seq: Array, i: int, kind: String) -> bool:
	return i < seq.size() and seq[i] == kind


static func _eat_n(seq: Array, i: int, kind: String, n: int) -> bool:
	if i + n > seq.size():
		return false
	for j in range(n):
		if seq[i + j] != kind:
			return false
	return true


## 消费 0..max_n 次 kind；超过 max_n 返回 -1；否则返回新下标
static func _consume_ability_run(seq: Array, i: int, kind: String, max_n: int) -> int:
	var count := 0
	while i < seq.size() and seq[i] == kind:
		count += 1
		if count > max_n:
			return -1
		i += 1
	return i


static func _count_kind(seq: Array, kind: String) -> int:
	var n := 0
	for k in seq:
		if k == kind:
			n += 1
	return n
