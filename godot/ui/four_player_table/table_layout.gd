class_name TableLayout

# 原创“结界舞台 HUD”1600×900 布局契约。
# 所有安全区从这里派生；只约束牌局可读性，不复刻第三方像素布局。

const VIEW_W: float = 1600.0
const VIEW_H: float = 900.0

const TOP_BAR_H: float = 48.0
# 桌面舞台（含毡）与固定 stage 同尺寸，HUD 叠加在其上。
const TABLE_W: float = 1600.0
const TABLE_H: float = 900.0

# 操作条（浮在手牌上方）
const ACTION_BAR_Y: float = 680.0
const ACTION_BAR_H: float = 78.0
const ACTION_BAR_RECT := Rect2(440.0, ACTION_BAR_Y, 720.0, ACTION_BAR_H)
const HAND_SAFE_RECT := Rect2(218.0, 778.0, 1164.0, 92.0)
const RESULT_PANEL_RECT := Rect2(350.0, 24.0, 900.0, 650.0)

# 四席状态印安全区；身份信息本身不再铺常驻面板。
const SEAT_HUD_RECTS := [
	Rect2(383.0, 616.0, 150.0, 22.0),
	Rect2(1426.0, 452.0, 150.0, 22.0),
	Rect2(1171.0, 166.0, 150.0, 22.0),
	Rect2(24.0, 452.0, 150.0, 22.0),
]


static func crowded_state_rects() -> Array[Rect2]:
	# 最大河牌与副露的合并公开信息区；用于 1600×900 几何门禁。
	return [
		Rect2(555.0, 476.0, 490.0, 184.0),
		Rect2(900.0, 220.0, 340.0, 400.0),
		Rect2(555.0, 142.0, 490.0, 154.0),
		Rect2(360.0, 220.0, 340.0, 400.0),
	]

# 四向牌桌的透视参数。
const PERSPECTIVE_DISTANCE: float = 1200.0
const PERSPECTIVE_ORIGIN := Vector2(800.0, 288.0)
const TABLE_PLANE_RECT := Rect2(0.0, -140.0, 1600.0, 1040.0)
const TABLE_PLANE_ORIGIN := Vector2(800.0, 900.0)
const TABLE_PLANE_ROTATION_X_DEGREES: float = 18.0

# 四向牌河网格：上下牌河决定 300px 中轨，左右牌河决定
# 300px 中轨高度；两侧轨 144px，轨间 gap 4px，总尺寸 596×596。
const BOARD_TRACKS := Vector3(144.0, 300.0, 144.0)
const BOARD_GAP: float = 4.0
const BOARD_SIZE := Vector2(596.0, 596.0)
# 固定舞台下变换前的布局盒顶边为 116.5px，横向由舞台居中推导。
const BOARD_LAYOUT_TOP: float = 116.5
const BOARD_ORIGIN := Vector2((TABLE_W - BOARD_SIZE.x) * 0.5, BOARD_LAYOUT_TOP)
const BOARD_TRANSLATE_Y: float = -30.0
const RIVER_INSET: float = 30.0

const RIVER_SIZE := Vector2(300.0, 144.0)
const CENTER_PLATE_SIZE := Vector2(220.0, 220.0)
const CENTER_CSS_SCALE: float = 1.04

# 参考桌面公开牌的两层牌身与接触阴影。方向沿各家最终屏幕朝向，
# 与 CSS 的 bottom/right/top/left 伪元素阴影保持一致。
const PUBLIC_TILE_GREEN_DEPTH: float = 7.0
const PUBLIC_TILE_WHITE_DEPTH: float = 4.0
const PUBLIC_TILE_SHADOW_OFFSET: float = 11.0

# 牌桌结构线的原始几何；位于 300×300 中轨中央，
# 再随 table-plane 统一做 18° 透视。保留 raw 点，禁止按截图手调 screen 坐标。
const BOARD_FRAME_SIZE := Vector2(852.0, 732.0)
const BOARD_FRAME_OUTER_RAW := [
	Vector2(50.0, 0.0),
	Vector2(802.0, 0.0),
	Vector2(802.0, 50.0),
	Vector2(852.0, 50.0),
	Vector2(852.0, 682.0),
	Vector2(802.0, 682.0),
	Vector2(802.0, 732.0),
	Vector2(50.0, 732.0),
	Vector2(50.0, 682.0),
	Vector2(0.0, 682.0),
	Vector2(0.0, 50.0),
	Vector2(50.0, 50.0),
]
const BOARD_FRAME_DIVIDERS_RAW := [
	[Vector2(50.0, 50.0), Vector2(316.0, 256.0)],
	[Vector2(802.0, 50.0), Vector2(536.0, 256.0)],
	[Vector2(50.0, 682.0), Vector2(316.0, 476.0)],
	[Vector2(802.0, 682.0), Vector2(536.0, 476.0)],
]

