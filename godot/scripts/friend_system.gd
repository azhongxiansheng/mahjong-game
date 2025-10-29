class_name FriendSystem
extends Node

## 好友集合
var friends: Dictionary = {}        # 已确认好友 {friend_id: Friend}
var pending_requests: Dictionary = {}  # 待确认请求 {from_player_id: Friend}
var blocked_players: Dictionary = {}   # 黑名单 {player_id: Friend}
var suggested_friends: Array = []   # 推荐好友

## 信号定义
signal friend_added(friend: Friend)
signal friend_removed(friend_id: String)
signal friend_status_changed(friend_id: String, new_status: String)
signal friend_stats_updated(friend_id: String, stats: Dictionary)
signal friend_request_received(from_player_id: String, from_player_name: String)
signal friend_request_accepted(friend_id: String)
signal friend_request_rejected(friend_id: String)
signal player_blocked(player_id: String)
signal player_unblocked(player_id: String)
signal friends_list_changed

## 统计数据
var total_friends: int = 0
var online_friends_count: int = 0


## 初始化和清理
func _ready() -> void:
    """初始化好友系统"""
    print("[FriendSystem] Initialized successfully")


func _process(_delta: float) -> void:
    """定期更新在线好友计数"""
    _update_online_count()


## 添加好友相关方法

func add_friend(friend: Friend) -> bool:
    """添加好友"""
    if friends.has(friend.friend_id):
        push_warning("[FriendSystem] Friend already exists: %s" % friend.friend_id)
        return false

    friends[friend.friend_id] = friend
    total_friends = friends.size()

    # 从待确认中移除
    if pending_requests.has(friend.friend_id):
        pending_requests.erase(friend.friend_id)

    friend_added.emit(friend)
    friends_list_changed.emit()
    print("[FriendSystem] Friend added: %s" % friend.friend_name)
    return true


func remove_friend(friend_id: String) -> bool:
    """删除好友"""
    if not friends.has(friend_id):
        push_warning("[FriendSystem] Friend not found: %s" % friend_id)
        return false

    var friend = friends[friend_id]
    friends.erase(friend_id)
    total_friends = friends.size()

    friend_removed.emit(friend_id)
    friends_list_changed.emit()
    print("[FriendSystem] Friend removed: %s" % friend.friend_name)
    return true


## 好友查询方法

func get_friend(friend_id: String) -> Friend:
    """获取单个好友"""
    return friends.get(friend_id, null)


func get_all_friends() -> Array:
    """获取所有好友"""
    return friends.values()


func get_friend_count() -> int:
    """获取好友总数"""
    return friends.size()


func has_friend(friend_id: String) -> bool:
    """检查是否有该好友"""
    return friends.has(friend_id)


func get_online_friends() -> Array:
    """获取在线好友"""
    var online = []
    for friend in friends.values():
        if friend.is_online():
            online.append(friend)

    # 按最后在线时间排序
    online.sort_custom(func(a, b): return a.last_seen > b.last_seen)
    return online


func get_playing_friends() -> Array:
    """获取正在游戏的好友"""
    var playing = []
    for friend in friends.values():
        if friend.is_playing():
            playing.append(friend)
    return playing


func get_offline_friends() -> Array:
    """获取离线好友"""
    var offline = []
    for friend in friends.values():
        if not friend.is_online():
            offline.append(friend)
    return offline


func get_friends_by_level(min_level: int, max_level: int = 999) -> Array:
    """按等级范围获取好友"""
    var result = []
    for friend in friends.values():
        if friend.level >= min_level and friend.level <= max_level:
            result.append(friend)
    return result


func get_friends_by_rating(min_rating: int, max_rating: int = 9999) -> Array:
    """按评分范围获取好友"""
    var result = []
    for friend in friends.values():
        if friend.rating >= min_rating and friend.rating <= max_rating:
            result.append(friend)
    return result


func get_top_friends(limit: int = 10) -> Array:
    """获取评分最高的好友"""
    var sorted_friends = friends.values()
    sorted_friends.sort_custom(func(a, b): return a.rating > b.rating)
    return sorted_friends.slice(0, min(limit, sorted_friends.size()))


## 状态更新方法

func update_friend_status(friend_id: String, new_status: String) -> bool:
    """更新好友状态"""
    if not friends.has(friend_id):
        push_warning("[FriendSystem] Friend not found: %s" % friend_id)
        return false

    var friend = friends[friend_id]
    friend.update_status(new_status)
    friend_status_changed.emit(friend_id, new_status)
    return true


func update_friend_stats(friend_id: String, stats: Dictionary) -> bool:
    """更新好友统计"""
    if not friends.has(friend_id):
        push_warning("[FriendSystem] Friend not found: %s" % friend_id)
        return false

    var friend = friends[friend_id]
    friend.update_stats(stats)
    friend_stats_updated.emit(friend_id, stats)
    return true


func update_all_friends_status(new_status: String) -> void:
    """更新所有好友状态"""
    for friend_id in friends.keys():
        update_friend_status(friend_id, new_status)


## 好友请求方法

func send_friend_request(from_player_id: String, from_player_name: String) -> bool:
    """接收好友请求"""
    if pending_requests.has(from_player_id):
        return false

    var friend = Friend.new(from_player_id, from_player_name)
    friend.relationship = "pending"
    pending_requests[from_player_id] = friend

    friend_request_received.emit(from_player_id, from_player_name)
    print("[FriendSystem] Friend request received from %s" % from_player_name)
    return true


