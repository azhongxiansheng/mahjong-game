class_name ChatUI
extends CanvasLayer

## 依赖
var chat_system: ChatSystem
var current_user_id: String = ""
var current_partner_id: String = ""
var current_partner_name: String = ""

## UI 组件
var chat_panel: PanelContainer
var title_label: Label
var messages_container: VBoxContainer
var scroll_container: ScrollContainer
var input_line_edit: LineEdit
var send_button: Button
var close_button: Button
var back_button: Button
var status_label: Label
var unread_label: Label

## UI 状态
var is_visible_ui: bool = false
var messages_displayed: Array = []
var auto_scroll: bool = true

## 配置
const PANEL_WIDTH = 500
const PANEL_HEIGHT = 600
const MESSAGE_ITEM_HEIGHT = 60
const MAX_MESSAGES_DISPLAY = 100


## 初始化
func _ready() -> void:
    """初始化聊天UI"""
    _create_ui()
    _setup_styles()
    print("[ChatUI] Initialized successfully")


func _process(_delta: float) -> void:
    """处理消息自动滚动"""
    if auto_scroll and scroll_container:
        scroll_container.scroll_vertical = int(scroll_container.get_v_scroll_bar().max_value)


## 公共方法

func set_chat_system(system: ChatSystem) -> void:
    """设置聊天系统"""
    chat_system = system
    if chat_system:
        chat_system.message_received.connect(_on_message_received)
        chat_system.message_sent.connect(_on_message_sent)


func set_current_user(user_id: String) -> void:
    """设置当前用户"""
    current_user_id = user_id
    print("[ChatUI] Current user set: %s" % user_id)


func open_chat(partner_id: String, partner_name: String) -> void:
    """打开与某个用户的聊天"""
    current_partner_id = partner_id
    current_partner_name = partner_name

    title_label.text = "💬 %s" % partner_name

    show_ui()
    _load_conversation()
    print("[ChatUI] Chat opened with %s" % partner_name)


func show_ui() -> void:
    """显示UI"""
    chat_panel.visible = true
    is_visible_ui = true
    print("[ChatUI] UI shown")


func hide_ui() -> void:
    """隐藏UI"""
    chat_panel.visible = false
    is_visible_ui = false
    print("[ChatUI] UI hidden")


func toggle_ui() -> void:
    """切换UI显示"""
    if is_visible_ui:
        hide_ui()
    else:
        show_ui()


func refresh_messages() -> void:
    """刷新消息显示"""
    _load_conversation()


func clear_input() -> void:
    """清空输入框"""
    input_line_edit.text = ""


## 私有方法

func _create_ui() -> void:
    """创建UI组件"""
    # 创建主面板
    chat_panel = PanelContainer.new()
    chat_panel.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
    chat_panel.position = Vector2(600, 50)
    chat_panel.visible = false
    add_child(chat_panel)

    # 创建主容器
    var main_vbox = VBoxContainer.new()
    main_vbox.add_theme_constant_override("separation", 5)
    chat_panel.add_child(main_vbox)

    # 创建顶部栏
    var top_hbox = HBoxContainer.new()
    top_hbox.add_theme_constant_override("separation", 10)
    main_vbox.add_child(top_hbox)

    # 返回按钮
    back_button = Button.new()
    back_button.text = "◀"
    back_button.custom_minimum_size = Vector2(40, 40)
    back_button.pressed.connect(_on_back_pressed)
    top_hbox.add_child(back_button)

    # 标题标签
    title_label = Label.new()
    title_label.text = "💬 聊天"
    title_label.add_theme_font_size_override("font_size", 18)
    top_hbox.add_child(title_label)

    # 状态标签
    status_label = Label.new()
    status_label.text = "在线"
    status_label.add_theme_font_size_override("font_size", 12)
    status_label.add_theme_color_override("font_color", Color.GREEN)
    top_hbox.add_child(status_label)

    # 未读标签
    unread_label = Label.new()
    unread_label.text = ""
    unread_label.add_theme_font_size_override("font_size", 12)
    top_hbox.add_child(unread_label)

    # 关闭按钮
    close_button = Button.new()
    close_button.text = "✕"
    close_button.custom_minimum_size = Vector2(40, 40)
    close_button.pressed.connect(_on_close_pressed)
    top_hbox.add_child(close_button)

    # 创建消息滚动区域
    scroll_container = ScrollContainer.new()
    scroll_container.custom_minimum_size = Vector2(0, 350)
    scroll_container.follow_focus = false
    main_vbox.add_child(scroll_container)

    messages_container = VBoxContainer.new()
    messages_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll_container.add_child(messages_container)

    # 创建输入区域
    var input_hbox = HBoxContainer.new()
    input_hbox.add_theme_constant_override("separation", 5)
    main_vbox.add_child(input_hbox)

    # 输入框
    input_line_edit = LineEdit.new()
    input_line_edit.placeholder_text = "输入消息..."
    input_line_edit.custom_minimum_size = Vector2(0, 40)
    input_line_edit.text_submitted.connect(_on_input_submitted)
    input_hbox.add_child(input_line_edit)

    # 发送按钮
    send_button = Button.new()
    send_button.text = "发送"
    send_button.custom_minimum_size = Vector2(80, 40)
    send_button.pressed.connect(_on_send_pressed)
    input_hbox.add_child(send_button)


