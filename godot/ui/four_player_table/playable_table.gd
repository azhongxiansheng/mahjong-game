class_name PlayableTable extends Control

# 麻将王 — 战斗节点真实可玩 顶层容器。
#
# 组合 FourPlayerTable + PlayerActionPanel + PlayableBattleController，
# 跑一局完整东风局玩家可玩对战。
#
# 1280×800：上方 720 给 four_player_table（含旋转的 4 个 SeatPanel），
# 下方 80 给 player_action_panel。

const FOUR_PLAYER_TABLE := preload("res://ui/four_player_table/four_player_table.tscn")
const PLAYER_ACTION_PANEL := preload("res://ui/four_player_table/player_action_panel.tscn")

const TABLE_HEIGHT: float = 720.0
const ACTION_PANEL_HEIGHT: float = 80.0

var _table: FourPlayerTable = null
var _action_panel: PlayerActionPanel = null
var _bc: PlayableBattleController = null

var _seat_panel_player: SeatPanel = null

func _ready() -> void:
	custom_minimum_size = Vector2(1280, TABLE_HEIGHT + ACTION_PANEL_HEIGHT)
	_build_layout()

func _build_layout() -> void:
	_table = FOUR_PLAYER_TABLE.instantiate()
	_table.position = Vector2(0, 0)
	add_child(_table)

	_action_panel = PLAYER_ACTION_PANEL.instantiate()
	# ActionPanel 在桌面下方 80 px 区，居中
	_action_panel.position = Vector2((_table.TABLE_WIDTH - PlayerActionPanel.PANEL_W) / 2.0, _table.TABLE_HEIGHT + 5)
	add_child(_action_panel)

func play_hand_async(bc: PlayableBattleController) -> Dictionary:
	_bc = bc
	if _table.seat_panels.size() >= 1:
		_seat_panel_player = _table.seat_panels[0]
		if not _seat_panel_player.player_card_clicked.is_connected(_on_player_tile_clicked):
			_seat_panel_player.player_card_clicked.connect(_on_player_tile_clicked)
	_bc.bind_ui(_action_panel, _seat_panel_player, get_tree())
	_table.bind_battle_state(bc.state, 0, 4)
	_action_panel.enter_idle("准备开局…")
	_attach_event_polling()
	var result: Dictionary = await bc.run_to_end_async()
	_action_panel.enter_idle("本局结束")
	_table.bind_battle_state(bc.state, 0, 4)
	return result

var _last_event_count: int = 0
var _polling_active: bool = false

func _attach_event_polling() -> void:
	if _polling_active:
		return
	_polling_active = true
	_polling_loop()

func _polling_loop() -> void:
	while _polling_active and _bc != null:
		await get_tree().process_frame
		if _bc == null:
			return
		var n: int = _bc.events.size()
		if n != _last_event_count:
			_last_event_count = n
			if is_instance_valid(_table) and _bc.state != null:
				_table.bind_battle_state(_bc.state, 0, 4)

func _exit_tree() -> void:
	_polling_active = false

func _on_player_tile_clicked(tile_id: int) -> void:
	if _action_panel != null:
		_action_panel.on_hand_tile_clicked(tile_id)
