class_name TileId

# Suit enum
enum Suit { MAN, PIN, SOU, HONOR }

# 34 个牌名整数常量（与 ALL 数组下标对应）
const W1 = 0; const W2 = 1; const W3 = 2; const W4 = 3; const W5 = 4
const W6 = 5; const W7 = 6; const W8 = 7; const W9 = 8
const T1 = 9; const T2 = 10; const T3 = 11; const T4 = 12; const T5 = 13
const T6 = 14; const T7 = 15; const T8 = 16; const T9 = 17
const S1 = 18; const S2 = 19; const S3 = 20; const S4 = 21; const S5 = 22
const S6 = 23; const S7 = 24; const S8 = 25; const S9 = 26
const E = 27           # 东
const S_WIND = 28      # 南
const W_WIND = 29      # 西
const N = 30           # 北
const HAKU = 31        # 白
const HATSU = 32       # 发
const CHUN = 33        # 中

const ALL: Array[int] = [
	0,1,2,3,4,5,6,7,8,
	9,10,11,12,13,14,15,16,17,
	18,19,20,21,22,23,24,25,26,
	27,28,29,30,31,32,33,
]

static func suit(t: int) -> Suit:
	if t <= W9: return Suit.MAN
	if t <= T9: return Suit.PIN
	if t <= S9: return Suit.SOU
	return Suit.HONOR

static func number(t: int) -> int:
	# 数牌返回 1-9，字牌返回 0
	var s := suit(t)
	if s == Suit.HONOR: return 0
	return (t % 9) + 1

static func is_honor(t: int) -> bool:
	return t >= E

static func is_terminal(t: int) -> bool:
	# 老头：数牌的 1 和 9（不含字牌）
	if is_honor(t): return false
	var n := number(t)
	return n == 1 or n == 9

static func is_yaochu(t: int) -> bool:
	# 幺九：1、9、字牌
	return is_terminal(t) or is_honor(t)

static func is_simple(t: int) -> bool:
	# 中张：2-8 of 数牌
	if is_honor(t): return false
	var n := number(t)
	return n >= 2 and n <= 8

static func next_for_dora(t: int) -> int:
	# Dora 指示牌的下一张
	var s := suit(t)
	match s:
		Suit.MAN, Suit.PIN, Suit.SOU:
			var n := number(t)
			return t - (n - 1) + (n % 9)  # 1->2,...,8->9,9->1
		Suit.HONOR:
			# 风牌循环 E->S->W->N->E
			if t >= E and t <= N:
				return E + (t - E + 1) % 4
			# 三元牌循环 白->发->中->白
			return HAKU + (t - HAKU + 1) % 3
	return t
