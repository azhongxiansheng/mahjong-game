class_name FriendManager
extends Node

## 依赖
var friend_system: FriendSystem
var ui: Node  # FriendUI reference

## 管理数据
var current_player_id: String = ""
var current_player_name: String = ""
var search_results: Array = []
var notification_queue: Array = []

## 配置
const MAX_FRIENDS = 1000
const MAX_BLOCKED = 500
const SEARCH_LIMIT = 20


## 信号
signal friend_request_sent(to_player_id: String)
signal friend_request_response(from_player_id: String, accepted: bool)
signal search_completed(results: Array)
signal notification_received(title: String, message: String)


## 初始化
func _ready() -> void:
    """初始化好友管理器"""
    if friend_system == null:
        friend_system = FriendSystem.new()
        add_child(friend_system)

    # 连接信号
    friend_system.friend_added.connect(_on_friend_added)
    friend_system.friend_removed.connect(_on_friend_removed)
    friend_system.friend_status_changed.connect(_on_friend_status_changed)
    friend_system.friend_request_received.connect(_on_friend_request_received)
    friend_system.player_blocked.connect(_on_player_blocked)

    print("[FriendManager] Initialized successfully")


## 玩家管理方法

func set_current_player(player_id: String, player_name: String) -> void:
    """设置当前玩家信息"""
    current_player_id = player_id
    current_player_name = player_name
    print("[FriendManager] Current player set: %s (%s)" % [player_name, player_id])


## 好友操作方法

func send_friend_request(target_player_id: String, target_player_name: String) -> bool:
    """发送好友请求"""
    if not _validate_player_id(target_player_id):
        push_error("[FriendManager] Invalid player ID")
        return false

    if friend_system.has_friend(target_player_id):
        _show_notification("好友已存在", "你们已经是好友了")
        return false

    if friend_system.is_blocked(target_player_id):
        _show_notification("无法添加", "该玩家已被屏蔽")
        return false

    # TODO: 向后端发送请求
    print("[FriendManager] Friend request sent to %s" % target_player_name)
    friend_request_sent.emit(target_player_id)
    _show_notification("好友请求已发送", "等待 %s 的回应" % target_player_name)
    return true


func accept_friend_request(from_player_id: String) -> bool:
    """接受好友请求"""
    var result = friend_system.accept_friend_request(from_player_id)

    if result:
        # TODO: 通知后端
        friend_request_response.emit(from_player_id, true)
        _show_notification("好友请求已接受", "你们成为了好友")
        print("[FriendManager] Friend request accepted from %s" % from_player_id)

    return result


func reject_friend_request(from_player_id: String) -> bool:
    """拒绝好友请求"""
    var result = friend_system.reject_friend_request(from_player_id)

    if result:
        # TODO: 通知后端
        friend_request_response.emit(from_player_id, false)
        print("[FriendManager] Friend request rejected from %s" % from_player_id)

    return result


func remove_friend(friend_id: String) -> bool:
    """删除好友"""
    var friend = friend_system.get_friend(friend_id)
    if friend == null:
        return false

    var result = friend_system.remove_friend(friend_id)

    if result:
        # TODO: 通知后端
        _show_notification("好友已删除", "已移除好友 %s" % friend.friend_name)
        print("[FriendManager] Friend removed: %s" % friend.friend_name)

    return result


## 好友查询方法

func get_all_friends() -> Array:
    """获取所有好友"""
    return friend_system.get_all_friends()


func get_online_friends(limit: int = 50) -> Array:
    """获取在线好友"""
    var online = friend_system.get_online_friends()
    return online.slice(0, min(limit, online.size()))


func get_friend_by_id(friend_id: String) -> Friend:
    """按ID获取好友"""
    return friend_system.get_friend(friend_id)


func search_friends(query: String, limit: int = SEARCH_LIMIT) -> Array:
    """搜索好友"""
    if query.length() < 2:
        search_results.clear()
        search_completed.emit([])
        return []

    var results = []
    var query_lower = query.to_lower()

    for friend in friend_system.get_all_friends():
        if friend.friend_name.to_lower().contains(query_lower) or \
           friend.friend_id.to_lower().contains(query_lower):
            results.append(friend)
            if results.size() >= limit:
                break

    search_results = results
    search_completed.emit(results)
    print("[FriendManager] Found %d friends matching '%s'" % [results.size(), query])
    return results


func search_by_level(min_level: int, max_level: int = 999) -> Array:
    """按等级搜索好友"""
    return friend_system.get_friends_by_level(min_level, max_level)


