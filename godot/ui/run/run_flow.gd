class_name RunFlow extends Control

# 麻将王 — 里程碑 4 第 4 步：Run 流程主控制器（plan-4 D6）
#
# 把 5 个 UI 子组件 + RunState + GameDriver 串成完整 Run：
#   1. starter_pack_picker → 选起始包 → new RunState
#   2. chapter_map_view → 玩家选下一节点
#   3a. 战斗节点 → BattleNodeRunner.run_battle_to_node_result → NodeResult
#   3b. 占位节点 → placeholder_node → "下一步"按钮 → from_placeholder
#   4. RunState.complete_node(result) → emit node_completed / run_failed / run_won
#   5. 失败 / 通关 → run_summary
#   6. "返回主菜单" → 回 starter_pack_picker

const STARTER_PACK_PICKER := preload("res://ui/run/starter_pack_picker.tscn")
const CHAPTER_MAP_VIEW := preload("res://ui/run/chapter_map_view.tscn")
const PLACEHOLDER_NODE := preload("res://ui/run/placeholder_node.tscn")
const RUN_SUMMARY := preload("res://ui/run/run_summary.tscn")
const RUN_HUD := preload("res://ui/run/run_hud.tscn")

var _run_state: RunState = null
var _hud: RunHud = null
var _current_panel: Control = null
var _last_node_ref: NodeRef = null
var _last_result: NodeResult = null
var _seed_seed: int = 42  # 全 Run 种子（每 Run 不同避免重复）

func _ready() -> void:
	custom_minimum_size = Vector2(1280, 720)
	_hud = RUN_HUD.instantiate()
	_hud.position = Vector2(0, 0)
	add_child(_hud)
	_show_starter_picker()

# ---- panel transitions ----

func _show_starter_picker() -> void:
	var picker: StarterPackPicker = STARTER_PACK_PICKER.instantiate()
	_swap_panel(picker)
	picker.pack_chosen.connect(_on_pack_chosen)

func _show_chapter_map() -> void:
	var view: ChapterMapView = CHAPTER_MAP_VIEW.instantiate()
	_swap_panel(view)
	view.set_options(_run_state.next_node_options())
	if _last_node_ref and _last_result:
		view.set_last_result_text(
			ChapterMapView.format_last_result(_last_node_ref, _last_result)
		)
	view.node_chosen.connect(_on_node_chosen)

func _show_summary() -> void:
	var summary: RunSummary = RUN_SUMMARY.instantiate()
	_swap_panel(summary)
	summary.bind_run_state(_run_state)
	summary.back_to_menu.connect(_reset)

# ---- callbacks ----

func _on_pack_chosen(pack_id: StringName) -> void:
	_run_state = RunState.new(_seed_seed)
	StarterPacks.apply_to(_run_state, pack_id)
	_run_state.node_completed.connect(_on_run_node_completed)
	_run_state.run_failed.connect(_on_run_failed)
	_run_state.run_won.connect(_on_run_won)
	_hud.bind_run_state(_run_state)
	_show_chapter_map()

func _on_node_chosen(node_index: int) -> void:
	_run_state.choose_next_node(node_index)
	var node_ref: NodeRef = _run_state.current_node_ref()
	_last_node_ref = node_ref
	if NodeKind.is_battle(node_ref.kind):
		_run_battle_node(node_ref)
	else:
		_show_placeholder(node_ref)

func _on_run_node_completed(_opts: Array) -> void:
	_hud.bind_run_state(_run_state)
	_show_chapter_map()

func _on_run_failed() -> void:
	_hud.bind_run_state(_run_state)
	_show_summary()

func _on_run_won() -> void:
	_hud.bind_run_state(_run_state)
	_show_summary()

# ---- node execution ----

# 战斗节点：v1 直接同步跑 BattleNodeRunner，不显示 4 人桌（M5/M6 视觉化时
# 改成 await 模式 + 显示 four_player_table.tscn）。
func _run_battle_node(node_ref: NodeRef) -> void:
	# 显示一个简单"战斗中..."Label 占位（v1 不卡顿，跑完毕就进结算）
	var battle_label := _make_loading_label(_loading_text_for_battle(node_ref))
	_swap_panel(battle_label)
	# 用节点 index 做 seed 偏移，避免同 Run 重复牌局
	var node_seed: int = _run_state.run_seed * 100 + node_ref.index
	var result: NodeResult = BattleNodeRunner.run_battle_to_node_result(node_seed)
	_last_result = result
	_run_state.complete_node(result)

func _show_placeholder(node_ref: NodeRef) -> void:
	var p: PlaceholderNode = PLACEHOLDER_NODE.instantiate()
	_swap_panel(p)
	p.set_node_kind(node_ref.kind)
	p.done.connect(func():
		_last_result = BattleNodeRunner.placeholder_result()
		_run_state.complete_node(_last_result)
	)

# ---- helpers ----

func _swap_panel(new_panel: Control) -> void:
	if _current_panel:
		_current_panel.queue_free()
	new_panel.position = Vector2(0, 50)  # HUD 占了 0..40
	add_child(new_panel)
	_current_panel = new_panel

func _make_loading_label(text: String) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(800, 600)
	var lbl := Label.new()
	lbl.text = text
	lbl.size = Vector2(800, 600)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 24)
	c.add_child(lbl)
	return c

static func _loading_text_for_battle(node_ref: NodeRef) -> String:
	var label := node_ref.display_name() if node_ref else "战斗"
	return "%s 进行中…\n（v1 v1 同步跑完整场东风战，无 4 人桌动画；M5/M6 视觉化）" % label

func _reset() -> void:
	_run_state = null
	_last_node_ref = null
	_last_result = null
	# Run 间种子不同
	_seed_seed += 1
	_hud._refresh_default()
	_show_starter_picker()
