class_name FriendUI
extends CanvasLayer

## 依赖
var friend_manager: FriendManager
var friend_notifier: FriendNotifier

## UI 组件
var main_panel: PanelContainer
var tab_container: TabContainer
var search_line_edit: LineEdit
var friends_list_container: VBoxContainer
var pending_list_container: VBoxContainer
var blocked_list_container: VBoxContainer
var stats_label: Label
var close_button: Button
var refresh_button: Button

## UI 状态
var is_visible_ui: bool = false
var current_tab: int = 0
var selected_friend_id: String = ""

## 配置
const PANEL_WIDTH = 400
const PANEL_HEIGHT = 600
const FRIEND_ITEM_HEIGHT = 80


## 初始化
func _ready() -> void:
    """初始化好友UI"""
    _create_ui()
    _setup_styles()
    _setup_signals()
    print("[FriendUI] Initialized successfully")


## 公共方法

func set_friend_manager(manager: FriendManager) -> void:
    """设置好友管理器"""
    friend_manager = manager
    if friend_manager:
        friend_manager.notification_received.connect(_on_notification_received)


func set_friend_notifier(notifier: FriendNotifier) -> void:
    """设置好友通知器"""
    friend_notifier = notifier


func show_ui() -> void:
    """显示UI"""
    main_panel.visible = true
    is_visible_ui = true
    _refresh_all()
    print("[FriendUI] UI shown")


func hide_ui() -> void:
    """隐藏UI"""
    main_panel.visible = false
    is_visible_ui = false
    print("[FriendUI] UI hidden")


func toggle_ui() -> void:
    """切换UI显示"""
    if is_visible_ui:
        hide_ui()
    else:
        show_ui()


func refresh_friends() -> void:
    """刷新好友列表"""
    _update_friends_list()
    _update_stats()


func refresh_pending() -> void:
    """刷新待确认列表"""
    _update_pending_list()


func refresh_blocked() -> void:
    """刷新黑名单"""
    _update_blocked_list()


## 私有方法

func _create_ui() -> void:
    """创建UI组件"""
    # 创建主面板
    main_panel = PanelContainer.new()
    main_panel.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
    main_panel.position = Vector2(50, 50)
    main_panel.visible = false
    add_child(main_panel)
    
    # 创建主容器
    var main_vbox = VBoxContainer.new()
    main_vbox.add_theme_constant_override("separation", 5)
    main_panel.add_child(main_vbox)
    
    # 创建顶部栏（标题和按钮）
    var top_hbox = HBoxContainer.new()
    top_hbox.add_theme_constant_override("separation", 10)
    main_vbox.add_child(top_hbox)
    
    var title_label = Label.new()
    title_label.text = "👥 好友列表"
    title_label.add_theme_font_size_override("font_size", 18)
    top_hbox.add_child(title_label)
    
    # 刷新按钮
    refresh_button = Button.new()
    refresh_button.text = "🔄"
    refresh_button.custom_minimum_size = Vector2(40, 40)
    refresh_button.pressed.connect(_on_refresh_pressed)
    top_hbox.add_child(refresh_button)
    
    # 关闭按钮
    close_button = Button.new()
    close_button.text = "✕"
    close_button.custom_minimum_size = Vector2(40, 40)
    close_button.pressed.connect(_on_close_pressed)
    top_hbox.add_child(close_button)
    
    # 创建搜索框
    search_line_edit = LineEdit.new()
    search_line_edit.placeholder_text = "搜索好友..."
    search_line_edit.custom_minimum_size = Vector2(0, 40)
    search_line_edit.text_changed.connect(_on_search_text_changed)
    main_vbox.add_child(search_line_edit)
    
    # 创建选项卡容器
    tab_container = TabContainer.new()
    tab_container.tab_changed.connect(_on_tab_changed)
    main_vbox.add_child(tab_container)
    
    # 创建好友列表选项卡
    var friends_tab = Control.new()
    friends_tab.name = "好友"
    tab_container.add_child(friends_tab)
    
    var friends_vbox = VBoxContainer.new()
    friends_tab.add_child(friends_vbox)
    
    var friends_scroll = ScrollContainer.new()
    friends_scroll.custom_minimum_size = Vector2(0, 300)
    friends_vbox.add_child(friends_scroll)
    
    friends_list_container = VBoxContainer.new()
    friends_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    friends_scroll.add_child(friends_list_container)
    
    # 创建待确认选项卡
    var pending_tab = Control.new()
    pending_tab.name = "待确认"
    tab_container.add_child(pending_tab)
    
    var pending_vbox = VBoxContainer.new()
    pending_tab.add_child(pending_vbox)
    
    var pending_scroll = ScrollContainer.new()
    pending_scroll.custom_minimum_size = Vector2(0, 300)
    pending_vbox.add_child(pending_scroll)
    
    pending_list_container = VBoxContainer.new()
    pending_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    pending_scroll.add_child(pending_list_container)
    
    # 创建黑名单选项卡
    var blocked_tab = Control.new()
    blocked_tab.name = "黑名单"
    tab_container.add_child(blocked_tab)
    
    var blocked_vbox = VBoxContainer.new()
    blocked_tab.add_child(blocked_vbox)
    
    var blocked_scroll = ScrollContainer.new()
    blocked_scroll.custom_minimum_size = Vector2(0, 300)
    blocked_vbox.add_child(blocked_scroll)
    
    blocked_list_container = VBoxContainer.new()
    blocked_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    blocked_scroll.add_child(blocked_list_container)
    
    # 创建统计标签
    stats_label = Label.new()
    stats_label.text = "👥 好友: 0 | 🟢 在线: 0 | 📋 待确认: 0"
    stats_label.add_theme_font_size_override("font_size", 12)
    main_vbox.add_child(stats_label)


