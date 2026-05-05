class_name Notification
extends RefCounted

## 通知类型枚举
enum NotificationType {
	FRIEND_REQUEST,      # 好友请求
	FRIEND_ACCEPTED,     # 好友接受
	TEAM_INVITE,         # 战队邀请
	SQUAD_INVITE,        # 组队邀请
	MATCH_FOUND,         # 匹配成功
	GAME_RESULT,         # 游戏结果
	ACHIEVEMENT_UNLOCKED,# 成就解锁
	SEASON_REWARD,       # 赛季奖励
	SYSTEM_MESSAGE,      # 系统消息
	PROMOTION,           # 晋级通知
	OFFLINE_MESSAGE      # 离线消息
}

## 优先级枚举
enum Priority {
	LOW = 0,
	NORMAL = 1,
	HIGH = 2,
	URGENT = 3
}

## 通知基础信息
var notification_id: String            # 通知ID
var notification_type: NotificationType # 通知类型
var priority: Priority = Priority.NORMAL # 优先级
var sender_id: String = ""             # 发送者ID
var sender_name: String = ""           # 发送者名称
var recipient_id: String               # 接收者ID
var title: String = ""                 # 标题
var content: String = ""               # 内容
var data: Dictionary = {}              # 附加数据

## 状态和时间
var is_read: bool = false              # 是否已读
var created_at: int = 0                # 创建时间戳
var read_at: int = 0                   # 阅读时间戳
var expires_at: int = 0                # 过期时间戳
var lifetime_seconds: int = 86400      # 生命周期 (默认 1 天)

## 初始化
func _init(p_type: NotificationType, p_recipient_id: String) -> void:
	"""初始化通知"""
	notification_type = p_type
	recipient_id = p_recipient_id
	notification_id = "%s_%s_%d" % [recipient_id, p_type, Time.get_ticks_msec()]
	created_at = int(Time.get_ticks_msec() / 1000)
	expires_at = created_at + lifetime_seconds


## 公共方法

func get_type_string() -> String:
	"""获取通知类型字符串"""
	match notification_type:
		NotificationType.FRIEND_REQUEST:
			return "好友请求"
		NotificationType.FRIEND_ACCEPTED:
			return "好友接受"
		NotificationType.TEAM_INVITE:
			return "战队邀请"
		NotificationType.SQUAD_INVITE:
			return "组队邀请"
		NotificationType.MATCH_FOUND:
			return "匹配成功"
		NotificationType.GAME_RESULT:
			return "游戏结果"
		NotificationType.ACHIEVEMENT_UNLOCKED:
			return "成就解锁"
		NotificationType.SEASON_REWARD:
			return "赛季奖励"
		NotificationType.SYSTEM_MESSAGE:
			return "系统消息"
		NotificationType.PROMOTION:
			return "晋级通知"
		NotificationType.OFFLINE_MESSAGE:
			return "离线消息"
		_:
			return "未知"


func get_icon_emoji() -> String:
	"""获取通知类型图标"""
	match notification_type:
		NotificationType.FRIEND_REQUEST:
			return "👋"
		NotificationType.FRIEND_ACCEPTED:
			return "✅"
		NotificationType.TEAM_INVITE:
			return "🎖️"
		NotificationType.SQUAD_INVITE:
			return "🎮"
		NotificationType.MATCH_FOUND:
			return "🎯"
		NotificationType.GAME_RESULT:
			return "🏆"
		NotificationType.ACHIEVEMENT_UNLOCKED:
			return "🏅"
		NotificationType.SEASON_REWARD:
			return "💎"
		NotificationType.SYSTEM_MESSAGE:
			return "📢"
		NotificationType.PROMOTION:
			return "⬆️"
		NotificationType.OFFLINE_MESSAGE:
			return "📨"
		_:
			return "📬"


func mark_as_read() -> void:
	"""标记为已读"""
	is_read = true
	read_at = int(Time.get_ticks_msec() / 1000)


func is_expired() -> bool:
	"""检查是否过期"""
	var now = int(Time.get_ticks_msec() / 1000)
	return now > expires_at


func get_time_ago() -> String:
	"""获取相对时间文本"""
	var now = int(Time.get_ticks_msec() / 1000)
	var diff = now - created_at

	if diff < 60:
		return "刚刚"
	elif diff < 3600:
		return "%d 分钟前" % (diff / 60)
	elif diff < 86400:
		return "%d 小时前" % (diff / 3600)
	elif diff < 604800:
		return "%d 天前" % (diff / 86400)
	else:
		return "%d 周前" % (diff / 604800)


func get_priority_color() -> Color:
	"""获取优先级颜色"""
	match priority:
		Priority.LOW:
			return Color.GRAY
		Priority.NORMAL:
			return Color.WHITE
		Priority.HIGH:
			return Color.YELLOW
		Priority.URGENT:
			return Color.RED
		_:
			return Color.WHITE


func get_display_text() -> String:
	"""获取显示文本"""
	var priority_text = ""
	match priority:
		Priority.HIGH:
			priority_text = "[!] "
		Priority.URGENT:
			priority_text = "[!!] "
		_:
			priority_text = ""

	return "%s%s %s: %s" % [priority_text, get_icon_emoji(), title, content]


