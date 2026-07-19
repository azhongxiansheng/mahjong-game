extends GutTest

# 手牌行增量匹配：同 (id, red) 应 reuse，多出来的 create，用不到的 free


func test_assign_reuse_exact_match() -> void:
	var prev: Array = [
		{"id": TileId.W1, "red": false},
		{"id": TileId.W5, "red": true},
		{"id": TileId.T3, "red": false},
	]
	var next: Array = [
		{"id": TileId.W1, "red": false},
		{"id": TileId.T3, "red": false},
		{"id": TileId.W5, "red": true},
	]
	var asg: Array = SeatPanel.assign_hand_reuse(prev, next)
	assert_eq(asg.size(), 3)
	assert_eq(int(asg[0]), 0, "W1 复用 prev0")
	assert_eq(int(asg[1]), 2, "T3 复用 prev2")
	assert_eq(int(asg[2]), 1, "赤五 复用 prev1")


func test_assign_reuse_prefers_red_match() -> void:
	var prev: Array = [
		{"id": TileId.W5, "red": false},
		{"id": TileId.W5, "red": true},
	]
	var next: Array = [
		{"id": TileId.W5, "red": true},
	]
	var asg: Array = SeatPanel.assign_hand_reuse(prev, next)
	assert_eq(int(asg[0]), 1, "赤五必须匹配 red 槽，不能吃普通五")


func test_assign_new_slots_are_minus_one() -> void:
	var prev: Array = [{"id": TileId.W1, "red": false}]
	var next: Array = [
		{"id": TileId.W1, "red": false},
		{"id": TileId.W2, "red": false},
	]
	var asg: Array = SeatPanel.assign_hand_reuse(prev, next)
	assert_eq(int(asg[0]), 0)
	assert_eq(int(asg[1]), -1, "新牌 W2 无 reuse")


func test_assign_drop_unused() -> void:
	# 切掉一张后 next 更短 — 分配只描述 next 侧
	var prev: Array = [
		{"id": TileId.W1, "red": false},
		{"id": TileId.W2, "red": false},
	]
	var next: Array = [{"id": TileId.W2, "red": false}]
	var asg: Array = SeatPanel.assign_hand_reuse(prev, next)
	assert_eq(int(asg[0]), 1)
	var used: Dictionary = {}
	for a in asg:
		if int(a) >= 0:
			used[int(a)] = true
	assert_false(used.has(0), "W1 槽应被释放（不在 used 中）")
