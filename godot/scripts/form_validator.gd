class_name FormValidator

# 表单验证器
# 提供各种字段的验证方法

# 验证规则
const MIN_USERNAME_LENGTH: int = 3
const MAX_USERNAME_LENGTH: int = 20
const MIN_PASSWORD_LENGTH: int = 6
const MAX_PASSWORD_LENGTH: int = 50
const MIN_EMAIL_LENGTH: int = 5
const MAX_EMAIL_LENGTH: int = 100

# 正则表达式
var username_regex: RegEx  # 字母、数字、下划线
var email_regex: RegEx     # 标准邮箱格式
var password_regex: RegEx  # 密码强度

func _init() -> void:
	"""初始化验证器"""
	# 用户名：字母开头，支持字母、数字、下划线
	username_regex = RegEx.create_from_string("^[a-zA-Z][a-zA-Z0-9_]*$")
	
	# 邮箱：标准邮箱格式
	email_regex = RegEx.create_from_string("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$")
	
	# 密码：至少包含大小写字母和数字
	password_regex = RegEx.create_from_string("^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d)[a-zA-Z0-9@$!%*?&]{6,}$")

static func is_valid_username(username: String) -> bool:
	"""验证用户名"""
	if username.length() < MIN_USERNAME_LENGTH:
		print("FormValidator: 用户名过短，最少 %d 个字符" % MIN_USERNAME_LENGTH)
		return false
	
	if username.length() > MAX_USERNAME_LENGTH:
		print("FormValidator: 用户名过长，最多 %d 个字符" % MAX_USERNAME_LENGTH)
		return false
	
	# 检查是否包含有效字符
	if not username[0].is_valid_identifier():
		print("FormValidator: 用户名必须以字母开头")
		return false
	
	for char in username:
		if not (char.is_alphanumeric() or char == "_"):
			print("FormValidator: 用户名只能包含字母、数字和下划线")
			return false
	
	return true

static func is_valid_password(password: String) -> bool:
	"""验证密码"""
	if password.length() < MIN_PASSWORD_LENGTH:
		print("FormValidator: 密码过短，最少 %d 个字符" % MIN_PASSWORD_LENGTH)
		return false
	
	if password.length() > MAX_PASSWORD_LENGTH:
		print("FormValidator: 密码过长，最多 %d 个字符" % MAX_PASSWORD_LENGTH)
		return false
	
	# 密码强度检查
	var has_upper = false
	var has_lower = false
	var has_digit = false
	
	for char in password:
		if char.is_uppercase():
			has_upper = true
		elif char.is_lowercase():
			has_lower = true
		elif char.is_digit():
			has_digit = true
	
	if not (has_upper and has_lower and has_digit):
		print("FormValidator: 密码必须包含大小写字母和数字")
		return false
	
	return true

static func is_valid_email(email: String) -> bool:
	"""验证邮箱"""
	if email.length() < MIN_EMAIL_LENGTH:
		print("FormValidator: 邮箱过短")
		return false
	
	if email.length() > MAX_EMAIL_LENGTH:
		print("FormValidator: 邮箱过长，最多 %d 个字符" % MAX_EMAIL_LENGTH)
		return false
	
	# 简单的邮箱格式检查
	if not ("@" in email):
		print("FormValidator: 邮箱格式无效")
		return false
	
	var parts = email.split("@")
	if parts.size() != 2:
		print("FormValidator: 邮箱格式无效")
		return false
	
	if not ("." in parts[1]):
		print("FormValidator: 邮箱格式无效")
		return false
	
	return true

static func is_empty(value: String) -> bool:
	"""检查字段是否为空"""
	return value.strip_edges() == ""

static func get_validation_error(field: String, value: String) -> String:
	"""获取验证错误信息"""
	match field:
		"username":
			if is_empty(value):
				return "用户名不能为空"
			if not is_valid_username(value):
				return "用户名格式不正确"
		"password":
			if is_empty(value):
				return "密码不能为空"
			if not is_valid_password(value):
				return "密码强度不足"
		"email":
			if is_empty(value):
				return "邮箱不能为空"
			if not is_valid_email(value):
				return "邮箱格式不正确"
		_:
			return "字段无效"
	
	return ""

static func validate_form(data: Dictionary) -> Dictionary:
	"""验证完整的表单"""
	var errors: Dictionary = {}
	
	for field in data.keys():
		var error = get_validation_error(field, data[field])
		if error != "":
			errors[field] = error
	
	return errors
