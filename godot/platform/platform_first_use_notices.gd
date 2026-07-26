extends RefCounted

# #258 Windows Alpha：应用内首次公共连接 / 首次 PTT 说明文案与判定。
# 无 class_name：调用方显式 preload，降低全局 class 解析风险。
# 生产仅在 Windows 运行时显示；macOS/Linux 不显示、不 ack、不消费 Windows flag。
# 系统防火墙与麦克风弹窗不保证出现。网络端到端未验证。

const PUBLIC_CONNECT_TITLE := "首次连接公共网络"
const PUBLIC_CONNECT_BODY := (
	"本客户端仅发起出站网络连接。"
	+ "若 Windows 防火墙询问，请仅允许本程序所需网络访问。"
	+ "未签名 Alpha 可能触发 SmartScreen「来源未知」提示，属预期风险。"
	+ "网络端到端未验证。"
)
const PUBLIC_CONNECT_CONFIRM := "我知道了"
const PUBLIC_CONNECT_CANCEL := "取消"

const PTT_TITLE := "麦克风与语音模型"
const PTT_BODY := (
	"请在 Windows 隐私设置中允许桌面应用使用麦克风。"
	+ "欢乐场语音模型按需下载到本地 user://models/whisper，经 SHA-256 校验后启用，不随安装包内置。"
	+ "STANDARD 标准场不请求麦克风或模型。"
)
const PTT_CONFIRM := "我知道了"
const PTT_CANCEL := "取消"

## 测试注入：null=自动检测；true/false 强制 Windows 判定。after 必须 clear。
static var _windows_runtime_override: Variant = null


static func set_windows_runtime_override(enabled: Variant) -> void:
	_windows_runtime_override = enabled


static func clear_windows_runtime_override() -> void:
	_windows_runtime_override = null


static func is_windows_runtime() -> bool:
	if _windows_runtime_override != null:
		return bool(_windows_runtime_override)
	if OS.has_feature("windows"):
		return true
	return OS.get_name() == "Windows"


static func public_connect_copy() -> Dictionary:
	return {
		"title": PUBLIC_CONNECT_TITLE,
		"body": PUBLIC_CONNECT_BODY,
		"confirm": PUBLIC_CONNECT_CONFIRM,
		"cancel": PUBLIC_CONNECT_CANCEL,
	}


static func ptt_copy() -> Dictionary:
	return {
		"title": PTT_TITLE,
		"body": PTT_BODY,
		"confirm": PTT_CONFIRM,
		"cancel": PTT_CANCEL,
	}


static func needs_public_connect_notice(sm: Object = null) -> bool:
	if not is_windows_runtime():
		return false
	var settings: Object = sm if sm != null else _settings()
	if settings == null:
		return true
	if settings.has_method("needs_windows_first_public_connect_notice"):
		return bool(settings.needs_windows_first_public_connect_notice())
	return not bool(settings.get("windows_first_public_connect_notice_acked"))


static func needs_ptt_notice(sm: Object = null) -> bool:
	if not is_windows_runtime():
		return false
	var settings: Object = sm if sm != null else _settings()
	if settings == null:
		return true
	if settings.has_method("needs_windows_first_ptt_notice"):
		return bool(settings.needs_windows_first_ptt_notice())
	return not bool(settings.get("windows_first_ptt_notice_acked"))


static func ack_public_connect_notice(sm: Object = null) -> void:
	if not is_windows_runtime():
		return
	var settings: Object = sm if sm != null else _settings()
	if settings == null:
		return
	if settings.has_method("ack_windows_first_public_connect_notice"):
		settings.ack_windows_first_public_connect_notice()
	else:
		settings.set("windows_first_public_connect_notice_acked", true)


static func ack_ptt_notice(sm: Object = null) -> void:
	if not is_windows_runtime():
		return
	var settings: Object = sm if sm != null else _settings()
	if settings == null:
		return
	if settings.has_method("ack_windows_first_ptt_notice"):
		settings.ack_windows_first_ptt_notice()
	else:
		settings.set("windows_first_ptt_notice_acked", true)


static func _settings() -> Object:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("/root/SettingsManager")
