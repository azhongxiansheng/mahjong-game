class_name CharacterPresentationCatalog extends RefCounted

const Profile := preload(
	"res://presentation/characters/character_presentation_profile.gd")


static func active_profiles() -> Array:
	return [
		Profile.new(
			&"qiu_jue",
			&"char_kaiji_passive_v1",
			"🔥 {skill_name}　+2 番（点数 < 15000）",
			Color("ffb347"),
			true,
		),
		Profile.new(
			&"lin_yeche",
			&"char_akagi_passive_v1",
			"👁 {skill_name}　透视下家手牌",
			Color("8fb8ff"),
			true,
			"读脊",
		),
		Profile.new(
			&"bai_touli",
			&"char_washizu_passive_v1",
			"🔮 {skill_name}　看破三家各两张手牌",
			Color("d7b8ff"),
			true,
			"镜华",
		),
		Profile.new(
			&"an_cheng",
			&"char_awai_passive_v1",
			"🫧 {skill_name}　净化振听并预知下一摸",
			Color("9de8df"),
			true,
			"",
			"预知",
		),
		Profile.new(
			&"hua_ling",
			&"char_saki_passive_v1",
			"✦ {skill_name}　+2 Dora",
			Color("7fe0c3"),
			true,
		),
	]
