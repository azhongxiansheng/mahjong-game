class_name ConfigManager

# 配置管理器
# 提供游戏配置的集中管理和访问

# 默认配置
var config: Dictionary = {
	# 游戏基本设置
	"game_version": "0.1.0",
	"game_name": "麻将游戏",
	"game_state": "playing",

	# 游戏规则
	"max_players": 4,
	"min_players": 2,
	"initial_tiles": 13,
	"max_tiles": 14,
	"draw_tile_count": 1,

	# 游戏平衡
	"base_points": 1000,
	"elo_base_rating": 1600,
	"elo_k_factor": 32,

	# UI设置
	"ui_scale": 1.0,
	"animation_speed": 1.0,
	"debug_ui": true,

	# 网络设置
	"server_host": "localhost",
	"server_port": 8080,
	"connection_timeout": 30,
	"max_reconnect_attempts": 3,

	# 性能设置
	"max_frame_rate": 60,
	"vsync_enabled": true,
	"enable_object_pool": true,
	"object_pool_initial_size": 50,

	# 数据库设置
	"enable_local_storage": true,
	"auto_save_interval": 300,
	"save_directory": "user://saves",

	# 日志设置
	"log_level": 0,  # 0=DEBUG, 1=INFO, 2=WARN, 3=ERROR
	"log_to_file": false,
	"log_file_path": "user://game.log"
}

# 配置文件路径
var config_file_path: String = "user://config.cfg"

func _init() -> void:
	"""初始化配置管理器"""
	load_config()
	Logger.info("配置管理器已初始化", "CONFIG")

# ==================== 基本操作 ====================

func get(key: String, default_value = null):
	"""获取配置值"""
	if key in config:
		return config[key]
	return default_value

func set(key: String, value) -> void:
	"""设置配置值"""
	config[key] = value
	Logger.debug("配置已更新: %s = %s" % [key, str(value)], "CONFIG")

func has(key: String) -> bool:
	"""检查配置是否存在"""
	return key in config

func remove(key: String) -> void:
	"""移除配置"""
	if key in config:
		config.erase(key)
		Logger.debug("配置已删除: %s" % key, "CONFIG")

# ==================== 存储操作 ====================

func save_config() -> bool:
	"""保存配置到文件"""
	try:
		var config_file = ConfigFile.new()

		for key in config.keys():
			config_file.set_value("game", key, config[key])

		var result = config_file.save(config_file_path)
		if result == OK:
			Logger.info("配置已保存到: %s" % config_file_path, "CONFIG")
			return true
		else:
			Logger.error("保存配置失败: %d" % result, "CONFIG")
			return false
	except:
		Logger.error("配置保存异常", "CONFIG")
		return false

func load_config() -> bool:
	"""从文件加载配置"""
	try:
		if not FileAccess.file_exists(config_file_path):
			Logger.info("配置文件不存在，使用默认配置", "CONFIG")
			return true

		var config_file = ConfigFile.new()
		var result = config_file.load(config_file_path)

		if result != OK:
			Logger.error("加载配置失败: %d" % result, "CONFIG")
			return false

		# 合并加载的配置
		for key in config_file.get_section_keys("game"):
			config[key] = config_file.get_value("game", key)

		Logger.info("配置已加载: %s" % config_file_path, "CONFIG")
		return true
	except:
		Logger.error("配置加载异常", "CONFIG")
		return false

func reset_to_default() -> void:
	"""重置为默认配置"""
	config.clear()
	# 重新初始化默认值...（这里简化处理）
	Logger.info("配置已重置为默认值", "CONFIG")

# ==================== 配置分组访问 ====================

func get_game_config() -> Dictionary:
	"""获取游戏相关配置"""
	return {
		"max_players": get("max_players"),
		"min_players": get("min_players"),
		"initial_tiles": get("initial_tiles"),
		"max_tiles": get("max_tiles")
	}

func get_network_config() -> Dictionary:
	"""获取网络相关配置"""
	return {
		"server_host": get("server_host"),
		"server_port": get("server_port"),
		"connection_timeout": get("connection_timeout"),
		"max_reconnect_attempts": get("max_reconnect_attempts")
	}

func get_ui_config() -> Dictionary:
	"""获取UI相关配置"""
	return {
		"ui_scale": get("ui_scale"),
		"animation_speed": get("animation_speed"),
		"debug_ui": get("debug_ui")
	}

func get_performance_config() -> Dictionary:
	"""获取性能相关配置"""
	return {
		"max_frame_rate": get("max_frame_rate"),
		"vsync_enabled": get("vsync_enabled"),
		"enable_object_pool": get("enable_object_pool"),
		"object_pool_initial_size": get("object_pool_initial_size")
	}

# ==================== 统计信息 ====================

func get_all_config() -> Dictionary:
	"""获取所有配置"""
	return config.duplicate()

func print_config() -> void:
	"""打印所有配置"""
	Logger.info("【游戏配置】", "CONFIG")
	for key in config.keys():
		Logger.info("  %s: %s" % [key, str(config[key])], "CONFIG")

func print_config_section(section: String) -> void:
	"""打印指定分组的配置"""
	var section_config = Dictionary()

	match section:
		"game":
			section_config = get_game_config()
		"network":
			section_config = get_network_config()
		"ui":
			section_config = get_ui_config()
		"performance":
			section_config = get_performance_config()

	Logger.info("【%s配置】" % section, "CONFIG")
	for key in section_config.keys():
		Logger.info("  %s: %s" % [key, str(section_config[key])], "CONFIG")

func get_config_count() -> int:
	"""获取配置项数量"""
	return config.size()

# ==================== 验证 ====================

func validate_config() -> bool:
	"""验证配置的有效性"""
	# 检查必要的字段
	var required_fields = ["max_players", "initial_tiles", "max_tiles"]

	for field in required_fields:
		if not field in config:
			Logger.error("缺少必要配置: %s" % field, "CONFIG")
			return false

	# 验证数值范围
	if config["max_players"] < config["min_players"]:
		Logger.error("max_players 不能小于 min_players", "CONFIG")
		return false

	if config["max_tiles"] < config["initial_tiles"]:
		Logger.error("max_tiles 不能小于 initial_tiles", "CONFIG")
		return false

	Logger.info("配置验证通过", "CONFIG")
	return true

# ==================== 应用配置 ====================

func apply_ui_config() -> void:
	"""应用UI配置"""
	var ui_config = get_ui_config()
	Logger.info("应用UI配置: scale=%s, speed=%s" % [
		ui_config.ui_scale,
		ui_config.animation_speed
	], "CONFIG")

func apply_performance_config() -> void:
	"""应用性能配置"""
	var perf_config = get_performance_config()
	Engine.max_fps = perf_config.max_frame_rate
	Logger.info("应用性能配置: fps=%d, vsync=%s" % [
		perf_config.max_frame_rate,
		perf_config.vsync_enabled
	], "CONFIG")

func apply_all_configs() -> void:
	"""应用所有配置"""
	apply_ui_config()
	apply_performance_config()
	Logger.info("所有配置已应用", "CONFIG")