# 1600×900 固定舞台下的手牌 host。对家 hand host 都保留
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
# 受控极限测量：满14张暗手旁强插1个pon，不是合法牌局状态。
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
	Rect2(322.0, 644.0, 56.0, 56.0),
	Rect2(1417.0, 370.0, 56.0, 56.0),
	Rect2(1110.0, 85.0, 56.0, 56.0),
	Rect2(105.0, 370.0, 56.0, 56.0),
]

# 侧家牌块的外包围盒与 host 纵向公式：
# scene=(66,48)、side cell top=69、height=596、host=494.63、左右分别
# translateY(0/-10)，右家再因 column-reverse 从预留槽之后的 44px 起排。
const SIDE_HAND_RAW_SIZE := Vector2(46.71, 66.63)
const SIDE_HAND_RAW_X_RIGHT: float = 1343.0
const SIDE_HAND_RAW_X_LEFT: float = 210.297237
const SIDE_HAND_RAW_Y_RIGHT: float = 211.185
const SIDE_HAND_RAW_Y_LEFT: float = 157.185
const SIDE_HAND_RAW_STEP: float = 32.0
const HAND_MELD_GAP: float = 12.0
const SIDE_MELD_MAIN_OVERHANG: float = 8.0
const TOP_HAND_PROJECTION_SCALE_X: float = 483.441 / 590.0
const SIDE_FLEX_CENTER_RAW_Y: float = 404.5


static func hand_main_extent(seat_id: int, base_count: int,
		has_drawn: bool = true) -> float:
	assert(base_count >= 0)
	match seat_id:
		0:
			var base_extent := base_count * 66.0 + maxi(base_count - 1, 0) * 4.0
			return base_extent + 24.0 + 66.0 if has_drawn else base_extent
		2:
			var base_extent := base_count * 38.0 + maxi(base_count - 1, 0) * 3.0
			return base_extent + 22.0 + 38.0 if has_drawn else base_extent
		1, 3:
			return 66.63 + base_count * SIDE_HAND_RAW_STEP + 12.0 \
				if has_drawn else 66.63 + maxi(base_count - 1, 0) * SIDE_HAND_RAW_STEP
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
	var hand_extent := hand_main_extent(seat_id, base_count, has_drawn)
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
	var hand_extent := hand_main_extent(seat_id, base_count, has_drawn)
	if meld_main_extent <= 0.0 and base_count == 13:
		return Rect2(
			1343.00023 if seat_id == 1 else 210.29774,
			167.187 if seat_id == 1 else 157.187,
			46.7024, hand_extent)
	var meld_outer := meld_main_extent + (SIDE_MELD_MAIN_OVERHANG \
		if meld_main_extent > 0.0 else 0.0)
	var flex := hand_meld_flex_layout(seat_id, hand_extent, meld_outer)
	# 侧家 hand 是 raw 46.703px 宽的竖盒；以合法1pon/base10为锚，
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


# `rotateX(18deg)` + 父级 1200px perspective 的逐点投影。
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


static func public_tile_depth_offset(seat_id: int, distance: float) -> Vector2:
	assert(seat_id >= 0 and seat_id <= 3)
	match seat_id:
		1:
			return Vector2(-distance, 0.0)
		2:
			return Vector2(0.0, -distance)
		3:
			return Vector2(distance, 0.0)
	return Vector2(0.0, distance)


static func offset_polygon(points: PackedVector2Array,
		offset: Vector2) -> PackedVector2Array:
	var shifted := PackedVector2Array()
	for point in points:
		shifted.append(point + offset)
	return shifted


static func unproject_table_point(point: Vector2) -> Vector2:
	var angle := deg_to_rad(TABLE_PLANE_ROTATION_X_DEGREES)
	var y_delta := point.y - PERSPECTIVE_ORIGIN.y
	var origin_delta := TABLE_PLANE_ORIGIN.y - PERSPECTIVE_ORIGIN.y
	var relative_y := PERSPECTIVE_DISTANCE * (y_delta - origin_delta) / (
		y_delta * sin(angle) + PERSPECTIVE_DISTANCE * cos(angle))
	var raw_y := TABLE_PLANE_ORIGIN.y + relative_y
	var perspective_scale := PERSPECTIVE_DISTANCE / (
		PERSPECTIVE_DISTANCE - sin(angle) * relative_y)
	var raw_x := PERSPECTIVE_ORIGIN.x + (
		point.x - PERSPECTIVE_ORIGIN.x) / perspective_scale
	return Vector2(raw_x, raw_y)


