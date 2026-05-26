class_name TextAnalyzer

const KEYWORDS: Dictionary = {
	Momentum.Attribute.DOMINATION: ["必胜", "绝对", "王者", "统治", "碾压", "无敌", "最强"],
	Momentum.Attribute.CALM: ["计算", "分析", "概率", "冷静", "观察", "读牌", "安全"],
	Momentum.Attribute.CUNNING: ["陷阱", "诱饵", "骗", "装", "阴", "暗算", "计谋"],
	Momentum.Attribute.PASSION: ["燃烧", "热血", "立直", "一发", "勝負", "来吧", "全力"],
	Momentum.Attribute.MYSTIC: ["命运", "天意", "奇迹", "预言", "感应", "直觉", "冥冥"],
}

static func analyze(text: String) -> Dictionary:
	var result: Dictionary = {}
	for attr in KEYWORDS:
		result[attr] = 0.0
	if text.is_empty():
		return result
	var lower: String = text.to_lower()
	for attr in KEYWORDS:
		var keywords: Array = KEYWORDS[attr]
		var hits: int = 0
		for kw in keywords:
			if lower.contains(kw):
				hits += 1
		result[attr] = clampf(float(hits) / 3.0, 0.0, 1.0)
	return result