func get_full_details() -> String:
	"""获取完整详情"""
	var time_text = get_time_ago()
	var status_text = "✓" if is_read else "•"
	var type_text = get_type_string()

	return "[%s] %s - %s\n%s\n来自: %s (%s)\n时间: %s" % [
		status_text, type_text, title, content, sender_name, sender_id, time_text
	]


func to_dict() -> Dictionary:
	"""转换为字典"""
	return {
		"notification_id": notification_id,
		"notification_type": notification_type,
		"priority": priority,
		"sender_id": sender_id,
		"sender_name": sender_name,
		"recipient_id": recipient_id,
		"title": title,
		"content": content,
		"data": data,
		"is_read": is_read,
		"created_at": created_at,
		"read_at": read_at,
		"expires_at": expires_at
	}


func from_dict(data: Dictionary) -> void:
	"""从字典恢复"""
	if data.has("notification_id"):
		notification_id = data["notification_id"]
	if data.has("notification_type"):
		notification_type = data["notification_type"]
	if data.has("priority"):
		priority = data["priority"]
	if data.has("sender_id"):
		sender_id = data["sender_id"]
	if data.has("sender_name"):
		sender_name = data["sender_name"]
	if data.has("recipient_id"):
		recipient_id = data["recipient_id"]
	if data.has("title"):
		title = data["title"]
	if data.has("content"):
		content = data["content"]
	if data.has("data"):
		data = data["data"]
	if data.has("is_read"):
		is_read = data["is_read"]
	if data.has("created_at"):
		created_at = data["created_at"]
	if data.has("read_at"):
		read_at = data["read_at"]
	if data.has("expires_at"):
		expires_at = data["expires_at"]


## 验证方法

func validate() -> bool:
	"""验证通知是否有效"""
	if recipient_id.length() == 0:
		return false
	if title.length() == 0:
		return false
	if content.length() == 0:
		return false
	if is_expired():
		return false
	return true


func get_validation_error() -> String:
	"""获取验证错误信息"""
	if recipient_id.length() == 0:
		return "接收者ID不能为空"
	if title.length() == 0:
		return "标题不能为空"
	if content.length() == 0:
		return "内容不能为空"
	if is_expired():
		return "通知已过期"
	return ""


## 工厂方法

static func create_friend_request(from_player_id: String, from_player_name: String, to_player_id: String) -> Notification:
	"""创建好友请求通知"""
	var notif = Notification.new(NotificationType.FRIEND_REQUEST, to_player_id)
	notif.sender_id = from_player_id
	notif.sender_name = from_player_name
	notif.title = "好友请求"
	notif.content = "%s 邀请你成为好友" % from_player_name
	notif.priority = Priority.HIGH
	notif.data = {
		"from_player_id": from_player_id,
		"from_player_name": from_player_name
	}
	return notif


static func create_team_invite(team_id: String, team_name: String, inviter_id: String, inviter_name: String, player_id: String) -> Notification:
	"""创建战队邀请通知"""
	var notif = Notification.new(NotificationType.TEAM_INVITE, player_id)
	notif.sender_id = inviter_id
	notif.sender_name = inviter_name
	notif.title = "战队邀请"
	notif.content = "%s 邀请你加入战队 %s" % [inviter_name, team_name]
	notif.priority = Priority.HIGH
	notif.data = {
		"team_id": team_id,
		"team_name": team_name,
		"inviter_id": inviter_id
	}
	return notif


static func create_game_result(won: bool, rank: int, points: int, player_id: String) -> Notification:
	"""创建游戏结果通知"""
	var notif = Notification.new(NotificationType.GAME_RESULT, player_id)
	notif.title = "游戏结束"
	if won:
		notif.content = "恭喜！你赢了！获得 %d 点积分，排名 %d" % [points, rank]
		notif.priority = Priority.HIGH
	else:
		notif.content = "本局失败，排名 %d，失去 %d 点积分" % [rank, abs(points)]
		notif.priority = Priority.NORMAL
	notif.data = {
		"won": won,
		"rank": rank,
		"points": points
	}
	return notif


static func create_achievement(achievement_name: String, achievement_desc: String, reward: int, player_id: String) -> Notification:
	"""创建成就解锁通知"""
	var notif = Notification.new(NotificationType.ACHIEVEMENT_UNLOCKED, player_id)
	notif.title = "成就解锁"
	notif.content = "%s：%s，获得 %d 金币" % [achievement_name, achievement_desc, reward]
	notif.priority = Priority.HIGH
	notif.data = {
		"achievement_name": achievement_name,
		"reward": reward
	}
	return notif


static func create_season_reward(season: int, rank: int, reward: int, player_id: String) -> Notification:
	"""创建赛季奖励通知"""
	var notif = Notification.new(NotificationType.SEASON_REWARD, player_id)
	notif.title = "赛季结束"
	notif.content = "第 %d 赛季已结束，你的排名是 %d，获得 %d 钻石" % [season, rank, reward]
	notif.priority = Priority.URGENT
	notif.data = {
		"season": season,
		"rank": rank,
		"reward": reward
	}
	return notif