# 将某席位的局部坐标逐点放到同一个桌面平面。局部 +x 沿该家牌面从左到右，
# 局部 +y 指向该家身前；四席只改变朝向，不再用投影后 AABB 冒充牌面。
static func project_seat_local_point(seat_id: int, raw_host: Rect2,
		local_point: Vector2) -> Vector2:
	assert(seat_id >= 0 and seat_id <= 3)
	var raw_point: Vector2
	match seat_id:
		0:
			raw_point = raw_host.position + local_point
		1:
			raw_point = Vector2(
				raw_host.position.x + local_point.y,
				raw_host.end.y - local_point.x)
		2:
			raw_point = raw_host.end - local_point
		3:
			raw_point = Vector2(
				raw_host.end.x - local_point.y,
				raw_host.position.y + local_point.x)
	return project_table_point(raw_point)


static func project_seat_local_rect(seat_id: int, raw_host: Rect2,
		local_rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		project_seat_local_point(seat_id, raw_host, local_rect.position),
		project_seat_local_point(seat_id, raw_host,
			Vector2(local_rect.end.x, local_rect.position.y)),
		project_seat_local_point(seat_id, raw_host, local_rect.end),
		project_seat_local_point(seat_id, raw_host,
			Vector2(local_rect.position.x, local_rect.end.y)),
	])


# 用既有布局目标只确定锚点；牌的大小与倾斜仍由真实桌面投影计算。
static func raw_host_for_projected_local_bounds(seat_id: int,
		target: Rect2, local_bounds: Rect2) -> Rect2:
	var host_size := local_bounds.size if seat_id == 0 or seat_id == 2 \
		else Vector2(local_bounds.size.y, local_bounds.size.x)
	var provisional := Rect2(Vector2.ZERO, host_size)
	var raw_corners := PackedVector2Array()
	for point in [
		local_bounds.position,
		Vector2(local_bounds.end.x, local_bounds.position.y),
		local_bounds.end,
		Vector2(local_bounds.position.x, local_bounds.end.y),
	]:
		var projected := project_seat_local_point(seat_id, provisional, point)
		raw_corners.append(unproject_table_point(projected))
	var raw_min: Vector2 = raw_corners[0]
	var raw_max: Vector2 = raw_corners[0]
	for point in raw_corners:
		raw_min = raw_min.min(point)
		raw_max = raw_max.max(point)
	var desired_top := unproject_table_point(
		Vector2(target.get_center().x, target.position.y)).y
	var desired_raw_center := unproject_table_point(Vector2(
		target.get_center().x,
		project_table_point(Vector2(PERSPECTIVE_ORIGIN.x,
			desired_top + (raw_max.y - raw_min.y) * 0.5)).y))
	var translation := Vector2(
		desired_raw_center.x - (raw_min.x + raw_max.x) * 0.5,
		desired_top - raw_min.y)
	return Rect2(translation, host_size)


static func board_frame_paths() -> Dictionary:
	var center_track_origin := Vector2(
		BOARD_ORIGIN.x + BOARD_TRACKS.x + BOARD_GAP,
		BOARD_ORIGIN.y + BOARD_TRACKS.x + BOARD_GAP + BOARD_TRANSLATE_Y,
	)
	var frame_origin := center_track_origin + (
		Vector2(BOARD_TRACKS.y, BOARD_TRACKS.y) - BOARD_FRAME_SIZE) * 0.5
	var outer := PackedVector2Array()
	for raw_point: Vector2 in BOARD_FRAME_OUTER_RAW:
		outer.append(project_table_point(frame_origin + raw_point))
	var dividers: Array[PackedVector2Array] = []
	for raw_segment: Array in BOARD_FRAME_DIVIDERS_RAW:
		var segment := PackedVector2Array()
		for raw_point: Vector2 in raw_segment:
			segment.append(project_table_point(frame_origin + raw_point))
		dividers.append(segment)
	return {"outer": outer, "dividers": dividers}


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
# 受控 full-hand fixture 专用；生产路径调用 `*_for_state` 动态版本。
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


static func river_raw_rect(seat_id: int) -> Rect2:
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
	var screen_quad := PackedVector2Array([
		project_table_point(css_origin),
		project_table_point(Vector2(css_origin.x + css_size.x, css_origin.y)),
		project_table_point(css_origin + css_size),
		project_table_point(Vector2(css_origin.x, css_origin.y + css_size.y)),
	])
	var projected := _projected_rect_aabb(Rect2(css_origin, css_size))
	var local_quad := PackedVector2Array()
	var projected_scale := projected.size / CENTER_PLATE_SIZE
	for point in screen_quad:
		local_quad.append((point - projected.get_center()) / projected_scale)
	return {
		"position": projected.get_center(),
		"scale": projected_scale,
		"screen_aabb": projected,
		"screen_quad": screen_quad,
		"local_quad": local_quad,
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


# 牌河公开区的兼容包围盒；生产牌面使用 project_seat_local_rect 逐牌投影。
static func discard_river(seat_id: int) -> Dictionary:
	var projected := _projected_rect_aabb(river_raw_rect(seat_id))
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
