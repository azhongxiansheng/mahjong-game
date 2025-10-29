class_name LeaderboardUI
extends CanvasLayer

## 排行榜 UI - 负责排行榜的可视化显示和交互

# UI 节点引用
@onready var panel = $Panel
@onready var title_label = $Panel/VBoxContainer/TitleLabel
@onready var tab_container = $Panel/VBoxContainer/TabContainer
@onready var scroll_container = $Panel/VBoxContainer/ScrollContainer
@onready var player_list_container = $Panel/VBoxContainer/ScrollContainer/VBoxContainer
@onready var close_button = $Panel/VBoxContainer/HBoxContainer/CloseButton
@onready var refresh_button = $Panel/VBoxContainer/HBoxContainer/RefreshButton
@onready var stats_label = $Panel/VBoxContainer/HBoxContainer/StatsLabel

# 排行榜系统和计算器
var leaderboard_system: LeaderboardSystem
var rank_calculator: RankCalculator

# 当前显示状态
var current_type: int = LeaderboardSystem.Type.GLOBAL
var current_entries: Array = []
var is_visible_ui: bool = false

# UI 配置
const ENTRY_HEIGHT = 60
const ENTRY_BACKGROUND_COLOR = Color(0.1, 0.1, 0.1, 0.5)
const ENTRY_HIGHLIGHT_COLOR = Color(0.2, 0.3, 0.5, 0.8)

func _ready() -> void:
    """初始化 UI"""
    print("✅ 排行榜 UI 已初始化")
    
    _setup_ui()
    _connect_signals()
    hide()

## 设置 UI 元素
func _setup_ui() -> void:
    """初始化 UI 元素"""
    if panel == null:
        print("❌ Panel 节点未找到")
        return
    
    # 设置标题
    if title_label:
        title_label.text = "🏆 全球排行榜"
    
    # 设置标签页 (排行榜类型)
    if tab_container:
        _setup_tabs()
    
    # 设置按钮
    if close_button:
        close_button.text = "✕ 关闭"
    if refresh_button:
        refresh_button.text = "🔄 刷新"

## 设置排行榜类型标签页
func _setup_tabs() -> void:
    """为不同的排行榜类型创建标签页"""
    var types = [
        {"name": "🌍 全球", "type": LeaderboardSystem.Type.GLOBAL},
        {"name": "🏆 赛季", "type": LeaderboardSystem.Type.SEASONAL},
        {"name": "📅 月度", "type": LeaderboardSystem.Type.MONTHLY},
        {"name": "📆 周度", "type": LeaderboardSystem.Type.WEEKLY},
        {"name": "🔥 日度", "type": LeaderboardSystem.Type.DAILY}
    ]
    
    # 清空现有标签页
    while tab_container.get_tab_count() > 0:
        tab_container.remove_tab(0)
    
    # 添加新标签页
    for i in range(types.size()):
        tab_container.add_tab(types[i].name)

## 连接信号
func _connect_signals() -> void:
    """连接 UI 信号"""
    if tab_container:
        tab_container.tab_changed.connect(_on_tab_changed)
    
    if close_button:
        close_button.pressed.connect(_on_close_pressed)
    
    if refresh_button:
        refresh_button.pressed.connect(_on_refresh_pressed)

## 设置排行榜系统
func set_leaderboard_system(system: LeaderboardSystem, calculator: RankCalculator = null) -> void:
    """
    设置排行榜系统
    参数:
        system: LeaderboardSystem 实例
        calculator: RankCalculator 实例 (可选)
    """
    leaderboard_system = system
    rank_calculator = calculator
    print("✅ 排行榜系统已设置")

## 刷新排行榜显示
func refresh_leaderboard() -> void:
    """刷新排行榜数据显示"""
    if leaderboard_system == null:
        print("❌ 排行榜系统未设置")
        return
    
    print("🔄 正在刷新排行榜...")
    
    # 获取当前类型的排行榜数据
    current_entries = leaderboard_system.get_leaderboard(current_type, 100)
    
    # 更新 UI
    _update_player_list()
    _update_stats()
    
    print("✅ 排行榜已刷新")

## 更新玩家列表显示
func _update_player_list() -> void:
    """更新玩家列表 UI"""
    if player_list_container == null:
        return
    
    # 清空现有列表
    for child in player_list_container.get_children():
        child.queue_free()
    
    # 为每个玩家创建 UI 项
    for i in range(current_entries.size()):
        var entry = current_entries[i]
        var item = _create_entry_item(entry, i + 1)
        player_list_container.add_child(item)

