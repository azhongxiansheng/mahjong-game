extends GutTest

func test_text_analyzer_detects_domination():
	var result := TextAnalyzer.analyze("必胜！绝对不会输！")
	assert_true(result[Momentum.Attribute.DOMINATION] > 0.0, "should detect domination keywords")

func test_text_analyzer_empty_text():
	var result := TextAnalyzer.analyze("")
	assert_eq(result[Momentum.Attribute.DOMINATION], 0.0)
	assert_eq(result[Momentum.Attribute.CALM], 0.0)

func test_momentum_skill_multiplier_low():
	var m := Momentum.new()
	assert_eq(m.skill_effect_multiplier(), 1.0, "no momentum = 1.0x")

func test_momentum_skill_multiplier_high():
	var m := Momentum.new()
	m.apply_text_analysis({
		Momentum.Attribute.DOMINATION: 1.0,
		Momentum.Attribute.CALM: 1.0,
		Momentum.Attribute.CUNNING: 1.0,
		Momentum.Attribute.PASSION: 1.0,
		Momentum.Attribute.MYSTIC: 1.0,
	})
	assert_eq(m.skill_effect_multiplier(), 2.0, "max momentum = 2.0x")

func test_momentum_reset():
	var m := Momentum.new()
	m.apply_text_analysis({Momentum.Attribute.DOMINATION: 1.0})
	m.reset()
	assert_eq(m.total_momentum, 0.0)
	assert_eq(m.skill_effect_multiplier(), 1.0)

func test_character_affinity():
	var m := Momentum.new()
	m.apply_text_analysis({
		Momentum.Attribute.DOMINATION: 0.5,
		Momentum.Attribute.CALM: 0.5,
	})
	m.apply_character_affinity({
		Momentum.Attribute.DOMINATION: 2.0,
		Momentum.Attribute.CALM: 0.5,
	})
	assert_true(m.scores[Momentum.Attribute.DOMINATION] > m.scores[Momentum.Attribute.CALM],
		"domination should be boosted by affinity")
