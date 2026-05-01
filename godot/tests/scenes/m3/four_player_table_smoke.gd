extends Control

# 麻将王 — 里程碑 3 第 2 步：4 人桌 F6 烟测场景
#
# 在 Godot 编辑器打开本场景按 F6：
#   - 视觉验证 4 个 SeatPanel 按 0/-90/180/+90 旋转摆四方位
#   - CenterInfoPanel 在中心显示「东 1 局 / 牌墙 70 / Dora: ...」
#   - AbilityPanel 在右侧显示 5 个空槽
#   - "Re-roll" 按钮重换 seed 看 dora 切换、风牌不变
#
# 与第 4 步的差别：本场景不跑 BattleController；只构造静态 BattleState 喂面板。
# 第 4 步会接入 GameDriver 真跑一整场东风战。

const FOUR_PLAYER_TABLE_SCENE := preload("res://ui/four_player_table/four_player_table.tscn")

var _table: FourPlayerTable = null
var _seed: int = 42
var _hand_index: int = 0
var _info_label: Label = null

func _ready() -> void:
	custom_minimum_size = Vector2(1280, 720)

	_table = FOUR_PLAYER_TABLE_SCENE.instantiate()
	add_child(_table)

	# 顶部状态条 + Re-roll 按钮
	var hbox := HBoxContainer.new()
	hbox.position = Vector2(10, 4)
	hbox.add_theme_constant_override("separation", 12)
	add_child(hbox)

	_info_label = Label.new()
	_info_label.text = "[smoke] seed=%d hand=%d" % [_seed, _hand_index]
	hbox.add_child(_info_label)

	var btn_reroll := Button.new()
	btn_reroll.text = "Re-roll seed +1"
	btn_reroll.pressed.connect(_on_reroll)
	hbox.add_child(btn_reroll)

	var btn_advance := Button.new()
	btn_advance.text = "Next hand (mock)"
	btn_advance.pressed.connect(_on_next_hand)
	hbox.add_child(btn_advance)

	_apply_mock_state()

func _apply_mock_state() -> void:
	# 用 BattleState.for_east_round 构造一个真实的初始 4 家状态
	# dealer=0..3 按 hand_index 旋转
	var dealer: int = _hand_index % 4
	var state := BattleState.for_east_round(_seed + _hand_index, dealer, _hand_index + 1, 0, 0)
	_table.bind_battle_state(state, _hand_index)
	_table.bind_cumulative_scores([25000, 25000, 25000, 25000])
	_info_label.text = "[smoke] seed=%d hand=%d dealer=%d wall=%d" % [
		_seed, _hand_index, dealer, state.wall.live_wall_size()
	]

func _on_reroll() -> void:
	_seed += 1
	_apply_mock_state()

func _on_next_hand() -> void:
	_hand_index = (_hand_index + 1) % 4
	_apply_mock_state()