func accept_friend_request(from_player_id: String) -> bool:
    """接受好友请求"""
    if not pending_requests.has(from_player_id):
        push_warning("[FriendSystem] No pending request from: %s" % from_player_id)
        return false

    var friend = pending_requests[from_player_id]
    pending_requests.erase(from_player_id)

    add_friend(friend)
    friend_request_accepted.emit(from_player_id)
    print("[FriendSystem] Friend request accepted from %s" % friend.friend_name)
    return true


func reject_friend_request(from_player_id: String) -> bool:
    """拒绝好友请求"""
    if not pending_requests.has(from_player_id):
        return false

    pending_requests.erase(from_player_id)
    friend_request_rejected.emit(from_player_id)
    return true


func get_pending_requests() -> Array:
    """获取待确认请求"""
    return pending_requests.values()


func get_pending_request_count() -> int:
    """获取待确认请求数"""
    return pending_requests.size()


## 黑名单方法

func block_player(player_id: String, player_name: String) -> bool:
    """屏蔽玩家"""
    if blocked_players.has(player_id):
        return false

    var friend = Friend.new(player_id, player_name)
    friend.relationship = "blocked"
    blocked_players[player_id] = friend

    # 如果在好友列表中，移除
    if friends.has(player_id):
        remove_friend(player_id)

    player_blocked.emit(player_id)
    print("[FriendSystem] Player blocked: %s" % player_name)
    return true


func unblock_player(player_id: String) -> bool:
    """解除屏蔽"""
    if not blocked_players.has(player_id):
        return false

    blocked_players.erase(player_id)
    player_unblocked.emit(player_id)
    return true


func is_blocked(player_id: String) -> bool:
    """检查是否被屏蔽"""
    return blocked_players.has(player_id)


func get_blocked_players() -> Array:
    """获取黑名单"""
    return blocked_players.values()


## 统计和报告方法

func get_statistics() -> Dictionary:
    """获取统计信息"""
    var online = get_online_friends().size()
    var playing = get_playing_friends().size()
    var offline = friends.size() - online

    var total_games = 0
    var total_wins = 0
    for friend in friends.values():
        total_games += friend.total_games
        total_wins += friend.wins

    var avg_rating = 0
    if friends.size() > 0:
        var rating_sum = 0
        for friend in friends.values():
            rating_sum += friend.rating
        avg_rating = rating_sum / friends.size()

    return {
        "total_friends": friends.size(),
        "online_friends": online,
        "playing_friends": playing,
        "offline_friends": offline,
        "blocked_players": blocked_players.size(),
        "pending_requests": pending_requests.size(),
        "total_games_with_friends": total_games,
        "total_wins_with_friends": total_wins,
        "average_friend_rating": avg_rating
    }


func print_summary() -> void:
    """打印摘要"""
    print("\n=== 好友系统摘要 ===")
    print("总好友数: %d" % friends.size())
    print("在线好友: %d" % get_online_friends().size())
    print("游戏中: %d" % get_playing_friends().size())
    print("离线: %d" % get_offline_friends().size())
    print("待确认: %d" % pending_requests.size())
    print("黑名单: %d" % blocked_players.size())

    var stats = get_statistics()
    print("\n统计:")
    print("  总对局: %d" % stats["total_games_with_friends"])
    print("  总胜场: %d" % stats["total_wins_with_friends"])
    print("  平均评分: %d" % stats["average_friend_rating"])
    print("==================\n")


## 导出和导入方法

func to_json(limit: int = 100) -> String:
    """导出为JSON"""
    var data = {
        "friends": [],
        "pending_requests": [],
        "blocked_players": [],
        "timestamp": Time.get_ticks_msec()
    }

    for friend in friends.values().slice(0, limit):
        data["friends"].append(friend.to_dict())

    for friend in pending_requests.values():
        data["pending_requests"].append(friend.to_dict())

    for friend in blocked_players.values():
        data["blocked_players"].append(friend.to_dict())

    return JSON.stringify(data)


func from_json(json_string: String) -> bool:
    """从JSON导入"""
    var json = JSON.new()
    var error = json.parse(json_string)

    if error:
        push_error("[FriendSystem] JSON parse error")
        return false

    var data = json.data

    # 清空现有数据
    friends.clear()
    pending_requests.clear()
    blocked_players.clear()

    # 加载好友
    if data.has("friends"):
        for friend_data in data["friends"]:
            var friend = Friend.new(friend_data["friend_id"], friend_data["friend_name"])
            friend.from_dict(friend_data)
            friends[friend.friend_id] = friend

    # 加载待确认
    if data.has("pending_requests"):
        for friend_data in data["pending_requests"]:
            var friend = Friend.new(friend_data["friend_id"], friend_data["friend_name"])
            friend.from_dict(friend_data)
            pending_requests[friend.friend_id] = friend

    # 加载黑名单
    if data.has("blocked_players"):
        for friend_data in data["blocked_players"]:
            var friend = Friend.new(friend_data["friend_id"], friend_data["friend_name"])
            friend.from_dict(friend_data)
            blocked_players[friend.friend_id] = friend

    total_friends = friends.size()
    print("[FriendSystem] Loaded from JSON: %d friends" % total_friends)
    return true


## 私有方法

func _update_online_count() -> void:
    """更新在线好友计数"""
    var new_count = get_online_friends().size()
    if new_count != online_friends_count:
        online_friends_count = new_count
