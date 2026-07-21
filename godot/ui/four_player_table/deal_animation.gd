class_name DealAnimation extends Control

# T5(spec 2026-06-11 G5-a):开局发牌演出。
# 严格对齐参考 bundle:按 4/4/4/1 四轮发牌,每轮同一家同时落下;
# 前三轮相邻玩家间隔 95ms,末轮 65ms,总时长 1675ms。
# 期间真手牌行隐藏(由调用方 PlayableTable 控制)。
# 对标参考作 .deal-anim。SettingsManager.skip_deal_animation 可关。

const BACK_PATH := "res://assets/tile_back_standing.png"
const TILES_PER_SEAT: int = 13
const DEAL_BLOCKS := [4, 4, 4, 1]
const BLOCK_INTERVAL: float = 0.095
const LAST_BLOCK_INTERVAL: float = 0.065
const FLIGHT: float = 0.115
const SETTLE_TIME: float = 0.160
const TOTAL_DURATION: float = 1.675
const DROP_OFFSET_Y: float = 14.0

var _target_rects: Array = []


# 在 parent 上播放整段发牌;await 至结束并自毁。
static func play_async(parent: Node) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var target_rects := _collect_target_rects(parent)
	if target_rects.size() != 4:
		return
	var anim := DealAnimation.new()
	anim._target_rects = target_rects
	anim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anim.z_index = 150
	parent.add_child(anim)
	await anim._run()
	anim.queue_free()
	await anim.tree_exited
	# tree_exited 早于 Object 真正释放；再过一帧，避免 52 张演出牌成为瞬时 orphan。
	await parent.get_tree().process_frame


# 与网页 getBoundingClientRect() 同构:运行时读取真实 13 个手牌槽,不维护魔法坐标。
static func _collect_target_rects(parent: Node) -> Array:
	var table = parent.get("_table")
	if table == null:
		return []
	var panels: Array = table.get("seat_panels")
	if panels.size() != 4:
		return []
	var result: Array = []
	for panel in panels:
		if panel == null or not panel.has_method("get_deal_target_rects"):
			return []
		var rects: Array = panel.get_deal_target_rects()
		if rects.size() < TILES_PER_SEAT:
			return []
		result.append(rects.slice(0, TILES_PER_SEAT))
	return result


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
	_start_block_sounds()
	for entry in build_reference_schedule():
		var seat_id: int = int(entry["seat"])
		var tile_index: int = int(entry["tile_index"])
		var rect: Rect2 = _target_rects[seat_id][tile_index]
		_drop_tile(back_tex, rect, float(entry["delay"]), seat_id)
	await get_tree().create_timer(TOTAL_DURATION).timeout


func build_reference_schedule() -> Array:
	var schedule: Array = []
	var elapsed: float = 0.0
	var tile_base: int = 0
	for block_id in range(DEAL_BLOCKS.size()):
		var block_size: int = int(DEAL_BLOCKS[block_id])
		var interval: float = BLOCK_INTERVAL if block_size > 1 else LAST_BLOCK_INTERVAL
		for seat_id in range(4):
			var delay: float = elapsed + seat_id * interval
			for offset in range(block_size):
				schedule.append({
					"block": block_id,
					"seat": seat_id,
					"tile_index": tile_base + offset,
					"delay": delay,
				})
		elapsed += interval * 4.0
		tile_base += block_size
	return schedule


func _start_block_sounds() -> void:
	var tw := create_tween()
	for block_size in DEAL_BLOCKS:
		tw.tween_callback(_play_deal_block_sound)
		var interval: float = BLOCK_INTERVAL if int(block_size) > 1 else LAST_BLOCK_INTERVAL
		tw.tween_interval(interval * 4.0)


func _play_deal_block_sound() -> void:
	var audio = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play"):
		audio.play("tile_draw", 0.04, 0.8)


func _drop_tile(tex: Texture2D, target_rect: Rect2, delay: float,
		seat_id: int = 0) -> Tween:
	var tile: Control
	if seat_id == 1 or seat_id == 3:
		tile = SeatPanel.make_reference_side_cube(seat_id == 3)
	elif tex != null:
		var tex_rect := TextureRect.new()
		tex_rect.texture = tex
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
		tile = tex_rect
	else:
		var cr := ColorRect.new()
		cr.color = Color(0.17, 0.36, 0.24)
		tile = cr
	var tile_size := target_rect.size
	tile.size = tile_size
	tile.pivot_offset = tile_size / 2.0
	var target: Vector2 = get_global_transform().affine_inverse() * target_rect.position
	var start := target - Vector2(0, DROP_OFFSET_Y)
	tile.position = start
	tile.modulate = Color(1, 1, 1, 0)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tile)
	var tw := create_tween()
	tw.tween_interval(delay)
	var update := func(progress: float) -> void:
		var eased := reference_ease(progress)
		tile.position = start.lerp(target, eased)
		tile.modulate.a = eased
	tw.tween_method(update, 0.0, 1.0, FLIGHT)
	return tw


# Framer Motion ease [.25,.85,.35,1] 的精确 cubic-bezier 映射。
static func reference_ease(progress: float) -> float:
	var x := clampf(progress, 0.0, 1.0)
	var t := x
	for _i in range(6):
		var current_x := _bezier_coord(t, 0.25, 0.35)
		var slope := _bezier_slope(t, 0.25, 0.35)
		if absf(slope) < 0.00001:
			break
		t = clampf(t - (current_x - x) / slope, 0.0, 1.0)
	return _bezier_coord(t, 0.85, 1.0)


static func _bezier_coord(t: float, p1: float, p2: float) -> float:
	var u := 1.0 - t
	return 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t


static func _bezier_slope(t: float, p1: float, p2: float) -> float:
	var u := 1.0 - t
	return 3.0 * u * u * p1 + 6.0 * u * t * (p2 - p1) + 3.0 * t * t * (1.0 - p2)
