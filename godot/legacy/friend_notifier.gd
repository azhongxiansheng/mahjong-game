class_name FriendNotifier
extends CanvasLayer

## 通知队列
var notification_queue: Array = []
var is_showing: bool = false
var current_notification: Dictionary = {}

## UI 组件
var notification_panel: PanelContainer
var title_label: Label
var message_label: Label
var icon_label: Label
var close_button: Button

## 配置
const NOTIFICATION_WIDTH = 300
const NOTIFICATION_HEIGHT = 100
const NOTIFICATION_DURATION = 3.0
const ANIMATION_DURATION = 0.3
const ANIMATION_EASING = Tween.EaseType.EASE_OUT

## 信号
signal notification_closed(notification_id: String)


## 初始化
func _ready() -> void:
    """初始化通知系统"""
    _create_ui()
    _setup_styles()
    print("[FriendNotifier] Initialized successfully")


func _process(_delta: float) -> void:
    """处理通知队列"""
    if not is_showing and notification_queue.size() > 0:
        _show_next_notification()


## 公共方法

func show_notification(title: String, message: String, icon: String = "👥", duration: float = NOTIFICATION_DURATION) -> void:
    """显示通知"""
    var notification = {
        "title": title,
        "message": message,
        "icon": icon,
        "duration": duration,
        "id": "%d" % Time.get_ticks_msec()
    }

    notification_queue.append(notification)
    print("[FriendNotifier] Notification queued: %s" % title)


func show_friend_request(friend_name: String) -> void:
    """显示好友请求通知"""
    show_notification("👋 好友请求", "%s 邀请你成为好友" % friend_name)


func show_friend_added(friend_name: String) -> void:
    """显示好友已添加通知"""
    show_notification("✅ 好友已添加", "现在可以与 %s 聊天了" % friend_name, "➕")


func show_friend_removed(friend_name: String) -> void:
    """显示好友已删除通知"""
    show_notification("❌ 好友已删除", "已移除 %s 作为好友" % friend_name, "➖")


func show_player_blocked(player_name: String) -> void:
    """显示玩家被屏蔽通知"""
    show_notification("🚫 已屏蔽", "已屏蔽玩家 %s" % player_name)


func show_message_received(sender_name: String, preview: String = "") -> void:
    """显示收到消息通知"""
    var msg = "来自 %s 的新消息" % sender_name
    if preview.length() > 0:
        msg += ": %s" % preview.substr(0, 30)
    show_notification("💬 新消息", msg, "📨")


func show_friend_online(friend_name: String) -> void:
    """显示好友上线通知"""
    show_notification("🟢 好友上线", "%s 已上线" % friend_name, "🟢")


func show_friend_offline(friend_name: String) -> void:
    """显示好友离线通知"""
    show_notification("⚫ 好友离线", "%s 已离线" % friend_name, "⚫")


func show_friend_playing(friend_name: String) -> void:
    """显示好友在游戏中通知"""
    show_notification("🎮 好友游戏中", "%s 正在游戏中" % friend_name, "🎮")


func clear_queue() -> void:
    """清空通知队列"""
    notification_queue.clear()
    print("[FriendNotifier] Queue cleared")


func get_pending_count() -> int:
    """获取待显示通知数"""
    return notification_queue.size()


## 私有方法

