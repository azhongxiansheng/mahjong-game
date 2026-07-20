class_name TableLayout

# 麻将王 — 雀魂式牌桌布局契约（P0）
#
# 参考站 1600×900 固定 stage：顶栏 / 桌面 / 手牌带 / 操作条。
# 所有坐标从这里派生，禁止在各 panel 再写魔法数。

const VIEW_W: float = 1600.0
const VIEW_H: float = 900.0

const TOP_BAR_H: float = 48.0
# 桌面舞台（含毡）与固定 stage 同尺寸，HUD 叠加在其上。
const TABLE_W: float = 1600.0
const TABLE_H: float = 900.0

# 操作条（浮在手牌上方）
const ACTION_BAR_Y: float = 700.0
const ACTION_BAR_H: float = 72.0

# 公开 bundle 的 `.table-scene > .table-plane` 透视契约。
const PERSPECTIVE_DISTANCE: float = 1200.0
const PERSPECTIVE_ORIGIN := Vector2(800.0, 288.0)
const TABLE_PLANE_RECT := Rect2(0.0, -140.0, 1600.0, 1040.0)
const TABLE_PLANE_ORIGIN := Vector2(800.0, 900.0)
const TABLE_PLANE_ROTATION_X_DEGREES: float = 18.0

# `.board` 的隐式 CSS grid：top/bottom 河决定 300px 中轨，left/right 河决定
# 300px 中轨高度；两侧轨 144px，轨间 gap 4px，总尺寸 596×596。
const BOARD_TRACKS := Vector3(144.0, 300.0, 144.0)
const BOARD_GAP: float = 4.0
const BOARD_SIZE := Vector2(596.0, 596.0)
# 固定 stage 下 `.board` 变换前的布局盒顶边为 116.5px，横向由舞台居中推导。
const BOARD_LAYOUT_TOP: float = 116.5
const BOARD_ORIGIN := Vector2((TABLE_W - BOARD_SIZE.x) * 0.5, BOARD_LAYOUT_TOP)
const BOARD_TRANSLATE_Y: float = -30.0
const RIVER_INSET: float = 30.0

const RIVER_SIZE := Vector2(300.0, 144.0)
const CENTER_PLATE_SIZE := Vector2(220.0, 220.0)
const CENTER_CSS_SCALE: float = 1.04

# 公开 bundle 在 1600×900 固定 stage 下的 hand host。对家 hand host 都保留
# 摸牌槽；出现副露时由同一个 flex 容器整体重排，而不是另写四角坐标。
const HAND_HOST_RECTS := [
	Rect2(302.0, 778.0, 996.0, 92.0),
	Rect2(1256.798, 216.539, 98.825, 434.654),
	Rect2(558.280, 24.341, 483.441, 45.067),
	Rect2(245.722, 208.710, 98.468, 432.665),
]
const HAND_HOST_WITH_MELD_RECTS := [
	Rect2(218.5, 778.0, 996.0, 92.0),
	Rect2(1265.727, 287.331, 102.096, 452.879),
	Rect2(626.699, 24.341, 483.441, 45.067),
	Rect2(257.346, 140.869, 95.406, 415.644),
]
# 受控 DOM 测量：满14张暗手旁强插1个pon，不是合法牌局状态，仅保留视觉回归。
const CONTROLLED_FULL_HAND_WITH_PON_RECTS := HAND_HOST_WITH_MELD_RECTS
# 合法生产状态：1 pon 后暗手 base=10，再含1张摸牌（总11张）。
const LEGAL_ONE_PON_POST_DRAW_HAND_RECTS := [
	Rect2(323.5, 778.0, 786.0, 92.0),
	Rect2(1274.128, 332.323, 90.898, 365.662),
	Rect2(677.091, 24.341, 382.656, 45.067),
	Rect2(261.397, 172.363, 84.754, 333.635),
]
const LEGAL_ONE_PON_POST_DRAW_MELD_RECTS := [
	Rect2(1141.5, 797.5, 135.0, 53.0),
	Rect2(1294.256, 183.113, 62.086, 119.370),
	Rect2(544.488, 27.162, 110.410, 37.759),
	Rect2(186.421, 539.219, 70.273, 144.716),
]
const LEGAL_LEFT_ONE_PON_POST_DISCARD_HAND_RECT := \
	Rect2(260.577179, 177.346008, 84.941772, 334.608917)
