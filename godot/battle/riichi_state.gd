class_name RiichiState

# 一座位的立直状态（spec §5）。仅数据 + 简单 helper；状态机由调用方驱动。

var declared: bool = false
var declared_turn: int = -1
var ippatsu_window: bool = false
var double_riichi: bool = false
var riichi_stick_paid: bool = false
# 立直宣告时,刚弃出的那张牌在该 seat 的 discards_per_seat 中的索引。
# DiscardRiver 据此把该 tile 在弃牌河里旋转 90° — 日麻最标志性的视觉记号。
# 未声立直 = -1。
var riichi_discard_index: int = -1

func declare(turn: int, is_double: bool) -> void:
	declared = true
	declared_turn = turn
	double_riichi = is_double
	ippatsu_window = true

func consume_ippatsu() -> void:
	ippatsu_window = false

func pay_stick() -> void:
	riichi_stick_paid = true