## 创建单个玩家条目 UI
func _create_entry_item(entry: LeaderboardEntry, display_rank: int) -> PanelContainer:
    """
    创建单个排行榜条目 UI
    参数:
        entry: LeaderboardEntry 对象
        display_rank: 显示的排名
    返回:
        PanelContainer UI 元素
    """
    var panel_container = PanelContainer.new()
    panel_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    panel_container.custom_minimum_size = Vector2(0, ENTRY_HEIGHT)
    
    # 设置背景颜色
    var style_box = StyleBoxFlat.new()
    style_box.bg_color = ENTRY_BACKGROUND_COLOR
    style_box.set_border_enabled_all(true)
    style_box.border_color = Color(0.3, 0.3, 0.3, 0.5)
    
    panel_container.add_theme_stylebox_override("panel", style_box)
    
    # 创建容器
    var hbox = HBoxContainer.new()
    hbox.add_theme_constant_override("separation", 10)
    panel_container.add_child(hbox)
    
    # 排名
    var rank_label = Label.new()
    rank_label.text = "#%d" % display_rank
    rank_label.custom_minimum_size = Vector2(50, 0)
    rank_label.add_theme_font_size_override("font_size", 16)
    rank_label.add_theme_color_override("font_color", Color.GOLD)
    hbox.add_child(rank_label)
    
    # 等级符号
    var tier_label = Label.new()
    tier_label.text = entry.get_tier_emoji()
    tier_label.custom_minimum_size = Vector2(30, 0)
    tier_label.add_theme_font_size_override("font_size", 20)
    hbox.add_child(tier_label)
    
    # 玩家名称
    var name_label = Label.new()
    name_label.text = entry.player_name
    name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    name_label.add_theme_font_size_override("font_size", 14)
    hbox.add_child(name_label)
    
    # 等级分
    var rating_label = Label.new()
    rating_label.text = "⭐ %d" % entry.rating
    rating_label.custom_minimum_size = Vector2(100, 0)
    rating_label.alignment = HORIZONTAL_ALIGNMENT_CENTER
    hbox.add_child(rating_label)
    
    # 胜率
    var winrate_label = Label.new()
    winrate_label.text = "%.1f%%" % (entry.win_rate * 100)
    winrate_label.custom_minimum_size = Vector2(80, 0)
    winrate_label.alignment = HORIZONTAL_ALIGNMENT_CENTER
    hbox.add_child(winrate_label)
    
    # 对局数
    var games_label = Label.new()
    games_label.text = "%d 场" % entry.games
    games_label.custom_minimum_size = Vector2(60, 0)
    games_label.alignment = HORIZONTAL_ALIGNMENT_CENTER
    hbox.add_child(games_label)
    
    return panel_container

## 更新统计信息显示
func _update_stats() -> void:
    """更新排行榜统计信息"""
    if leaderboard_system == null or stats_label == null:
        return
    
    var stats = leaderboard_system.get_statistics()
    var leaderboard_type_name = LeaderboardSystem.TYPE_NAMES[current_type]
    
    stats_label.text = "📊 %s | 玩家: %d | 平均分: %d | 最高分: %d" % [
        leaderboard_type_name,
        stats.total_players,
        stats.avg_rating,
        stats.max_rating
    ]

## 标签页切换信号处理
func _on_tab_changed(tab: int) -> void:
    """标签页切换时的处理"""
    current_type = tab
    refresh_leaderboard()
    
    # 更新标题
    if title_label:
        title_label.text = "🏆 " + LeaderboardSystem.TYPE_NAMES[current_type]

## 关闭按钮信号处理
func _on_close_pressed() -> void:
    """关闭按钮被点击"""
    hide()
    is_visible_ui = false

## 刷新按钮信号处理
func _on_refresh_pressed() -> void:
    """刷新按钮被点击"""
    refresh_leaderboard()

## 显示排行榜
func show_leaderboard() -> void:
    """显示排行榜 UI"""
    show()
    is_visible_ui = true
    refresh_leaderboard()

## 隐藏排行榜
func hide_leaderboard() -> void:
    """隐藏排行榜 UI"""
    hide()
    is_visible_ui = false

## 切换排行榜显示
func toggle_leaderboard() -> void:
    """切换排行榜显示状态"""
    if is_visible_ui:
        hide_leaderboard()
    else:
        show_leaderboard()

## 获取排行榜摘要文本 (调试用)
func get_summary() -> String:
    """获取排行榜摘要文本"""
    if leaderboard_system == null:
        return "排行榜系统未初始化"
    return leaderboard_system.get_summary(10)

## 打印排行榜摘要 (调试用)
func print_summary() -> void:
    """打印排行榜摘要"""
    print(get_summary())
