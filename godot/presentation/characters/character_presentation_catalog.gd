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
	]
