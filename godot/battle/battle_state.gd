class_name BattleState

const MAX_EVENT_CHAIN_DEPTH := 16
const STARTING_SCORE := 25000

var event_chain_depth: int = 0
var scores: Array[int] = [STARTING_SCORE, STARTING_SCORE, STARTING_SCORE, STARTING_SCORE]
var furiten_flags: Array[bool] = [false, false, false, false]
var ron_cancelled: Array[bool] = [false, false, false, false]
var revealed_tiles: Array = []
var haitei_forced_seat: int = -1
