class_name RewardWindowModule extends RefCounted

# E2-04：欢乐场 RewardWindow 生产模块（最小对象）。
# 不推进 phase、不发射 REWARD_WINDOW_*、不实现 E5 三出口业务。

const PHASE_IDLE := &"IDLE"

var phase: StringName = PHASE_IDLE
var window_id: String = ""
var window_exit = null
