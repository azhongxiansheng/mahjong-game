class_name ChatMessage
extends RefCounted

## 消息基础信息
var message_id: String              # 消息ID
var sender_id: String               # 发送者ID
var sender_name: String             # 发送者名称
var receiver_id: String             # 接收者ID
var receiver_name: String           # 接收者名称
var content: String                 # 消息内容

## 消息状态
var created_at: int = 0             # 创建时间戳
var sent_at: int = 0                # 发送时间戳
var is_read: bool = false           # 是否已读
var read_at: int = 0                # 阅读时间戳

## 消息类型
var message_type: String = "text"   # 消息类型 (text/image/emoji/system)

## 初始化
func _init(p_sender_id: String, p_sender_name: String, p_receiver_id: String, p_receiver_name: String, p_content: String) -> void:
    """初始化聊天消息"""
    sender_id = p_sender_id
    sender_name = p_sender_name
    receiver_id = p_receiver_id
    receiver_name = p_receiver_name
    content = p_content

    # 生成消息ID
    message_id = "%s_%s_%d" % [sender_id, receiver_id, Time.get_ticks_msec()]
    created_at = int(Time.get_ticks_msec() / 1000)
    sent_at = created_at


## 公共方法

func mark_as_sent() -> void:
    """标记为已发送"""
    sent_at = int(Time.get_ticks_msec() / 1000)


func mark_as_read() -> void:
    """标记为已读"""
    is_read = true
    read_at = int(Time.get_ticks_msec() / 1000)


func is_sent() -> bool:
    """检查是否已发送"""
    return sent_at > 0


func get_send_delay() -> int:
    """获取发送延迟 (秒)"""
    if sent_at == 0:
        return -1
    return sent_at - created_at


func get_read_delay() -> int:
    """获取阅读延迟 (秒)"""
    if not is_read or read_at == 0:
        return -1
    return read_at - sent_at


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


func get_display_text() -> String:
    """获取显示文本"""
    var status = "✓" if is_sent() else "⏳"
    if is_read:
        status = "✓✓"

    return "[%s] %s: %s" % [status, sender_name, content]


func get_formatted_text(include_timestamp: bool = true) -> String:
    """获取格式化文本"""
    var timestamp = ""
    if include_timestamp:
        var time_dict = Time.get_datetime_dict_from_unix_time(created_at)
        timestamp = "[%02d:%02d:%02d] " % [time_dict["hour"], time_dict["minute"], time_dict["second"]]

    var status = ""
    if is_read:
        status = " [已读]"
    elif is_sent():
        status = " [已发送]"
    else:
        status = " [发送中]"

    return "%s%s: %s%s" % [timestamp, sender_name, content, status]


func get_length() -> int:
    """获取消息长度"""
    return content.length()


func is_empty() -> bool:
    """检查消息是否为空"""
    return content.strip_edges().length() == 0


func is_too_long(max_length: int = 500) -> bool:
    """检查消息是否过长"""
    return content.length() > max_length


func is_recent(seconds: int = 60) -> bool:
    """检查消息是否是最近的"""
    var now = int(Time.get_ticks_msec() / 1000)
    return (now - created_at) <= seconds


func to_dict() -> Dictionary:
    """转换为字典"""
    return {
        "message_id": message_id,
        "sender_id": sender_id,
        "sender_name": sender_name,
        "receiver_id": receiver_id,
        "receiver_name": receiver_name,
        "content": content,
        "created_at": created_at,
        "sent_at": sent_at,
        "is_read": is_read,
        "read_at": read_at,
        "message_type": message_type
    }


func from_dict(data: Dictionary) -> void:
    """从字典恢复"""
    if data.has("message_id"):
        message_id = data["message_id"]
    if data.has("sender_id"):
        sender_id = data["sender_id"]
    if data.has("sender_name"):
        sender_name = data["sender_name"]
    if data.has("receiver_id"):
        receiver_id = data["receiver_id"]
    if data.has("receiver_name"):
        receiver_name = data["receiver_name"]
    if data.has("content"):
        content = data["content"]
    if data.has("created_at"):
        created_at = data["created_at"]
    if data.has("sent_at"):
        sent_at = data["sent_at"]
    if data.has("is_read"):
        is_read = data["is_read"]
    if data.has("read_at"):
        read_at = data["read_at"]
    if data.has("message_type"):
        message_type = data["message_type"]


## 验证方法

func validate() -> bool:
    """验证消息是否有效"""
    if sender_id.length() == 0:
        return false
    if receiver_id.length() == 0:
        return false
    if content.strip_edges().length() == 0:
        return false
    if is_too_long():
        return false
    return true


func get_validation_error() -> String:
    """获取验证错误信息"""
    if sender_id.length() == 0:
        return "发送者ID不能为空"
    if receiver_id.length() == 0:
        return "接收者ID不能为空"
    if content.strip_edges().length() == 0:
        return "消息内容不能为空"
    if is_too_long():
        return "消息过长 (最大 500 字符)"
    return ""
