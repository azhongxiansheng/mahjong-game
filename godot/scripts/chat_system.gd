class_name ChatSystem
extends Node

## 消息存储 {user_pair: [ChatMessage]}
var conversations: Dictionary = {}  # 对话集合
var all_messages: Array = []        # 所有消息（按时间排序）
var unread_messages: Dictionary = {} # 未读消息 {user_pair: [ChatMessage]}

## 统计数据
var total_messages: int = 0
var total_conversations: int = 0
var total_unread: int = 0

## 信号
signal message_sent(message: ChatMessage)
signal message_received(message: ChatMessage)
signal message_read(message_id: String)
signal conversation_started(user1_id: String, user2_id: String)
signal conversation_ended(user1_id: String, user2_id: String)
signal unread_count_changed(count: int)


## 初始化
func _ready() -> void:
    """初始化聊天系统"""
    print("[ChatSystem] Initialized successfully")


## 消息发送方法

func send_message(sender_id: String, sender_name: String, receiver_id: String, receiver_name: String, content: String) -> ChatMessage:
    """发送消息"""
    # 验证
    if not _validate_ids(sender_id, receiver_id):
        push_error("[ChatSystem] Invalid sender or receiver ID")
        return null
    
    if content.strip_edges().length() == 0:
        push_error("[ChatSystem] Message content cannot be empty")
        return null
    
    # 创建消息
    var message = ChatMessage.new(sender_id, sender_name, receiver_id, receiver_name, content)
    
    if not message.validate():
        push_error("[ChatSystem] Message validation failed: %s" % message.get_validation_error())
        return null
    
    # 标记为已发送
    message.mark_as_sent()
    
    # 存储消息
    _store_message(message)
    
    message_sent.emit(message)
    print("[ChatSystem] Message sent from %s to %s" % [sender_name, receiver_name])
    return message


func receive_message(message: ChatMessage) -> bool:
    """接收消息"""
    if not message.validate():
        push_error("[ChatSystem] Invalid message received")
        return false
    
    # 存储消息
    _store_message(message)
    
    # 添加到未读
    var user_pair = _get_user_pair(message.sender_id, message.receiver_id)
    if not unread_messages.has(user_pair):
        unread_messages[user_pair] = []
    
    unread_messages[user_pair].append(message)
    total_unread += 1
    unread_count_changed.emit(total_unread)
    
    message_received.emit(message)
    print("[ChatSystem] Message received from %s" % message.sender_name)
    return true


func mark_message_as_read(message_id: String) -> bool:
    """标记消息为已读"""
    for msg in all_messages:
        if msg.message_id == message_id:
            if not msg.is_read:
                msg.mark_as_read()
                total_unread -= 1
                unread_count_changed.emit(total_unread)
                message_read.emit(message_id)
                return true
    
    return false


func mark_conversation_as_read(user_pair: String) -> int:
    """标记整个对话为已读"""
    if not unread_messages.has(user_pair):
        return 0
    
    var count = 0
    for msg in unread_messages[user_pair]:
        if not msg.is_read:
            msg.mark_as_read()
            count += 1
    
    total_unread -= count
    unread_messages[user_pair].clear()
    unread_count_changed.emit(total_unread)
    print("[ChatSystem] Marked %d messages as read" % count)
    return count


## 对话管理方法

func get_conversation(user1_id: String, user2_id: String) -> Array:
    """获取对话消息"""
    var user_pair = _get_user_pair(user1_id, user2_id)
    return conversations.get(user_pair, [])


func get_conversation_count(user1_id: String, user2_id: String) -> int:
    """获取对话消息数"""
    return get_conversation(user1_id, user2_id).size()


func get_recent_messages(user1_id: String, user2_id: String, limit: int = 50) -> Array:
    """获取最近的消息"""
    var conv = get_conversation(user1_id, user2_id)
    var start = max(0, conv.size() - limit)
    return conv.slice(start, conv.size())


func get_older_messages(user1_id: String, user2_id: String, limit: int = 50, offset: int = 0) -> Array:
    """获取旧消息"""
    var conv = get_conversation(user1_id, user2_id)
    var start = offset
    var end = min(conv.size(), offset + limit)
    
    if start >= conv.size():
        return []
    
    return conv.slice(start, end)


func clear_conversation(user1_id: String, user2_id: String) -> bool:
    """清空对话"""
    var user_pair = _get_user_pair(user1_id, user2_id)
    
    if not conversations.has(user_pair):
        return false
    
    var count = conversations[user_pair].size()
    conversations.erase(user_pair)
    
    # 从所有消息中移除
    all_messages = all_messages.filter(func(msg):
        var pair = _get_user_pair(msg.sender_id, msg.receiver_id)
        return pair != user_pair
    )
    
    total_messages -= count
    conversation_ended.emit(user1_id, user2_id)
    print("[ChatSystem] Conversation cleared: %d messages removed" % count)
    return true


## 查询方法

