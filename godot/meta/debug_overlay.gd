extends Node

# DebugOverlay - autoload 单例,F3 toggle 半透明 Pro 调试面板。
# 显示运行时关键指标:FPS / draw calls / autoload 实例 / 当前 PlayableBattleController state 摘要。
# 非 Debug builds 也包含(轻量,无业务逻辑),靠 F3 / settings.show_debug_overlay 开关。
#
# 设计:UI 走 CanvasLayer + Panel,挂在 root tree。每 0.5s 刷新内容(避免每帧 GC 压力)。
# 当 PlayableBattleController 在场景树某处时自动追踪;否则只显基础信息。

const PANEL_W: int = 320
const PANEL_H: int = 240
const REFRESH_INTERVAL: float = 0.5

var _layer: CanvasLayer = null
var _panel: Panel = null
var _label: Label = null
var _visible: bool = false
var _accumulator: float = 0.0


func _ready() -> void:
	# 不暂停 game pause
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100  # 最顶层
	add_child(_layer)

	_panel = Panel.new()
	_panel.custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	_panel.size = Vector2(PANEL_W, PANEL_H)
	_panel.position = Vector2(8, 8)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不挡点击
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.72)
	sb.border_color = Color(0.5, 0.5, 0.5, 0.6)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	_panel.add_theme_stylebox_override("panel", sb)
	_layer.add_child(_panel)

	_label = Label.new()
	_label.position = Vector2(10, 8)
	_label.size = Vector2(PANEL_W - 20, PANEL_H - 16)
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(0.85, 1, 0.85))
	_label.add_theme_constant_override("line_spacing", 2)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)

	_layer.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo and k.keycode == KEY_F3:
			toggle()
			get_viewport().set_input_as_handled()


func toggle() -> void:
	_visible = not _visible
	if _layer:
		_layer.visible = _visible
	if _visible:
		_refresh()


func _process(delta: float) -> void:
	if not _visible:
		return
	_accumulator += delta
	if _accumulator >= REFRESH_INTERVAL:
		_accumulator = 0.0
		_refresh()


# BattleController 是 RefCounted 不在树中。PlayableTable 在 play_hand_async
# 里调 DebugOverlay.register_battle_controller(bc) 注册;hand 结束时调 unregister。
var _active_bc = null


func register_battle_controller(bc) -> void:
	_active_bc = bc


func unregister_battle_controller(bc) -> void:
	if _active_bc == bc:
		_active_bc = null


# 收集运行时数据 → 文本。完整 reference 调用都 try/catch,UI 工具不该因业务异常崩。
func _refresh() -> void:
	if _label == null:
		return
	var lines: PackedStringArray = []
	# 基础 perf
	lines.append("=== DEBUG OVERLAY (F3 toggle) ===")
	lines.append("FPS: %d" % Engine.get_frames_per_second())
	var phys_fps: float = float(Engine.physics_ticks_per_second)
	if phys_fps > 0:
		lines.append("Physics tick: %d Hz" % int(phys_fps))
	lines.append("Frame: %d" % Engine.get_process_frames())
	# 节点数
	var tree := get_tree()
	if tree and tree.root:
		lines.append("Nodes: %d" % _count_nodes(tree.root))
	# Autoload 实例
	lines.append("")
	lines.append("--- Autoloads ---")
	for n in ["AudioManager", "SettingsManager", "StatsManager",
			"SaveSystem", "MetaProgress", "DebugOverlay"]:
		var present: bool = tree and tree.root.get_node_or_null("/root/" + n) != null
		lines.append("  %s: %s" % [n, "✓" if present else "✗"])
	# 当前 PlayableBattleController(由 PlayableTable register)
	lines.append("")
	lines.append("--- Battle state ---")
	if _active_bc != null and _active_bc.state != null:
		var s = _active_bc.state
		lines.append("phase=%d  current=%d  dealer=%d" % [
			int(s.phase), int(s.current_seat), int(s.dealer_seat)])
		lines.append("turn_count: %d  honba: %d" % [int(s.turn_count), int(s.honba)])
		lines.append("riichi_sticks: %d" % int(s.riichi_sticks))
		if s.wall:
			lines.append("wall_live: %d" % int(s.wall.live_wall_size()))
		lines.append("dora_indicators: %d" % s.dora_indicators.visible.size())
		lines.append("event_chain_depth: %d" % int(s.event_chain_depth))
		lines.append("scores: %s" % str(s.scores))
	else:
		lines.append("(no BattleController registered)")
	_label.text = "\n".join(lines)


# 递归计数节点(供 perf 显示)
static func _count_nodes(root: Node) -> int:
	var c: int = 1
	for child in root.get_children():
		c += _count_nodes(child)
	return c
