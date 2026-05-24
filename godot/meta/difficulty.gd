class_name Difficulty

enum Level {
	NORMAL,
	HARD,
	LUNATIC,
}

static func display_name(level: int) -> String:
	match level:
		Level.NORMAL: return "普通"
		Level.HARD: return "困难"
		Level.LUNATIC: return "狂气"
	return "?"

static func description(level: int) -> String:
	match level:
		Level.NORMAL: return "标准起始 HP，AI 使用基础策略。推荐新手。"
		Level.HARD: return "起始 HP -1，AI 使用高级策略，Boss 增强。"
		Level.LUNATIC: return "起始 HP -2，AI 使用向听分析，Boss 双倍增强，商店涨价。"
	return ""

static func hp_modifier(level: int) -> int:
	match level:
		Level.NORMAL: return 0
		Level.HARD: return -1
		Level.LUNATIC: return -2
	return 0

static func use_heuristic_ai(level: int) -> bool:
	return level >= Level.HARD

static func use_shanten_ai(level: int) -> bool:
	return level >= Level.LUNATIC

static func shop_price_multiplier(level: int) -> float:
	match level:
		Level.NORMAL: return 1.0
		Level.HARD: return 1.0
		Level.LUNATIC: return 1.5
	return 1.0

static func color(level: int) -> Color:
	match level:
		Level.NORMAL: return Color(0.4, 0.8, 0.4)
		Level.HARD: return Color(1.0, 0.6, 0.2)
		Level.LUNATIC: return Color(1.0, 0.2, 0.2)
	return Color.WHITE