const LEGAL_LEFT_ONE_PON_POST_DISCARD_MELD_RECT := \
	Rect2(187.394669, 545.277039, 68.464783, 132.166626)
const SINGLE_PON_RECTS := [
	Rect2(1246.5, 797.5, 135.0, 53.0),
	Rect2(1289.893, 151.433, 59.806, 106.771),
	Rect2(494.917, 27.162, 110.950, 37.759),
	Rect2(180.129, 590.599, 69.488, 135.268),
]
const AVATAR_RECTS := [
	Rect2(322.0, 644.0, 78.0, 78.0),
	Rect2(1417.0, 370.0, 78.0, 78.0),
	Rect2(1110.0, 85.0, 78.0, 78.0),
	Rect2(105.0, 370.0, 78.0, 78.0),
]

# q0()/aw() 的 SVG 外包围盒与 host 纵向公式。raw 坐标来自公开 DOM：
# scene=(66,48)、side cell top=69、height=596、host=494.63、左右分别
# translateY(0/-10)，右家再因 column-reverse 从预留槽之后的 44px 起排。
const SIDE_HAND_RAW_SIZE := Vector2(46.71, 66.63)
const SIDE_HAND_RAW_X_RIGHT: float = 1343.0
const SIDE_HAND_RAW_X_LEFT: float = 210.297237
const SIDE_HAND_RAW_Y_RIGHT: float = 211.185
const SIDE_HAND_RAW_Y_LEFT: float = 157.185
const SIDE_HAND_RAW_STEP: float = 32.0
const HAND_MELD_GAP: float = 32.0
const SIDE_MELD_MAIN_OVERHANG: float = 8.0
const TOP_HAND_PROJECTION_SCALE_X: float = 483.441 / 590.0
const SIDE_FLEX_CENTER_RAW_Y: float = 404.5


static func hand_main_extent(seat_id: int, base_count: int) -> float:
	assert(base_count >= 0)
	match seat_id:
		0:
			return base_count * 66.0 + maxi(base_count - 1, 0) * 4.0 + 24.0 + 66.0
		2:
			return base_count * 38.0 + maxi(base_count - 1, 0) * 3.0 + 22.0 + 38.0
		1, 3:
			return 66.63 + base_count * SIDE_HAND_RAW_STEP + 12.0
	return 0.0


# hand 与 meld 外盒在同一个 flex 容器内居中；返回的是变换前 main-axis 坐标。
static func hand_meld_flex_layout(seat_id: int, hand_extent: float,
		meld_outer_extent: float) -> Dictionary:
	var has_meld := meld_outer_extent > 0.0
	var gap := HAND_MELD_GAP if has_meld else 0.0
	var center_ := 800.0 if seat_id == 0 or seat_id == 2 \
		else SIDE_FLEX_CENTER_RAW_Y
	var total := hand_extent + gap + meld_outer_extent
	var first := center_ - total * 0.5
	var hand_start := first
	var meld_start := first + hand_extent + gap
	if seat_id == 1 or seat_id == 2:
		meld_start = first
		hand_start = first + meld_outer_extent + gap
	return {
		"hand_start": hand_start,
		"meld_start": meld_start,
		"gap": gap,
		"combined_center": center_,
		"combined_extent": total,
	}


static func hand_host_rect_for_state(seat_id: int, base_count: int,
		meld_main_extent: float = 0.0, has_drawn: bool = true) -> Rect2:
	var hand_extent := hand_main_extent(seat_id, base_count)
	var meld_outer := meld_main_extent + (SIDE_MELD_MAIN_OVERHANG \
		if meld_main_extent > 0.0 and (seat_id == 1 or seat_id == 3) else 0.0)
	var flex := hand_meld_flex_layout(seat_id, hand_extent, meld_outer)
	if seat_id == 0:
		return Rect2(float(flex["hand_start"]), 778.0, hand_extent, 92.0)
	if seat_id == 2:
		return Rect2(
			800.0 + (float(flex["hand_start"]) - 800.0) * TOP_HAND_PROJECTION_SCALE_X,
			24.341, hand_extent * TOP_HAND_PROJECTION_SCALE_X, 45.067)
	return _projected_rect_aabb(_side_hand_raw_host_rect_for_state(
		seat_id, base_count, meld_main_extent, has_drawn))