func _setup_styles() -> void:
    """设置样式"""
    # 面板样式
    var panel_style = StyleBoxFlat.new()
    panel_style.bg_color = Color(0.05, 0.05, 0.08, 0.95)
    panel_style.set_border_enabled_all(true)
    panel_style.set_border_width_all(2)
    panel_style.border_color = Color(0.3, 0.6, 1.0, 0.8)
    panel_style.set_corner_radius_all(10)
    main_panel.add_theme_stylebox_override("panel", panel_style)


func _setup_signals() -> void:
    """设置信号"""
    pass


func _refresh_all() -> void:
    """刷新所有列表"""
    _update_friends_list()
    _update_pending_list()
    _update_blocked_list()
    _update_stats()


func _update_friends_list() -> void:
    """更新好友列表"""
    # 清空列表
    for child in friends_list_container.get_children():
        child.queue_free()
    
    if not friend_manager:
        return
    
    var friends = friend_manager.get_all_friends()
    
    if friends.size() == 0:
        var empty_label = Label.new()
        empty_label.text = "没有好友"
        empty_label.add_theme_color_override("font_color", Color.GRAY)
        friends_list_container.add_child(empty_label)
        return
    
    # 按在线状态排序
    var online_friends = friend_manager.get_online_friends()
    var offline_friends = []
    for friend in friends:
        if not friend.is_online():
            offline_friends.append(friend)
    
    # 添加在线好友
    for friend in online_friends:
        var item = _create_friend_item(friend)
        friends_list_container.add_child(item)
    
    # 添加离线好友
    for friend in offline_friends:
        var item = _create_friend_item(friend)
        friends_list_container.add_child(item)


func _update_pending_list() -> void:
    """更新待确认列表"""
    # 清空列表
    for child in pending_list_container.get_children():
        child.queue_free()
    
    if not friend_manager:
        return
    
    var pending = friend_manager.get_pending_requests()
    
    if pending.size() == 0:
        var empty_label = Label.new()
        empty_label.text = "没有待确认请求"
        empty_label.add_theme_color_override("font_color", Color.GRAY)
        pending_list_container.add_child(empty_label)
        return
    
    # 添加待确认请求
    for request in pending:
        var item = _create_pending_item(request)
        pending_list_container.add_child(item)