func get_all_conversations() -> Array:
    """获取所有对话"""
    return conversations.keys()


func get_conversation_partners(user_id: String) -> Array:
    """获取对话伙伴列表"""
    var partners = []
    
    for user_pair in conversations.keys():
        var parts = user_pair.split("|")
        if parts[0] == user_id:
            partners.append(parts[1])
        elif parts[1] == user_id:
            partners.append(parts[0])
    
    return partners


func has_conversation(user1_id: String, user2_id: String) -> bool:
    """检查是否有对话"""
    var user_pair = _get_user_pair(user1_id, user2_id)
    return conversations.has(user_pair)


func get_unread_count() -> int:
    """获取未读消息总数"""
    return total_unread


func get_unread_count_for_user(user1_id: String, user2_id: String) -> int:
    """获取与某用户的未读消息数"""
    var user_pair = _get_user_pair(user1_id, user2_id)
    return unread_messages.get(user_pair, []).size()


## 搜索方法

func search_messages(user1_id: String, user2_id: String, query: String) -> Array:
    """搜索消息"""
    if query.length() < 2:
        return []
    
    var conv = get_conversation(user1_id, user2_id)
    var results = []
    var query_lower = query.to_lower()
    
    for msg in conv:
        if msg.content.to_lower().contains(query_lower) or \
           msg.sender_name.to_lower().contains(query_lower):
            results.append(msg)
    
    return results


func get_messages_by_date(user1_id: String, user2_id: String, date: String) -> Array:
    """按日期获取消息"""
    var conv = get_conversation(user1_id, user2_id)
    var results = []
    
    for msg in conv:
        var time_dict = Time.get_datetime_dict_from_unix_time(msg.created_at)
        var msg_date = "%04d-%02d-%02d" % [time_dict["year"], time_dict["month"], time_dict["day"]]
        
        if msg_date == date:
            results.append(msg)
    
    return results


## 统计方法

func get_statistics() -> Dictionary:
    """获取统计信息"""
    var unread_conversations = 0
    for user_pair in unread_messages.keys():
        if unread_messages[user_pair].size() > 0:
            unread_conversations += 1
    
    return {
        "total_messages": total_messages,
        "total_conversations": total_conversations,
        "total_unread": total_unread,
        "unread_conversations": unread_conversations,
        "active_partners": get_conversation_partners("").size()
    }


func print_summary() -> void:
    """打印摘要"""
    print("\n=== 聊天系统摘要 ===")
    print("总消息数: %d" % total_messages)
    print("对话数: %d" % total_conversations)
    print("未读消息: %d" % total_unread)
    print("====================\n")


## 导出和导入

func to_json(user_pair: String = "", limit: int = 1000) -> String:
    """导出为JSON"""
    var data = {
        "conversations": [],
        "timestamp": Time.get_ticks_msec()
    }
    
    if user_pair != "":
        # 导出单个对话
        if conversations.has(user_pair):
            var messages = conversations[user_pair].slice(0, limit)
            for msg in messages:
                data["conversations"].append(msg.to_dict())
    else:
        # 导出所有对话
        for pair in conversations.keys():
            var messages = conversations[pair].slice(0, limit)
            for msg in messages:
                data["conversations"].append(msg.to_dict())
    
    return JSON.stringify(data)


func from_json(json_string: String) -> bool:
    """从JSON导入"""
    var json = JSON.new()
    var error = json.parse(json_string)
    
    if error:
        push_error("[ChatSystem] JSON parse error")
        return false
    
    var data = json.data
    
    if not data.has("conversations"):
        return false
    
    for msg_data in data["conversations"]:
        var message = ChatMessage.new(
            msg_data.get("sender_id", ""),
            msg_data.get("sender_name", ""),
            msg_data.get("receiver_id", ""),
            msg_data.get("receiver_name", ""),
            msg_data.get("content", "")
        )
        message.from_dict(msg_data)
        _store_message(message)
    
    print("[ChatSystem] Loaded from JSON: %d messages" % total_messages)
    return true


## 私有方法

func _store_message(message: ChatMessage) -> void:
    """存储消息"""
    # 获取对话用户对
    var user_pair = _get_user_pair(message.sender_id, message.receiver_id)
    
    # 添加到对话
    if not conversations.has(user_pair):
        conversations[user_pair] = []
        total_conversations += 1
        conversation_started.emit(message.sender_id, message.receiver_id)
    
    conversations[user_pair].append(message)
    
    # 添加到所有消息
    all_messages.append(message)
    total_messages += 1


func _get_user_pair(user1_id: String, user2_id: String) -> String:
    """获取用户对的标准化字符串"""
    if user1_id < user2_id:
        return "%s|%s" % [user1_id, user2_id]
    else:
        return "%s|%s" % [user2_id, user1_id]


func _validate_ids(sender_id: String, receiver_id: String) -> bool:
    """验证ID"""
    if sender_id.length() == 0 or receiver_id.length() == 0:
        return false
    if sender_id == receiver_id:
        return false
    return true