static func _side_hand_raw_host_rect_for_state(seat_id: int, base_count: int,
		meld_main_extent: float, has_drawn: bool) -> Rect2:
	var hand_extent := hand_main_extent(seat_id, base_count)
	if meld_main_extent <= 0.0 and base_count == 13:
		return Rect2(
			1343.00023 if seat_id == 1 else 210.29774,
			167.187 if seat_id == 1 else 157.187,
			46.7024, hand_extent)
	var meld_outer := meld_main_extent + (SIDE_MELD_MAIN_OVERHANG \
		if meld_main_extent > 0.0 else 0.0)
	var flex := hand_meld_flex_layout(seat_id, hand_extent, meld_outer)
	# side DOM hand 是 raw 46.703px 宽的竖盒；以合法1pon/base10实测为锚，
	# count/meld 变化严格按同一 flex 居中量平移。
	var reference_hand_extent := hand_main_extent(seat_id, 10)
	var reference_meld_outer := 137.0 + SIDE_MELD_MAIN_OVERHANG
	var reference_flex := hand_meld_flex_layout(
		seat_id, reference_hand_extent, reference_meld_outer)
	var reference_raw_y := 310.1875 if seat_id == 1 else (
		110.1875 if has_drawn else 116.6875)
	var raw_y := reference_raw_y + float(flex["hand_start"]) \
		- float(reference_flex["hand_start"])
	var raw_x := 1346.14096 if seat_id == 1 else 207.14062
	return Rect2(raw_x, raw_y, 46.7033, hand_extent)


static func side_hand_slot_rect_for_state(seat_id: int, slot_index: int,
		base_count: int, meld_main_extent: float = 0.0,
		has_drawn: bool = true) -> Rect2:
	return _projected_rect_aabb(Rect2(side_hand_slot_raw_origin_for_state(
		seat_id, slot_index, base_count, meld_main_extent, has_drawn),
		SIDE_HAND_RAW_SIZE))


static func side_hand_slot_raw_origin_for_state(seat_id: int, slot_index: int,
		base_count: int, meld_main_extent: float = 0.0,
		has_drawn: bool = true) -> Vector2:
	assert(slot_index >= 0 and slot_index < base_count)
	var host := _side_hand_raw_host_rect_for_state(
		seat_id, base_count, meld_main_extent, has_drawn)
	var raw_x := host.position.x
	var raw_y := host.position.y + slot_index * SIDE_HAND_RAW_STEP
	if seat_id == 1:
		raw_y += 44.0
	return Vector2(raw_x, raw_y)


static func side_hand_drawn_slot_rect_for_state(seat_id: int,
		base_count: int, meld_main_extent: float = 0.0) -> Rect2:
	return _projected_rect_aabb(Rect2(side_hand_drawn_slot_raw_origin_for_state(
		seat_id, base_count, meld_main_extent), SIDE_HAND_RAW_SIZE))


static func side_hand_drawn_slot_raw_origin_for_state(seat_id: int,
		base_count: int, meld_main_extent: float = 0.0) -> Vector2:
	var host := _side_hand_raw_host_rect_for_state(
		seat_id, base_count, meld_main_extent, true)
	var raw_y := host.position.y if seat_id == 1 else (
		host.position.y + base_count * SIDE_HAND_RAW_STEP + 12.0)
	return Vector2(host.position.x, raw_y)


