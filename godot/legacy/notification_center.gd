class_name NotificationCenter
extends Node

## 通知队列 - 按优先级分类
var notification_queue: Array = []       # 待显示通知队列
var unread_notifications: Dictionary = {} # 未读通知 {user_id: [notifications]}
var read_notifications: Dictionary = {}  # 已读通知 {user_id: [notifications]}
var all_notifications: Array = []        # 所有通知（按时间排序）

## 统计数据
var total_notifications: int = 0
var total_unread: int = 0
var current_user_id: String = ""

## 配置
const MAX_STORED_NOTIFICATIONS = 1000
const CLEANUP_INTERVAL = 300  # 5 分钟清理一次过期通知


## 信号
signal notification_received(notification: Notification)
signal notification_read(notification_id: String)
signal unread_count_changed(count: int)
signal notification_expired(notification_id: String)
signal queue_updated


## 初始化
func _ready() -> void:
	"""初始化通知中心"""
	set_process(true)
	print("[NotificationCenter] Initialized successfully")


func _process(_delta: float) -> void:
	"""定期清理过期通知"""
	# 定期清理过期通知 (每 5 分钟)
	if get_tree().get_frame() % 300 == 0:
		_cleanup_expired_notifications()


## 用户管理

func set_current_user(user_id: String) -> void:
	"""设置当前用户"""
	current_user_id = user_id
	if not unread_notifications.has(user_id):
		unread_notifications[user_id] = []
	if not read_notifications.has(user_id):
		read_notifications[user_id] = []
	print("[NotificationCenter] Current user set: %s" % user_id)


## 通知接收和队列管理

func receive_notification(notification: Notification) -> bool:
	"""接收新通知"""
	if not notification.validate():
		push_error("[NotificationCenter] Invalid notification: %s" % notification.get_validation_error())
		return false

	# 添加到队列
	notification_queue.append(notification)
	notification_queue.sort_custom(func(a, b): return a.priority > b.priority)

	# 添加到存储
	_store_notification(notification)

	notification_received.emit(notification)
	queue_updated.emit()
	total_notifications += 1

	print("[NotificationCenter] Notification received: %s" % notification.title)
	return true


func _store_notification(notification: Notification) -> void:
	"""存储通知"""
	var user_id = notification.recipient_id

	# 添加到未读
	if not unread_notifications.has(user_id):
		unread_notifications[user_id] = []

	unread_notifications[user_id].append(notification)
	total_unread += 1
	unread_count_changed.emit(total_unread)

	# 添加到所有通知
	all_notifications.append(notification)

	# 限制存储数量
	if all_notifications.size() > MAX_STORED_NOTIFICATIONS:
		var oldest = all_notifications[0]
		all_notifications.remove_at(0)
		_cleanup_notification(oldest)


## 通知查询

func get_pending_notifications() -> Array:
	"""获取待显示通知"""
	return notification_queue.duplicate()


func pop_next_notification() -> Notification:
	"""获取并移除下一个待显示通知"""
	if notification_queue.size() == 0:
		return null

	var notif = notification_queue[0]
	notification_queue.remove_at(0)
	queue_updated.emit()
	return notif


func get_unread_notifications(user_id: String) -> Array:
	"""获取未读通知"""
	if not unread_notifications.has(user_id):
		return []
	return unread_notifications[user_id].duplicate()


func get_read_notifications(user_id: String) -> Array:
	"""获取已读通知"""
	if not read_notifications.has(user_id):
		return []
	return read_notifications[user_id].duplicate()


func get_all_notifications(user_id: String) -> Array:
	"""获取所有通知"""
	var all = []
	all.append_array(get_unread_notifications(user_id))
	all.append_array(get_read_notifications(user_id))
	all.sort_custom(func(a, b): return a.created_at > b.created_at)
	return all


func get_unread_count(user_id: String) -> int:
	"""获取未读通知数"""
	if not unread_notifications.has(user_id):
		return 0
	return unread_notifications[user_id].size()


func get_notification_by_id(notification_id: String) -> Notification:
	"""按 ID 获取通知"""
	for notif in all_notifications:
		if notif.notification_id == notification_id:
			return notif
	return null


