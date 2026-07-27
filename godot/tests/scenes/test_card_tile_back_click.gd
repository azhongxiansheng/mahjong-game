extends GutTest

# CardTileBack — 点击响应 + clickable gating 单测。
# 视觉/atlas 渲染走 F6 手测（card_tile_back_face_test.tscn）。

var _tile: CardTileBack = null
var _captured_instance_id: int = -999

func before_each() -> void:
	_tile = CardTileBack.new()
	add_child_autofree(_tile)
	# 等 _ready 跑完（gui_input 连接在 _ready 中）
	await get_tree().process_frame
	_tile.card_clicked.connect(_on_clicked)
	_captured_instance_id = -999

func _on_clicked(tile_instance_id: int) -> void:
	_captured_instance_id = tile_instance_id

func _set_action_tile(tile_id: int, tile_instance_id: int) -> void:
	var tile := Tile.new(tile_id, false, 0, tile_instance_id)
	_tile.set_tile_instance(TileSkillAnchor.make(tile, 0))

func _emit_left_click() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	_tile._on_gui_input(ev)

func test_click_does_not_fire_when_not_clickable() -> void:
	_set_action_tile(TileId.W5, 104)
	# 默认 _is_clickable = false
	_emit_left_click()
	assert_eq(_captured_instance_id, -999, "未启用 clickable 时点击应被吞")

func test_click_fires_card_clicked_with_instance_id_when_clickable() -> void:
	_set_action_tile(TileId.W5, 104)
	_tile.set_clickable(true)
	_emit_left_click()
	assert_eq(_captured_instance_id, 104,
		"可点击时应 emit card_clicked(tile_instance_id)")

func test_click_with_other_tile_instance_id() -> void:
	_set_action_tile(TileId.HAKU, 131)
	_tile.set_clickable(true)
	_emit_left_click()
	assert_eq(_captured_instance_id, 131)

func test_set_clickable_false_blocks_subsequent_clicks() -> void:
	_set_action_tile(TileId.S3, 120)
	_tile.set_clickable(true)
	_emit_left_click()
	assert_eq(_captured_instance_id, 120)
	# reset 后切 clickable=false
	_captured_instance_id = -999
	_tile.set_clickable(false)
	_emit_left_click()
	assert_eq(_captured_instance_id, -999, "切回 false 后点击应再次被吞")

func test_right_click_does_not_fire() -> void:
	_set_action_tile(TileId.T7, 115)
	_tile.set_clickable(true)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	_tile._on_gui_input(ev)
	assert_eq(_captured_instance_id, -999, "右键不应 emit card_clicked")

func test_release_does_not_fire() -> void:
	_set_action_tile(TileId.T7, 115)
	_tile.set_clickable(true)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false  # 松开
	_tile._on_gui_input(ev)
	assert_eq(_captured_instance_id, -999, "松开事件不应 emit card_clicked")
