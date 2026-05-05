class_name GameConfig
extends Node

# 游戏配置
var config_data: Dictionary = {
	"game_name": "麻将游戏",
	"version": "0.5.0",
	"max_players": 4,
	"initial_hand_size": 13,
	"max_hand_size": 14,
	"animation_speed": 0.3,
	"enable_sound": true,
	"enable_music": true,
	"debug_mode": false,
	"window_width": 1280,
	"window_height": 720,
}

# 音频配置
var audio_config: Dictionary = {
	"master_volume": 1.0,
	"music_volume": 0.7,
	"sfx_volume": 0.8,
}

# 游戏难度
enum Difficulty { EASY, NORMAL, HARD, EXTREME }
var current_difficulty: Difficulty = Difficulty.NORMAL

func _ready() -> void:
	print("========== 游戏配置系统初始化 ==========")
	load_config()
	print("✓ 配置系统已加载")
	print("游戏版本: ", config_data.version)
	print("========================================")

func load_config() -> void:
	"""加载游戏配置"""
	# 这里可以从文件加载配置
	# 目前使用默认配置
	print("✓ 使用默认配置")

func save_config() -> void:
	"""保存游戏配置"""
	print("✓ 配置已保存")

func get_config_value(key: String, default_value = null):
	"""获取配置值"""
	if key in config_data:
		return config_data[key]
	return default_value

func set_config_value(key: String, value) -> void:
	"""设置配置值"""
	config_data[key] = value
	print("✓ 配置已更新: ", key, " = ", value)

func get_game_info() -> String:
	"""获取游戏信息"""
	var info = "\n"
	info += "游戏名称: " + config_data.game_name + "\n"
	info += "版本: " + config_data.version + "\n"
	info += "最大玩家数: " + str(config_data.max_players) + "\n"
	info += "初始手牌: " + str(config_data.initial_hand_size) + "张\n"
	return info

func set_difficulty(difficulty: Difficulty) -> void:
	"""设置游戏难度"""
	current_difficulty = difficulty
	var difficulty_names = ["简单", "普通", "困难", "极难"]
	print("✓ 难度已设置为: ", difficulty_names[difficulty])

func get_difficulty_multiplier() -> float:
	"""获取难度倍数"""
	match current_difficulty:
		Difficulty.EASY:
			return 0.5
		Difficulty.NORMAL:
			return 1.0
		Difficulty.HARD:
			return 1.5
		Difficulty.EXTREME:
			return 2.0
	return 1.0

func set_master_volume(volume: float) -> void:
	"""设置主音量"""
	audio_config.master_volume = clamp(volume, 0.0, 1.0)
	print("✓ 主音量已设置为: ", int(audio_config.master_volume * 100), "%")

func get_master_volume() -> float:
	"""获取主音量"""
	return audio_config.master_volume

func print_all_config() -> void:
	"""打印所有配置"""
	print("\n========== 游戏配置 ==========")
	for key in config_data:
		print(key, ": ", config_data[key])
	print("\n========== 音频配置 ==========")
	for key in audio_config:
		print(key, ": ", audio_config[key])
	print("==============================\n")
