class_name BattlePhase

# 一局对战的 4 个子阶段（spec §5）。

enum Kind { DRAW, DISCARD, CLAIM, SETTLE }

static func phase_name(k: int) -> String:
	match k:
		Kind.DRAW: return "DRAW"
		Kind.DISCARD: return "DISCARD"
		Kind.CLAIM: return "CLAIM"
		Kind.SETTLE: return "SETTLE"
	return "UNKNOWN"