## 通知操作

func mark_as_read(notification_id: String) -> bool:
	"""标记通知为已读"""
	var notification = get_notification_by_id(notification_id)
	if notification == null:
		return false

	if notification.is_read:
		return true  # 已经是已读状态

	notification.mark_as_read()

	# 从未读移到已读
	var user_id = notification.recipient_id
	if unread_notifications.has(user_id):
		for i in range(unread_notifications[user_id].size()):
			if unread_notifications[user_id][i].notification_id == notification_id:
				unread_notifications[user_id].remove_at(i)
				break

	if not read_notifications.has(user_id):
		read_notifications[user_id] = []
	read_notifications[user_id].append(notification)

	total_unread -= 1
	unread_count_changed.emit(total_unread)
	notification_read.emit(notification_id)

	return true


func mark_all_as_read(user_id: String) -> int:
	"""标记所有通知为已读"""
	if not unread_notifications.has(user_id):
		return 0

	var count = 0
	for notification in unread_notifications[user_id]:
		notification.mark_as_read()
		if not read_notifications.has(user_id):
			read_notifications[user_id] = []
		read_notifications[user_id].append(notification)
		notification_read.emit(notification.notification_id)
		count += 1

	total_unread -= count
	unread_notifications[user_id].clear()
	unread_count_changed.emit(total_unread)

	print("[NotificationCenter] Marked %d notifications as read" % count)
	return count


func delete_notification(notification_id: String) -> bool:
	"""删除通知"""
	var notification = get_notification_by_id(notification_id)
	if notification == null:
		return false

	var user_id = notification.recipient_id

	# 从未读中删除
	if unread_notifications.has(user_id):
		for i in range(unread_notifications[user_id].size()):
			if unread_notifications[user_id][i].notification_id == notification_id:
				unread_notifications[user_id].remove_at(i)
				total_unread -= 1
				unread_count_changed.emit(total_unread)
				break

	# 从已读中删除
	if read_notifications.has(user_id):
		for i in range(read_notifications[user_id].size()):
			if read_notifications[user_id][i].notification_id == notification_id:
				read_notifications[user_id].remove_at(i)
				break

	# 从所有通知中删除
	for i in range(all_notifications.size()):
		if all_notifications[i].notification_id == notification_id:
			all_notifications.remove_at(i)
			break

	return true


func clear_all_notifications(user_id: String) -> int:
	"""清空所有通知"""
	var count = 0

	if unread_notifications.has(user_id):
		count += unread_notifications[user_id].size()
		unread_notifications[user_id].clear()

	if read_notifications.has(user_id):
		count += read_notifications[user_id].size()
		read_notifications[user_id].clear()

	total_unread -= count
	unread_count_changed.emit(total_unread)

	print("[NotificationCenter] Cleared %d notifications" % count)
	return count


## 通知过滤和搜索

func get_notifications_by_type(user_id: String, notif_type: Notification.NotificationType) -> Array:
	"""按类型获取通知"""
	var all = get_all_notifications(user_id)
	return all.filter(func(n): return n.notification_type == notif_type)


func get_recent_notifications(user_id: String, limit: int = 20) -> Array:
	"""获取最近的通知"""
	var all = get_all_notifications(user_id)
	all.sort_custom(func(a, b): return a.created_at > b.created_at)
	return all.slice(0, min(limit, all.size()))


func get_high_priority_notifications(user_id: String) -> Array:
	"""获取高优先级通知"""
	var all = get_all_notifications(user_id)
	return all.filter(func(n): return n.priority >= Notification.Priority.HIGH)


func search_notifications(user_id: String, query: String) -> Array:
	"""搜索通知"""
	if query.length() < 2:
		return []

	var all = get_all_notifications(user_id)
	var query_lower = query.to_lower()
	return all.filter(func(n):
		return n.title.to_lower().contains(query_lower) or \
		       n.content.to_lower().contains(query_lower)
	)


## 统计和报告