func _setup_styles() -> void:
    """设置样式"""
    # 面板样式
    var panel_style = StyleBoxFlat.new()
    panel_style.bg_color = Color(0.05, 0.05, 0.08, 0.95)
    panel_style.set_border_enabled_all(true)
    panel_style.set_border_width_all(2)
    panel_style.border_color = Color(0.3, 0.6, 1.0, 0.8)
    panel_style.set_corner_radius_all(10)
    chat_panel.add_theme_stylebox_override("panel", panel_style)

    # 输入框样式
    input_line_edit.add_theme_color_override("font_color", Color.WHITE)
    input_line_edit.add_theme_color_override("caret_color", Color.WHITE)


func _load_conversation() -> void:
    """加载对话"""
    if not chat_system:
        return

    # 清空容器
    for child in messages_container.get_children():
        child.queue_free()

    messages_displayed.clear()

    # 获取消息
    var messages = chat_system.get_recent_messages(current_user_id, current_partner_id, MAX_MESSAGES_DISPLAY)

    if messages.size() == 0:
        var empty_label = Label.new()
        empty_label.text = "暂无消息"
        empty_label.add_theme_color_override("font_color", Color.GRAY)
        messages_container.add_child(empty_label)
        return

    # 显示所有消息
    for message in messages:
        var item = _create_message_item(message)
        messages_container.add_child(item)
        messages_displayed.append(message)

        # 自动标记为已读
        if not message.is_read and message.receiver_id == current_user_id:
            chat_system.mark_message_as_read(message.message_id)

    # 自动滚动到底部
    await get_tree().process_frame
    scroll_container.scroll_vertical = int(scroll_container.get_v_scroll_bar().max_value)


func _create_message_item(message: ChatMessage) -> PanelContainer:
    """创建消息项"""
    var item = PanelContainer.new()
    item.custom_minimum_size = Vector2(0, 60)

    # 判断是否为当前用户发送
    var is_sender = message.sender_id == current_user_id

    # 背景样式
    var style = StyleBoxFlat.new()
    if is_sender:
        style.bg_color = Color(0.2, 0.4, 0.8, 0.6)  # 蓝色背景
    else:
        style.bg_color = Color(0.2, 0.2, 0.3, 0.6)  # 灰色背景
    style.set_corner_radius_all(5)
    style.set_margins_all(10)
    item.add_theme_stylebox_override("panel", style)

    # 容器
    var vbox = VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 3)
    item.add_child(vbox)

    # 发送者信息
    var sender_label = Label.new()
    sender_label.text = message.sender_name
    sender_label.add_theme_font_size_override("font_size", 12)
    if is_sender:
        sender_label.add_theme_color_override("font_color", Color(0.8, 0.8, 1.0))
    else:
        sender_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
    vbox.add_child(sender_label)

    # 消息内容
    var content_label = Label.new()
    content_label.text = message.content
    content_label.add_theme_font_size_override("font_size", 14)
    content_label.add_theme_color_override("font_color", Color.WHITE)
    content_label.autowrap_mode = TextServer.AUTOWRAP_WORD
    vbox.add_child(content_label)

    # 时间和状态
    var info_hbox = HBoxContainer.new()
    info_hbox.add_theme_constant_override("separation", 10)
    vbox.add_child(info_hbox)

    # 时间
    var time_label = Label.new()
    time_label.text = message.get_time_ago()
    time_label.add_theme_font_size_override("font_size", 10)
    time_label.add_theme_color_override("font_color", Color.GRAY)
    info_hbox.add_child(time_label)

    # 状态
    if is_sender:
        var status_text = "✓✓" if message.is_read else "✓"
        var status_label = Label.new()
        status_label.text = status_text
        status_label.add_theme_font_size_override("font_size", 10)
        status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 1.0))
        info_hbox.add_child(status_label)

    return item


## 信号处理

func _on_send_pressed() -> void:
    """发送按钮按下"""
    var content = input_line_edit.text.strip_edges()

    if content.length() == 0:
        return

    if not chat_system:
        return

    # 发送消息
    var message = chat_system.send_message(
        current_user_id,
        "当前玩家",
        current_partner_id,
        current_partner_name,
        content
    )

    if message:
        clear_input()
        _load_conversation()
        print("[ChatUI] Message sent")


func _on_input_submitted(new_text: String) -> void:
    """输入框回车"""
    if new_text.length() > 0:
        _on_send_pressed()


func _on_message_received(message: ChatMessage) -> void:
    """收到消息"""
    # 如果是当前对话的消息，刷新显示
    var user_pair = _get_user_pair(message.sender_id, message.receiver_id)
    var current_pair = _get_user_pair(current_user_id, current_partner_id)

    if user_pair == current_pair:
        _load_conversation()


func _on_message_sent(message: ChatMessage) -> void:
    """消息已发送"""
    # 刷新消息显示
    _load_conversation()


func _on_back_pressed() -> void:
    """返回按钮按下"""
    hide_ui()


func _on_close_pressed() -> void:
    """关闭按钮按下"""
    hide_ui()


## 私有辅助方法

func _get_user_pair(user1_id: String, user2_id: String) -> String:
    """获取用户对"""
    if user1_id < user2_id:
        return "%s|%s" % [user1_id, user2_id]
    else:
        return "%s|%s" % [user2_id, user1_id]


## 调试方法

func print_status() -> void:
    """打印状态"""
    print("\n=== 聊天UI状态 ===")
    print("当前用户: %s" % current_user_id)
    print("对话对象: %s (%s)" % [current_partner_name, current_partner_id])
    print("消息显示: %d" % messages_displayed.size())
    print("==================\n")
