extends Node

## 游戏全局管理器（单例）
## 负责管理用户信息、游戏状态等全局数据

var user_data: Dictionary = {}
var is_logged_in: bool = false

func _ready() -> void:
	print("🎮 GameManager 已初始化")
	# #257：导出 release app 不支持 --script；仅精确 download/check 门闩触发 smoke。
	var e7_mode := OS.get_environment("E7_257_MODE")
	if e7_mode == "download" or e7_mode == "check":
		var root_env := OS.get_environment("E7_257_MODELS_ROOT")
		if root_env.is_empty() or not root_env.begins_with("/tmp/mahjong-e7-257-"):
			push_error("E7_257_MODE set but E7_257_MODELS_ROOT invalid; skip smoke gate")
			return
		var runner: Node = load("res://tools/e7_257_model_smoke_runner.gd").new()
		runner.name = "E7257ModelSmokeRunner"
		get_tree().root.call_deferred("add_child", runner)


## 设置用户数据
func set_user_data(data: Dictionary) -> void:
	user_data = data
	is_logged_in = true
	print("✅ 用户数据已保存: ", data)

## 获取用户数据
func get_user_data() -> Dictionary:
	return user_data

## 获取用户ID
func get_user_id() -> String:
	return user_data.get("user_id", "")

## 获取用户昵称
func get_nickname() -> String:
	return user_data.get("nickname", "未知玩家")

## 获取登录类型
func get_login_type() -> String:
	return user_data.get("login_type", "guest")

## 是否已登录
func is_user_logged_in() -> bool:
	return is_logged_in

## 登出
func logout() -> void:
	user_data.clear()
	is_logged_in = false
	print("👋 用户已登出")
