class_name Tile

# 0e 扩展：owner_seat 字段，默认 NO_OWNER。卡组系统（里程碑 6）真正接入时填实际座位；
# v1 (M3 收尾) 由 Wall.new_full_set 按 copy_index 给每张牌做"卡组合并"占位分配。
# spec §5 设计了 TileInstance 含 owner_seat / skill / is_revealed_to —— 0e 阶段
# 仅引入 owner_seat，其余字段在里程碑 1 技能框架时由 TileInstance 包装。
#
# 备注：本字段最早由 commit 2b87929 引入（PR #9 plan-0e Task 1），合并冲突中
# 被吃掉；M3 收尾恢复并真正用上（SeatPanel 手牌色块归属可视化）。

const NO_OWNER: int = -1

var id: int
var is_red_dora: bool
var owner_seat: int

func _init(p_id: int, p_red: bool = false, p_owner: int = NO_OWNER) -> void:
	id = p_id
	is_red_dora = p_red
	owner_seat = p_owner

func equals_by_id(other: Tile) -> bool:
	return id == other.id

static func make_red_five_man() -> Tile:
	return Tile.new(TileId.W5, true)

static func make_red_five_pin() -> Tile:
	return Tile.new(TileId.T5, true)

static func make_red_five_sou() -> Tile:
	return Tile.new(TileId.S5, true)