# CSS `rotateX(18deg)` + 父级 1200px perspective 的逐点投影。
static func project_table_point(point: Vector2) -> Vector2:
	var angle := deg_to_rad(TABLE_PLANE_ROTATION_X_DEGREES)
	var relative_y := point.y - TABLE_PLANE_ORIGIN.y
	var rotated_y := TABLE_PLANE_ORIGIN.y + cos(angle) * relative_y
	var rotated_z := sin(angle) * relative_y
	var perspective_scale := PERSPECTIVE_DISTANCE / (
		PERSPECTIVE_DISTANCE - rotated_z)
	return Vector2(
		PERSPECTIVE_ORIGIN.x
			+ (point.x - PERSPECTIVE_ORIGIN.x) * perspective_scale,
		PERSPECTIVE_ORIGIN.y
			+ (rotated_y - PERSPECTIVE_ORIGIN.y) * perspective_scale,
	)


static func _projected_rect_aabb(raw_rect: Rect2) -> Rect2:
	var points := [
		project_table_point(raw_rect.position),
		project_table_point(Vector2(raw_rect.end.x, raw_rect.position.y)),
		project_table_point(raw_rect.end),
		project_table_point(Vector2(raw_rect.position.x, raw_rect.end.y)),
	]
	var minimum: Vector2 = points[0]
	var maximum: Vector2 = points[0]
	for point: Vector2 in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return Rect2(minimum, maximum - minimum)


static func hand_host_rect(seat_id: int, has_meld: bool) -> Rect2:
	assert(seat_id >= 0 and seat_id <= 3)
	return HAND_HOST_WITH_MELD_RECTS[seat_id] if has_meld \
		else HAND_HOST_RECTS[seat_id]


static func single_pon_rect(seat_id: int) -> Rect2:
	assert(seat_id >= 0 and seat_id <= 3)
	return SINGLE_PON_RECTS[seat_id]


static func avatar_rect(seat_id: int) -> Rect2:
	assert(seat_id >= 0 and seat_id <= 3)
	return AVATAR_RECTS[seat_id]


# 左右家不能把整列当 rigid stack：每个 SVG 的四角分别过 rotateX +
# perspective，故靠近镜头的末槽会自然变宽、变高并向外偏移。
# 受控 full-hand DOM fixture 专用；生产路径调用 `*_for_state` 动态版本。
static func controlled_side_hand_slot_rect(seat_id: int, slot_index: int,
		meld_main_extent: float = 0.0) -> Rect2:
	assert(seat_id == 1 or seat_id == 3)
	assert(slot_index >= 0)
	var raw_x := SIDE_HAND_RAW_X_RIGHT if seat_id == 1 \
		else SIDE_HAND_RAW_X_LEFT
	var raw_y := SIDE_HAND_RAW_Y_RIGHT if seat_id == 1 \
		else SIDE_HAND_RAW_Y_LEFT
	if meld_main_extent > 0.0:
		# 左右 `.tile__side` 有8px main-axis外伸；再加 flex gap=32。
		var reflow_shift := (meld_main_extent + SIDE_MELD_MAIN_OVERHANG \
			+ HAND_MELD_GAP) * 0.5
		raw_y += reflow_shift if seat_id == 1 else -reflow_shift
	raw_y += slot_index * SIDE_HAND_RAW_STEP
	return _projected_rect_aabb(Rect2(Vector2(raw_x, raw_y), SIDE_HAND_RAW_SIZE))


static func controlled_side_hand_drawn_slot_rect(seat_id: int,
		meld_main_extent: float = 0.0) -> Rect2:
	assert(seat_id == 1 or seat_id == 3)
	var raw_x := SIDE_HAND_RAW_X_RIGHT if seat_id == 1 \
		else SIDE_HAND_RAW_X_LEFT
	# right 的 column-reverse 摸牌占 host index0；基础13槽从44px开始。
	# left 的摸牌放在13槽之后，并在 13*32 后再留12px reserve。
	var raw_y := SIDE_HAND_RAW_Y_RIGHT - 44.0 if seat_id == 1 \
		else SIDE_HAND_RAW_Y_LEFT + 13.0 * SIDE_HAND_RAW_STEP + 12.0
	if meld_main_extent > 0.0:
		var reflow_shift := (meld_main_extent + SIDE_MELD_MAIN_OVERHANG \
			+ HAND_MELD_GAP) * 0.5
		raw_y += reflow_shift if seat_id == 1 else -reflow_shift
	return _projected_rect_aabb(Rect2(Vector2(raw_x, raw_y), SIDE_HAND_RAW_SIZE))