func _update_blocked_list() -> void:
    """更新黑名单"""
    # 清空列表
    for child in blocked_list_container.get_children():
        child.queue_free()
    
    if not friend_manager:
        return
    
    var blocked = friend_manager.get_blocked_players()
    
    if blocked.size() == 0:
        var empty_label = Label.new()
        empty_label.text = "黑名单为空"
        empty_label.add_theme_color_override("font_color", Color.GRAY)
        blocked_list_container.add_child(empty_label)
        return
    
    # 添加黑名单
    for player in blocked:
        var item = _create_blocked_item(player)
        blocked_list_container.add_child(item)


func _update_stats() -> void:
    """更新统计信息"""
    if not friend_manager:
        stats_label.text = "🔗 未连接"
        return
    
    var stats = friend_manager.get_friend_statistics()
    stats_label.text = friend_manager.get_summary_text()


func _create_friend_item(friend: Friend) -> PanelContainer:
    """创建好友项"""
    var item = PanelContainer.new()
    item.custom_minimum_size = Vector2(0, FRIEND_ITEM_HEIGHT)
    
    # 背景样式
    var style = StyleBoxFlat.new()
    style.bg_color = Color(0.1, 0.1, 0.15, 0.7)
    style.set_corner_radius_all(5)
    item.add_theme_stylebox_override("panel", style)
    
    # 容器
    var hbox = HBoxContainer.new()
    hbox.add_theme_constant_override("separation", 10)
    item.add_child(hbox)
    
    # 状态图标
    var status_label = Label.new()
    status_label.text = "🟢" if friend.is_online() else "⚫"
    status_label.add_theme_font_size_override("font_size", 20)
    hbox.add_child(status_label)
    
    # 好友信息容器
    var info_vbox = VBoxContainer.new()
    hbox.add_child(info_vbox)
    
    # 名称和等级
    var name_label = Label.new()
    name_label.text = "%s (Lv.%d ⭐%d)" % [friend.friend_name, friend.level, friend.rating]
    name_label.add_theme_font_size_override("font_size", 14)
    info_vbox.add_child(name_label)
    
    # 等级显示
    var tier_label = Label.new()
    tier_label.text = "%s %s | 胜率: %.1f%%" % [friend.get_tier_emoji(), friend.get_tier(), friend.win_rate * 100]
    tier_label.add_theme_font_size_override("font_size", 12)
    tier_label.add_theme_color_override("font_color", Color.GRAY)
    info_vbox.add_child(tier_label)
    
    # 按钮容器
    var button_hbox = HBoxContainer.new()
    button_hbox.add_theme_constant_override("separation", 5)
    hbox.add_child(button_hbox)
    
    # 聊天按钮
    var chat_button = Button.new()
    chat_button.text = "💬"
    chat_button.custom_minimum_size = Vector2(40, 40)
    button_hbox.add_child(chat_button)
    
    # 删除按钮
    var remove_button = Button.new()
    remove_button.text = "✕"
    remove_button.custom_minimum_size = Vector2(40, 40)
    remove_button.pressed.connect(func():
        if friend_manager:
            friend_manager.remove_friend(friend.friend_id)
            _refresh_all()
    )
    button_hbox.add_child(remove_button)
    
    return item


