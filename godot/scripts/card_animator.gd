class_name CardAnimator
extends Node

# 动画速度
const ANIMATION_SPEED = 0.3  # 秒

func animate_select(node: Node) -> void:
	"""选中卡牌动画 - 缩放"""
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", Vector2(1.15, 1.15), ANIMATION_SPEED)
	print("✓ 选中动画: ", node.name)

func animate_deselect(node: Node) -> void:
	"""取消选中动画 - 缩放回原状"""
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", Vector2(1.0, 1.0), ANIMATION_SPEED)
	print("✓ 取消选中动画: ", node.name)

func animate_play_card(node: Node, target_pos: Vector2) -> void:
	"""出牌动画 - 移动到目标位置"""
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN_OUT)

	# 移动到目标位置
	tween.tween_property(node, "position", target_pos, ANIMATION_SPEED)

	# 同时缩小（出牌效果）
	tween.parallel().tween_property(node, "scale", Vector2(0.8, 0.8), ANIMATION_SPEED)

	# 淡出
	tween.parallel().tween_property(node, "modulate:a", 0.5, ANIMATION_SPEED)

	print("✓ 出牌动画: ", node.name)

func animate_win(node: Node) -> void:
	"""胡牌动画 - 旋转和跳跃"""
	var tween = create_tween()
	tween.set_loops(2)  # 重复2次
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.set_ease(Tween.EASE_OUT)

	# 旋转
	tween.tween_property(node, "rotation", TAU, ANIMATION_SPEED * 2)

	# 跳跃（Y轴移动）
	tween.parallel().tween_property(node, "position:y", node.position.y - 50, ANIMATION_SPEED)
	tween.tween_property(node, "position:y", node.position.y, ANIMATION_SPEED)

	print("✓ 胡牌动画: ", node.name)

func animate_hover(node: Node) -> void:
	"""悬停动画 - 轻微上升"""
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(node, "position:y", node.position.y - 10, ANIMATION_SPEED)
	print("✓ 悬停动画: ", node.name)

func animate_unhover(node: Node, original_y: float) -> void:
	"""取消悬停动画 - 回到原位"""
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(node, "position:y", original_y, ANIMATION_SPEED)
	print("✓ 取消悬停动画: ", node.name)

func animate_shuffle(nodes: Array) -> void:
	"""洗牌动画 - 所有卡牌旋转"""
	for node in nodes:
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(node, "rotation", TAU * 0.5, ANIMATION_SPEED * 0.5)
		tween.tween_property(node, "rotation", 0, ANIMATION_SPEED * 0.5)

	print("✓ 洗牌动画: 已应用到 ", nodes.size(), " 张卡牌")

func animate_draw_card(node: Node, from_pos: Vector2, to_pos: Vector2) -> void:
	"""抽卡动画 - 从牌堆移动到手牌"""
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)

	node.position = from_pos
	node.scale = Vector2(0.5, 0.5)

	tween.tween_property(node, "position", to_pos, ANIMATION_SPEED)
	tween.parallel().tween_property(node, "scale", Vector2(1.0, 1.0), ANIMATION_SPEED)

	print("✓ 抽卡动画: ", node.name)
