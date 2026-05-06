extends Node2D

# F6 手测：玩家完整可玩 1 局东风局 vs 3 个 AI。
# 玩家 = seat 0；可点切手牌、宣告自摸/立直/荣和。

const PLAYABLE_TABLE := preload("res://ui/four_player_table/playable_table.tscn")

var _table: PlayableTable = null
var _bc: PlayableBattleController = null
var _result_label: Label = null

func _ready() -> void:
	_table = PLAYABLE_TABLE.instantiate()
	_table.position = Vector2(0, 0)
	add_child(_table)

	# 测试结果浮层（顶部）
	_result_label = Label.new()
	_result_label.text = "玩家可玩战斗 — 一局东风局测试。点手牌切；可立直/自摸/荣和。"
	_result_label.position = Vector2(20, 4)
	_result_label.size = Vector2(1240, 24)
	_result_label.add_theme_font_size_override("font_size", 14)
	_result_label.add_theme_color_override("font_color", Color(1, 1, 0.7))
	add_child(_result_label)

	_run_one_hand()

func _run_one_hand() -> void:
	_bc = PlayableBattleController.new(42, 0, false, TileId.E)
	var result: Dictionary = await _table.play_hand_async(_bc)
	var last_event: String = String(result.get("last_event", "?"))
	_result_label.text = "本局结束：last_event=%s | scores=%s" % [last_event, str(_bc.state.scores)]
