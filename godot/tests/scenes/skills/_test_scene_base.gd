# 6 个 demo skill 手测场景共用基类
# 子类只需覆盖 _build_skill / _on_trigger / 提供标题与按钮文案
class_name SkillTestSceneBase extends Node2D

var _state: BattleState
var _registry: SkillRegistry
var _scheduler: SkillScheduler
var _state_label: Label
var _result_label: Label

func _ready() -> void:
	_setup_ui()
	_reset()

func _setup_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(40, 40)
	vbox.size = Vector2(1200, 640)
	vbox.add_theme_constant_override("separation", 16)
	add_child(vbox)

	var title := Label.new()
	title.text = _scene_title()
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	_state_label = Label.new()
	_state_label.text = "[State Panel]"
	vbox.add_child(_state_label)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(hbox)
	for spec in _trigger_buttons():
		var btn := Button.new()
		btn.text = spec.label
		var bound: Callable = Callable(self, "_handle_trigger").bind(spec.id)
		btn.pressed.connect(bound)
		hbox.add_child(btn)
	var reset_btn := Button.new()
	reset_btn.text = "Reset State"
	reset_btn.pressed.connect(_reset)
	hbox.add_child(reset_btn)

	_result_label = Label.new()
	_result_label.text = "[Result Panel]"
	_result_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_result_label)

func _reset() -> void:
	_state = BattleState.new()
	_registry = SkillRegistry.new()
	_scheduler = SkillScheduler.new(_registry, _state)
	_register_skill()
	_refresh_state_label("(初始化完成,点 Trigger 触发事件)")

func _refresh_state_label(extra: String = "") -> void:
	var lines := PackedStringArray()
	lines.append("scores         = %s" % str(_state.scores))
	lines.append("furiten_flags  = %s" % str(_state.furiten_flags))
	lines.append("ron_cancelled  = %s" % str(_state.ron_cancelled))
	lines.append("revealed_count = %d" % _state.revealed_tiles.size())
	lines.append("haitei_forced  = %d" % _state.haitei_forced_seat)
	lines.append("chain_depth    = %d" % _state.event_chain_depth)
	if extra != "":
		lines.append("")
		lines.append(extra)
	_state_label.text = "\n".join(lines)

func _handle_trigger(trigger_id: StringName) -> void:
	var ctx := _on_trigger(trigger_id)
	var msg := _evaluate(ctx)
	_refresh_state_label(msg)

# ---- 子类覆盖 ----
func _scene_title() -> String:
	return "(子类未覆盖标题)"

func _trigger_buttons() -> Array:
	# 返回 [{id: StringName, label: String}, ...]
	return []

func _register_skill() -> void:
	pass

func _on_trigger(_trigger_id: StringName) -> SkillCtx:
	return null

func _evaluate(_ctx: SkillCtx) -> String:
	return ""
