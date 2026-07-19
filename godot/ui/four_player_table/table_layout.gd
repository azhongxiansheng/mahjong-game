class_name TableLayout

# 麻将王 — 雀魂式牌桌布局契约（P0）
#
# 1280×800 满屏：顶栏 / 桌面 / 手牌带 / 操作条。
# 所有坐标从这里派生，禁止在各 panel 再写魔法数。

const VIEW_W: float = 1280.0
const VIEW_H: float = 800.0

const TOP_BAR_H: float = 48.0
# 桌面区域（含毡）：顶栏下到操作条上
const TABLE_W: float = 1280.0
const TABLE_H: float = 720.0

# 操作条（浮在手牌上方）
const ACTION_BAR_Y: float = 548.0
const ACTION_BAR_H: float = 56.0

# 中心盘（略上移，给自家手牌/河更多呼吸）
static func center() -> Vector2:
	return Vector2(TABLE_W * 0.5, TABLE_H * 0.44)


# 四家 seat 锚点（相对桌面 0,0）
static func seat_anchor(seat_id: int) -> Vector2:
	var cx := TABLE_W * 0.5
	var cy := TABLE_H * 0.44
	match seat_id:
		0:  # 下 — 自家
			return Vector2(cx, TABLE_H - 88.0)
		1:  # 右
			return Vector2(TABLE_W - 88.0, cy)
		2:  # 上
			return Vector2(cx, 78.0)
		3:  # 左
			return Vector2(88.0, cy)
	return Vector2(cx, cy)


# 弃牌河：四边贴中心盘外围
const RIVER_W: float = 248.0
const RIVER_H: float = 160.0

static func discard_river(seat_id: int) -> Dictionary:
	var cx := TABLE_W * 0.5
	var cy := TABLE_H * 0.44
	var inner := 156.0
	var inner_self := 128.0
	match seat_id:
		0:
			return {"position": Vector2(cx - RIVER_W / 2.0, cy + inner_self), "rotation_degrees": 0.0}
		1:
			return {"position": Vector2(cx + inner, cy + RIVER_W / 2.0), "rotation_degrees": -90.0}
		2:
			return {"position": Vector2(cx + RIVER_W / 2.0, cy - inner), "rotation_degrees": 180.0}
		3:
			return {"position": Vector2(cx - inner, cy - RIVER_W / 2.0), "rotation_degrees": 90.0}
	return {"position": Vector2(cx, cy), "rotation_degrees": 0.0}


const MELD_MARGIN: float = 36.0

static func meld_area(seat_id: int) -> Dictionary:
	match seat_id:
		0:
			return {"position": Vector2(TABLE_W - MELD_MARGIN, TABLE_H - 88.0), "rotation_degrees": 0.0}
		1:
			return {"position": Vector2(TABLE_W - MELD_MARGIN, MELD_MARGIN + 40.0), "rotation_degrees": -90.0}
		2:
			return {"position": Vector2(MELD_MARGIN + 40.0, MELD_MARGIN + 40.0), "rotation_degrees": 180.0}
		3:
			return {"position": Vector2(MELD_MARGIN, TABLE_H - 88.0), "rotation_degrees": 90.0}
	return {"position": Vector2.ZERO, "rotation_degrees": 0.0}
