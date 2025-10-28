class_name GameRecord

# 游戏记录类
# 记录每场游戏的详细信息

var record_id: String         # 记录ID（唯一标识）
var game_id: String           # 游戏ID
var user_id: String           # 用户ID
var timestamp: int            # 游戏时间戳
var result: String            # 游戏结果 (win/loss/draw)
var fan: int                  # 番数
var points_change: int        # 积分变化
var opponent_ids: Array       # 对手ID列表
var game_duration: int        # 游戏时长（秒）
var notes: String             # 备注信息

func _init(p_user_id: String = "", p_game_id: String = "") -> void:
	"""初始化游戏记录"""
	record_id = generate_record_id()
	game_id = p_game_id
	user_id = p_user_id
	timestamp = Time.get_ticks_msec()
	result = ""
	fan = 0
	points_change = 0
	opponent_ids = []
	game_duration = 0
	notes = ""

static func generate_record_id() -> String:
	"""生成唯一记录ID"""
	var timestamp = Time.get_ticks_msec()
	var random_part = randi() % 1000000
	return "record_%d_%d" % [timestamp, random_part]

func set_game_result(p_result: String, p_fan: int = 0, p_points_change: int = 0) -> void:
	"""设置游戏结果"""
	if p_result not in ["win", "loss", "draw"]:
		print("GameRecord: 无效的游戏结果 %s" % p_result)
		return
	
	result = p_result
	fan = p_fan
	points_change = p_points_change
	print("GameRecord: 游戏结果已设置 - %s (%d番, %+d积分)" % [result, fan, points_change])

func add_opponent(opponent_id: String) -> void:
	"""添加对手"""
	if opponent_id not in opponent_ids:
		opponent_ids.append(opponent_id)

func set_game_duration(duration_seconds: int) -> void:
	"""设置游戏时长"""
	game_duration = duration_seconds

func add_note(note: String) -> void:
	"""添加备注"""
	notes = note

func get_formatted_time() -> String:
	"""获取格式化的时间"""
	var time_dict = Time.get_datetime_dict_from_system(false)
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		time_dict.year,
		time_dict.month,
		time_dict.day,
		time_dict.hour,
		time_dict.minute,
		time_dict.second
	]

func get_record_info() -> Dictionary:
	"""获取记录信息字典"""
	return {
		"record_id": record_id,
		"game_id": game_id,
		"user_id": user_id,
		"timestamp": timestamp,
		"result": result,
		"fan": fan,
		"points_change": points_change,
		"opponent_ids": opponent_ids,
		"game_duration": game_duration,
		"notes": notes
	}

func get_summary_string() -> String:
	"""获取记录摘要字符串"""
	var opponent_str = " vs ".join(opponent_ids) if opponent_ids.size() > 0 else "未知"
	return "游戏%s: [%s] %s | %d番 | %+d积分 | 对手: %s" % [
		record_id,
		result.to_upper(),
		get_formatted_time(),
		fan,
		points_change,
		opponent_str
	]

func to_json() -> String:
	"""转换为JSON字符串"""
	return JSON.stringify(get_record_info())

static func from_dict(data: Dictionary) -> GameRecord:
	"""从字典创建游戏记录"""
	var record = GameRecord.new(
		data.get("user_id", ""),
		data.get("game_id", "")
	)
	record.record_id = data.get("record_id", record.record_id)
	record.timestamp = data.get("timestamp", record.timestamp)
	record.result = data.get("result", "")
	record.fan = data.get("fan", 0)
	record.points_change = data.get("points_change", 0)
	record.opponent_ids = data.get("opponent_ids", []) as Array
	record.game_duration = data.get("game_duration", 0)
	record.notes = data.get("notes", "")
	return record