func _create_ui() -> void:
    """创建UI组件"""
    # 创建面板
    notification_panel = PanelContainer.new()
    notification_panel.custom_minimum_size = Vector2(NOTIFICATION_WIDTH, NOTIFICATION_HEIGHT)
    notification_panel.position = Vector2(20, 20)
    notification_panel.visible = false
    add_child(notification_panel)

    # 创建容器
    var vbox = VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 5)
    notification_panel.add_child(vbox)

    # 创建顶部容器（图标和标题）
    var hbox_top = HBoxContainer.new()
    hbox_top.add_theme_constant_override("separation", 10)
    vbox.add_child(hbox_top)

    # 创建图标标签
    icon_label = Label.new()
    icon_label.text = "👥"
    icon_label.add_theme_font_size_override("font_size", 24)
    hbox_top.add_child(icon_label)

    # 创建标题标签
    title_label = Label.new()
    title_label.text = "标题"
    title_label.add_theme_font_size_override("font_size", 16)
    hbox_top.add_child(title_label)

    # 创建关闭按钮
    close_button = Button.new()
    close_button.text = "×"
    close_button.custom_minimum_size = Vector2(30, 30)
    close_button.add_theme_font_size_override("font_size", 20)
    close_button.pressed.connect(_on_close_pressed)
    hbox_top.add_child(close_button)

    # 创建消息标签
    message_label = Label.new()
    message_label.text = "消息"
    message_label.add_theme_font_size_override("font_size", 12)
    message_label.autowrap_mode = TextServer.AUTOWRAP_WORD
    vbox.add_child(message_label)


func _setup_styles() -> void:
    """设置样式"""
    # 面板样式
    var panel_style = StyleBoxFlat.new()
    panel_style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
    panel_style.set_border_enabled_all(true)
    panel_style.set_border_width_all(2)
    panel_style.border_color = Color(0.3, 0.6, 1.0, 0.8)
    panel_style.set_corner_radius_all(10)
    notification_panel.add_theme_stylebox_override("panel", panel_style)

    # 标题标签样式
    title_label.add_theme_color_override("font_color", Color.WHITE)

    # 消息标签样式
    message_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))

    # 关闭按钮样式
    close_button.add_theme_color_override("font_color", Color.WHITE)
    close_button.add_theme_color_override("font_hover_color", Color.RED)


func _show_next_notification() -> void:
    """显示下一个通知"""
    if notification_queue.size() == 0:
        return

    current_notification = notification_queue.pop_front()
    is_showing = true

    # 更新UI
    icon_label.text = current_notification.get("icon", "👥")
    title_label.text = current_notification.get("title", "通知")
    message_label.text = current_notification.get("message", "")

    # 显示动画
    _animate_in()

    # 设置自动关闭
    await get_tree().create_timer(current_notification.get("duration", NOTIFICATION_DURATION)).timeout
    _animate_out()


func _animate_in() -> void:
    """显示动画"""
    notification_panel.visible = true

    # 位置动画：从左侧滑入
    var tween = create_tween()
    tween.set_ease(ANIMATION_EASING)
    tween.set_trans(Tween.TransitionType.TRANS_BACK)
    tween.tween_property(notification_panel, "position", Vector2(20, 20), ANIMATION_DURATION)

    # 透明度动画：淡入
    var tween2 = create_tween()
    tween2.set_ease(ANIMATION_EASING)
    tween2.tween_property(notification_panel, "modulate", Color.WHITE, ANIMATION_DURATION)


func _animate_out() -> void:
    """隐藏动画"""
    # 位置动画：向左滑出
    var tween = create_tween()
    tween.set_ease(ANIMATION_EASING)
    tween.set_trans(Tween.TransitionType.TRANS_BACK)
    tween.tween_property(notification_panel, "position", Vector2(-350, 20), ANIMATION_DURATION)

    # 透明度动画：淡出
    var tween2 = create_tween()
    tween2.set_ease(ANIMATION_EASING)
    tween2.tween_property(notification_panel, "modulate", Color(1, 1, 1, 0), ANIMATION_DURATION)

    # 隐藏面板
    await tween.finished
    notification_panel.visible = false
    notification_panel.position = Vector2(20, 20)
    notification_panel.modulate = Color.WHITE

    is_showing = false
    notification_closed.emit(current_notification.get("id", ""))


func _on_close_pressed() -> void:
    """关闭按钮按下"""
    _animate_out()


## 调试方法

func print_queue() -> void:
    """打印队列信息"""
    print("\n=== 通知队列 ===")
    print("待显示: %d" % notification_queue.size())
    print("当前显示: %s" % ("是" if is_showing else "否"))
    print("===============\n")
