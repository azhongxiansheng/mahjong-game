class_name YakuList

# 役清单 — 0c 与 0b 的共享数据契约（依据 spec §5）。
# - yaku 是 [{id: StringName, han: int}] 的数组，由 0b 役判定写入
# - dora_count 含 Dora + 裏 Dora + 赤 Dora 累计（0d 翻 Dora 时填入）
# - 役满走 is_yakuman + yakuman_multiplier；ScoreFormula 处理上限钳制

var yaku: Array = []
var dora_count: int = 0
var is_yakuman: bool = false
var yakuman_multiplier: int = 0

static func empty() -> YakuList:
	return YakuList.new()

func add_yaku(id: StringName, han: int) -> void:
	yaku.append({"id": id, "han": han})

func has_yaku(id: StringName) -> bool:
	for entry in yaku:
		if entry.id == id:
			return true
	return false

func total_han() -> int:
	var sum := 0
	for entry in yaku:
		sum += entry.han
	return sum + dora_count

func is_pinfu() -> bool:
	return has_yaku(&"pinfu")

func is_chiitoi() -> bool:
	return has_yaku(&"chiitoitsu")
