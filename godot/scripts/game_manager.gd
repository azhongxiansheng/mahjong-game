extends Node

## 游戏全局管理器（单例）
## 负责管理用户信息、游戏状态等全局数据

var user_data: Dictionary = {}
var is_logged_in: bool = false

func _ready() -> void:
	print("🎮 GameManager 已初始化")

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
