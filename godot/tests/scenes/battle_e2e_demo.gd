extends Control

# 里程碑 2 — F6 手测 demo。
# 极简 UI：4 座手牌字符串 + 事件 log + 「重跑」按钮（不同 seed）。
# 不引用 atlas / TextureExtractor，避开纹理不变量。

const _TILE_NAMES: Dictionary = {
	TileId.W1: "1m", TileId.W2: "2m", TileId.W3: "3m", TileId.W4: "4m",
	TileId.W5: "5m", TileId.W6: "6m", TileId.W7: "7m", TileId.W8: "8m",
	TileId.W9: "9m",
	TileId.T1: "1p", TileId.T2: "2p", TileId.T3: "3p", TileId.T4: "4p",
	TileId.T5: "5p", TileId.T6: "6p", TileId.T7: "7p", TileId.T8: "8p",
	TileId.T9: "9p",
	TileId.S1: "1s", TileId.S2: "2s", TileId.S3: "3s", TileId.S4: "4s",
	TileId.S5: "5s", TileId.S6: "6s", TileId.S7: "7s", TileId.S8: "8s",
	TileId.S9: "9s",
	TileId.E: "E", TileId.S_WIND: "S", TileId.W_WIND: "W", TileId.N: "N",
	TileId.HAKU: "白", TileId.HATSU: "发", TileId.CHUN: "中",
}

@onready var _seat_labels: Array[Label] = [
	$Layout/Seats/Seat0, $Layout/Seats/Seat1,
	$Layout/Seats/Seat2, $Layout/Seats/Seat3,
]
@onready var _log: RichTextLabel = $Layout/EventLog
@onready var _summary: Label = $Layout/Summary
@onready var _seed_input: SpinBox = $Layout/Controls/SeedInput

func _ready() -> void:
	$Layout/Controls/RunButton.pressed.connect(_on_run_pressed)
	_seed_input.value = 42
	_run(int(_seed_input.value))

func _on_run_pressed() -> void:
	_seed_input.value = int(_seed_input.value) + 1
	_run(int(_seed_input.value))

func _run(seed: int) -> void:
	var bc := BattleController.new(seed, 0)
	var result: Dictionary = bc.run_to_end()

	for i in range(4):
		_seat_labels[i].text = "seat %d (%s): %s" % [
			i, _wind_name(bc.state.seats[i].seat_wind), _hand_str(bc.state.seats[i].hand)
		]

	_log.clear()
	_log.append_text("[b]seed=%d[/b]\n" % seed)
	for ev in result.events:
		_log.append_text("%s actor=%d%s\n" % [
			ev.type,
			ev.actor_seat,
			(" tile=%s" % _tile_str(ev.tile_anchor.tile)) if ev.tile_anchor != null else "",
		])

	_summary.text = "最末事件: %s | 事件总数: %d | scores: %s" % [
		result.last_event,
		result.events.size(),
		bc.state.scores,
	]

func _hand_str(hand: Hand) -> String:
	var parts: Array = []
	for t in hand.tiles():
		parts.append(_tile_str(t))
	return " ".join(parts)

func _tile_str(t: Tile) -> String:
	if t == null:
		return "?"
	return _TILE_NAMES.get(t.id, str(t.id))

func _wind_name(w: int) -> String:
	match w:
		TileId.E: return "东"
		TileId.S_WIND: return "南"
		TileId.W_WIND: return "西"
		TileId.N: return "北"
		_: return "?"
