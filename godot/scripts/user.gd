class_name User

# 用户账户管理类
# 管理用户的基本信息、认证和统计数据

var user_id: String           # 唯一用户ID
var username: String          # 用户名
var password_hash: String     # 密码哈希值
var email: String             # 邮箱
var created_at: int           # 创建时间戳
var last_login: int           # 最后登录时间戳
var is_active: bool           # 是否激活

func _init(p_username: String = "", p_email: String = "") -> void:
	"""初始化用户对象"""
	user_id = generate_user_id()
	username = p_username
	email = p_email
	password_hash = ""
	created_at = Time.get_ticks_msec()
	last_login = 0
	is_active = true

static func generate_user_id() -> String:
	"""生成唯一用户ID"""
	var timestamp = Time.get_ticks_msec()
	var random_part = randi() % 100000
	return "user_%d_%d" % [timestamp, random_part]

func set_password(password: String) -> void:
	"""设置并哈希密码"""
	if password.length() < 6:
		print("User: 密码长度至少6个字符")
		return
	
	password_hash = password.sha256_text()
	print("User: 密码已设置")

func verify_password(password: String) -> bool:
	"""验证密码"""
	var input_hash = password.sha256_text()
	return input_hash == password_hash

func update_last_login() -> void:
	"""更新最后登录时间"""
	last_login = Time.get_ticks_msec()
	print("User %s: 最后登录时间已更新" % username)

func get_user_info() -> Dictionary:
	"""获取用户信息字典"""
	return {
		"user_id": user_id,
		"username": username,
		"email": email,
		"created_at": created_at,
		"last_login": last_login,
		"is_active": is_active
	}

func to_json() -> String:
	"""转换为JSON字符串"""
	var data = get_user_info()
	return JSON.stringify(data)

static func from_dict(data: Dictionary) -> User:
	"""从字典创建用户对象"""
	var user = User.new(data.get("username", ""), data.get("email", ""))
	user.user_id = data.get("user_id", user.user_id)
	user.password_hash = data.get("password_hash", "")
	user.created_at = data.get("created_at", user.created_at)
	user.last_login = data.get("last_login", 0)
	user.is_active = data.get("is_active", true)
	return user
