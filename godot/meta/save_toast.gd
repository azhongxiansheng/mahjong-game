extends Node

# SaveToast - autoload 监听 SaveSystem.save_completed,弹小 "💾 已保存" toast
# 1.2s 自动消失。商业级 polish — 玩家知道存档有发生,不会担心进度丢失。
#
# 监听 emit 后 build CanvasLayer + Label + Tween,旧 toast 仍可见时不重叠
# (kill 老 tween 再新建)。

const TOAST_LIFETIME: float = 1.2

var _layer: CanvasLayer = null
var _label: Label = null
var _tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 监听 SaveSystem(也是 autoload — 启动顺序看 project.godot,SaveSystem 在
	# SaveToast 之前注册即可。defer 避免 ready 期 autoload 还没 hook 上)
	call_deferred("_connect_save_system")


func _connect_save_system() -> void:
	var ss = get_node_or_null("/root/SaveSystem")
	if ss == null:
		return
	if ss.has_signal("save_completed") and not ss.save_completed.is_connected(_on_save_completed):
		ss.save_completed.connect(_on_save_completed)


func _on_save_completed() -> void:
	_show_toast("💾 已保存")


# 公开 API:外部模块也可调(成就/Run 通关等场合自定义提示)
func show_message(text: String) -> void:
	_show_toast(text)


func _show_toast(text: String) -> void:
	_ensure_ui()
	if _label == null:
		return
	_label.text = text
	if _tween and _tween.is_valid():
		_tween.kill()
	_label.modulate = Color(1, 1, 1, 0)
	_tween = create_tween()
	_tween.tween_property(_label, "modulate:a", 1.0, 0.15)
	_tween.tween_interval(TOAST_LIFETIME - 0.45)
	_tween.tween_property(_label, "modulate:a", 0.0, 0.30)


func _ensure_ui() -> void:
	if _layer != null:
		return
	_layer = CanvasLayer.new()
	_layer.layer = 99
	add_child(_layer)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.85, 1, 0.85))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.92))
	# 右下角靠边:1280×800 默认 viewport。anchor 右下,offset 内推一点
	_label.anchor_left = 1.0
	_label.anchor_top = 1.0
	_label.anchor_right = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_left = -200
	_label.offset_top = -50
	_label.offset_right = -16
	_label.offset_bottom = -16
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.modulate = Color(1, 1, 1, 0)
	_layer.add_child(_label)
