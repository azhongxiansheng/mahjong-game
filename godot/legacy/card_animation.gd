## 卡牌动画管理器
## 负责卡牌的各种动画效果（摸牌、出牌、胡牌等）
class_name CardAnimation
extends Node

## 动画配置
var draw_duration: float = 0.3 # 摸牌动画时间
var play_duration: float = 0.4 # 出牌动画时间
var win_duration: float = 0.5 # 胡牌动画时间

## 信号
signal animation_started(animation_type: String)
signal animation_completed(animation_type: String)

## 摸牌动画
func animate_draw_card(card_ui: CardUI, from_pos: Vector2, to_pos: Vector2) -> void:
	animation_started.emit("draw")

	card_ui.position = from_pos

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)

	# 移动动画
	tween.tween_property(card_ui, "position", to_pos, draw_duration)

	# 翻转动画（从背面到正面）
	tween.parallel().tween_property(card_ui, "modulate:a", 1.0, draw_duration * 0.5)

	await tween.finished
	animation_completed.emit("draw")

## 出牌动画
func animate_play_card(card_ui: CardUI, _from_pos: Vector2, to_pos: Vector2) -> void:
	animation_started.emit("play")

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)

	# 移动到出牌位置
	tween.tween_property(card_ui, "position", to_pos, play_duration)

	# 同时进行旋转效果
	tween.parallel().tween_property(card_ui, "rotation", TAU * 0.5, play_duration)

	await tween.finished
	animation_completed.emit("play")

## 胡牌动画
func animate_win(card_uis: Array[CardUI]) -> void:
	animation_started.emit("win")

	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.set_ease(Tween.EASE_OUT)

	# 所有卡牌同时放大和抖动
	for card_ui in card_uis:
		tween.tween_property(card_ui, "scale", Vector2(1.2, 1.2), win_duration)
		tween.parallel().tween_property(card_ui, "modulate", Color.YELLOW, win_duration * 0.5)

	await tween.finished
	animation_completed.emit("win")

## 听牌提示动画（闪烁）
func animate_ting_hint(card_ui: CardUI) -> void:
	animation_started.emit("ting")

	var tween = create_tween()
	tween.set_loops(3)
	tween.set_trans(Tween.TRANS_SINE)

	tween.tween_property(card_ui, "modulate", Color.WHITE, 0.3)
	tween.tween_property(card_ui, "modulate", Color.CYAN, 0.3)

	await tween.finished
	animation_completed.emit("ting")

## 碰牌动画
func animate_peng(player_cards: Array[CardUI], from_pos: Vector2) -> void:
	animation_started.emit("peng")

	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)

	# 三张卡牌从中间分散
	for i in range(player_cards.size()):
		var offset = (i - 1) * 30
		tween.tween_property(player_cards[i], "position:x", from_pos.x + offset, 0.4)

	await tween.finished
	animation_completed.emit("peng")

## 杠牌动画
func animate_kong(player_cards: Array[CardUI], center_pos: Vector2) -> void:
	animation_started.emit("kong")

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.set_ease(Tween.EASE_OUT)

	# 四张卡牌围绕中心旋转
	for i in range(player_cards.size()):
		var angle = (i / float(player_cards.size())) * TAU
		var offset = Vector2(cos(angle), sin(angle)) * 50
		tween.tween_property(player_cards[i], "position", center_pos + offset, 0.5)

	await tween.finished
	animation_completed.emit("kong")

## 弃牌堆动画（卡牌堆叠）
func animate_discard_pile(new_card: CardUI, pile_pos: Vector2) -> void:
	new_card.position = pile_pos

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)

	# 卡牌下落到弃牌堆
	tween.tween_property(new_card, "position:y", pile_pos.y + 100, 0.3)
	tween.parallel().tween_property(new_card, "rotation", randf_range(-0.2, 0.2), 0.3)

	await tween.finished

## 错误提示动画（抖动）
func animate_error_shake(control: Control) -> void:
	animation_started.emit("error")

	var original_pos = control.position
	var tween = create_tween()
	tween.set_loops(4)
	tween.set_trans(Tween.TRANS_SINE)

	tween.tween_property(control, "position", original_pos + Vector2(-10, 0), 0.1)
	tween.tween_property(control, "position", original_pos + Vector2(10, 0), 0.1)

	await tween.finished
	control.position = original_pos
	animation_completed.emit("error")

## 粒子效果 - 胡牌时的金光特效
func animate_win_particles(_pos: Vector2) -> void:
	# 创建粒子效果（可选）
	# 这里简化处理，实际可以使用GPUParticles2D
	pass

## 停止所有动画
func stop_all_animations() -> void:
	if is_node_ready():
		# 停止所有正在运行的补间
		for tween in get_tree().get_root().get_tweens():
			tween.kill()
