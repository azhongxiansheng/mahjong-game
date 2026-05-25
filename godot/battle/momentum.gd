class_name Momentum

enum Attribute { DOMINATION, CALM, CUNNING, PASSION, MYSTIC }

const ATTRIBUTE_NAMES: Dictionary = {
	Attribute.DOMINATION: "霸气",
	Attribute.CALM: "冷静",
	Attribute.CUNNING: "狡猾",
	Attribute.PASSION: "热血",
	Attribute.MYSTIC: "神秘",
}

var scores: Dictionary = {
	Attribute.DOMINATION: 0.0,
	Attribute.CALM: 0.0,
	Attribute.CUNNING: 0.0,
	Attribute.PASSION: 0.0,
	Attribute.MYSTIC: 0.0,
}

var total_momentum: float = 0.0

# Step 1: call this first to set base scores from text analysis (replaces scores).
func apply_text_analysis(analysis: Dictionary) -> void:
	for attr in analysis:
		if scores.has(attr):
			scores[attr] = clampf(float(analysis[attr]), 0.0, 1.0)
	_recalculate_total()

# Step 2: call after apply_text_analysis to multiply by character affinity.
func apply_character_affinity(affinities: Dictionary) -> void:
	for attr in affinities:
		if scores.has(attr):
			scores[attr] *= float(affinities[attr])
	_recalculate_total()

func skill_effect_multiplier() -> float:
	if total_momentum < 0.3:
		return 1.0
	elif total_momentum < 0.6:
		return 1.25
	elif total_momentum < 0.8:
		return 1.5
	else:
		return 2.0

func _recalculate_total() -> void:
	var sum: float = 0.0
	for v in scores.values():
		sum += float(v)
	total_momentum = clampf(sum / scores.size(), 0.0, 1.0)

func reset() -> void:
	for key in scores:
		scores[key] = 0.0
	total_momentum = 0.0