func search_by_rating(min_rating: int, max_rating: int = 9999) -> Array:
    """按评分搜索好友"""
    return friend_system.get_friends_by_rating(min_rating, max_rating)


func get_top_friends(limit: int = 10) -> Array:
    """获取评分最高的好友"""
    return friend_system.get_top_friends(limit)


## 屏蔽管理方法

func block_player(player_id: String, player_name: String) -> bool:
    """屏蔽玩家"""
    var result = friend_system.block_player(player_id, player_name)

    if result:
        # TODO: 通知后端
        _show_notification("已屏蔽", "屏蔽玩家 %s" % player_name)
        print("[FriendManager] Player blocked: %s" % player_name)

    return result


func unblock_player(player_id: String) -> bool:
    """解除屏蔽"""
    var result = friend_system.unblock_player(player_id)

    if result:
        # TODO: 通知后端
        _show_notification("已解除屏蔽", "解除屏蔽")
        print("[FriendManager] Player unblocked: %s" % player_id)

    return result


func get_blocked_players() -> Array:
    """获取黑名单"""
    return friend_system.get_blocked_players()


func is_blocked(player_id: String) -> bool:
    """检查是否被屏蔽"""
    return friend_system.is_blocked(player_id)


## 待确认请求方法

func get_pending_requests() -> Array:
    """获取待确认请求"""
    return friend_system.get_pending_requests()


func get_pending_count() -> int:
    """获取待确认数"""
    return friend_system.get_pending_request_count()


## 统计和报告

func get_friend_statistics() -> Dictionary:
    """获取好友统计"""
    return friend_system.get_statistics()


func get_summary_text() -> String:
    """获取摘要文本"""
    var stats = get_friend_statistics()
    return "👥 好友: %d | 🟢 在线: %d | 🎮 游戏中: %d | 📋 待确认: %d" % [
        stats["total_friends"],
        stats["online_friends"],
        stats["playing_friends"],
        stats["pending_requests"]
    ]


## 数据持久化

func save_friends_to_file(path: String) -> bool:
    """保存好友到文件"""
    var json_str = friend_system.to_json()

    var file = FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        push_error("[FriendManager] Failed to open file: %s" % path)
        return false

    file.store_string(json_str)
    print("[FriendManager] Friends saved to %s" % path)
    return true


func load_friends_from_file(path: String) -> bool:
    """从文件加载好友"""
    if not FileAccess.file_exists(path):
        push_warning("[FriendManager] File not found: %s" % path)
        return false

    var file = FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("[FriendManager] Failed to open file: %s" % path)
        return false

    var json_str = file.get_as_text()
    var result = friend_system.from_json(json_str)

    if result:
        print("[FriendManager] Friends loaded from %s" % path)

    return result


## 私有方法

func _validate_player_id(player_id: String) -> bool:
    """验证玩家ID"""
    if player_id.length() == 0:
        return false
    if player_id == current_player_id:
        _show_notification("无效操作", "不能添加自己为好友")
        return false
    return true


func _show_notification(title: String, message: String) -> void:
    """显示通知"""
    notification_received.emit(title, message)
    print("[FriendManager] Notification: %s - %s" % [title, message])


## 信号处理

func _on_friend_added(friend: Friend) -> void:
    """好友添加时"""
    print("[FriendManager] Event: Friend added - %s" % friend.friend_name)


func _on_friend_removed(friend_id: String) -> void:
    """好友删除时"""
    print("[FriendManager] Event: Friend removed - %s" % friend_id)


func _on_friend_status_changed(friend_id: String, new_status: String) -> void:
    """好友状态改变时"""
    var friend = friend_system.get_friend(friend_id)
    if friend != null:
        print("[FriendManager] Event: %s is now %s" % [friend.friend_name, new_status])


func _on_friend_request_received(from_player_id: String, from_player_name: String) -> void:
    """收到好友请求时"""
    _show_notification("好友请求", "%s 邀请你成为好友" % from_player_name)


func _on_player_blocked(player_id: String) -> void:
    """玩家被屏蔽时"""
    print("[FriendManager] Event: Player blocked - %s" % player_id)


## 调试方法

func print_summary() -> void:
    """打印摘要"""
    print("\n=== 好友管理器摘要 ===")
    print("当前玩家: %s (%s)" % [current_player_name, current_player_id])
    print(get_summary_text())
    friend_system.print_summary()
    print("====================\n")
