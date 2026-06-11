class_name DealAnimation extends Control

# T5(spec 2026-06-11 G5-a):开局发牌演出。
# 52 张牌背从桌心按"逐家轮发"顺序飞向四家手牌位,总时长 ~1.6s;
# 期间真手牌行隐藏(由调用方 PlayableTable 控制)。
# 对标参考作 .deal-anim。SettingsManager.skip_deal_animation 可关。

const BACK_PATH := "res://assets/tile_back_standing.png"
const TILES_PER_SEAT: int = 13
const STAGGER: float = 0.022
const FLIGHT: float = 0.22

const CENTER := Vector2(540, 360)
# 每家手牌行:起点 + 每张步进 + 牌背旋转角(对手侧视牌横放)
const SEAT_ROWS: Array = [
	[Vector2(204, 632), Vector2(51, 0), 0.0],    # 0 玩家(底,大牌位)
	[Vector2(982, 552), Vector2(0, -31), 90.0],  # 1 右家(向上排)
	[Vector2(742, 142), Vector2(-31, 0), 180.0], # 2 对面(向左排)
	[Vector2(98, 168), Vector2(0, 31), -90.0],   # 3 左家(向下排)
]


# 在 parent 上播放整段发牌;await 至结束并自毁。
static func play_async(parent: Node) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var anim := DealAnimation.new()
	anim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anim.z_index = 150
	parent.add_child(anim)
	await anim._run()
	anim.queue_free()


# 是否跳过:设置项 skip_deal_animation,或 headless(GUT/CI)环境恒跳。
static func should_skip(tree: SceneTree) -> bool:
	if tree == null:
		return true
	if DisplayServer.get_name() == "headless":
		return true
	var sm = tree.root.get_node_or_null("SettingsManager")
	return sm != null and bool(sm.get("skip_deal_animation"))


func _run() -> void:
	var back_tex: Texture2D = load(BACK_PATH) as Texture2D if ResourceLoader.exists(BACK_PATH) else null
	var last_tween: Tween = null
	# 真实配牌序:4 家轮流(简化为逐张轮发,节奏一致)
	for round_i in range(TILES_PER_SEAT):
		for seat in range(4):
			var row: Array = SEAT_ROWS[seat]
			var target: Vector2 = (row[0] as Vector2) + (row[1] as Vector2) * round_i
			var order: int = round_i * 4 + seat
			last_tween = _fly_tile(back_tex, seat, target, order * STAGGER, row[2])
	if last_tween != null:
		await last_tween.finished
	# 收尾停顿一拍,让最后一张落定被看见
	await get_tree().create_timer(0.12).timeout


func _fly_tile(tex: Texture2D, seat: int, target: Vector2, delay: float,
		rot_deg: float) -> Tween:
	var tile: Control
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tile = tr
	else:
		var cr := ColorRect.new()
		cr.color = Color(0.17, 0.36, 0.24)
		tile = cr
	var tile_size := Vector2(26, 38) if seat == 0 else Vector2(22, 32)
	tile.size = tile_size
	tile.pivot_offset = tile_size / 2.0
	tile.rotation_degrees = rot_deg
	tile.position = CENTER - tile_size / 2.0
	tile.scale = Vector2.ONE * 0.4
	tile.modulate = Color(1, 1, 1, 0)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tile)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(tile, "modulate:a", 1.0, 0.08).set_delay(delay)
	tw.tween_property(tile, "position", target - tile_size / 2.0, FLIGHT) \
		.set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(tile, "scale", Vector2.ONE, FLIGHT) \
		.set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return tw