func _create_pending_item(friend: Friend) -> PanelContainer:
    """创建待确认项"""
    var item = PanelContainer.new()
    item.custom_minimum_size = Vector2(0, FRIEND_ITEM_HEIGHT)
    
    # 背景样式
    var style = StyleBoxFlat.new()
    style.bg_color = Color(0.15, 0.12, 0.08, 0.7)
    style.set_corner_radius_all(5)
    item.add_theme_stylebox_override("panel", style)
    
    # 容器
    var hbox = HBoxContainer.new()
    hbox.add_theme_constant_override("separation", 10)
    item.add_child(hbox)
    
    # 请求图标
    var icon_label = Label.new()
    icon_label.text = "👋"
    icon_label.add_theme_font_size_override("font_size", 20)
    hbox.add_child(icon_label)
    
    # 名称
    var name_label = Label.new()
    name_label.text = "%s 请求添加你为好友" % friend.friend_name
    name_label.add_theme_font_size_override("font_size", 14)
    hbox.add_child(name_label)
    
    # 按钮容器
    var button_hbox = HBoxContainer.new()
    button_hbox.add_theme_constant_override("separation", 5)
    hbox.add_child(button_hbox)
    
    # 接受按钮
    var accept_button = Button.new()
    accept_button.text = "✓"
    accept_button.custom_minimum_size = Vector2(40, 40)
    accept_button.pressed.connect(func():
        if friend_manager:
            friend_manager.accept_friend_request(friend.friend_id)
            _refresh_all()
    )
    button_hbox.add_child(accept_button)
    
    # 拒绝按钮
    var reject_button = Button.new()
    reject_button.text = "✕"
    reject_button.custom_minimum_size = Vector2(40, 40)
    reject_button.pressed.connect(func():
        if friend_manager:
            friend_manager.reject_friend_request(friend.friend_id)
            _refresh_all()
    )
    button_hbox.add_child(reject_button)
    
    return item


func _create_blocked_item(player: Friend) -> PanelContainer:
    """创建黑名单项"""
    var item = PanelContainer.new()
    item.custom_minimum_size = Vector2(0, 60)
    
    # 背景样式
    var style = StyleBoxFlat.new()
    style.bg_color = Color(0.15, 0.08, 0.08, 0.7)
    style.set_corner_radius_all(5)
    item.add_theme_stylebox_override("panel", style)
    
    # 容器
    var hbox = HBoxContainer.new()
    hbox.add_theme_constant_override("separation", 10)
    item.add_child(hbox)
    
    # 屏蔽图标
    var icon_label = Label.new()
    icon_label.text = "🚫"
    icon_label.add_theme_font_size_override("font_size", 20)
    hbox.add_child(icon_label)
    
    # 名称
    var name_label = Label.new()
    name_label.text = player.friend_name
    name_label.add_theme_font_size_override("font_size", 14)
    hbox.add_child(name_label)
    
    # 解除屏蔽按钮
    var unblock_button = Button.new()
    unblock_button.text = "解除"
    unblock_button.custom_minimum_size = Vector2(60, 40)
    unblock_button.pressed.connect(func():
        if friend_manager:
            friend_manager.unblock_player(player.friend_id)
            _refresh_all()
    )
    hbox.add_child(unblock_button)
    
    return item


## 信号处理

func _on_tab_changed(tab: int) -> void:
    """选项卡改变"""
    current_tab = tab
    match tab:
        0:
            _update_friends_list()
        1:
            _update_pending_list()
        2:
            _update_blocked_list()


func _on_search_text_changed(new_text: String) -> void:
    """搜索文本改变"""
    if not friend_manager:
        return
    
    if new_text.length() < 2:
        _update_friends_list()
        return
    
    var results = friend_manager.search_friends(new_text)
    
    # 清空并显示搜索结果
    for child in friends_list_container.get_children():
        child.queue_free()
    
    if results.size() == 0:
        var empty_label = Label.new()
        empty_label.text = "未找到匹配的好友"
        empty_label.add_theme_color_override("font_color", Color.GRAY)
        friends_list_container.add_child(empty_label)
        return
    
    for friend in results:
        var item = _create_friend_item(friend)
        friends_list_container.add_child(item)


func _on_refresh_pressed() -> void:
    """刷新按钮按下"""
    _refresh_all()
    if friend_notifier:
        friend_notifier.show_notification("🔄 刷新", "好友列表已刷新")


func _on_close_pressed() -> void:
    """关闭按钮按下"""
    hide_ui()


func _on_notification_received(title: String, message: String) -> void:
    """收到通知"""
    if friend_notifier:
        friend_notifier.show_notification(title, message)