func get_statistics(user_id: String) -> Dictionary:
	"""获取统计信息"""
	var all_notifs = get_all_notifications(user_id)
	var unread_count = get_unread_count(user_id)

	var by_type = {}
	var by_priority = {}

	for notif in all_notifs:
		# 按类型统计
		var type_str = notif.get_type_string()
		if not by_type.has(type_str):
			by_type[type_str] = 0
		by_type[type_str] += 1

		# 按优先级统计
		var priority_str = ["低", "普通", "高", "紧急"][notif.priority]
		if not by_priority.has(priority_str):
			by_priority[priority_str] = 0
		by_priority[priority_str] += 1

	return {
		"total": all_notifs.size(),
		"unread": unread_count,
		"read": all_notifs.size() - unread_count,
		"pending": notification_queue.size(),
		"by_type": by_type,
		"by_priority": by_priority
	}


func print_summary() -> void:
	"""打印摘要"""
	print("\n=== 通知中心摘要 ===")
	print("待显示通知: %d" % notification_queue.size())
	print("总通知数: %d" % total_notifications)
	print("未读通知: %d" % total_unread)
	print("已读通知: %d" % (total_notifications - total_unread))

	var stats = get_statistics(current_user_id)
	print("\n用户统计 (%s):" % current_user_id)
	print("  总数: %d" % stats["total"])
	print("  未读: %d" % stats["unread"])
	print("  已读: %d" % stats["read"])
	print("==================\n")


## 导出和导入

func to_json(user_id: String, limit: int = 500) -> String:
	"""导出为 JSON"""
	var data = {
		"notifications": [],
		"timestamp": Time.get_ticks_msec()
	}

	var all = get_all_notifications(user_id).slice(0, limit)
	for notif in all:
		data["notifications"].append(notif.to_dict())

	return JSON.stringify(data)


func from_json(json_string: String, user_id: String) -> bool:
	"""从 JSON 导入"""
	var json = JSON.new()
	var error = json.parse(json_string)

	if error:
		push_error("[NotificationCenter] JSON parse error")
		return false

	var data = json.data

	if not data.has("notifications"):
		return false

	# 清空现有通知
	if unread_notifications.has(user_id):
		unread_notifications[user_id].clear()
	if read_notifications.has(user_id):
		read_notifications[user_id].clear()

	# 加载通知
	for notif_data in data["notifications"]:
		var notification = Notification.new(notif_data["notification_type"], user_id)
		notification.from_dict(notif_data)

		if notification.is_read:
			if not read_notifications.has(user_id):
				read_notifications[user_id] = []
			read_notifications[user_id].append(notification)
		else:
			if not unread_notifications.has(user_id):
				unread_notifications[user_id] = []
			unread_notifications[user_id].append(notification)
			total_unread += 1

		all_notifications.append(notification)
		total_notifications += 1

	unread_count_changed.emit(total_unread)
	print("[NotificationCenter] Loaded from JSON: %d notifications" % total_notifications)
	return true


## 私有方法

func _cleanup_expired_notifications() -> void:
	"""清理过期通知"""
	var removed = 0

	# 清理所有已过期的通知
	for i in range(all_notifications.size() - 1, -1, -1):
		if all_notifications[i].is_expired():
			_cleanup_notification(all_notifications[i])
			all_notifications.remove_at(i)
			removed += 1

	if removed > 0:
		print("[NotificationCenter] Cleaned up %d expired notifications" % removed)


func _cleanup_notification(notification: Notification) -> void:
	"""清理单个通知"""
	var user_id = notification.recipient_id

	# 从未读中移除
	if unread_notifications.has(user_id):
		for i in range(unread_notifications[user_id].size() - 1, -1, -1):
			if unread_notifications[user_id][i].notification_id == notification.notification_id:
				unread_notifications[user_id].remove_at(i)
				total_unread -= 1
				break

	# 从已读中移除
	if read_notifications.has(user_id):
		for i in range(read_notifications[user_id].size() - 1, -1, -1):
			if read_notifications[user_id][i].notification_id == notification.notification_id:
				read_notifications[user_id].remove_at(i)
				break

	notification_expired.emit(notification.notification_id)