static func _river_raw_rect(seat_id: int) -> Rect2:
	var middle_x := BOARD_ORIGIN.x + BOARD_TRACKS.x + BOARD_GAP
	var middle_y := (BOARD_ORIGIN.y + BOARD_TRACKS.x + BOARD_GAP
		+ BOARD_TRANSLATE_Y)
	match seat_id:
		0:
			return Rect2(
				Vector2(middle_x,
					middle_y + BOARD_TRACKS.y + BOARD_GAP - RIVER_INSET),
				RIVER_SIZE)
		1:
			return Rect2(
				Vector2(middle_x + BOARD_TRACKS.y + BOARD_GAP - RIVER_INSET,
					middle_y),
				Vector2(RIVER_SIZE.y, RIVER_SIZE.x))
		2:
			return Rect2(
				Vector2(middle_x,
					BOARD_ORIGIN.y + BOARD_TRANSLATE_Y + RIVER_INSET),
				RIVER_SIZE)
		3:
			return Rect2(
				Vector2(BOARD_ORIGIN.x + RIVER_INSET, middle_y),
				Vector2(RIVER_SIZE.y, RIVER_SIZE.x))
	return Rect2(Vector2.ZERO, RIVER_SIZE)


# 中心盘最终节点锚点；基础盘仍保持以局部原点为中心的 220×220。
static func center_plate() -> Dictionary:
	var track_origin := Vector2(
		BOARD_ORIGIN.x + BOARD_TRACKS.x + BOARD_GAP,
		BOARD_ORIGIN.y + BOARD_TRACKS.x + BOARD_GAP + BOARD_TRANSLATE_Y,
	)
	var unscaled_origin := track_origin + (
		Vector2(BOARD_TRACKS.y, BOARD_TRACKS.y) - CENTER_PLATE_SIZE) * 0.5
	var css_size := CENTER_PLATE_SIZE * CENTER_CSS_SCALE
	var css_origin := unscaled_origin - (css_size - CENTER_PLATE_SIZE) * 0.5
	var projected := _projected_rect_aabb(Rect2(css_origin, css_size))
	return {
		"position": projected.get_center(),
		"scale": projected.size / CENTER_PLATE_SIZE,
		"screen_aabb": projected,
	}


static func center() -> Vector2:
	var layout: Dictionary = center_plate()
	return layout.position


# 四家 seat 锚点（相对桌面 0,0）
static func seat_anchor(seat_id: int) -> Vector2:
	match seat_id:
		0:  # 下 — 自家
			return Vector2(800.0, 700.0)
		1:  # 右
			return Vector2(1495.0, 370.0)
		2:  # 上
			return Vector2(800.0, 85.0)
		3:  # 左
			return Vector2(105.0, 370.0)
	return center()


# 弃牌河：逐项翻译 `.board` grid、四向 30px 内移与透视后的屏幕 AABB。
static func discard_river(seat_id: int) -> Dictionary:
	var projected := _projected_rect_aabb(_river_raw_rect(seat_id))
	var rotation_degrees := 0.0
	var position := projected.position
	var scale := projected.size / RIVER_SIZE
	match seat_id:
		1:
			rotation_degrees = -90.0
			position = Vector2(projected.position.x, projected.end.y)
			scale = Vector2(
				projected.size.y / RIVER_SIZE.x,
				projected.size.x / RIVER_SIZE.y,
			)
		2:
			rotation_degrees = 180.0
			position = projected.end
		3:
			rotation_degrees = 90.0
			position = Vector2(projected.end.x, projected.position.y)
			scale = Vector2(
				projected.size.y / RIVER_SIZE.x,
				projected.size.x / RIVER_SIZE.y,
			)
	return {
		"position": position,
		"rotation_degrees": rotation_degrees,
		"scale": scale,
		"screen_aabb": projected,
	}
